"""Planner service for multi-turn advisor execution orchestration.

This service keeps proactive/chat flows free of business-specific logic.
It drives advisor_orchestrator in multiple turns, persists trace records,
and can auto-confirm to continue execution when advisor asks for confirmation.
"""

from __future__ import annotations

import asyncio
import json
import logging
import uuid
from collections import deque
from datetime import datetime, timedelta, timezone
from typing import Any

from ..core.config import settings
from ..core.datetime_utils import format_utc_datetime
from . import capability_service
from .llm_client import chat_completion
from .skill_registry_service import skill_registry

logger = logging.getLogger(__name__)

# Safety guardrails to prevent planner/advisor LLM loops.
MAX_LLM_CALLS_PER_SESSION = 24
MAX_CONSECUTIVE_LOOP_SIGNATURE = 3


async def _wait_for_execution_job_terminal(
    db,
    job_id: str,
    timeout_seconds: int = 180,
) -> dict:
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


def _initial_instruction(goal_text: str, source: str) -> str:
    prelude = (
        "[Planner execution]\n"
        "Execute this goal end-to-end when possible. "
        "Interpret quoted phrases as literal task/template names unless a person is explicitly requested.\n\n"
    )
    if source == "proactive":
        return f"{prelude}{goal_text}"
    return f"{prelude}{goal_text}"


def _safe_json(raw: str, default: dict) -> dict:
    try:
        text = (raw or "").strip()
        if text.startswith("```"):
            lines = text.splitlines()
            text = "\n".join(lines[1:-1]) if len(lines) > 2 else text
        data = json.loads(text)
        if isinstance(data, dict):
            return data
        return default
    except Exception:
        return default


async def _build_skill_catalog_for_planning(user_id: str, goal_text: str) -> dict:
    enabled_caps = await capability_service.get_user_enabled_capability_ids(user_id)
    if not enabled_caps:
        enabled_caps = {"lumie_internal_data"}

    relevant = skill_registry.retrieve_top_k(
        query=goal_text,
        enabled_capabilities=enabled_caps,
        top_k=10,
    )
    all_enabled = [
        s for s in skill_registry.get_all_skills()
        if s.status == "indexed" and s.capability_id in enabled_caps
    ]

    def _fmt(items: list) -> list[dict]:
        out = []
        for s in items:
            out.append(
                {
                    "skill_id": s.skill_id,
                    "title": s.title,
                    "summary": s.summary,
                    "capability_id": s.capability_id,
                }
            )
        return out

    return {
        "enabled_capabilities": sorted(list(enabled_caps)),
        "relevant_skills": _fmt(relevant),
        "all_enabled_skills": _fmt(all_enabled),
    }


async def _create_execution_plan(
    *,
    user_id: str,
    goal_text: str,
    source: str,
    max_steps: int,
) -> dict:
    skill_catalog = await _build_skill_catalog_for_planning(user_id, goal_text)
    system = (
        "You are a planning service. Build a concise execution plan for an advisor agent.\n"
        "Return JSON only.\n"
        "The plan must include step-level completion criteria and a global completion criteria.\n"
        "Do not ask user confirmation in steps. Steps should be executable instructions.\n"
        "Use the provided skill catalog to design feasible steps. Prefer skills from relevant_skills.\n"
        "If a step depends on data from a prior step (query -> decision -> possible create), keep that dependency explicit."
    )
    user = (
        f"Source: {source}\n"
        f"Goal: {goal_text}\n"
        f"Max steps: {max_steps}\n\n"
        f"Skill catalog:\n{json.dumps(skill_catalog, ensure_ascii=False)}\n\n"
        "Return JSON with this shape:\n"
        "{\n"
        '  "steps":[{"step_id":"s1","objective":"...","instruction":"message to advisor","done_criteria":"observable evidence","preferred_skill_ids":["..."]}],\n'
        '  "global_done_criteria":"...",\n'
        '  "completion_summary_style":"1-2 sentence concise summary"\n'
        "}"
    )
    resp = await chat_completion(
        model=settings.PALEBLUEDOT_MODEL,
        max_tokens=900,
        temperature=0,
        system=system,
        messages=[{"role": "user", "content": user}],
    )
    parsed = _safe_json(resp.text, default={})
    steps = parsed.get("steps") or []
    normalized_steps = []
    for i, step in enumerate(steps[:max_steps], 1):
        normalized_steps.append(
            {
                "step_id": str(step.get("step_id") or f"s{i}"),
                "objective": str(step.get("objective") or "").strip(),
                "instruction": str(step.get("instruction") or "").strip(),
                "done_criteria": str(step.get("done_criteria") or "").strip(),
                "preferred_skill_ids": step.get("preferred_skill_ids") or [],
            }
        )
    if not normalized_steps:
        normalized_steps = [
            {
                "step_id": "s1",
                "objective": "Execute goal end-to-end",
                "instruction": (
                    f"{_initial_instruction(goal_text, source)}\n"
                    "Do not ask for confirmation. Execute now and return concrete results."
                ),
                "done_criteria": "Concrete execution evidence shows goal completed.",
                "preferred_skill_ids": [],
            }
        ]
    return {
        "steps": normalized_steps,
        "global_done_criteria": str(parsed.get("global_done_criteria") or "Goal is fully completed with concrete evidence."),
        "completion_summary_style": str(parsed.get("completion_summary_style") or "concise"),
    }


