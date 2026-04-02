"""Proactive Advisor Service — structured assessment-driven design.

Instead of packing raw data + full skill markdown into one LLM prompt,
this service:
  1. Runs domain-specific assessment modules (sleep, activity, medication,
     recovery, dayprint follow-up) that each query their own data and
     return a structured ProactiveSkillResult.
  2. Evaluates deterministic guardrails to short-circuit obvious cases.
  3. Sends only structured assessment results + compact decision policy
     to the LLM for the final nudge decision.
  4. Persists audit records for observability.

Adding a new domain = add a new assessment module + register it.
No changes to this orchestrator needed.
"""

import asyncio
import json
import logging
import uuid
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

from ..core.config import settings
from ..core.database import get_database
from ..models.proactive import ProactiveSkillResult
from ..services.capability_service import get_user_enabled_capability_ids
from ..services.chat_history_service import save_message
from ..services.notification_service import queue_checkin_notification
from . import proactive_audit_service as audit
from . import proactive_guardrails as guardrails
from .llm_client import chat_completion
from .proactive_skills import ALL_ASSESSMENTS

logger = logging.getLogger(__name__)

_DECISION_MODEL = settings.PALEBLUEDOT_MODEL

# Capabilities whose data we can assess directly from MongoDB
_INTERNAL_CAP_ID = "lumie_internal_data"

# Capabilities that require execution infrastructure — noted for context
_EXECUTION_CAPS = {
    "email_read": "Email (enabled, data not available in proactive mode)",
    "browser_portal_access": "Web portal (enabled, data not available in proactive mode)",
    "web_read": "Web read (enabled, data not available in proactive mode)",
}


# ── Assessment execution ────────────────────────────────────────────────────

async def _run_single_assessment(assess_fn, db, user_id: str, now_utc: datetime) -> ProactiveSkillResult | None:
    """Run a single assessment with fault isolation."""
    try:
        return await assess_fn(db, user_id, now_utc)
    except Exception as e:
        fn_name = getattr(assess_fn, "__module__", "unknown")
        logger.error("Assessment %s failed for user=%s: %s", fn_name, user_id, e, exc_info=True)
        return None


async def _run_all_assessments(db, user_id: str, now_utc: datetime) -> list[ProactiveSkillResult]:
    """Run all assessment modules concurrently with fault isolation."""
    tasks = [_run_single_assessment(fn, db, user_id, now_utc) for fn in ALL_ASSESSMENTS]
    raw_results = await asyncio.gather(*tasks)
    return [r for r in raw_results if r is not None]


# ── LLM decision prompt ────────────────────────────────────────────────────

def _build_decision_prompt(
    user_name: str,
    role: str,
    icd10: str,
    local_time_str: str,
    skill_results: list[ProactiveSkillResult],
    last_nudge_str: str,
    guardrail_summary: dict,
    execution_caps_notes: list[str],
) -> tuple[str, str]:
    """Build compact system + user prompt from structured assessment results."""

    # Serialize skill results for the LLM
    results_for_llm = []
    for r in skill_results:
        results_for_llm.append({
            "skill_id": r.skill_id,
            "domain": r.domain,
            "status": r.status.value,
            "summary": r.summary,
            "score": r.score,
            "signals": r.signals,
            "recommended_actions": r.recommended_actions,
        })

    condition_str = f" with condition code {icd10}" if icd10 else ""

    system_prompt = (
        f"You are a proactive health advisor for {user_name}, a {role}{condition_str}.\n"
        f"Current local time: {local_time_str}.\n\n"
        "You are in PROACTIVE MODE. You are reviewing structured assessment results to decide "
        "whether to send a nudge notification.\n\n"
        "DECISION POLICY:\n"
        "1. First check follow-up domain: if a recent dayprint shows an unresolved concern, "
        "struggle, or prior advice topic, prefer a follow-up nudge.\n"
        "2. If no strong follow-up, check other domains for actionable concerns (score >= 0.3).\n"
        "3. Only nudge if genuinely worth addressing NOW. Avoid minor, speculative, or future concerns.\n"
        "4. When multiple domains have concerns, prefer the most personally grounded one.\n"
        "5. Never repeat the same nudge reason if the situation hasn't materially changed.\n\n"
        f"Nudge history: {last_nudge_str}\n\n"
        "Respond with valid JSON only — no markdown, no explanation:\n"
        '{"should_nudge": true|false, "message": "<friendly nudge message ≤120 chars, or null>", '
        '"reason": "<brief internal reason>", "primary_domain": "<domain>", "confidence": 0.0-1.0}'
    )

    # Build user message with assessment results + guardrail summary
    user_parts = ["Assessment results:\n"]
    user_parts.append(json.dumps(results_for_llm, indent=2))

    if guardrail_summary:
        user_parts.append(f"\nGuardrail summary: {json.dumps(guardrail_summary)}")

    if execution_caps_notes:
        user_parts.append("\nNote: " + "; ".join(execution_caps_notes))

    user_parts.append("\n\nBased on these assessments, should I reach out?")
    user_message = "\n".join(user_parts)

    return system_prompt, user_message


