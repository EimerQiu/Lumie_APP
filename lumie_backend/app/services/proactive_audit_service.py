"""Proactive Audit Service — persists structured run records.

Every proactive run (whether it results in a nudge or not) gets structured
records across three collections for post-hoc analysis and traceability:

  - proactive_runs         — one record per run (timing, selected skills, guardrail, delivery)
  - proactive_skill_results — one record per skill result per run
  - proactive_decisions     — one record per LLM decision per run
"""
import logging
from datetime import datetime, timezone

from ..models.proactive import (
    GuardrailVerdict,
    ProactiveSkillResult,
)

logger = logging.getLogger(__name__)


async def save_run_record(
    db,
    run_id: str,
    user_id: str,
    started_at: datetime,
    skill_results: list[ProactiveSkillResult],
    guardrail: GuardrailVerdict | dict,
    decision: dict | None,
    delivery: dict | None = None,
) -> None:
    """Persist structured audit records across three collections."""
    try:
        guardrail_dict = (
            guardrail.model_dump() if isinstance(guardrail, GuardrailVerdict)
            else guardrail
        )
        finished_at = datetime.now(timezone.utc).isoformat()

        # 1. proactive_runs — the run envelope
        run_doc = {
            "run_id": run_id,
            "user_id": user_id,
            "started_at": started_at.isoformat(),
            "finished_at": finished_at,
            "selected_skills": [r.skill_id for r in skill_results],
            "guardrail_result": guardrail_dict,
            "delivery_result": delivery or {},
        }
        await db.proactive_runs.insert_one(run_doc)

        # 2. proactive_skill_results — one doc per skill per run
        if skill_results:
            skill_docs = []
            for r in skill_results:
                doc = r.model_dump()
                doc["run_id"] = run_id
                doc["user_id"] = user_id
                doc["assessed_at"] = finished_at
                skill_docs.append(doc)
            await db.proactive_skill_results.insert_many(skill_docs)

        # 3. proactive_decisions — one doc per LLM decision
        if decision is not None:
            decision_doc = {
                "run_id": run_id,
                "user_id": user_id,
                "decided_at": finished_at,
                **decision,
            }
            await db.proactive_decisions.insert_one(decision_doc)

        logger.info("Proactive audit: run_id=%s user=%s skills=%d", run_id, user_id, len(skill_results))
    except Exception as e:
        logger.error("Failed to save proactive audit run_id=%s user=%s: %s", run_id, user_id, e)


async def get_recent_runs(db, user_id: str, limit: int = 10) -> list[dict]:
    """Retrieve recent proactive run records for a user."""
    cursor = db.proactive_runs.find(
        {"user_id": user_id},
        {"_id": 0},
    ).sort("started_at", -1).limit(limit)
    return await cursor.to_list(limit)


async def get_skill_results_for_run(db, run_id: str) -> list[dict]:
    """Retrieve all skill results for a specific run."""
    cursor = db.proactive_skill_results.find(
        {"run_id": run_id},
        {"_id": 0},
    )
    return await cursor.to_list(50)


async def get_decision_for_run(db, run_id: str) -> dict | None:
    """Retrieve the decision record for a specific run."""
    return await db.proactive_decisions.find_one(
        {"run_id": run_id},
        {"_id": 0},
    )
