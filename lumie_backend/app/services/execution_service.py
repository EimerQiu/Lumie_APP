"""Execution Service — unified skill execution engine.

Handles execution job lifecycle, script generation via LLM,
runtime dispatch, and retry logic.
"""
import asyncio
import logging
import uuid
from datetime import datetime
from typing import Optional

import anthropic

from ..core.config import settings
from ..core.database import get_database
from . import lumie_db_connector
from . import browser_skill_runtime
from .execution_prompt_service import (
    build_lumie_db_execution_prompt,
    build_browser_execution_prompt,
)
from .skill_registry_service import SkillIndexItem

logger = logging.getLogger(__name__)

# LLM for code generation (Layer 2)
_CODE_GEN_MODEL = "claude-sonnet-4-6"
_client: Optional[anthropic.AsyncAnthropic] = None

# Concurrency control
_semaphore = asyncio.Semaphore(3)

MAX_RETRIES = 2


def _get_client() -> anthropic.AsyncAnthropic:
    global _client
    if _client is None:
        _client = anthropic.AsyncAnthropic(api_key=settings.ANTHROPIC_API_KEY)
    return _client


# ── Job creation ─────────────────────────────────────────────────────────────

async def create_execution_job(
    user_id: str,
    session_id: Optional[str],
    skill: SkillIndexItem,
    prompt: str,
    target_user_id: Optional[str] = None,
    team_id: Optional[str] = None,
) -> str:
    """Create an execution job record in MongoDB. Returns job_id."""
    db = get_database()
    job_id = str(uuid.uuid4())
    now = datetime.utcnow().isoformat()

    await db.execution_jobs.insert_one({
        "job_id": job_id,
        "user_id": user_id,
        "session_id": session_id,
        "skill_id": skill.skill_id,
        "capability_id": skill.capability_id,
        "runtime_type": skill.runtime_type,
        "prompt": prompt,
        "target_user_id": target_user_id or user_id,
        "team_id": team_id,
        "normalized_request": {},
        "status": "pending",
        "generated_script": None,
        "retry_count": 0,
        "max_retries": MAX_RETRIES,
        "stdout": "",
        "stderr": "",
        "error": None,
        "result": None,
        "created_at": now,
        "started_at": None,
        "finished_at": None,
    })
    return job_id


# ── Job execution ────────────────────────────────────────────────────────────

async def run_execution_job(
    job_id: str,
    skill: SkillIndexItem,
    skill_full_text: str,
    credential: Optional[dict],
    user_context: dict,
    history_summary: str = "",
) -> None:
    """Execute a job asynchronously with semaphore-controlled concurrency."""
    async with _semaphore:
        await _execute_job(
            job_id, skill, skill_full_text, credential,
            user_context, history_summary,
        )


async def _execute_job(
    job_id: str,
    skill: SkillIndexItem,
    skill_full_text: str,
    credential: Optional[dict],
    user_context: dict,
    history_summary: str,
) -> None:
    """Internal job execution pipeline."""
    db = get_database()

    # Load job record
    job = await db.execution_jobs.find_one({"job_id": job_id})
    if not job:
        logger.error(f"Job {job_id} not found")
        return

    if job["status"] not in ("pending", "retrying"):
        logger.warning(f"Job {job_id} in unexpected status: {job['status']}")
        return

    user_id = job["user_id"]
    target_user_id = job.get("target_user_id", user_id)
    prompt = job["prompt"]
    now = datetime.utcnow().isoformat()

    # Update status to generating
    await db.execution_jobs.update_one(
        {"job_id": job_id},
        {"$set": {"status": "generating", "started_at": now}},
    )

    try:
        # ── Route by runtime_type ────────────────────────────────────────
        if skill.runtime_type == "lumie_db":
            await _execute_lumie_db(
                db, job_id, job, skill, skill_full_text,
                credential, user_context, history_summary,
            )
        elif skill.runtime_type == "browser":
            await _execute_browser(
                db, job_id, job, skill, skill_full_text, credential, user_context,
            )
        elif skill.runtime_type == "external_api":
            # Phase 1: not implemented
            await _fail_job(db, job_id, "External API runtime not yet available")
        elif skill.runtime_type == "hybrid":
            # Phase 1: not implemented
            await _fail_job(db, job_id, "Hybrid runtime not yet available")
        else:
            await _fail_job(db, job_id, f"Unknown runtime_type: {skill.runtime_type}")

    except Exception as e:
        logger.exception(f"Execution failed for job {job_id}")
        await _fail_job(db, job_id, str(e))


