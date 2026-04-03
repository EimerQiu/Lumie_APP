"""Proactive Advisor Service — structured assessment-driven design.

Instead of packing raw data + full skill markdown into one LLM prompt,
this service:
  1. Runs domain-specific assessment modules (sleep, activity, medication,
     recovery, dayprint follow-up, team follow-up) that each query their own data and
     return a structured ProactiveSkillResult.
  2. Evaluates deterministic guardrails to short-circuit obvious cases.
  3. Sends only structured assessment results + compact decision policy
     to the LLM for the final nudge decision.
  4. Persists audit records for observability.

Adding a new domain = add a new assessment module + register it.
No changes to this orchestrator needed.
"""

import asyncio
import hashlib
import json
import logging
import re
import uuid
from datetime import datetime, timedelta, timezone
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
from .proactive_skill_selector import select_proactive_skills
from .proactive_skills import DOMAIN_ASSESSMENTS

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
_MIN_ALT_CONCERN_SCORE = 0.30
_LOW_PRIORITY_DOMAINS = {"dayprint", "team_followup"}


# ── Assessment execution ────────────────────────────────────────────────────

async def _run_single_assessment(assess_fn, db, user_id: str, now_utc: datetime) -> ProactiveSkillResult | None:
    """Run a single assessment with fault isolation."""
    try:
        return await assess_fn(db, user_id, now_utc)
    except Exception as e:
        fn_name = getattr(assess_fn, "__module__", "unknown")
        logger.error("Assessment %s failed for user=%s: %s", fn_name, user_id, e, exc_info=True)
        return None


async def _run_all_assessments(
    db,
    user_id: str,
    now_utc: datetime,
    assessment_fns: list,
) -> list[ProactiveSkillResult]:
    """Run selected assessment modules concurrently with fault isolation."""
    tasks = [_run_single_assessment(fn, db, user_id, now_utc) for fn in assessment_fns]
    raw_results = await asyncio.gather(*tasks)
    return [r for r in raw_results if r is not None]


async def _get_no_material_change_streak(db, user_id: str, lookback: int = 12) -> int:
    """Count consecutive recent runs with guardrail reason=no_material_change."""
    docs = await db.proactive_runs.find(
        {"user_id": user_id},
        {"_id": 0, "guardrail_result.reason": 1},
    ).sort("started_at", -1).to_list(lookback)

    streak = 0
    for doc in docs:
        reason = ((doc or {}).get("guardrail_result") or {}).get("reason")
        if reason == "no_material_change":
            streak += 1
            continue
        break
    return streak


def _canonicalize(text: str) -> str:
    """Canonicalize a text fragment to compare semantic repetition."""
    t = (text or "").lower().strip()
    if not t:
        return ""
    t = re.sub(r"\d{4}-\d{2}-\d{2}", "date", t)
    t = re.sub(r"\d+", "n", t)
    t = re.sub(r"[^a-z_ ]+", " ", t)
    t = re.sub(r"\s+", " ", t).strip()
    return t


def _build_concern_key(
    domain: str,
    _reason: str,
    skill_result: ProactiveSkillResult | None,
) -> str:
    """Build a semantic concern fingerprint (not wording-based)."""
    signals = (skill_result.signals if skill_result else [])[:3]
    canonical_signals = [_canonicalize(s) for s in signals if s]
    canonical_action = _canonicalize((skill_result.recommended_actions or [""])[0] if skill_result else "")
    payload = {
        "domain": _canonicalize(domain),
        "signals": sorted([s for s in canonical_signals if s]),
        "action": canonical_action,
    }
    raw = json.dumps(payload, sort_keys=True, ensure_ascii=True)
    digest = hashlib.sha1(raw.encode("utf-8")).hexdigest()[:16]
    return f"{payload['domain']}:{digest}"


def _find_skill_by_domain(skill_results: list[ProactiveSkillResult], domain: str | None) -> ProactiveSkillResult | None:
    if not domain:
        return None
    for r in skill_results:
        if r.domain == domain:
            return r
    return None


def _pick_alternate_concern(
    skill_results: list[ProactiveSkillResult],
    sent_concern_keys: set[str],
    allowed_domains: set[str] | None = None,
) -> tuple[str, str, str, str] | None:
    """Pick the highest-score unsent concern for same-day dedupe fallback."""
    candidates = sorted(skill_results, key=lambda r: r.score, reverse=True)
    for r in candidates:
        if allowed_domains is not None and r.domain not in allowed_domains:
            continue
        if r.score < _MIN_ALT_CONCERN_SCORE:
            continue
        alt_reason = f"alternate_{r.domain}_concern_same_day_dedupe"
        alt_key = _build_concern_key(r.domain, alt_reason, r)
        if alt_key in sent_concern_keys:
            continue
        alt_message = (
            r.recommended_actions[0]
            if r.recommended_actions
            else f"Quick check-in on your {r.domain.replace('_', ' ')} data."
        )
        return r.domain, alt_message, alt_reason, alt_key
    return None


