"""Proactive Advisor Service — skill-driven execution architecture.

New design (v3):
  1. All proactive-eligible assessment skills run in parallel each round via execution service.
  2. Skills are executed dynamically by reading markdown and generating code — no hardcoded assessments.
  3. Raw execution results are persisted in proactive_information_rounds collection.
  4. A proactive checklist is assembled before decision: manual priorities + today's dayprint + enabled skills.
  5. LLM gets: current round results + last round results + today's dayprint + last nudge + proactive checklist.
  5. LLM decides whether to nudge (no deterministic guardrails, no hardcoded scores).
  6. Audit records persisted for observability.

Skills are flat and unsorted by domain — all assessment skills run, sorted by priority.
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
from ..core.datetime_utils import format_utc_datetime, format_utc_datetime_with_ms
from ..core.database import get_database
from ..core.credential_utils import resolve_credential_key
from ..models.proactive import ProactiveSkillData
from ..services.capability_service import get_user_enabled_capability_ids
from ..services.chat_history_service import save_message
from ..services.notification_service import queue_checkin_notification
from ..services.skill_registry_service import skill_registry, SkillIndexItem
from . import proactive_audit_service as audit
from .llm_client import chat_completion
from .proactive_skill_selector import select_proactive_skills

logger = logging.getLogger(__name__)

_DECISION_MODEL = settings.PALEBLUEDOT_MODEL

# Capabilities whose data we can assess directly from MongoDB
_INTERNAL_CAP_ID = "lumie_internal_data"


# ── Skill execution ────────────────────────────────────────────────────────

async def _load_proactive_credential(db, user_id: str, skill: SkillIndexItem) -> dict | None:
    """Load credential for a skill from the database.

    For lumie_internal_data skills, credentials are auto-generated on capability enable.
    Returns None if credential is missing or has no ping token.
    """
    if not skill.requires_credentials:
        return None

    # Resolve the credential key (handles shared_credential_id)
    credential_key = resolve_credential_key(skill)

    # Look up credential by user_id + credential key
    cred = await db.advisor_skill_credentials.find_one(
        {"user_id": user_id, "skill_id": credential_key},
        {"_id": 0}
    )

    if not cred:
        logger.warning("Skill %s requires credential but none found for user %s", skill.skill_id, user_id)
        return None

    # For skills that require ping validation, ensure ping exists
    if cred.get("ping"):
        return cred

    # Credential exists but no ping - cannot execute
    logger.warning("Skill %s has credential but missing ping for user %s", skill.skill_id, user_id)
    return None


async def _run_skill_for_proactive(
    db,
    user_id: str,
    skill: SkillIndexItem,
    user_context: dict,
) -> ProactiveSkillData:
    """Run one skill via execution service, return raw data."""
    from .execution_service import create_execution_job, run_execution_job

    try:
        skill_full_text = skill_registry.load_skill_full_text(skill.skill_id)
        credential = await _load_proactive_credential(db, user_id, skill)

        # If credential is required but missing, skip execution
        if skill.requires_credentials and not credential:
            logger.info("Skill %s skipped: required credential not found or missing ping", skill.skill_id)
            return ProactiveSkillData(
                skill_id=skill.skill_id,
                domain=skill.proactive_domain or "unknown",
                priority=skill.proactive_priority,
                execution_status="no_data",
                summary="Credential not configured",
            )

        job_id = await create_execution_job(
            user_id=user_id,
            session_id="proactive",
            skill=skill,
            prompt=f"[Proactive check] {skill.summary}",
        )

        await run_execution_job(
            job_id=job_id,
            skill=skill,
            skill_full_text=skill_full_text or "",
            credential=credential,
            user_context=user_context,
        )

        job_doc = await db.execution_jobs.find_one({"job_id": job_id}, {"_id": 0})
        if not job_doc:
            return ProactiveSkillData(
                skill_id=skill.skill_id,
                domain=skill.proactive_domain or "unknown",
                priority=skill.proactive_priority,
                execution_status="failed",
                summary="Job record not found",
            )

        result = job_doc.get("result") or {}
        status = job_doc.get("status", "failed")

        return ProactiveSkillData(
            skill_id=skill.skill_id,
            domain=skill.proactive_domain or "unknown",
            priority=skill.proactive_priority,
            execution_status=status,
            data=result.get("data") or {},
            summary=result.get("summary", ""),
        )
    except Exception as e:
        logger.error("Skill %s failed for user=%s: %s", skill.skill_id, user_id, e, exc_info=True)
        return ProactiveSkillData(
            skill_id=skill.skill_id,
            domain=skill.proactive_domain or "unknown",
            priority=skill.proactive_priority,
            execution_status="failed",
            summary=f"Execution error: {str(e)[:100]}",
        )


async def _run_all_skills_for_proactive(
    db, user_id: str, skills: list[SkillIndexItem], user_context: dict
) -> list[ProactiveSkillData]:
    """Run all selected skills concurrently with fault isolation."""
    tasks = [_run_skill_for_proactive(db, user_id, skill, user_context) for skill in skills]
    results = await asyncio.gather(*tasks, return_exceptions=True)
    out = []
    for skill, result in zip(skills, results):
        if isinstance(result, Exception):
            logger.error("Skill %s exception: %s", skill.skill_id, result)
            out.append(ProactiveSkillData(
                skill_id=skill.skill_id,
                domain=skill.proactive_domain or "unknown",
                priority=skill.proactive_priority,
                execution_status="failed",
                summary=f"Exception: {str(result)[:100]}",
            ))
        else:
            out.append(result)
    return out


async def _run_skills_with_dependencies(
    db,
    user_id: str,
    skills: list[SkillIndexItem],
    user_context: dict,
) -> list[ProactiveSkillData]:
    """Run skills respecting DAG dependencies.

    Skills with dependencies are organized into tiers:
    - Tier 0: Skills with no dependencies (run in parallel)
    - Tier N: Skills whose all dependencies are in tiers 0..N-1

    Returns: List of ProactiveSkillData (one per original skill)
    """
    from .execution_service import _build_skill_dag, _topological_sort

    # Build DAG and compute tiers
    try:
        dag = await _build_skill_dag(skills)
        tiers = await _topological_sort(dag)
    except ValueError as e:
        logger.error("DAG error: %s", e)
        # Fall back to parallel execution (ignore dependencies)
        return await _run_all_skills_for_proactive(db, user_id, skills, user_context)

    results_by_skill_id = {}
    all_results = []

    # Execute each tier
    for tier_idx, tier_skill_ids in enumerate(tiers):
        tier_skills = [s for s in skills if s.skill_id in tier_skill_ids]
        logger.info(f"Proactive[{user_id}]: Tier {tier_idx} ({len(tier_skills)} skills)")

        # Run all skills in tier in parallel
        tasks = [
            _run_skill_for_proactive_with_context(
                db, user_id, skill, user_context,
                context=results_by_skill_id,
            )
            for skill in tier_skills
        ]
        tier_results = await asyncio.gather(*tasks, return_exceptions=True)

        # Collect results
        for skill, result in zip(tier_skills, tier_results):
            if isinstance(result, Exception):
                logger.error("Skill %s exception in tier %d: %s", skill.skill_id, tier_idx, result)
                result_data = ProactiveSkillData(
                    skill_id=skill.skill_id,
                    domain=skill.proactive_domain or "unknown",
                    priority=skill.proactive_priority,
                    execution_status="failed",
                    summary=f"Exception: {str(result)[:100]}",
                )
            else:
                result_data = result

            results_by_skill_id[skill.skill_id] = result_data
            all_results.append(result_data)

    return all_results


async def _run_skill_for_proactive_with_context(
    db,
    user_id: str,
    skill: SkillIndexItem,
    user_context: dict,
    context: dict = None,
) -> ProactiveSkillData:
    """Run one skill via execution service with access to previous results.

    Args:
        context: Dict of skill_id -> ProactiveSkillData from prior tiers.
    """
    from .execution_service import create_execution_job, run_execution_job

    try:
        skill_full_text = skill_registry.load_skill_full_text(skill.skill_id)
        credential = await _load_proactive_credential(db, user_id, skill)

        # If credential is required but missing, skip execution
        if skill.requires_credentials and not credential:
            logger.info("Skill %s skipped: required credential not found or missing ping", skill.skill_id)
            return ProactiveSkillData(
                skill_id=skill.skill_id,
                domain=skill.proactive_domain or "unknown",
                priority=skill.proactive_priority,
                execution_status="no_data",
                summary="Credential not configured",
            )

        job_id = await create_execution_job(
            user_id=user_id,
            session_id="proactive",
            skill=skill,
            prompt=f"[Proactive check] {skill.summary}",
        )

        await run_execution_job(
            job_id=job_id,
            skill=skill,
            skill_full_text=skill_full_text or "",
            credential=credential,
            user_context=user_context,
            previous_results=context,  # ← Pass previous tier results
        )

        job_doc = await db.execution_jobs.find_one({"job_id": job_id}, {"_id": 0})
        if not job_doc:
            return ProactiveSkillData(
                skill_id=skill.skill_id,
                domain=skill.proactive_domain or "unknown",
                priority=skill.proactive_priority,
                execution_status="failed",
                summary="Job record not found",
            )

        result = job_doc.get("result") or {}
        status = job_doc.get("status", "failed")

        return ProactiveSkillData(
            skill_id=skill.skill_id,
            domain=skill.proactive_domain or "unknown",
            priority=skill.proactive_priority,
            execution_status=status,
            data=result.get("data") or {},
            summary=result.get("summary", ""),
        )
    except Exception as e:
        logger.error("Skill %s failed for user=%s: %s", skill.skill_id, user_id, e, exc_info=True)
        return ProactiveSkillData(
            skill_id=skill.skill_id,
            domain=skill.proactive_domain or "unknown",
            priority=skill.proactive_priority,
            execution_status="failed",
            summary=f"Execution error: {str(e)[:100]}",
        )


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
    skill_data: ProactiveSkillData | None,
) -> str:
    """Build a semantic concern fingerprint (not wording-based)."""
    # For v3, concern key is simpler: just based on domain and reason
    payload = {
        "domain": _canonicalize(domain),
        "reason": _canonicalize(_reason),
    }
    raw = json.dumps(payload, sort_keys=True, ensure_ascii=True)
    digest = hashlib.sha1(raw.encode("utf-8")).hexdigest()[:16]
    return f"{payload['domain']}:{digest}"


def _find_skill_by_domain(skill_data_list: list[ProactiveSkillData], domain: str | None) -> ProactiveSkillData | None:
    if not domain:
        return None
    for s in skill_data_list:
        if s.domain == domain:
            return s
    return None


def _normalize_manual_items(raw_items: list) -> list[dict]:
    """Normalize manual checklist entries to dict records."""
    out: list[dict] = []
    for item in raw_items or []:
        if isinstance(item, str):
            text = item.strip()
            if not text:
                continue
            out.append({"item_id": str(uuid.uuid4()), "text": text, "status": "pending"})
        elif isinstance(item, dict):
            text = str(item.get("text", "")).strip()
            if not text:
                continue
            out.append({
                "item_id": str(item.get("item_id") or uuid.uuid4()),
                "text": text,
                "status": str(item.get("status") or "pending"),
                "last_run_at": item.get("last_run_at"),
                "last_result": item.get("last_result"),
                "retry_count": int(item.get("retry_count") or 0),
            })
    return out[:20]


async def _read_manual_checklist_items(db, user_id: str, profile: dict) -> list[dict]:
    """Read user-defined proactive priorities for checklist item #1."""
    items: list[dict] = []

    checklist_doc = await db.proactive_checklists.find_one({"user_id": user_id}, {"_id": 0})
    if checklist_doc:
        raw_items = checklist_doc.get("manual_items") if isinstance(checklist_doc.get("manual_items"), list) else []
        items = _normalize_manual_items(raw_items)

    # Backward-compatible fallback in profile for local testing/gradual rollout
    profile_items = profile.get("proactive_manual_items")
    if isinstance(profile_items, list):
        for item in profile_items:
            if isinstance(item, str):
                t = item.strip()
                if t and not any((x.get("text") == t) for x in items):
                    items.append({"item_id": str(uuid.uuid4()), "text": t, "status": "pending"})

    return items[:20]


