"""Analysis job lifecycle management and async execution.

Handles job creation, status tracking, async execution via create_task,
and result storage.
"""
import asyncio
import logging
import uuid
from datetime import datetime
from typing import Optional

from ..core.database import get_database
from ..models.analysis import AnalysisJobStatus
from .analysis_prompt_service import build_analysis_prompt
from .analysis_llm_service import generate_analysis_code
from .analysis_security_service import scan_code
from .analysis_sandbox_service import run_in_sandbox, cleanup_sandbox, kill_container

logger = logging.getLogger(__name__)

# ── Concurrency control ──────────────────────────────────────────────────────

MAX_CONCURRENT_SANDBOXES = 3
_sandbox_semaphore = asyncio.Semaphore(MAX_CONCURRENT_SANDBOXES)

# ── Subscription limits (analysis path only) ─────────────────────────────────

ANALYSIS_LIMIT_FREE = 200
ANALYSIS_LIMIT_PRO = 200


def get_analysis_limit(subscription_tier: str) -> int:
    """Return daily analysis limit for subscription tier."""
    if subscription_tier in ("monthly", "annual"):
        return ANALYSIS_LIMIT_PRO
    return ANALYSIS_LIMIT_FREE


# ── Rate limiting (in-memory) ────────────────────────────────────────────────

_user_call_timestamps: dict[str, list[float]] = {}
_global_call_timestamps: list[float] = []

MAX_USER_CALLS_PER_MINUTE = 2
MAX_GLOBAL_CALLS_PER_SECOND = 5


def _check_rate_limit(user_id: str) -> Optional[str]:
    """Check rate limits. Returns error message or None if OK."""
    import time
    now = time.time()

    # Per-user: max 2 calls per minute
    user_ts = _user_call_timestamps.setdefault(user_id, [])
    user_ts[:] = [t for t in user_ts if now - t < 60]
    if len(user_ts) >= MAX_USER_CALLS_PER_MINUTE:
        return "Rate limit exceeded. Please wait a moment before requesting another analysis."

    # Global: max 5 calls per second
    _global_call_timestamps[:] = [t for t in _global_call_timestamps if now - t < 1]
    if len(_global_call_timestamps) >= MAX_GLOBAL_CALLS_PER_SECOND:
        return "System is busy. Please try again in a few seconds."

    # Record this call
    user_ts.append(now)
    _global_call_timestamps.append(now)
    return None


# ── Job creation ─────────────────────────────────────────────────────────────

async def check_analysis_quota(user_id: str, subscription_tier: str) -> Optional[str]:
    """Check if user has remaining analysis quota for today.

    Returns None if OK, or a user-friendly message if quota exceeded.
    """
    db = get_database()
    today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)

    count = await db.analysis_jobs.count_documents({
        "user_id": user_id,
        "created_at": {"$gte": today_start.isoformat()},
        "status": {"$ne": AnalysisJobStatus.CANCELLED.value},
    })

    limit = get_analysis_limit(subscription_tier)
    if count >= limit:
        return (
            f"You've used all your data analysis quota for today ({count}/{limit}). "
            f"{'Upgrade to Pro for 20 analyses per day. ' if subscription_tier == 'free' else ''}"
            f"I can still help you with questions that don't require data lookup."
        )
    return None


async def create_analysis_job(
    user_id: str,
    prompt: str,
    target_user_id: str,
    team_id: Optional[str] = None,
    timeout: int = 30,
) -> str:
    """Create a new analysis job record in MongoDB. Returns the job_id."""
    db = get_database()
    job_id = str(uuid.uuid4())

    job_doc = {
        "job_id": job_id,
        "user_id": user_id,
        "team_id": team_id,
        "target_user_id": target_user_id,
        "prompt": prompt,
        "status": AnalysisJobStatus.PENDING.value,
        "generated_code": "",
        "result": None,
        "stdout": "",
        "stderr": "",
        "error": "",
        "created_at": datetime.utcnow().isoformat(),
        "started_at": None,
        "finished_at": None,
        "timeout_sec": timeout,
        "docker_container_id": "",
        "model": "claude-haiku-4-5-20251001",
        "token_usage": {"input_tokens": 0, "output_tokens": 0},
    }

    await db.analysis_jobs.insert_one(job_doc)
    logger.info(f"Created analysis job {job_id} for user {user_id}")
    return job_id


# ── Async job execution ──────────────────────────────────────────────────────

async def run_analysis_job(job_id: str) -> None:
    """Execute an analysis job asynchronously. Scheduled via asyncio.create_task."""
    async with _sandbox_semaphore:
        await _execute_job(job_id)