async def _collect_recent_topics(
    db,
    user_id: str,
    now_utc: datetime,
    days: int = 15,
) -> list[dict]:
    """Collect all candidate concern topics from recent dayprints."""
    since_date = (now_utc - timedelta(days=days)).strftime("%Y-%m-%d")
    docs = await db.dayprints.find(
        {"user_id": user_id, "date": {"$gte": since_date}},
        {"_id": 0, "date": 1, "events": 1},
    ).sort("date", -1).to_list(200)

    by_key: dict[str, dict] = {}
    for doc in docs:
        date = doc.get("date", "")
        for event in (doc.get("events") or []):
            e_type = event.get("type")
            if e_type not in {"important_insight", "advisor_chat"}:
                continue
            data = event.get("data") or {}
            category = _canonicalize(data.get("category") or e_type or "other") or "other"
            summary = (data.get("summary") or "").strip()
            if not summary:
                continue

            canonical_summary = _canonicalize(summary)
            stem = " ".join(canonical_summary.split(" ")[:8])
            digest = hashlib.sha1(f"{category}|{stem}".encode("utf-8")).hexdigest()[:12]
            topic_key = f"{category}:{digest}"

            current = by_key.get(topic_key)
            if current is None:
                by_key[topic_key] = {
                    "topic_key": topic_key,
                    "category": category,
                    "summary": summary,
                    "count": 1,
                    "last_seen_at": date,
                }
            else:
                current["count"] += 1
                if date > (current.get("last_seen_at") or ""):
                    current["last_seen_at"] = date
                    current["summary"] = summary

    return sorted(by_key.values(), key=lambda x: (x.get("count", 0), x.get("last_seen_at", "")), reverse=True)


async def _rank_topics_with_llm(
    user_name: str,
    local_time_str: str,
    topics: list[dict],
) -> list[dict]:
    """Use LLM to score and rank concern topics."""
    if not topics:
        return []

    compact_topics = [
        {
            "topic_key": t["topic_key"],
            "category": t.get("category"),
            "summary": t.get("summary"),
            "count": t.get("count"),
            "last_seen_at": t.get("last_seen_at"),
        }
        for t in topics[:30]
    ]

    system_prompt = (
        f"You are ranking proactive concern topics for {user_name}.\n"
        f"Current local time: {local_time_str}.\n"
        "Score each topic 0.0-1.0 by urgency+importance for a caring check-in.\n"
        "Return JSON only:\n"
        '{"ranked":[{"topic_key":"...","score":0.0,"reason":"...","suggested_message":"<=120 chars"}]}'
    )
    user_message = "Topics JSON:\n" + json.dumps(compact_topics, ensure_ascii=False, indent=2)

    try:
        response = await chat_completion(
            model=_DECISION_MODEL,
            max_tokens=500,
            temperature=0,
            system=system_prompt,
            messages=[{"role": "user", "content": user_message}],
        )
        raw = response.text.strip()
        if raw.startswith("```"):
            raw_lines = raw.split("\n")
            raw = "\n".join(raw_lines[1:-1]) if len(raw_lines) > 2 else raw
        parsed = json.loads(raw)
        ranked = parsed.get("ranked") or []
        if not isinstance(ranked, list):
            return []
        by_key = {t["topic_key"]: t for t in topics}
        out: list[dict] = []
        for r in ranked:
            key = r.get("topic_key")
            if key not in by_key:
                continue
            out.append({
                "topic_key": key,
                "score": float(r.get("score", 0.0)),
                "reason": r.get("reason", ""),
                "suggested_message": (r.get("suggested_message") or "").strip(),
                "topic": by_key[key],
            })
        return out
    except Exception as e:
        logger.warning("Topic LLM ranking failed: %s", e)
        return []