# ── Lumie DB execution ───────────────────────────────────────────────────────

async def _execute_lumie_db(
    db, job_id: str, job: dict, skill: SkillIndexItem,
    skill_full_text: str, credential: Optional[dict],
    user_context: dict, history_summary: str,
) -> None:
    """Generate a Python script and execute it via lumie_db_connector."""
    user_id = job["user_id"]
    target_user_id = job.get("target_user_id", user_id)
    prompt = job["prompt"]
    ping = credential.get("ping", "") if credential else ""

    retry_count = job.get("retry_count", 0)
    last_error = None

    for attempt in range(retry_count, MAX_RETRIES + 1):
        # Generate script
        gen_prompt = build_lumie_db_execution_prompt(
            user_request=prompt,
            skill_full_text=skill_full_text,
            request_user_id=user_id,
            target_user_id=target_user_id,
            user_context=user_context,
            history_summary=history_summary,
        )

        # If retrying, include the error context
        if last_error:
            gen_prompt += f"\n\n## Previous Attempt Failed\nError: {last_error}\nPlease fix the script and try again."

        script = await _generate_script(gen_prompt)
        if not script:
            await _fail_job(db, job_id, "LLM failed to generate a script")
            return

        # Update job with generated script
        await db.execution_jobs.update_one(
            {"job_id": job_id},
            {"$set": {
                "status": "running",
                "generated_script": script,
                "retry_count": attempt,
            }},
        )

        # Execute via connector
        result = await lumie_db_connector.execute(
            request_user_id=user_id,
            ping=ping,
            skill_id=skill.skill_id,
            job_id=job_id,
            script=script,
            target_user_id=target_user_id,
            request_summary=prompt,
        )

        if result["success"]:
            # Success!
            await _complete_job(db, job_id, result["data"],
                                result.get("stdout", ""),
                                result.get("stderr", ""))
            return

        # Check if retryable
        if not result.get("retryable", False) or attempt >= MAX_RETRIES:
            await _fail_job(db, job_id, result.get("error", "Execution failed"),
                            result.get("stdout", ""), result.get("stderr", ""))
            return

        # Retry
        last_error = result.get("error", "Unknown error")
        await db.execution_jobs.update_one(
            {"job_id": job_id},
            {"$set": {"status": "retrying", "retry_count": attempt + 1}},
        )
        logger.info(f"Retrying job {job_id} (attempt {attempt + 1})")


# ── Browser execution ────────────────────────────────────────────────────────

async def _execute_browser(
    db, job_id: str, job: dict, skill: SkillIndexItem,
    skill_full_text: str, credential: Optional[dict],
    user_context: dict,
) -> None:
    """Generate browser steps and execute via browser_skill_runtime."""
    if not credential:
        await _fail_job(db, job_id, "No credentials configured for this browser skill")
        return

    # Generate browser automation steps
    gen_prompt = build_browser_execution_prompt(
        user_request=job["prompt"],
        skill_full_text=skill_full_text,
        credential=credential,
        user_context=user_context,
    )

    steps_json = await _generate_script(gen_prompt)
    if not steps_json:
        await _fail_job(db, job_id, "LLM failed to generate browser steps")
        return

    await db.execution_jobs.update_one(
        {"job_id": job_id},
        {"$set": {"status": "running", "generated_script": steps_json}},
    )

    # Execute
    import json
    try:
        steps_data = json.loads(steps_json)
        steps = steps_data.get("steps", [])
    except (json.JSONDecodeError, AttributeError):
        steps = []

    result = await browser_skill_runtime.execute_browser_skill(
        skill_id=skill.skill_id,
        job_id=job_id,
        steps=steps,
        credential=credential,
    )

    if result["success"]:
        await _complete_job(db, job_id, result.get("data"),
                            result.get("stdout", ""), result.get("stderr", ""))
    else:
        await _fail_job(db, job_id, result.get("error", "Browser execution failed"),
                        result.get("stdout", ""), result.get("stderr", ""))