def _build_checklist(
    manual_items: list[dict],
    today_dayprint: dict | None,
    selected_skills: list[SkillIndexItem],
    manual_instruction_results: list[dict] | None = None,
) -> dict:
    """Build normalized proactive checklist payload for this run."""
    return {
        "manual_items": manual_items,
        "today_dayprint": {
            "date": (today_dayprint or {}).get("date"),
            "summary": (today_dayprint or {}).get("summary", ""),
            "events_count": len((today_dayprint or {}).get("events", [])),
        } if today_dayprint else None,
        "enabled_skills": [
            {
                "skill_id": s.skill_id,
                "domain": s.proactive_domain or "unknown",
                "priority": s.proactive_priority,
                "title": s.title,
            }
            for s in selected_skills
        ],
        "manual_instruction_results": manual_instruction_results or [],
    }


def _tokenize_for_match(text: str) -> set[str]:
    base = _canonicalize(text)
    return {t for t in base.split(" ") if len(t) >= 4}


def _build_preserve_clause(summary: str) -> str:
    """Turn checklist execution summary into compact sentence for final nudge."""
    s = (summary or "").strip()
    if not s:
        return ""
    # Keep first sentence only, avoid oversized message.
    first = s.split(". ")[0].strip()
    if len(first) > 96:
        first = first[:96].rstrip() + "..."
    return first