async def _pick_alternate_topic_nudge(
    db,
    user_id: str,
    user_name: str,
    local_time_str: str,
    now_utc: datetime,
    sent_topic_keys: set[str],
) -> tuple[str, str, str, str, str] | None:
    """Pick next unsent topic from last 15 days using LLM topic scoring."""
    topics = await _collect_recent_topics(db, user_id, now_utc, days=15)
    if not topics:
        return None

    ranked = await _rank_topics_with_llm(user_name, local_time_str, topics)
    if not ranked:
        ranked = [
            {
                "topic_key": t["topic_key"],
                "score": min(1.0, 0.2 + 0.08 * int(t.get("count", 1))),
                "reason": "fallback_topic_ranking",
                "suggested_message": "",
                "topic": t,
            }
            for t in topics
        ]

    for item in ranked:
        topic_key = item["topic_key"]
        if topic_key in sent_topic_keys:
            continue
        score = float(item.get("score", 0.0))
        if score < 0.3:
            continue
        suggested = item.get("suggested_message") or ""
        summary = (item.get("topic") or {}).get("summary", "")
        message = suggested if suggested else f"Quick check-in: {summary[:96]}"
        reason = f"alternate_topic_queue_llm_scored:{topic_key}"
        concern_key = f"topic:{topic_key}"
        return "dayprint", message, reason, concern_key, topic_key

    return None


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
        "1. First check dayprint/team follow-up domains: if there is an unresolved concern, "
        "ongoing struggle, or notable team-member risk, prefer a follow-up nudge.\n"
        "2. If dayprint includes family health concern signals (family/family_concern/health_concern), "
        "treat them as high-priority follow-up evidence.\n"
        "3. If no strong follow-up signal, check other domains for actionable concerns (score >= 0.3).\n"
        "4. Only nudge if genuinely worth addressing NOW. Avoid minor, speculative, or future concerns.\n"
        "5. When multiple domains have concerns, prefer the most personally grounded one.\n"
        "6. Never repeat the same nudge reason if the situation hasn't materially changed.\n\n"
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

    # ── 3. Select and run proactive assessments ─────────────────────────────
    selected_skills = select_proactive_skills(enabled_cap_ids)
    if not selected_skills:
        logger.warning("Proactive[%s]: no proactive skills selected", user_id)
        return {"nudged": False, "message": None, "reason": "no_proactive_skills_selected"}

    assessment_fns = []
    for skill in selected_skills:
        domain = skill.proactive_domain or ""
        fn = DOMAIN_ASSESSMENTS.get(domain)
        if fn is None:
            logger.warning(
                "Proactive[%s]: selected skill %s has unmapped domain=%s",
                user_id,
                skill.skill_id,
                domain,
            )
            continue
        assessment_fns.append(fn)

    if not assessment_fns:
        logger.warning("Proactive[%s]: no mapped assessment functions for selected proactive skills", user_id)
        return {"nudged": False, "message": None, "reason": "no_mapped_proactive_assessments"}

    skill_results = await _run_all_assessments(db, user_id, now_utc, assessment_fns)
    logger.info(
        "Proactive[%s]: selected proactive skills=%s",
        user_id,
        [(s.skill_id, s.proactive_domain, s.proactive_priority) for s in selected_skills],
    )
    logger.info(
        "Proactive[%s]: %d assessment results: %s",
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
    no_change_streak = await _get_no_material_change_streak(db, user_id)
    logger.info("Proactive[%s]: no_material_change_streak=%d", user_id, no_change_streak)

    guardrail = guardrails.evaluate(
        skill_results=skill_results,
        last_nudge=last_nudge,
        now_utc=now_utc,
        no_material_change_streak=no_change_streak,
    )
    logger.info("Proactive[%s]: guardrail action=%s reason=%s", user_id, guardrail.action, guardrail.reason)

    if guardrail.action == "skip_nudge":
        skip_decision = {
            "should_nudge": False,
            "reason_code": guardrail.reason,
            "message": None,
            "primary_domain": None,
            "confidence": 1.0,
            "decision_summary": "guardrail_skip_nudge",
        }
        await audit.save_run_record(db, run_id, user_id, now_utc, skill_results, guardrail, skip_decision)
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
        error_decision = {
            "should_nudge": False,
            "reason_code": f"llm_error: {e}",
            "message": None,
            "primary_domain": None,
            "confidence": 0.0,
            "decision_summary": "llm_error_exit",
        }
        await audit.save_run_record(db, run_id, user_id, now_utc, skill_results, guardrail, error_decision)
        return {"nudged": False, "message": None, "reason": f"llm_error: {e}"}

    should_nudge: bool = bool(result.get("should_nudge", False))
    message: str | None = result.get("message") or None
    reason: str = result.get("reason", "")

    # If guardrail said force_nudge, override LLM if it said no
    if guardrail.action == "force_nudge" and not should_nudge:
        logger.info("Proactive[%s]: guardrail force_nudge overriding model no-nudge", user_id)
        should_nudge = True
        target_domain = guardrail.details.get("target_domain") or guardrail.details.get("domain")
        target_result = None
        if target_domain:
            target_result = next((r for r in skill_results if r.domain == target_domain), None)
        if not message:
            if target_result and target_result.recommended_actions:
                message = target_result.recommended_actions[0]
            else:
                top = max(skill_results, key=lambda r: r.score)
                message = top.recommended_actions[0] if top.recommended_actions else "Hey, just checking in — how are you doing?"
        if target_domain and not result.get("primary_domain"):
            result["primary_domain"] = target_domain
        reason = guardrail.reason

    # ── 7. Same-day semantic dedupe & alternate concern selection ─────────
    local_date_key = now_local.date().isoformat()
    daily_sent_concerns = (
        ((checkin_doc or {}).get("daily_sent_concerns") or {}).get(local_date_key) or []
    )
    sent_concern_keys = set(daily_sent_concerns)
    daily_sent_topics = (
        ((checkin_doc or {}).get("daily_sent_topics") or {}).get(local_date_key) or []
    )
    sent_topic_keys = set(daily_sent_topics)

    selected_domain = (
        result.get("primary_domain")
        or guardrail.details.get("target_domain")
        or guardrail.details.get("domain")
    )
    if not selected_domain and skill_results:
        selected_domain = max(skill_results, key=lambda r: r.score).domain

    selected_skill = _find_skill_by_domain(skill_results, selected_domain)
    concern_key = _build_concern_key(selected_domain or "unknown", reason, selected_skill)
    selected_topic_key = ""

    if should_nudge and message and concern_key in sent_concern_keys:
        logger.info(
            "Proactive[%s]: suppress duplicate concern key=%s for date=%s, trying alternate",
            user_id,
            concern_key,
            local_date_key,
        )
        alt_topic = await _pick_alternate_topic_nudge(
            db=db,
            user_id=user_id,
            user_name=user_name,
            local_time_str=local_time_str,
            now_utc=now_utc,
            sent_topic_keys=sent_topic_keys,
        )
        if alt_topic is not None:
            selected_domain, message, reason, concern_key, selected_topic_key = alt_topic
            result["primary_domain"] = selected_domain
            logger.info("Proactive[%s]: switched to alternate topic concern key=%s", user_id, concern_key)
        else:
            alt_allowed_domains = None
            if selected_domain in _LOW_PRIORITY_DOMAINS:
                alt_allowed_domains = _LOW_PRIORITY_DOMAINS

            alt = _pick_alternate_concern(
                skill_results=skill_results,
                sent_concern_keys=sent_concern_keys,
                allowed_domains=alt_allowed_domains,
            )
            if alt is None:
                should_nudge = False
                message = None
                reason = "suppressed_duplicate_same_day"
                selected_domain = None
                concern_key = ""
            else:
                selected_domain, message, reason, concern_key = alt
                result["primary_domain"] = selected_domain
                logger.info(
                    "Proactive[%s]: switched to alternate concern domain=%s key=%s",
                    user_id,
                    selected_domain,
                    concern_key,
                )

    # ── 7. Deliver ──────────────────────────────────────────────────────────
    decision_data = {
        "should_nudge": should_nudge,
        "reason_code": reason,
        "message": message,
        "primary_domain": selected_domain or result.get("primary_domain"),
        "confidence": result.get("confidence", 0.0),
    }

    delivery_data = {"delivered": False}

    if should_nudge and message:
        await save_message(
            user_id=user_id,
            session_id="proactive",
            role="assistant",
            content=message,
            metadata={
                "type": "proactive",
                "reason": reason,
                "run_id": run_id,
                "primary_domain": selected_domain,
                "concern_key": concern_key,
                "topic_key": selected_topic_key or None,
            },
        )

        await queue_checkin_notification(user_id, message)

        # Build structured last_nudge with evidence summary and inputs hash
        evidence_summary = guardrails.build_evidence_summary(skill_results)
        decision_inputs_hash = guardrails.compute_decision_inputs_hash(skill_results)

        await db.advisor_checkins.update_one(
            {"user_id": user_id},
            {
                "$set": {"last_nudge": {
                    "reason": reason,
                    "nudged_at": now_utc.isoformat(),
                    "run_id": run_id,
                    "primary_domain": selected_domain or result.get("primary_domain"),
                    "evidence_summary": evidence_summary,
                    "decision_inputs_hash": decision_inputs_hash,
                    "concern_key": concern_key,
                }},
                "$addToSet": {
                    f"daily_sent_concerns.{local_date_key}": concern_key,
                    f"daily_sent_domains.{local_date_key}": selected_domain or "unknown",
                    f"daily_sent_topics.{local_date_key}": selected_topic_key or concern_key,
                },
                "$inc": {
                    f"daily_sent_count.{local_date_key}": 1,
                },
            },
            upsert=True,
        )

        delivery_data = {"delivered": True, "run_id": run_id, "reason": reason}
        logger.info(
            "Proactive[%s]: nudge delivered, reason=%s domain=%s concern_key=%s",
            user_id,
            reason,
            selected_domain or result.get("primary_domain"),
            concern_key,
        )
    else:
        logger.info("Proactive[%s]: no nudge, reason=%s", user_id, reason)

    # ── 8. Audit ────────────────────────────────────────────────────────────
    await audit.save_run_record(
        db, run_id, user_id, now_utc, skill_results, guardrail, decision_data, delivery_data,
    )

    return {"nudged": should_nudge, "message": message, "reason": reason}
