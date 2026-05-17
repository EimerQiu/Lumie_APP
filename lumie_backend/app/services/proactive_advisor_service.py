"""Proactive Advisor Service — checklist-driven execution architecture.

New design (v3):
  1. Manual checklist items are executed first via advisor orchestration flow.
  2. Manual execution may trigger skills when needed (tool-call path in orchestrator).
  3. Manual execution outputs are normalized into current-round assessment data.
  4. Raw round data is persisted in proactive_information_rounds collection.
  5. LLM gets: current round results + last round results + today's dayprint + last nudge + proactive checklist.
  6. LLM decides whether to nudge (no deterministic guardrails, no hardcoded scores).
  7. Audit records persisted for observability.
"""

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
from ..models.proactive import ProactiveSkillData
from ..services.chat_history_service import save_message
from ..services.notification_service import queue_checkin_notification
from . import proactive_audit_service as audit
from .llm_client import chat_completion

logger = logging.getLogger(__name__)

_DECISION_MODEL = settings.PALEBLUEDOT_MODEL


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
    # Keep first sentence only.
    first = s.split(". ")[0].strip()
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
            out = f"{out[:room].rstrip()} ... {clause}"
        out_tokens = _tokenize_for_match(out)
    return out


async def _execute_manual_checklist_instructions(
    db,
    user_id: str,
    manual_items: list[dict],
) -> tuple[list[dict], list[dict]]:
    """Execute each manual checklist item through planner service."""
    from .planner_service import run_planner_session

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
            planner_result = await run_planner_session(
                db=db,
                user_id=user_id,
                source="proactive",
                goal_text=text,
                session_id="proactive",
                max_steps=4,
                auto_confirm=True,
            )
            result_doc["planner_session_id"] = planner_result.get("planner_session_id")
            result_doc["status"] = "success" if planner_result.get("status") == "done" else "failed"
            result_doc["summary"] = (planner_result.get("final_summary") or "")[:240]

            steps = planner_result.get("steps") or []
            last_step = steps[-1] if steps else {}
            result_doc["result_type"] = last_step.get("advisor_response_type")
            result_doc["job_id"] = last_step.get("job_id")
            result_doc["executed_skill_id"] = last_step.get("executed_skill_id")

            # Detect whether any execution in this planner session was a write-operation job.
            write_job_ids: list[str] = []
            for st in steps:
                jid = st.get("job_id")
                if not jid:
                    continue
                job = await db.execution_jobs.find_one(
                    {"job_id": jid},
                    {"_id": 0, "job_id": 1, "is_write_operation_task": 1},
                )
                if job and bool(job.get("is_write_operation_task")):
                    write_job_ids.append(jid)
            result_doc["had_write_execution"] = bool(write_job_ids)
            result_doc["write_execution_job_ids"] = write_job_ids
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


def _build_skill_data_from_manual_instruction_results(
    manual_instruction_results: list[dict],
) -> list[ProactiveSkillData]:
    """Normalize manual checklist execution outputs into proactive skill-style records."""
    out: list[ProactiveSkillData] = []
    for r in manual_instruction_results or []:
        item_id = str(r.get("item_id") or uuid.uuid4())
        status = str(r.get("status") or "failed")
        execution_status = "success" if status == "success" else "failed"
        source_skill_id = (r.get("executed_skill_id") or "").strip()
        summary = str(r.get("summary") or "").strip()
        text = str(r.get("text") or "").strip()
        domain = "manual_checklist"
        if source_skill_id:
            if "task" in source_skill_id:
                domain = "tasks"
            elif "health" in source_skill_id or "hr" in source_skill_id or "spo2" in source_skill_id:
                domain = "health"

        out.append(
            ProactiveSkillData(
                skill_id=f"manual_item:{item_id}",
                domain=domain,
                priority=100,
                execution_status=execution_status,
                data={
                    "manual_item_text": text,
                    "source_skill_id": source_skill_id or None,
                    "result_type": r.get("result_type"),
                    "execution_result_data": r.get("execution_result_data") or {},
                },
                summary=summary,
            )
        )
    return out