def _ensure_checklist_preserved_in_message(
    message: str | None,
    manual_instruction_results: list[dict],
) -> str | None:
    """Enforce preserving must_preserve checklist instructions in final nudge."""
    if not message:
        return message
    out = message
    out_tokens = _tokenize_for_match(out)
    for r in manual_instruction_results:
        if not bool(r.get("must_preserve")):
            continue
        if (r.get("status") or "") != "success":
            continue
        src_summary = (r.get("summary") or "").strip()
        if not src_summary:
            continue
        src_tokens = _tokenize_for_match(src_summary)
        # Preserve if at least one meaningful token overlaps.
        preserved = bool(out_tokens.intersection(src_tokens))
        if preserved:
            continue
        clause = _build_preserve_clause(src_summary)
        if not clause:
            continue
        # Append concise actionable clause.
        if len(out) + len(clause) + 2 <= 240:
            out = f"{out} {clause}"
        else:
            # Replace tail to keep reminder present in capped length.
            room = max(0, 240 - len(out) - 5)
            out = f"{out[:room].rstrip()} ... {clause[:80]}"
        out_tokens = _tokenize_for_match(out)
    return out


async def _wait_for_execution_job_terminal(
    db,
    job_id: str,
    timeout_seconds: int = 180,
) -> dict:
    """Poll one execution job until terminal state or timeout."""
    deadline = datetime.now(timezone.utc) + timedelta(seconds=timeout_seconds)
    while datetime.now(timezone.utc) < deadline:
        job = await db.execution_jobs.find_one({"job_id": job_id}, {"_id": 0})
        if not job:
            return {"status": "failed", "error": "job_not_found"}
        status = job.get("status")
        if status in {"success", "failed", "cancelled"}:
            return job
        await asyncio.sleep(2)
    return {"status": "timeout", "error": f"job_timeout_after_{timeout_seconds}s"}


