"""Proactive Audit Service — persists structured run records and information rounds.

Persists:
  - proactive_information_rounds — one record per round (all skill data fetched in that round)
  - proactive_runs         — one record per run (timing, selected skills, delivery)
  - proactive_skill_results — one record per skill execution per run
  - proactive_decisions     — one record per LLM decision per run
"""
import logging
from datetime import datetime, timezone
from ..core.datetime_utils import format_utc_datetime, format_utc_datetime_with_ms

from ..models.proactive import (
    ProactiveSkillData,
)

logger = logging.getLogger(__name__)


async def save_round_record(
    db,
    round_id: str,
    user_id: str,
    created_at: datetime,
    skill_data: list[ProactiveSkillData],
    checklist: dict | None = None,
) -> None:
    """Persist information round — snapshot of all skill data fetched in one round."""
    try:
        round_doc = {
            "round_id": round_id,
            "user_id": user_id,
            "created_at": format_utc_datetime(created_at),
            "skill_data": [s.model_dump() for s in skill_data],
        }
        if checklist is not None:
            round_doc["checklist"] = checklist
        await db.proactive_information_rounds.insert_one(round_doc)
        logger.info("Proactive round: round_id=%s user=%s skills=%d", round_id, user_id, len(skill_data))
    except Exception as e:
        logger.error("Failed to save proactive round round_id=%s user=%s: %s", round_id, user_id, e)


async def get_last_round(db, user_id: str) -> dict | None:
    """Retrieve the most recent information round for a user."""
    cursor = db.proactive_information_rounds.find(
        {"user_id": user_id},
        {"_id": 0},
    ).sort("created_at", -1).limit(1)
    results = await cursor.to_list(1)
    return results[0] if results else None


async def save_run_record(
    db,
    run_id: str,
    user_id: str,
    started_at: datetime,
    skill_data: list[ProactiveSkillData],
    decision: dict | None,
    delivery: dict | None = None,
    round_id: str | None = None,
) -> None:
    """Persist run record and decision across collections."""
    try:
        finished_at = format_utc_datetime(datetime.now(timezone.utc))

        # 1. proactive_runs — the run envelope
        run_doc = {
            "run_id": run_id,
            "user_id": user_id,
            "started_at": format_utc_datetime(started_at),
            "finished_at": finished_at,
            "round_id": round_id,
            "selected_skills": [s.skill_id for s in skill_data],
            "delivery_result": delivery or {},
        }
        await db.proactive_runs.insert_one(run_doc)

        # 2. proactive_skill_results — one doc per skill execution per run
        if skill_data:
            skill_docs = []
            for s in skill_data:
                doc = s.model_dump()
                doc["run_id"] = run_id
                doc["user_id"] = user_id
                doc["executed_at"] = finished_at
                skill_docs.append(doc)
            await db.proactive_skill_results.insert_many(skill_docs)

        # 3. proactive_decisions — one doc per run
        if decision is not None:
            decision_doc = {
                "run_id": run_id,
                "user_id": user_id,
                "decided_at": finished_at,
                **decision,
            }
            await db.proactive_decisions.insert_one(decision_doc)

        logger.info("Proactive audit: run_id=%s user=%s skills=%d", run_id, user_id, len(skill_data))
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