def _build_prompt_checklist_payload(proactive_checklist: dict | None) -> dict | None:
    """Build a deduplicated prompt payload so each manual item text appears once."""
    if not proactive_checklist:
        return None

    manual_items = proactive_checklist.get("manual_items") or []
    manual_results = proactive_checklist.get("manual_instruction_results") or []

    # Keep full manual text only in manual_items.
    # Do not repeat execution summaries here; summaries are already present in
    # CURRENT ROUND ASSESSMENTS to reduce prompt duplication.
    compact_results = []
    for r in manual_results:
        compact_results.append({
            "item_id": r.get("item_id"),
            "status": r.get("status"),
            "result_type": r.get("result_type"),
            "must_preserve": bool(r.get("must_preserve")),
            "executed_skill_id": r.get("executed_skill_id"),
            "had_write_execution": bool(r.get("had_write_execution")),
        })

    return {
        "manual_items": [
            {
                "item_id": i.get("item_id"),
                "text": i.get("text"),
                "status": i.get("status"),
            }
            for i in manual_items
        ],
        "today_dayprint": proactive_checklist.get("today_dayprint"),
        "manual_instruction_results": compact_results,
    }


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
    manual_summary_by_item: dict[str, str] = {}
    for s in skill_data:
        data_for_prompt = dict(s.data or {})
        # Text already exists in checklist.manual_items; avoid repeating it here.
        data_for_prompt.pop("manual_item_text", None)
        item_id = ""
        if s.skill_id.startswith("manual_item:"):
            item_id = s.skill_id.split("manual_item:", 1)[1]
        if item_id and s.summary:
            manual_summary_by_item[item_id] = s.summary

        current_results_for_llm.append({
            "skill_id": s.skill_id,
            "domain": s.domain,
            "priority": s.priority,
            "execution_status": s.execution_status,
            "summary": s.summary,
            "data": data_for_prompt,
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
        # Keep previous round compact to reduce repeated long summaries.
        compact_last_round = []
        for r in last_round_results:
            compact_last_round.append({
                "skill_id": r.get("skill_id"),
                "domain": r.get("domain"),
                "status": r.get("status"),
                "priority": r.get("priority"),
            })
        user_parts.append(json.dumps(compact_last_round, indent=2))

    if today_dayprint:
        user_parts.append("\n=== TODAY'S DAYPRINT ===\n")
        dayprint_summary = {
            "date": today_dayprint.get("date"),
            "summary": today_dayprint.get("summary", ""),
            "events_count": len(today_dayprint.get("events", [])),
        }
        user_parts.append(json.dumps(dayprint_summary, indent=2))

    prompt_checklist = _build_prompt_checklist_payload(proactive_checklist)
    if prompt_checklist:
        # Attach summary references once via current-round item map only.
        manual_items_enriched = []
        for i in (prompt_checklist.get("manual_items") or []):
            item_id = i.get("item_id")
            manual_items_enriched.append({
                "item_id": item_id,
                "text": i.get("text"),
                "status": i.get("status"),
                "current_round_summary_ref": manual_summary_by_item.get(item_id, ""),
            })
        user_parts.append("\n=== PROACTIVE CHECKLIST ===\n")
        user_parts.append(json.dumps({
            "manual_items": manual_items_enriched,
            "today_dayprint": prompt_checklist.get("today_dayprint"),
            "manual_instruction_results": prompt_checklist.get("manual_instruction_results"),
        }, indent=2))

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
    - Manual checklist items are handled first (may trigger skills via orchestrator)
    - Current-round assessment data comes from manual execution outputs
    - Information rounds are persisted for trend analysis
    - A proactive checklist (manual priorities + today's dayprint)
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

    logger.info("Proactive[%s]: run_id=%s round_id=%s", user_id, run_id, round_id)

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
        manual_instruction_results=manual_instruction_results,
    )
    logger.info(
        "Proactive[%s]: checklist built manual=%d dayprint=%s manual_results=%d",
        user_id,
        len(proactive_checklist.get("manual_items") or []),
        "yes" if proactive_checklist.get("today_dayprint") else "no",
        len(proactive_checklist.get("manual_instruction_results") or []),
    )

    # Build assessment data from manual checklist execution outputs.
    skill_data = _build_skill_data_from_manual_instruction_results(manual_instruction_results)

    logger.info(
        "Proactive[%s]: %d manual assessment results",
        user_id,
        len(skill_data),
    )

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
                "data": {
                    k: v
                    for k, v in (r.get("data") or {}).items()
                    if k != "manual_item_text"
                },
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
    force_nudge_due_to_write = any(bool(r.get("had_write_execution")) for r in (manual_results or []))
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

    if force_nudge_due_to_write:
        should_nudge = True
        if not message:
            write_result = next((r for r in manual_results if bool(r.get("had_write_execution"))), None)
            if write_result:
                message = _build_preserve_clause(write_result.get("summary") or "")
            if not message:
                message = "I completed updates from your proactive checklist and wanted to keep you posted."
        reason = "write_execution_override"
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
    is_duplicate = (not force_nudge_due_to_write) and should_nudge and message and (
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