# ── Main entry point ────────────────────────────────────────────────────────

async def run_proactive_check(user_id: str) -> dict:
    """Run a proactive advisor check for a single user.

    Returns::

        {
            "nudged": bool,
            "message": str | None,
            "reason": str,
        }
    """
    run_id = str(uuid.uuid4())
    db = get_database()
    now_utc = datetime.now(timezone.utc)

    # ── 1. User profile ─────────────────────────────────────────────────────
    profile = await db.profiles.find_one({"user_id": user_id}, {"_id": 0})
    if not profile:
        return {"nudged": False, "message": None, "reason": "no_profile"}

    user_name = profile.get("name", "the user")
    user_timezone = profile.get("timezone", "UTC")
    icd10 = profile.get("icd10_code", "")
    role = profile.get("role", "teen")

    try:
        local_tz = ZoneInfo(user_timezone)
    except Exception:
        local_tz = ZoneInfo("UTC")

    now_local = datetime.now(local_tz)
    local_time_str = now_local.strftime("%A, %B %d, %I:%M %p")

    # ── 2. Enabled capabilities ─────────────────────────────────────────────
    enabled_cap_ids = await get_user_enabled_capability_ids(user_id)
    if not enabled_cap_ids:
        logger.info("Proactive[%s]: no enabled capabilities — skip", user_id)
        return {"nudged": False, "message": None, "reason": "no_enabled_capabilities"}

    if _INTERNAL_CAP_ID not in enabled_cap_ids:
        logger.info("Proactive[%s]: lumie_internal_data not enabled — skip", user_id)
        return {"nudged": False, "message": None, "reason": "no_internal_data_capability"}

    logger.info("Proactive[%s]: run_id=%s, capabilities=%s", user_id, run_id, sorted(enabled_cap_ids))

    # ── 3. Run all domain assessments ───────────────────────────────────────
    skill_results = await _run_all_assessments(db, user_id, now_utc)
    logger.info(
        "Proactive[%s]: %d assessments: %s",
        user_id,
        len(skill_results),
        [(r.skill_id, r.status.value, r.score) for r in skill_results],
    )

    if not skill_results:
        logger.warning("Proactive[%s]: all assessments failed — skip", user_id)
        return {"nudged": False, "message": None, "reason": "all_assessments_failed"}

    # ── 4. Last nudge context ───────────────────────────────────────────────
    checkin_doc = await db.advisor_checkins.find_one({"user_id": user_id})
    last_nudge = (checkin_doc or {}).get("last_nudge")
    if last_nudge:
        nudged_at_raw = last_nudge.get("nudged_at", "")
        try:
            nudged_at_dt = datetime.fromisoformat(nudged_at_raw)
            if nudged_at_dt.tzinfo is None:
                nudged_at_dt = nudged_at_dt.replace(tzinfo=timezone.utc)
            minutes_ago = int((now_utc - nudged_at_dt).total_seconds() / 60)
            last_nudge_str = (
                f"Last nudge sent {minutes_ago} minutes ago. "
                f"Reason: \"{last_nudge.get('reason', '')}\". "
                f"Domain: {last_nudge.get('primary_domain', 'unknown')}. "
                "Only nudge again for the same concern if the situation has materially changed."
            )
        except Exception:
            last_nudge_str = ""
    else:
        last_nudge_str = "No nudge has been sent yet."

    logger.info(
        "Proactive[%s]: last_nudge reason=%s domain=%s",
        user_id,
        last_nudge.get("reason", "none") if last_nudge else "none",
        last_nudge.get("primary_domain", "none") if last_nudge else "none",
    )

    # ── 5. Evaluate guardrails ──────────────────────────────────────────────
    guardrail = guardrails.evaluate(skill_results, last_nudge, now_utc)
    logger.info("Proactive[%s]: guardrail action=%s reason=%s", user_id, guardrail.action, guardrail.reason)

    if guardrail.action == "skip_nudge":
        await audit.save_run_record(db, run_id, user_id, now_utc, skill_results, guardrail, None)
        return {"nudged": False, "message": None, "reason": guardrail.reason}

    # ── 6. Build prompt and call LLM ────────────────────────────────────────
    execution_notes = [
        label for cap_id, label in _EXECUTION_CAPS.items()
        if cap_id in enabled_cap_ids
    ]

    system_prompt, user_message = _build_decision_prompt(
        user_name=user_name,
        role=role,
        icd10=icd10,
        local_time_str=local_time_str,
        skill_results=skill_results,
        last_nudge_str=last_nudge_str,
        guardrail_summary=guardrail.details,
        execution_caps_notes=execution_notes,
    )

    # For force_nudge, we still call the LLM to generate the message
    logger.info("Proactive[%s]: calling decision model", user_id)
    logger.debug("Proactive[%s]: system_prompt=\n%s", user_id, system_prompt)
    logger.debug("Proactive[%s]: user_message=\n%s", user_id, user_message)

    try:
        response = await chat_completion(
            model=_DECISION_MODEL,
            max_tokens=200,
            temperature=0,
            system=system_prompt,
            messages=[{"role": "user", "content": user_message}],
        )
        raw = response.text.strip()
        if raw.startswith("```"):
            raw_lines = raw.split("\n")
            raw = "\n".join(raw_lines[1:-1]) if len(raw_lines) > 2 else raw
        logger.info("Proactive[%s]: model response=%r", user_id, raw)
        result = json.loads(raw)
    except Exception as e:
        logger.error("Proactive[%s]: decision model call failed: %s", user_id, e)
        await audit.save_run_record(db, run_id, user_id, now_utc, skill_results, guardrail, None)
        return {"nudged": False, "message": None, "reason": f"llm_error: {e}"}

    should_nudge: bool = bool(result.get("should_nudge", False))
    message: str | None = result.get("message") or None
    reason: str = result.get("reason", "")

    # If guardrail said force_nudge, override LLM if it said no
    if guardrail.action == "force_nudge" and not should_nudge:
        logger.info("Proactive[%s]: guardrail force_nudge overriding model no-nudge", user_id)
        should_nudge = True
        if not message:
            top = max(skill_results, key=lambda r: r.score)
            message = top.recommended_actions[0] if top.recommended_actions else "Hey, just checking in — how are you doing?"
        reason = guardrail.reason

    # ── 7. Deliver ──────────────────────────────────────────────────────────
    decision_data = {
        "should_nudge": should_nudge,
        "reason_code": reason,
        "message": message,
        "primary_domain": result.get("primary_domain"),
        "confidence": result.get("confidence", 0.0),
    }

    delivery_data = {"delivered": False}

    if should_nudge and message:
        await save_message(
            user_id=user_id,
            session_id="proactive",
            role="assistant",
            content=message,
            metadata={"type": "proactive", "reason": reason, "run_id": run_id},
        )

        await queue_checkin_notification(user_id, message)

        # Build structured last_nudge with evidence summary and inputs hash
        evidence_summary = guardrails.build_evidence_summary(skill_results)
        decision_inputs_hash = guardrails.compute_decision_inputs_hash(skill_results)

        await db.advisor_checkins.update_one(
            {"user_id": user_id},
            {"$set": {"last_nudge": {
                "reason": reason,
                "nudged_at": now_utc.isoformat(),
                "run_id": run_id,
                "primary_domain": result.get("primary_domain"),
                "evidence_summary": evidence_summary,
                "decision_inputs_hash": decision_inputs_hash,
            }}},
            upsert=True,
        )

        delivery_data = {"delivered": True, "run_id": run_id, "reason": reason}
        logger.info("Proactive[%s]: nudge delivered, reason=%s domain=%s", user_id, reason, result.get("primary_domain"))
    else:
        logger.info("Proactive[%s]: no nudge, reason=%s", user_id, reason)

    # ── 8. Audit ────────────────────────────────────────────────────────────
    await audit.save_run_record(
        db, run_id, user_id, now_utc, skill_results, guardrail, decision_data, delivery_data,
    )

    return {"nudged": should_nudge, "message": message, "reason": reason}
