"""Planner service for multi-turn advisor execution orchestration.

This service keeps proactive/chat flows free of business-specific logic.
It drives advisor_orchestrator in multiple turns, persists trace records,
and can auto-confirm to continue execution when advisor asks for confirmation.
"""

from __future__ import annotations

import asyncio
import logging
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from ..core.datetime_utils import format_utc_datetime

logger = logging.getLogger(__name__)


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
        }
    )

    history: list[dict[str, str]] = []
    steps: list[dict[str, Any]] = []
    next_message = _initial_instruction(goal_text, source)
    status = "failed"
    final_summary = ""

    try:
        for step_no in range(1, max_steps + 1):
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

            if rtype == "execution" and job_id:
                job = await _wait_for_execution_job_terminal(db, job_id, timeout_seconds=180)
                job_status = job.get("status")
                executed_skill_id = job.get("skill_id")
                if job_status == "success":
                    decision = "done"
                    status = "done"
                    job_result_summary = ((job.get("result") or {}).get("summary") or "")[:240]
                    final_summary = job_result_summary or reply
                else:
                    decision = "failed"
                    status = "failed"
                    job_result_summary = (job.get("error") or "execution_failed")[:240]
                    final_summary = job_result_summary
            else:
                # Non-execution turns: proactively confirm once and continue.
                if auto_confirm and step_no < max_steps:
                    next_message = "Yes, proceed now and execute it."
                    decision = "continue"
                else:
                    decision = "failed"
                    status = "failed"
                    final_summary = (reply or "planner_non_execution_terminal")[:240]

            step_doc = {
                "planner_session_id": planner_session_id,
                "step_no": step_no,
                "planner_message": current_message,
                "advisor_response_type": rtype,
                "advisor_reply": reply,
                "job_id": job_id,
                "job_status": job_status,
                "executed_skill_id": executed_skill_id,
                "job_result_summary": job_result_summary,
                "decision": decision,
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
            }
        },
    )

    return {
        "planner_session_id": planner_session_id,
        "status": status,
        "final_summary": final_summary,
        "steps": steps,
    }
