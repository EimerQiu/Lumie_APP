"""Proactive Advisor Service — skill-driven execution architecture.

New design (v3):
  1. All proactive-eligible assessment skills run in parallel each round via execution service.
  2. Skills are executed dynamically by reading markdown and generating code — no hardcoded assessments.
  3. Raw execution results are persisted in proactive_information_rounds collection.
  4. LLM gets: current round results + last round results + today's dayprint + last nudge.
  5. LLM decides whether to nudge (no deterministic guardrails, no hardcoded scores).
  6. If LLM says no: fall back to LLM-ranked 15-day dayprint topics.
  7. Audit records persisted for observability.

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
from ..core.database import get_database
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
    """Load credential for a skill, or provision lumie_internal_data automatically."""
    if not skill.requires_credentials:
        return None
    cred_id = skill.shared_credential_id
    if cred_id:
        return await db.advisor_skill_credentials.find_one(
            {"credential_id": cred_id, "user_id": user_id}, {"_id": 0}
        )
    # lumie_internal_data: auto-provision (no external credential needed)
    return {"type": "lumie_internal_data"}


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
            max_tokens=1000,
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
    skill_data: list[ProactiveSkillData],
    last_round_results: list[dict],
    today_dayprint: dict | None,
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
        "whether to send a nudge notification.\n\n"
        "DECISION POLICY:\n"
        "1. Review all current skill data. Higher priority values indicate more important skills.\n"
        "2. Focus on data from successfully-executed skills (execution_status='success').\n"
        "3. Look for concrete concerns in the raw data (not scores — use your judgment).\n"
        "4. Consider trends from the previous round (if available).\n"
        "5. Check today's dayprint for context (if available).\n"
        "6. Only nudge if genuinely worth addressing NOW. Avoid minor or speculative concerns.\n"
        "7. Prefer personalized, grounded concerns over vague ones.\n\n"
        f"Nudge history: {last_nudge_str}\n\n"
        "Respond with valid JSON only — no markdown, no explanation:\n"
        '{"should_nudge": true|false, "message": "<friendly nudge message ≤120 chars, or null>", '
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

    user_parts.append("\n\nBased on these assessments and context, should I reach out to the user?")
    user_message = "\n".join(user_parts)

    return system_prompt, user_message


# ── Main entry point ────────────────────────────────────────────────────────

async def run_proactive_check(user_id: str) -> dict:
    """Run a proactive advisor check for a single user.

    New architecture:
    - All proactive-eligible assessment skills run in parallel
    - Information rounds are persisted for trend analysis
    - LLM gets current round + last round + today's dayprint + last nudge
    - No deterministic guardrails; LLM decides everything
    - If LLM says no nudge: fallback to LLM-ranked 15-day topic selection

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

    # ── 2. Enabled capabilities ─────────────────────────────────────────────
    enabled_cap_ids = await get_user_enabled_capability_ids(user_id)
    if not enabled_cap_ids:
        logger.info("Proactive[%s]: no enabled capabilities — skip", user_id)
        return {"nudged": False, "message": None, "reason": "no_enabled_capabilities"}

    if _INTERNAL_CAP_ID not in enabled_cap_ids:
        logger.info("Proactive[%s]: lumie_internal_data not enabled — skip", user_id)
        return {"nudged": False, "message": None, "reason": "no_internal_data_capability"}

    logger.info("Proactive[%s]: run_id=%s round_id=%s capabilities=%s", user_id, run_id, round_id, sorted(enabled_cap_ids))

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

    # Build user context for execution
    user_context = {
        "name": user_name,
        "role": role,
        "icd10_code": icd10,
        "timezone": user_timezone,
        "advisor_name": "Lumie",
    }

    # Run all skills concurrently via execution service (fault-isolated)
    skill_data = await _run_all_skills_for_proactive(db, user_id, selected_skills, user_context)

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
    await audit.save_round_record(db, round_id, user_id, now_utc, skill_data)

    # ── 4. Fetch last nudge, last round, and today's dayprint ───────────────
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
                "status": r.get("status"),
                "score": r.get("score"),
            }
            for r in last_round_doc.get("skill_results", [])
        ]
        logger.info("Proactive[%s]: found last round with %d results", user_id, len(last_round_results))

    # Fetch today's dayprint for context
    today_str = now_local.date().isoformat()
    today_dayprint = await db.dayprints.find_one(
        {"user_id": user_id, "date": today_str},
        {"_id": 0},
    )
    if today_dayprint:
        logger.info("Proactive[%s]: found today's dayprint with %d events", user_id, len(today_dayprint.get("events", [])))

    # ── 5. Build prompt and call LLM ────────────────────────────────────────
    system_prompt, user_message = _build_decision_prompt(
        user_name=user_name,
        role=role,
        icd10=icd10,
        local_time_str=local_time_str,
        skill_data=skill_data,
        last_round_results=last_round_results,
        today_dayprint=today_dayprint,
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
        await audit.save_run_record(db, run_id, user_id, now_utc, skill_results, error_decision, None, round_id)
        return {"nudged": False, "message": None, "reason": f"llm_error: {e}"}

    should_nudge: bool = bool(result.get("should_nudge", False))
    message: str | None = result.get("message") or None
    reason: str = result.get("reason", "")

    # ── 6. Same-day semantic dedupe & alternate topic selection ──────────
    local_date_key = now_local.date().isoformat()
    daily_sent_concerns = (
        ((checkin_doc or {}).get("daily_sent_concerns") or {}).get(local_date_key) or []
    )
    sent_concern_keys = set(daily_sent_concerns)
    daily_sent_topics = (
        ((checkin_doc or {}).get("daily_sent_topics") or {}).get(local_date_key) or []
    )
    sent_topic_keys = set(daily_sent_topics)

    selected_domain = result.get("primary_domain")
    if not selected_domain and skill_data:
        selected_domain = max(skill_data, key=lambda s: s.priority).domain

    selected_skill_data = _find_skill_by_domain(skill_data, selected_domain)
    concern_key = _build_concern_key(selected_domain or "unknown", reason, selected_skill_data)
    selected_topic_key = ""

    # Check for same-day duplicate concern
    is_duplicate = should_nudge and message and concern_key in sent_concern_keys
    if is_duplicate:
        logger.info(
            "Proactive[%s]: suppress duplicate concern key=%s for date=%s, trying topic fallback",
            user_id,
            concern_key,
            local_date_key,
        )

    # If no nudge OR duplicate: try topic fallback (LLM-ranked 15-day dayprint topics)
    if not should_nudge or is_duplicate:
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
            should_nudge = True  # Override to true if we found a good topic
            logger.info("Proactive[%s]: selected topic fallback key=%s", user_id, concern_key)
        else:
            should_nudge = False
            message = None
            reason = "no_concern_or_duplicate_no_topic_fallback"
            selected_domain = None
            concern_key = ""
            logger.info("Proactive[%s]: no nudge and no topic fallback", user_id)

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
                    "nudged_at": now_utc.isoformat(),
                    "run_id": run_id,
                    "primary_domain": selected_domain or result.get("primary_domain"),
                    "evidence_summary": evidence_summary,
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
        db, run_id, user_id, now_utc, skill_data, decision_data, delivery_data, round_id,
    )

    return {"nudged": should_nudge, "message": message, "reason": reason}