async def _execute_job(job_id: str) -> None:
    """Internal job execution logic."""
    db = get_database()

    try:
        # 1. Load job record
        job = await db.analysis_jobs.find_one({"job_id": job_id})
        if not job:
            logger.error(f"Job {job_id} not found")
            return

        if job["status"] == AnalysisJobStatus.CANCELLED.value:
            logger.info(f"Job {job_id} was cancelled before execution")
            return

        # 2. Update status → generating
        await _update_status(db, job_id, AnalysisJobStatus.GENERATING, {
            "started_at": datetime.utcnow().isoformat(),
        })

        # 3. Load user profile for context
        profile = await db.profiles.find_one({"user_id": job["target_user_id"]}) or {}

        # 4. Build prompt
        analysis_prompt = await build_analysis_prompt(
            question=job["prompt"],
            target_user_id=job["target_user_id"],
            user_profile=profile,
        )

        # 5. Generate code via Claude
        try:
            code, token_usage = await generate_analysis_code(analysis_prompt)
        except (ValueError, RuntimeError) as e:
            await _fail_job(db, job_id, f"code_generation_failed: {e}")
            return

        await db.analysis_jobs.update_one(
            {"job_id": job_id},
            {"$set": {
                "generated_code": code,
                "token_usage": token_usage,
            }},
        )

        # 6. Security scan
        violation = scan_code(code)
        if violation:
            await _fail_job(db, job_id, f"security_violation: {violation}")
            return

        # 7. Check if cancelled during generation
        job = await db.analysis_jobs.find_one({"job_id": job_id})
        if job and job["status"] == AnalysisJobStatus.CANCELLED.value:
            return

        # 8. Update status → running
        await _update_status(db, job_id, AnalysisJobStatus.RUNNING)

        # 9. Execute in Docker sandbox
        sandbox_result = await run_in_sandbox(
            job_id=job_id,
            code=code,
            target_user_id=job["target_user_id"],
            timeout_sec=job.get("timeout_sec", 30),
        )

        # 10. Process results
        update_fields = {
            "stdout": sandbox_result.get("stdout", "")[:5000],
            "stderr": sandbox_result.get("stderr", "")[:5000],
            "docker_container_id": sandbox_result.get("container_id", ""),
            "finished_at": datetime.utcnow().isoformat(),
        }

        if sandbox_result["success"] and sandbox_result["result"]:
            result_data = sandbox_result["result"]
            update_fields["result"] = {
                "summary": result_data.get("summary", "Analysis complete."),
                "data": result_data.get("data"),
                "chart_base64": result_data.get("chart_base64"),
            }
            update_fields["status"] = AnalysisJobStatus.SUCCESS.value
            logger.info(f"Job {job_id} completed successfully")
        else:
            error_msg = sandbox_result.get("error", "unknown_error")
            update_fields["error"] = error_msg
            update_fields["status"] = AnalysisJobStatus.FAILED.value
            logger.error(f"Job {job_id} failed: {error_msg}")

        await db.analysis_jobs.update_one(
            {"job_id": job_id},
            {"$set": update_fields},
        )

    except Exception as e:
        logger.error(f"Unexpected error in job {job_id}: {e}", exc_info=True)
        await _fail_job(db, job_id, f"internal_error: {e}")

    finally:
        cleanup_sandbox(job_id)


async def _update_status(db, job_id: str, status: AnalysisJobStatus, extra: dict = None):
    """Update job status with optional extra fields."""
    update = {"status": status.value}
    if extra:
        update.update(extra)
    await db.analysis_jobs.update_one({"job_id": job_id}, {"$set": update})


async def _fail_job(db, job_id: str, error: str):
    """Mark a job as failed."""
    await db.analysis_jobs.update_one(
        {"job_id": job_id},
        {"$set": {
            "status": AnalysisJobStatus.FAILED.value,
            "error": error,
            "finished_at": datetime.utcnow().isoformat(),
        }},
    )
    logger.error(f"Job {job_id} failed: {error}")


# ── Job queries ──────────────────────────────────────────────────────────────

async def get_job(job_id: str, user_id: str) -> Optional[dict]:
    """Get a job by ID, checking ownership."""
    db = get_database()
    job = await db.analysis_jobs.find_one({"job_id": job_id, "user_id": user_id})
    if job:
        job.pop("_id", None)
    return job


async def get_jobs(user_id: str, limit: int = 10, offset: int = 0) -> tuple[list[dict], bool]:
    """Get a user's analysis job history."""
    db = get_database()
    cursor = db.analysis_jobs.find(
        {"user_id": user_id},
        {"_id": 0, "generated_code": 0},
    ).sort("created_at", -1).skip(offset).limit(limit + 1)

    jobs = await cursor.to_list(length=limit + 1)
    has_more = len(jobs) > limit
    return jobs[:limit], has_more


async def cancel_job(job_id: str, user_id: str) -> bool:
    """Cancel an analysis job. Returns True if cancelled, False if not found/not cancellable."""
    db = get_database()
    job = await db.analysis_jobs.find_one({"job_id": job_id, "user_id": user_id})

    if not job:
        return False

    if job["status"] in (
        AnalysisJobStatus.SUCCESS.value,
        AnalysisJobStatus.FAILED.value,
        AnalysisJobStatus.CANCELLED.value,
    ):
        return False

    # Kill container if running
    if job["status"] == AnalysisJobStatus.RUNNING.value:
        await kill_container(job_id)

    await db.analysis_jobs.update_one(
        {"job_id": job_id},
        {"$set": {
            "status": AnalysisJobStatus.CANCELLED.value,
            "finished_at": datetime.utcnow().isoformat(),
        }},
    )
    logger.info(f"Cancelled job {job_id}")
    return True