async def _execute_manual_checklist_instructions(
    db,
    user_id: str,
    manual_items: list[dict],
) -> tuple[list[dict], list[dict]]:
    """Execute each manual checklist item through advisor orchestrator flow."""
    from . import advisor_orchestrator

    now_str = format_utc_datetime(datetime.now(timezone.utc))
    updated_items: list[dict] = []
    instruction_results: list[dict] = []

    for item in manual_items:
        item_id = str(item.get("item_id") or uuid.uuid4())
        text = str(item.get("text", "")).strip()
        if not text:
            continue

        logger.info("Proactive[%s]: executing manual checklist item %s", user_id, item_id)
        result_doc = {
            "item_id": item_id,
            "text": text,
            "started_at": now_str,
            "path": "advisor_chat_equivalent",
            "result_type": None,
            "status": "pending",
            "summary": "",
            "job_id": None,
            "priority": item.get("priority") or "high",
            "must_preserve": bool(item.get("must_preserve", True)),
            "nudge_directive": item.get("nudge_directive") or "force_include",
        }

        try:
            result = await advisor_orchestrator.handle_chat(
                user_id=user_id,
                message=text,
                history=[],
                session_id="proactive",
            )
            result_doc["result_type"] = result.get("type")
            result_doc["summary"] = (result.get("reply") or "")[:240]

            if result.get("type") == "execution" and result.get("job_id"):
                job_id = result.get("job_id")
                result_doc["job_id"] = job_id
                job = await _wait_for_execution_job_terminal(db, job_id, timeout_seconds=180)
                result_doc["status"] = job.get("status", "failed")
                if job.get("status") == "success":
                    result_doc["summary"] = ((job.get("result") or {}).get("summary") or result_doc["summary"])[:240]
                else:
                    result_doc["summary"] = (job.get("error") or result_doc["summary"] or "execution_failed")[:240]
            else:
                # direct/guidance is still a completed instruction-handling turn
                result_doc["status"] = "success" if result.get("type") in {"direct", "guidance"} else "failed"
        except Exception as e:
            result_doc["status"] = "failed"
            result_doc["summary"] = f"instruction_error: {str(e)[:180]}"

        result_doc["finished_at"] = format_utc_datetime(datetime.now(timezone.utc))
        instruction_results.append(result_doc)

        next_item = {
            **item,
            "item_id": item_id,
            "text": text,
            "status": "done" if result_doc["status"] == "success" else "failed",
            "last_run_at": result_doc["finished_at"],
            "last_result": result_doc["summary"],
            "retry_count": int(item.get("retry_count") or 0) + (0 if result_doc["status"] == "success" else 1),
            "priority": result_doc.get("priority", "high"),
            "must_preserve": result_doc.get("must_preserve", True),
            "nudge_directive": result_doc.get("nudge_directive", "force_include"),
        }
        updated_items.append(next_item)

        logger.info(
            "Proactive[%s]: manual checklist item %s finished status=%s type=%s",
            user_id,
            item_id,
            result_doc["status"],
            result_doc.get("result_type"),
        )

    return updated_items, instruction_results