async def _evaluate_progress(
    *,
    goal_text: str,
    plan: dict,
    current_step_index: int,
    current_step: dict,
    advisor_result: dict,
    job: dict | None,
    evidence_log: list[dict[str, Any]],
) -> dict:
    system = (
        "You are a strict planner evaluator.\n"
        "Decide whether the current step is completed and whether the whole goal is completed.\n"
        "Use only provided evidence. Return JSON only."
    )
    payload = {
        "goal_text": goal_text,
        "global_done_criteria": plan.get("global_done_criteria"),
        "current_step_index": current_step_index,
        "current_step": current_step,
        "advisor_result": advisor_result,
        "job": job or {},
        "evidence_log": evidence_log[-8:],
    }
    user = (
        f"Evaluate this execution state:\n{json.dumps(payload, ensure_ascii=False)}\n\n"
        "Return JSON:\n"
        "{\n"
        '  "step_completed": true|false,\n'
        '  "goal_completed": true|false,\n'
        '  "reason":"short",\n'
        '  "next_action":"repeat_step|advance_step|goal_done|fail",\n'
        '  "next_message":"message to advisor for next turn, if needed"\n'
        "}"
    )
    resp = await chat_completion(
        model=settings.PALEBLUEDOT_MODEL,
        max_tokens=700,
        temperature=0,
        system=system,
        messages=[{"role": "user", "content": user}],
    )
    parsed = _safe_json(resp.text, default={})
    action = str(parsed.get("next_action") or "repeat_step").strip()
    if action not in {"repeat_step", "advance_step", "goal_done", "fail"}:
        action = "repeat_step"
    return {
        "step_completed": bool(parsed.get("step_completed", False)),
        "goal_completed": bool(parsed.get("goal_completed", False)),
        "reason": str(parsed.get("reason") or "").strip(),
        "next_action": action,
        "next_message": str(parsed.get("next_message") or "").strip(),
    }


