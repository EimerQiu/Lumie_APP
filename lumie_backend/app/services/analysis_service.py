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
from .notification_service import queue_analysis_complete_notification

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


def _compute_nav_hint(data_types: list, time_range: str, question: str = "") -> Optional[str]:
    """Determine which screen to navigate to based on what data was queried."""
    if not data_types or "tasks" not in data_types:
        return None
    # Dashboard: completion/miss status questions, or explicit historical time ranges.
    # Task list: current/upcoming task queries.
    dashboard_keywords = {
        "miss", "missed", "completion", "complete", "completed",
        "how many", "did i", "have i", "status",
        "last", "past", "week", "month", "days", "history",
        "rate", "statistic", "trend", "ago", "previous",
    }
    combined = f"{time_range} {question}".lower()
    if any(kw in combined for kw in dashboard_keywords):
        return "task_dashboard"
    return "task_list"


async def create_analysis_job(
    user_id: str,
    prompt: str,
    target_user_id: str,
    team_id: Optional[str] = None,
    timeout: int = 30,
    data_types: list = None,
    time_range: str = "",
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
        "data_types": data_types or [],
        "time_range": time_range,
    }

    await db.analysis_jobs.insert_one(job_doc)
    logger.info(f"Created analysis job {job_id} for user {user_id}")
    return job_id


# ── Async job execution ──────────────────────────────────────────────────────

async def run_analysis_job(job_id: str) -> None:
    """Execute an analysis job asynchronously. Scheduled via asyncio.create_task."""
    async with _sandbox_semaphore:
        await _execute_job(job_id)


_MAX_RETRIES = 2
_FRIENDLY_ERROR = "I wasn't able to complete this analysis. Please try rephrasing your question."


def _build_retry_prompt(original_prompt: str, failed_code: str, error: str) -> str:
    """Build a follow-up prompt that includes the previous error so Claude can fix it."""
    return (
        f"{original_prompt}\n\n"
        f"## Previous attempt failed\n"
        f"The code below was generated but failed with this error:\n"
        f"```\n{error[:800]}\n```\n\n"
        f"Failed code:\n"
        f"```python\n{failed_code[:2000]}\n```\n\n"
        f"Fix the error and return corrected Python code only."
    )


async def _execute_job(job_id: str) -> None:
    """Internal job execution logic with retry on sandbox failure."""
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

        # 4. Build base prompt
        analysis_prompt = await build_analysis_prompt(
            question=job["prompt"],
            target_user_id=job["target_user_id"],
            user_profile=profile,
        )

        code = ""
        token_usage = {"input_tokens": 0, "output_tokens": 0}
        last_error = ""

        for attempt in range(_MAX_RETRIES + 1):
            # 5. Generate code (or regenerate with error context)
            try:
                prompt = (
                    analysis_prompt if attempt == 0
                    else _build_retry_prompt(analysis_prompt, code, last_error)
                )
                code, token_usage = await generate_analysis_code(prompt)
            except (ValueError, RuntimeError) as e:
                logger.warning(f"Job {job_id} code generation failed (attempt {attempt+1}): {e}")
                if attempt == _MAX_RETRIES:
                    await _fail_job(db, job_id, _FRIENDLY_ERROR)
                    return
                last_error = str(e)
                continue

            await db.analysis_jobs.update_one(
                {"job_id": job_id},
                {"$set": {"generated_code": code, "token_usage": token_usage}},
            )

            # 6. Security scan (no retry — violation is intentional)
            violation = scan_code(code)
            if violation:
                await _fail_job(db, job_id, _FRIENDLY_ERROR)
                logger.error(f"Job {job_id} security violation: {violation}")
                return

            # 7. Check if cancelled
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

            if sandbox_result["success"] and sandbox_result["result"]:
                # ✅ Success
                result_data = sandbox_result["result"]
                nav_hint = _compute_nav_hint(
                    job.get("data_types", []),
                    job.get("time_range", ""),
                    job.get("prompt", ""),
                )
                await db.analysis_jobs.update_one(
                    {"job_id": job_id},
                    {"$set": {
                        "stdout": sandbox_result.get("stdout", "")[:5000],
                        "stderr": sandbox_result.get("stderr", "")[:5000],
                        "docker_container_id": sandbox_result.get("container_id", ""),
                        "finished_at": datetime.utcnow().isoformat(),
                        "result": {
                            "summary": result_data.get("summary", "Analysis complete."),
                            "data": result_data.get("data"),
                            "chart_base64": result_data.get("chart_base64"),
                            "nav_hint": nav_hint,
                        },
                        "status": AnalysisJobStatus.SUCCESS.value,
                    }},
                )
                logger.info(f"Job {job_id} completed successfully (attempt {attempt+1})")

                # Queue push notification so the user knows the result is ready
                try:
                    summary_text = result_data.get("summary", "Your analysis is ready.")
                    await queue_analysis_complete_notification(
                        user_id=job["user_id"],
                        job_id=job_id,
                        summary=summary_text,
                    )
                except Exception as notify_err:
                    logger.warning(f"Failed to queue analysis notification for job {job_id}: {notify_err}")

                return

            # ❌ Execution failed — capture error and retry
            last_error = sandbox_result.get("error", "unknown_error")
            stderr = sandbox_result.get("stderr", "")
            last_error = f"{last_error}\n{stderr}".strip()
            logger.warning(f"Job {job_id} execution failed (attempt {attempt+1}): {last_error[:200]}")

            if attempt == _MAX_RETRIES:
                await db.analysis_jobs.update_one(
                    {"job_id": job_id},
                    {"$set": {
                        "stdout": sandbox_result.get("stdout", "")[:5000],
                        "stderr": stderr[:5000],
                        "docker_container_id": sandbox_result.get("container_id", ""),
                        "finished_at": datetime.utcnow().isoformat(),
                        "error": _FRIENDLY_ERROR,
                        "status": AnalysisJobStatus.FAILED.value,
                    }},
                )
                logger.error(f"Job {job_id} failed after {_MAX_RETRIES+1} attempts")
                return

            # Back to top of loop for retry
            await _update_status(db, job_id, AnalysisJobStatus.GENERATING)

    except Exception as e:
        logger.error(f"Unexpected error in job {job_id}: {e}", exc_info=True)
        await _fail_job(db, job_id, _FRIENDLY_ERROR)

    finally:
        cleanup_sandbox(job_id)


async def _update_status(db, job_id: str, status: AnalysisJobStatus, extra: dict = None):
    """Update job status with optional extra fields."""
    update = {"status": status.value}
    if extra:
        update.update(extra)
    await db.analysis_jobs.update_one({"job_id": job_id}, {"$set": update})


async def _fail_job(db, job_id: str, internal_error: str):
    """Mark a job as failed with a friendly user-facing error message."""
    logger.error(f"Job {job_id} failed: {internal_error}")
    await db.analysis_jobs.update_one(
        {"job_id": job_id},
        {"$set": {
            "status": AnalysisJobStatus.FAILED.value,
            "error": _FRIENDLY_ERROR,
            "finished_at": datetime.utcnow().isoformat(),
        }},
    )


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