# ── LLM decision prompt ────────────────────────────────────────────────────

def _build_decision_prompt(
    user_name: str,
    role: str,
    icd10: str,
    local_time_str: str,
    skill_data: list[ProactiveSkillData],
    last_round_results: list[dict],
    today_dayprint: dict | None,
    proactive_checklist: dict | None,
    last_nudge_str: str,
) -> tuple[str, str]:
    """Build compact system + user prompt from raw skill execution data.

    Args:
        user_name, role, icd10, local_time_str: user context
        skill_data: current round skill execution results
        last_round_results: previous round results (for comparison)
        today_dayprint: today's dayprint data (if available)
        last_nudge_str: description of last nudge
    """
    # Serialize current round skill data with priority embedded
    current_results_for_llm = []
    for s in skill_data:
        current_results_for_llm.append({
            "skill_id": s.skill_id,
            "domain": s.domain,
            "priority": s.priority,
            "execution_status": s.execution_status,
            "summary": s.summary,
            "data": s.data,
        })

    condition_str = f" with condition code {icd10}" if icd10 else ""

    system_prompt = (
        f"You are a proactive health advisor for {user_name}, a {role}{condition_str}.\n"
        f"Current local time: {local_time_str}.\n\n"
        "You are in PROACTIVE MODE. You are reviewing skill execution data to decide "
        "whether to send a contextual check-in notification.\n\n"
        "CRITICAL RULE: DO NOT repeat any topic (domain/subject) mentioned in the last 6 hours "
        "UNLESS the current data shows SIGNIFICANT CHANGE from when it was last mentioned.\n\n"
        "WHAT COUNTS AS 'SIGNIFICANT CHANGE':\n"
        "- Numeric change >15-20% (e.g., sleep 5h→3h, steps 8k→5k, temp 24°C→26°C)\n"
        "- Status/threshold crossing (e.g., goes from 'ok' to 'concerning' or vice versa)\n"
        "- New concerning pattern (e.g., was stable, now declining)\n\n"
        "DECISION POLICY:\n"
        "1. Review all current skill data. Higher priority values indicate more important skills.\n"
        "2. Focus on data from successfully-executed skills (execution_status='success').\n"
        "3. Look for concrete concerns, patterns, or insights worth mentioning (urgent OR routine check-ins).\n"
        "4. Include positive signals and good news alongside concerns — balanced perspective matters.\n"
        "5. Consider trends from the previous round (if available).\n"
        "6. Check today's dayprint and proactive checklist for context.\n"
        "7. Send nudges regularly (not just emergencies) to build supportive, ongoing connection.\n"
        "8. Compare recent nudge evidence to current data. Only nudge if significant change detected.\n"
        "9. Prefer personalized, grounded insights over vague ones. Include specific numbers (temperature, duration, percentage).\n\n"
        "10. CHECKLIST PRIORITY RULE: Any manual_instruction_results item with "
        "must_preserve=true and status=success must be reflected in the final message.\n\n"
        f"RECENT NUDGE HISTORY (last 6 hours):\n{last_nudge_str}\n\n"
        "Respond with valid JSON only — no markdown, no explanation:\n"
        '{"should_nudge": true|false, "message": "<friendly check-in message ≤120 chars, or null>", '
        '"reason": "<brief internal reason>", "primary_domain": "<domain>", "confidence": 0.0-1.0}'
    )

    # Build user message with assessment results + context
    user_parts = ["=== CURRENT ROUND ASSESSMENTS ===\n"]
    user_parts.append(json.dumps(current_results_for_llm, indent=2))

    if last_round_results:
        user_parts.append("\n=== PREVIOUS ROUND ASSESSMENTS (for comparison) ===\n")
        user_parts.append(json.dumps(last_round_results, indent=2))

    if today_dayprint:
        user_parts.append("\n=== TODAY'S DAYPRINT ===\n")
        dayprint_summary = {
            "date": today_dayprint.get("date"),
            "summary": today_dayprint.get("summary", ""),
            "events_count": len(today_dayprint.get("events", [])),
        }
        user_parts.append(json.dumps(dayprint_summary, indent=2))

    if proactive_checklist:
        user_parts.append("\n=== PROACTIVE CHECKLIST ===\n")
        user_parts.append(json.dumps(proactive_checklist, indent=2))

    user_parts.append("\n\nBased on these assessments and context, should I reach out to the user?\n\n"
                      "GUIDANCE FOR YOUR MESSAGE:\n"
                      "- Weave together insights from multiple domains (e.g., sleep + activity + energy) in a single message.\n"
                      "- Include positive signals and good news alongside concerns (e.g., 'Home energy is looking great, AND let's check on sleep').\n"
                      "- Regular check-ins on routine topics are welcome — you don't need to wait for urgent issues.\n"
                      "- A balanced message that mentions both strengths and areas to focus on is more supportive than doom-focused.\n"
                      "- ALWAYS include specific numbers and metrics instead of vague language:\n"
                      "  - Say '6.4k steps' not 'good activity'\n"
                      "  - Say '25.8°C' not 'a bit warm'\n"
                      "  - Say '5.5 hours sleep' not 'short sleep'\n"
                      "  - Say '35 active minutes' not 'some exercise'\n"
                      "- Show the actual data from the skill results in your message.")
    user_message = "\n".join(user_parts)

    return system_prompt, user_message