async def run_planner_session(
    *,
    db,
    user_id: str,
    source: str,
    goal_text: str,
    session_id: str,
    max_steps: int = 4,
    auto_confirm: bool = True,
) -> dict:
    """Run one planner session and return structured trace/result."""
    from . import advisor_orchestrator

    planner_session_id = str(uuid.uuid4())
    started_at = datetime.now(timezone.utc)
    now_str = format_utc_datetime(started_at)
    await db.planner_sessions.insert_one(
        {
            "planner_session_id": planner_session_id,
            "source": source,
            "user_id": user_id,
            "session_id": session_id,
            "goal_text": goal_text,
            "status": "running",
            "max_steps": max_steps,
            "current_step": 0,
            "started_at": now_str,
            "finished_at": None,
            "final_summary": "",
            "error": None,
            "llm_calls": 0,
        }
    )

    plan = await _create_execution_plan(
        user_id=user_id,
        goal_text=goal_text,
        source=source,
        max_steps=max_steps,
    )
    logger.info(
        "Planner[%s]: generated plan for source=%s session=%s\n%s",
        user_id,
        source,
        session_id,
        json.dumps(plan, ensure_ascii=False, indent=2),
    )
    await db.planner_sessions.update_one(
        {"planner_session_id": planner_session_id},
        {"$set": {"plan": plan, "llm_calls": 1}},
    )

    history: list[dict[str, str]] = []
    evidence_log: list[dict[str, Any]] = []
    steps: list[dict[str, Any]] = []
    llm_calls = 1  # planning call already happened above
    loop_signatures: deque[str] = deque(maxlen=MAX_CONSECUTIVE_LOOP_SIGNATURE)
    plan_steps = plan.get("steps") or []
    current_plan_index = 0
    next_message = plan_steps[0]["instruction"] if plan_steps else _initial_instruction(goal_text, source)
    status = "failed"
    final_summary = ""

    try:
        max_turns = max(max_steps * 3, 4)
        for step_no in range(1, max_turns + 1):
            if current_plan_index >= len(plan_steps):
                status = "done"
                final_summary = final_summary or "planner_plan_completed"
                break

            active_plan_index = current_plan_index
            current_plan_step = plan_steps[active_plan_index]
            current_message = next_message
            advisor_result = await advisor_orchestrator.handle_chat(
                user_id=user_id,
                message=current_message,
                history=history,
                session_id=session_id,
            )
            reply = advisor_result.get("reply") or ""
            rtype = advisor_result.get("type") or "guidance"
            decision = "continue"
            job_id = advisor_result.get("job_id")
            job_status = None
            job_result_summary = None
            executed_skill_id = None
            job_record = None

            if rtype == "execution" and job_id:
                job = await _wait_for_execution_job_terminal(db, job_id, timeout_seconds=180)
                job_record = job
                job_status = job.get("status")
                executed_skill_id = job.get("skill_id")
                if job_status == "success":
                    job_result_summary = ((job.get("result") or {}).get("summary") or "")[:240]
                else:
                    job_result_summary = (job.get("error") or "execution_failed")[:240]

            evidence_log.append(
                {
                    "turn": step_no,
                    "message": current_message,
                    "advisor_type": rtype,
                    "advisor_reply": reply,
                    "job_status": job_status,
                    "executed_skill_id": executed_skill_id,
                    "job_result_summary": job_result_summary,
                    "plan_step_id": current_plan_step.get("step_id"),
                    "plan_objective": current_plan_step.get("objective"),
                }
            )

            eval_result = await _evaluate_progress(
                goal_text=goal_text,
                plan=plan,
                current_step_index=active_plan_index + 1,
                current_step=current_plan_step,
                advisor_result=advisor_result,
                job=job_record,
                evidence_log=evidence_log,
            )
            llm_calls += 1
            if llm_calls >= MAX_LLM_CALLS_PER_SESSION:
                decision = "failed"
                status = "failed"
                final_summary = "planner_guardrail_llm_call_limit"
                step_doc = {
                    "planner_session_id": planner_session_id,
                    "step_no": step_no,
                    "planner_message": current_message,
                    "plan_step_index": active_plan_index + 1,
                    "plan_step_id": current_plan_step.get("step_id"),
                    "plan_step_objective": current_plan_step.get("objective"),
                    "plan_step_done_criteria": current_plan_step.get("done_criteria"),
                    "advisor_response_type": rtype,
                    "advisor_reply": reply,
                    "job_id": job_id,
                    "job_status": job_status,
                    "executed_skill_id": executed_skill_id,
                    "job_result_summary": job_result_summary,
                    "evaluator_step_completed": False,
                    "evaluator_goal_completed": False,
                    "evaluator_reason": "LLM call limit reached; planner aborted to prevent loop.",
                    "evaluator_next_action": "fail",
                    "evaluator_next_message": "",
                    "decision": decision,
                    "guardrail": "llm_call_limit",
                    "llm_calls": llm_calls,
                    "created_at": format_utc_datetime(datetime.now(timezone.utc)),
                }
                steps.append(step_doc)
                await db.planner_steps.insert_one(step_doc)
                break

            step_completed = bool(eval_result.get("step_completed"))
            goal_completed = bool(eval_result.get("goal_completed"))
            eval_reason = str(eval_result.get("reason") or "")
            next_action = str(eval_result.get("next_action") or "repeat_step")
            eval_next_message = str(eval_result.get("next_message") or "").strip()

            loop_sig = f"{current_plan_step.get('step_id','')}|{next_action}|{eval_next_message[:120]}"
            loop_signatures.append(loop_sig)
            if len(loop_signatures) == MAX_CONSECUTIVE_LOOP_SIGNATURE and len(set(loop_signatures)) == 1:
                decision = "failed"
                status = "failed"
                final_summary = "planner_guardrail_loop_detected"
                step_doc = {
                    "planner_session_id": planner_session_id,
                    "step_no": step_no,
                    "planner_message": current_message,
                    "plan_step_index": active_plan_index + 1,
                    "plan_step_id": current_plan_step.get("step_id"),
                    "plan_step_objective": current_plan_step.get("objective"),
                    "plan_step_done_criteria": current_plan_step.get("done_criteria"),
                    "advisor_response_type": rtype,
                    "advisor_reply": reply,
                    "job_id": job_id,
                    "job_status": job_status,
                    "executed_skill_id": executed_skill_id,
                    "job_result_summary": job_result_summary,
                    "evaluator_step_completed": False,
                    "evaluator_goal_completed": False,
                    "evaluator_reason": "Repeated planner loop signature detected; aborted.",
                    "evaluator_next_action": "fail",
                    "evaluator_next_message": "",
                    "decision": decision,
                    "guardrail": "loop_signature",
                    "llm_calls": llm_calls,
                    "created_at": format_utc_datetime(datetime.now(timezone.utc)),
                }
                steps.append(step_doc)
                await db.planner_steps.insert_one(step_doc)
                break

            if next_action == "goal_done" or goal_completed:
                decision = "done"
                status = "done"
                final_summary = (job_result_summary or reply or eval_reason or "goal_completed")[:240]
            elif next_action == "fail":
                decision = "failed"
                status = "failed"
                final_summary = (eval_reason or job_result_summary or reply or "planner_evaluator_failed")[:240]
            elif step_completed or next_action == "advance_step":
                current_plan_index += 1
                if current_plan_index >= len(plan_steps):
                    decision = "done"
                    status = "done"
                    final_summary = (job_result_summary or reply or eval_reason or "goal_completed")[:240]
                else:
                    decision = "continue"
                    next_message = plan_steps[current_plan_index]["instruction"]
            else:
                decision = "continue"
                if eval_next_message:
                    next_message = eval_next_message
                elif auto_confirm:
                    next_message = "Yes, proceed now and execute the next required action."
                else:
                    next_message = current_plan_step.get("instruction") or current_message

            step_doc = {
                "planner_session_id": planner_session_id,
                "step_no": step_no,
                "planner_message": current_message,
                "plan_step_index": active_plan_index + 1,
                "plan_step_id": current_plan_step.get("step_id"),
                "plan_step_objective": current_plan_step.get("objective"),
                "plan_step_done_criteria": current_plan_step.get("done_criteria"),
                "advisor_response_type": rtype,
                "advisor_reply": reply,
                "job_id": job_id,
                "job_status": job_status,
                "executed_skill_id": executed_skill_id,
                "job_result_summary": job_result_summary,
                "evaluator_step_completed": step_completed,
                "evaluator_goal_completed": goal_completed,
                "evaluator_reason": eval_reason,
                "evaluator_next_action": next_action,
                "evaluator_next_message": eval_next_message,
                "decision": decision,
                "llm_calls": llm_calls,
                "created_at": format_utc_datetime(datetime.now(timezone.utc)),
            }
            steps.append(step_doc)
            await db.planner_steps.insert_one(step_doc)
            await db.planner_sessions.update_one(
                {"planner_session_id": planner_session_id},
                {"$set": {"current_step": step_no}},
            )

            # Update conversation history after persisting step.
            history.append({"role": "user", "content": current_message})
            if reply:
                history.append({"role": "assistant", "content": reply})

            if decision in {"done", "failed"}:
                break

        if status not in {"done", "failed"}:
            status = "timeout"
            final_summary = "planner_max_steps_reached"
    except Exception as exc:
        logger.exception("Planner session failed user=%s source=%s", user_id, source)
        status = "failed"
        final_summary = f"planner_error: {str(exc)[:180]}"

    finished_at = format_utc_datetime(datetime.now(timezone.utc))
    await db.planner_sessions.update_one(
        {"planner_session_id": planner_session_id},
        {
            "$set": {
                "status": status,
                "finished_at": finished_at,
                "final_summary": final_summary,
                "llm_calls": llm_calls,
            }
        },
    )

    return {
        "planner_session_id": planner_session_id,
        "status": status,
        "final_summary": final_summary,
        "steps": steps,
    }