# ── LLM script generation ───────────────────────────────────────────────────

async def _generate_script(prompt: str) -> Optional[str]:
    """Use Claude to generate a script from the execution prompt.

    Retries up to 2 times on transient API errors (overloaded, rate limit).
    """
    client = _get_client()

    for attempt in range(3):
        try:
            response = await client.messages.create(
                model=_CODE_GEN_MODEL,
                max_tokens=4096,
                temperature=0,
                messages=[{"role": "user", "content": prompt}],
            )

            text = ""
            for block in response.content:
                if block.type == "text":
                    text += block.text

            # Strip markdown code fencing if present
            text = text.strip()
            if text.startswith("```python"):
                text = text[9:]
            elif text.startswith("```json"):
                text = text[7:]
            elif text.startswith("```"):
                text = text[3:]
            if text.endswith("```"):
                text = text[:-3]

            return text.strip()

        except anthropic.APIStatusError as e:
            if e.status_code in (429, 529) and attempt < 2:
                wait = 2 ** (attempt + 1)  # 2s, 4s
                logger.warning(f"API transient error ({e.status_code}), retrying in {wait}s (attempt {attempt + 1}/3)")
                await asyncio.sleep(wait)
                continue
            logger.error(f"Script generation failed: {e}")
            return None
        except Exception as e:
            logger.error(f"Script generation failed: {e}")
            return None


# ── Job status helpers ───────────────────────────────────────────────────────

async def _complete_job(
    db, job_id: str, result_data, stdout: str = "", stderr: str = "",
) -> None:
    now = datetime.utcnow().isoformat()
    await db.execution_jobs.update_one(
        {"job_id": job_id},
        {"$set": {
            "status": "success",
            "result": result_data,
            "stdout": stdout,
            "stderr": stderr,
            "finished_at": now,
        }},
    )
    logger.info(f"Job {job_id} completed successfully")

    # Save the result summary to chat history so it appears in History panel
    try:
        job = await db.execution_jobs.find_one({"job_id": job_id})
        if job:
            summary = ""
            if isinstance(result_data, dict):
                summary = result_data.get("summary", "")
            session_id = job.get("session_id") or "default"
            user_id = job.get("user_id", "")
            if summary and user_id:
                from .chat_history_service import save_message
                await save_message(
                    user_id=user_id,
                    session_id=session_id,
                    role="assistant",
                    content=summary,
                    metadata={"type": "execution", "job_id": job_id, "skill_id": job.get("skill_id")},
                )
    except Exception as e:
        logger.warning(f"Failed to save execution result to chat history: {e}")


async def _fail_job(
    db, job_id: str, error: str, stdout: str = "", stderr: str = "",
) -> None:
    now = datetime.utcnow().isoformat()
    await db.execution_jobs.update_one(
        {"job_id": job_id},
        {"$set": {
            "status": "failed",
            "error": error,
            "stdout": stdout,
            "stderr": stderr,
            "finished_at": now,
        }},
    )
    logger.warning(f"Job {job_id} failed: {error}")


# ── Job queries ──────────────────────────────────────────────────────────────

async def get_job(job_id: str, user_id: str) -> Optional[dict]:
    """Get a job by ID with ownership check."""
    db = get_database()
    job = await db.execution_jobs.find_one(
        {"job_id": job_id, "user_id": user_id},
        {"_id": 0, "generated_script": 0},  # Don't expose script to frontend
    )
    return job


async def cancel_job(job_id: str, user_id: str) -> bool:
    """Cancel a pending or generating job."""
    db = get_database()
    result = await db.execution_jobs.update_one(
        {
            "job_id": job_id,
            "user_id": user_id,
            "status": {"$in": ["pending", "generating"]},
        },
        {"$set": {
            "status": "cancelled",
            "finished_at": datetime.utcnow().isoformat(),
        }},
    )
    return result.modified_count > 0