# ── Main entry point ────────────────────────────────────────────────────────

async def run_proactive_check(user_id: str) -> dict:
    """Run a proactive advisor check for a single user.

    New architecture:
    - All proactive-eligible assessment skills run in parallel
    - Information rounds are persisted for trend analysis
    - A proactive checklist (manual priorities + today's dayprint + enabled skills)
      is assembled before decision.
    - LLM gets current round + last round + today's dayprint + last nudge + checklist
    - No deterministic guardrails; LLM decides everything

    Returns:
        {
            "nudged": bool,
            "message": str | None,
            "reason": str,
        }
    """
    run_id = str(uuid.uuid4())
    round_id = str(uuid.uuid4())
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
    logger.info(
        "Proactive[%s]: profile loaded role=%s tz=%s icd10=%s",
        user_id,
        role,
        user_timezone,
        icd10 or "none",
    )

    # ── 2. Enabled capabilities ─────────────────────────────────────────────
    enabled_cap_ids = await get_user_enabled_capability_ids(user_id)
    if not enabled_cap_ids:
        logger.info("Proactive[%s]: no enabled capabilities — skip", user_id)
        return {"nudged": False, "message": None, "reason": "no_enabled_capabilities"}

    if _INTERNAL_CAP_ID not in enabled_cap_ids:
        logger.info("Proactive[%s]: lumie_internal_data not enabled — skip", user_id)
        return {"nudged": False, "message": None, "reason": "no_internal_data_capability"}

    logger.info("Proactive[%s]: run_id=%s round_id=%s capabilities=%s", user_id, run_id, round_id, sorted(enabled_cap_ids))

    # ── 2.5 Build proactive checklist context ─────────────────────────────
    manual_items = await _read_manual_checklist_items(db, user_id, profile)
    logger.info("Proactive[%s]: manual checklist items=%d", user_id, len(manual_items))

    today_str = now_local.date().isoformat()
    today_dayprint = await db.dayprints.find_one(
        {"user_id": user_id, "date": today_str},
        {"_id": 0},
    )
    if today_dayprint:
        logger.info("Proactive[%s]: found today's dayprint with %d events", user_id, len(today_dayprint.get("events", [])))

    # ── 3. Select and run proactive skills (enabled capabilities only) ──
    selected_skills = select_proactive_skills(enabled_cap_ids)
    if not selected_skills:
        logger.warning("Proactive[%s]: no proactive skills selected", user_id)
        return {"nudged": False, "message": None, "reason": "no_proactive_skills_selected"}

    logger.info(
        "Proactive[%s]: selected proactive skills=%s",
        user_id,
        [(s.skill_id, s.proactive_domain, s.proactive_priority) for s in selected_skills],
    )

    manual_items_updated, manual_instruction_results = await _execute_manual_checklist_instructions(
        db=db,
        user_id=user_id,
        manual_items=manual_items,
    )
    if manual_items_updated:
        await db.proactive_checklists.update_one(
            {"user_id": user_id},
            {
                "$set": {
                    "user_id": user_id,
                    "manual_items": manual_items_updated,
                    "updated_at": format_utc_datetime(now_utc),
                }
            },
            upsert=True,
        )
        logger.info(
            "Proactive[%s]: manual checklist execution complete items=%d",
            user_id,
            len(manual_instruction_results),
        )

    proactive_checklist = _build_checklist(
        manual_items=manual_items_updated or manual_items,
        today_dayprint=today_dayprint,
        selected_skills=selected_skills,
        manual_instruction_results=manual_instruction_results,
    )
    logger.info(
        "Proactive[%s]: checklist built manual=%d dayprint=%s enabled_skills=%d",
        user_id,
        len(proactive_checklist.get("manual_items") or []),
        "yes" if proactive_checklist.get("today_dayprint") else "no",
        len(proactive_checklist.get("enabled_skills") or []),
    )

    # Build user context for execution
    user_context = {
        "name": user_name,
        "role": role,
        "icd10_code": icd10,
        "timezone": user_timezone,
        "advisor_name": "Lumie",
    }

    # Run all skills with DAG dependency resolution (fault-isolated)
    skill_data = await _run_skills_with_dependencies(db, user_id, selected_skills, user_context)

    logger.info(
        "Proactive[%s]: %d skill results: %s",
        user_id,
        len(skill_data),
        [(s.skill_id, s.execution_status) for s in skill_data],
    )

    if not skill_data:
        logger.warning("Proactive[%s]: all skills failed — skip", user_id)
        return {"nudged": False, "message": None, "reason": "all_skills_failed"}

    # ── 3.5. Save information round for this proactive run ─────────────────
    logger.info("Proactive[%s]: saving information round round_id=%s", user_id, round_id)
    await audit.save_round_record(
        db,
        round_id,
        user_id,
        now_utc,
        skill_data,
        checklist=proactive_checklist,
    )

    # ── 4. Fetch nudge history (last 6 hours), last round, and today's dayprint
    checkin_doc = await db.advisor_checkins.find_one({"user_id": user_id})
    last_nudge = (checkin_doc or {}).get("last_nudge")

    # Build nudge history from last 6 hours
    six_hours_ago = now_utc - timedelta(hours=6)
    nudge_history = (checkin_doc or {}).get("nudge_history", [])
    recent_nudges = [
        n for n in nudge_history
        if datetime.fromisoformat(n.get("nudged_at", "2000-01-01")) > six_hours_ago
    ]

    if recent_nudges:
        recent_nudges_str = "\n".join([
            f"  - {n.get('domain', 'unknown')}: {n.get('reason', '')} (evidence: {n.get('evidence_summary', 'none')})"
            for n in recent_nudges
        ])
        last_nudge_str = f"Recent nudges (last 6 hours):\n{recent_nudges_str}\n\nIf the current data shows SIGNIFICANT CHANGE from the evidence above, you MAY nudge again."
    elif last_nudge:
        nudged_at_raw = last_nudge.get("nudged_at", "")
        try:
            nudged_at_dt = datetime.fromisoformat(nudged_at_raw)
            if nudged_at_dt.tzinfo is None:
                nudged_at_dt = nudged_at_dt.replace(tzinfo=timezone.utc)
            minutes_ago = int((now_utc - nudged_at_dt).total_seconds() / 60)
            last_nudge_str = (
                f"Last nudge sent {minutes_ago} minutes ago. "
                f"Reason: {last_nudge.get('reason', 'unknown')}. "
                f"Domain: {last_nudge.get('primary_domain', 'unknown')}."
            )
        except Exception:
            last_nudge_str = "Previous nudge context available."
    else:
        last_nudge_str = "No nudge has been sent yet."

    logger.info(
        "Proactive[%s]: last_nudge reason=%s domain=%s",
        user_id,
        last_nudge.get("reason", "none") if last_nudge else "none",
        last_nudge.get("primary_domain", "none") if last_nudge else "none",
    )

    # Fetch last round for trend comparison
    last_round_doc = await audit.get_last_round(db, user_id)
    last_round_results = []
    if last_round_doc:
        last_round_results = [
            {
                "skill_id": r.get("skill_id"),
                "domain": r.get("domain"),
                "status": r.get("execution_status"),
                "priority": r.get("priority"),
                "summary": r.get("summary"),
                "data": r.get("data"),
            }
            for r in last_round_doc.get("skill_data", [])
        ]
        logger.info("Proactive[%s]: found last round with %d results", user_id, len(last_round_results))

    # ── 5. Build prompt and call LLM ────────────────────────────────────────
    system_prompt, user_message = _build_decision_prompt(
        user_name=user_name,
        role=role,
        icd10=icd10,
        local_time_str=local_time_str,
        skill_data=skill_data,
        last_round_results=last_round_results,
        today_dayprint=today_dayprint,
        proactive_checklist=proactive_checklist,
        last_nudge_str=last_nudge_str,
    )

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
        }
        await audit.save_run_record(db, run_id, user_id, now_utc, skill_data, error_decision, None, round_id)
        return {"nudged": False, "message": None, "reason": f"llm_error: {e}"}

    manual_results = proactive_checklist.get("manual_instruction_results") if proactive_checklist else []
    should_nudge: bool = bool(result.get("should_nudge", False))
    message: str | None = result.get("message") or None
    message = _ensure_checklist_preserved_in_message(message, manual_results)
    reason: str = result.get("reason", "")

    must_preserve_success = [
        r for r in manual_results
        if bool(r.get("must_preserve")) and (r.get("status") == "success")
    ]
    if not should_nudge and must_preserve_success:
        should_nudge = True
        if not message:
            message = _build_preserve_clause(must_preserve_success[0].get("summary") or "")
        reason = f"checklist_must_preserve_override:{must_preserve_success[0].get('item_id')}"
    logger.info(
        "Proactive[%s]: decision parsed should_nudge=%s domain=%s confidence=%s",
        user_id,
        should_nudge,
        result.get("primary_domain"),
        result.get("confidence", 0.0),
    )

    # ── 6. Time-based dedupe (6-hour cooldown per domain) ────────────────
    local_date_key = now_local.date().isoformat()
    daily_sent_concerns = (
        ((checkin_doc or {}).get("daily_sent_concerns") or {}).get(local_date_key) or []
    )
    sent_concern_keys = set(daily_sent_concerns)

    # Get nudge history for 6-hour cooldown check
    nudge_history = checkin_doc.get("nudge_history", []) if checkin_doc else []
    six_hours_ago = now_utc - timedelta(hours=6)

    selected_domain = result.get("primary_domain")
    if not selected_domain and skill_data:
        selected_domain = max(skill_data, key=lambda s: s.priority).domain

    selected_skill_data = _find_skill_by_domain(skill_data, selected_domain)
    concern_key = _build_concern_key(selected_domain or "unknown", reason, selected_skill_data)

    # Check for duplicate: same-day concern OR same domain within 6 hours
    is_duplicate = should_nudge and message and (
        concern_key in sent_concern_keys or
        any(h.get("domain") == selected_domain and
            datetime.fromisoformat(h.get("nudged_at", "2000-01-01")) > six_hours_ago
            for h in nudge_history)
    )
    if is_duplicate:
        logger.info(
            "Proactive[%s]: suppress duplicate concern key=%s for date=%s",
            user_id,
            concern_key,
            local_date_key,
        )

    # If no nudge OR duplicate: finalize as no nudge (no topic fallback)
    if not should_nudge or is_duplicate:
        should_nudge = False
        message = None
        if is_duplicate:
            reason = "duplicate_concern_or_domain_in_6h"
        elif not reason:
            reason = "llm_decided_no_nudge"
        selected_domain = None
        concern_key = ""
        logger.info("Proactive[%s]: no nudge after decision/dedupe, reason=%s", user_id, reason)

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
            },
        )

        await queue_checkin_notification(user_id, message)

        # Build structured last_nudge for next run context
        evidence_summary = {
            s.domain: {
                "execution_status": s.execution_status,
                "priority": s.priority,
                "summary": s.summary,
            }
            for s in skill_data
        }

        await db.advisor_checkins.update_one(
            {"user_id": user_id},
            {
                "$set": {"last_nudge": {
                    "reason": reason,
                    "nudged_at": format_utc_datetime(now_utc),
                    "run_id": run_id,
                    "primary_domain": selected_domain or result.get("primary_domain"),
                    "evidence_summary": evidence_summary,
                }},
                "$push": {
                    "nudge_history": {
                        "domain": selected_domain or "unknown",
                        "nudged_at": format_utc_datetime(now_utc),
                        "reason": reason,
                        "evidence_summary": evidence_summary,
                        "run_id": run_id,
                    }
                },
                "$addToSet": {
                    f"daily_sent_concerns.{local_date_key}": concern_key,
                    f"daily_sent_domains.{local_date_key}": selected_domain or "unknown",
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
        db, run_id, user_id, now_utc, skill_data, decision_data, delivery_data, round_id,
    )

    return {"nudged": should_nudge, "message": message, "reason": reason}
