"""Execution Service — unified skill execution engine.

Handles execution job lifecycle, script generation via LLM,
runtime dispatch, and retry logic.
"""
import asyncio
import logging
import uuid
from datetime import datetime, timedelta
from typing import Optional

from ..core.config import settings
from ..core.datetime_utils import format_utc_datetime, format_utc_datetime_with_ms
from ..core.database import get_database
from . import lumie_db_connector
from . import browser_skill_runtime
from .llm_client import chat_completion
from .execution_prompt_service import (
    build_lumie_db_execution_prompt,
    build_browser_execution_prompt,
    build_external_api_summary_prompt,
    build_external_api_post_body_prompt,
)
from .skill_registry_service import SkillIndexItem

logger = logging.getLogger(__name__)

# LLM for code generation (Layer 2)
_CODE_GEN_MODEL = settings.PALEBLUEDOT_MODEL

# Concurrency control
_semaphore = asyncio.Semaphore(3)

MAX_RETRIES = 2


# ── DAG (Directed Acyclic Graph) Utilities ───────────────────────────────────

async def _build_skill_dag(skills: list[SkillIndexItem]) -> dict[str, list[str]]:
    """Build DAG: skill_id → list of dependent skill_ids.

    Returns: {skill_id: [dependent_skill_ids]}
    """
    dag = {}
    for skill in skills:
        dag[skill.skill_id] = []
        for dep in skill.dependencies:
            dag[skill.skill_id].append(dep.skill_id)
    return dag


async def _topological_sort(dag: dict[str, list[str]]) -> list[list[str]]:
    """Return tiers: [[tier_0_skills], [tier_1_skills], ...].

    Tier N contains skills whose all dependencies are in tiers 0..N-1.
    Raises ValueError if circular dependency detected.
    """
    tiers = []
    processed = set()

    while len(processed) < len(dag):
        tier = []
        for skill_id, deps in dag.items():
            if skill_id not in processed:
                # Check if all dependencies are already processed
                if all(dep in processed for dep in deps):
                    tier.append(skill_id)

        if not tier:
            # No skills can be added → circular dependency
            unprocessed = [sid for sid in dag if sid not in processed]
            raise ValueError(f"Circular dependency or missing skill detected: {unprocessed}")

        tiers.append(tier)
        processed.update(tier)

    return tiers


# ── Job creation ─────────────────────────────────────────────────────────────

async def create_execution_job(
    user_id: str,
    session_id: Optional[str],
    skill: SkillIndexItem,
    prompt: str,
    target_user_id: Optional[str] = None,
    team_id: Optional[str] = None,
    is_write_operation_task: bool = False,
    cross_advisor_context: Optional[dict] = None,
) -> str:
    """Create an execution job record in MongoDB. Returns job_id.

    ``cross_advisor_context`` (when set) carries the cross-advisor thread
    metadata so the post-completion hook can fire a result callback into
    the requester's collab thread.
    """
    db = get_database()
    job_id = str(uuid.uuid4())
    now = format_utc_datetime(datetime.utcnow())

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
        "is_write_operation_task": bool(is_write_operation_task),
        "cross_advisor_context": cross_advisor_context,
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
    previous_results: Optional[dict] = None,
) -> None:
    """Execute a job asynchronously with semaphore-controlled concurrency.

    Args:
        previous_results: Dict of skill_id -> ProactiveSkillData from prior tiers in DAG.
    """
    async with _semaphore:
        await _execute_job(
            job_id, skill, skill_full_text, credential,
            user_context, history_summary, previous_results,
        )


async def _execute_job(
    job_id: str,
    skill: SkillIndexItem,
    skill_full_text: str,
    credential: Optional[dict],
    user_context: dict,
    history_summary: str,
    previous_results: Optional[dict] = None,
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
    now = format_utc_datetime(datetime.utcnow())

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
                credential, user_context, history_summary, previous_results,
            )
        elif skill.runtime_type == "browser":
            await _execute_browser(
                db, job_id, job, skill, skill_full_text, credential, user_context,
            )
        elif skill.runtime_type == "external_api":
            await _execute_external_api(
                db, job_id, job, skill, skill_full_text, credential, user_context,
            )
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
    previous_results: Optional[dict] = None,
) -> None:
    """Generate a Python script and execute it via lumie_db_connector.

    Args:
        previous_results: Dict of skill_id -> ProactiveSkillData from prior tiers in DAG.
    """
    user_id = job["user_id"]
    target_user_id = job.get("target_user_id", user_id)
    prompt = job["prompt"]
    ping = credential.get("ping", "") if credential else ""

    retry_count = job.get("retry_count", 0)
    last_error = None

    for attempt in range(retry_count, MAX_RETRIES + 1):
        # Check if job was cancelled before each attempt
        current = await db.execution_jobs.find_one({"job_id": job_id}, {"status": 1})
        if current and current.get("status") == "cancelled":
            logger.info(f"Job {job_id} was cancelled, stopping execution")
            return

        # Generate script
        gen_prompt = build_lumie_db_execution_prompt(
            user_request=prompt,
            skill_full_text=skill_full_text,
            request_user_id=user_id,
            target_user_id=target_user_id,
            user_context=user_context,
            history_summary=history_summary,
            previous_results=previous_results,
            is_write_operation_task=bool(job.get("is_write_operation_task")),
        )

        # If retrying, include the error context
        if last_error:
            gen_prompt += f"\n\n## Previous Attempt Failed\nError: {last_error}\nPlease fix the script and try again."

        script = await _generate_script(gen_prompt)
        if not script:
            await _fail_job(db, job_id, "LLM failed to generate a script")
            return

        logger.info(f"Job {job_id} generated script:\n{script}")

        # Check again after LLM call (user may have cancelled during generation)
        current = await db.execution_jobs.find_one({"job_id": job_id}, {"status": 1})
        if current and current.get("status") == "cancelled":
            logger.info(f"Job {job_id} was cancelled after script generation, not executing")
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
            user_timezone=user_context.get("timezone", "UTC"),
        )

        stdout = result.get("stdout", "")
        stderr = result.get("stderr", "")
        if stdout:
            logger.info(f"Job {job_id} stdout:\n{stdout}")
        if stderr:
            logger.warning(f"Job {job_id} stderr:\n{stderr}")

        if result["success"]:
            # Success!
            await _complete_job(db, job_id, result["data"], stdout, stderr)
            return

        # Check if retryable
        if not result.get("retryable", False) or attempt >= MAX_RETRIES:
            await _fail_job(db, job_id, result.get("error", "Execution failed"), stdout, stderr)
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
        skill_id=skill.skill_id,
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


# ── External API execution ──────────────────────────────────────────────────

async def _execute_external_api(
    db, job_id: str, job: dict, skill: SkillIndexItem,
    skill_full_text: str, credential: Optional[dict],
    user_context: dict,
) -> None:
    """Make an HTTP GET request and summarize the response with LLM."""
    import httpx
    import json as _json

    if not credential:
        await _fail_job(db, job_id, "No credentials configured for this external API skill")
        return

    base_url = credential.get("base_url", "").rstrip("/")
    endpoint = (skill.api_endpoint or "").strip()
    url = base_url + endpoint if endpoint else base_url

    if not url:
        await _fail_job(db, job_id, "No URL configured for this external API skill")
        return

    await db.execution_jobs.update_one(
        {"job_id": job_id},
        {"$set": {"status": "running"}},
    )

    api_method = skill.api_method  # "GET" or "POST"
    api_key = credential.get("password") or credential.get("api_key")
    headers = {}
    if api_key:
        headers["X-API-Key"] = api_key

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            if api_method == "POST":
                # Generate request body via LLM
                body_prompt = build_external_api_post_body_prompt(
                    user_request=job["prompt"],
                    skill_full_text=skill_full_text,
                )
                body_json_str = await _generate_script(body_prompt)
                if not body_json_str:
                    await _fail_job(db, job_id, "LLM failed to generate request body")
                    return
                try:
                    body = _json.loads(body_json_str)
                except _json.JSONDecodeError:
                    await _fail_job(db, job_id, f"LLM generated invalid JSON body: {body_json_str}")
                    return
                await db.execution_jobs.update_one(
                    {"job_id": job_id},
                    {"$set": {"generated_script": body_json_str}},
                )
                response = await client.post(url, json=body, headers=headers)
            else:
                response = await client.get(url, headers=headers)
            response.raise_for_status()
            api_data = response.json()
    except httpx.HTTPStatusError as e:
        await _fail_job(db, job_id, f"API returned HTTP {e.response.status_code}")
        return
    except httpx.RequestError as e:
        await _fail_job(db, job_id, f"HTTP request failed: {e}")
        return
    except Exception as e:
        await _fail_job(db, job_id, f"Failed to fetch API data: {e}")
        return

    # Generate a user-friendly summary via LLM
    summary_prompt = build_external_api_summary_prompt(
        user_request=job["prompt"],
        skill_full_text=skill_full_text,
        api_data=_json.dumps(api_data, ensure_ascii=False),
        user_context=user_context,
    )

    summary = await _generate_script(summary_prompt)
    await _complete_job(db, job_id, {"summary": summary or "", "data": api_data})


# ── LLM script generation ───────────────────────────────────────────────────

async def _generate_script(prompt: str) -> Optional[str]:
    """Use Claude to generate a script from the execution prompt.

    Retries up to 2 times on transient API errors (overloaded, rate limit).
    """
    for attempt in range(3):
        try:
            response = await chat_completion(
                model=_CODE_GEN_MODEL,
                max_tokens=4096,
                temperature=0,
                messages=[{"role": "user", "content": prompt}],
            )

            text = response.text

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

        except Exception as e:
            status_code = getattr(getattr(e, "response", None), "status_code", None)
            if status_code in (429, 529) and attempt < 2:
                wait = 2 ** (attempt + 1)  # 2s, 4s
                logger.warning(f"API transient error ({status_code}), retrying in {wait}s (attempt {attempt + 1}/3)")
                await asyncio.sleep(wait)
                continue
            logger.error(f"Script generation failed: {e}")
            return None


# ── Job status helpers ───────────────────────────────────────────────────────

async def _complete_job(
    db, job_id: str, result_data, stdout: str = "", stderr: str = "",
) -> None:
    now = format_utc_datetime(datetime.utcnow())
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

    # Save the result summary to chat history and log to Dayprint
    try:
        job = await db.execution_jobs.find_one({"job_id": job_id})
        if job:
            await _maybe_create_pending_clarification_from_result(db, job, result_data)
            summary = ""
            if isinstance(result_data, dict):
                summary = result_data.get("summary", "")
            # Guardrail: avoid "I created/updated/sent" style claims unless we can
            # confirm actual write effects for write-operation tasks.
            if job.get("is_write_operation_task"):
                write_confirmed = _is_write_confirmed(result_data)
                if summary:
                    summary = _sanitize_non_executed_claims(summary)
                if write_confirmed and isinstance(result_data, dict) and result_data.get("summary"):
                    # Keep the original summary when execution is confirmed.
                    summary = result_data.get("summary", "")
            session_id = job.get("session_id") or "default"
            user_id = job.get("user_id", "")
            prompt = job.get("prompt", "")

            # Skip chat history and dayprint logging for proactive runs
            if session_id == "proactive":
                return

            if summary and user_id:
                from .chat_history_service import save_message
                await save_message(
                    user_id=user_id,
                    session_id=session_id,
                    role="assistant",
                    content=summary,
                    metadata={"type": "execution", "job_id": job_id, "skill_id": job.get("skill_id")},
                )
                # Log to Dayprint
                from .dayprint_service import log_advisor_chat
                profile = await db.profiles.find_one({"user_id": user_id}, {"name": 1}) or {}
                user_name = profile.get("name", "")
                asyncio.create_task(
                    log_advisor_chat(user_id, user_name, prompt, summary, session_id=session_id)
                )

            # Cross-advisor callback: announce result back to the requester's
            # collab thread.  Runs after main chat persistence so a callback
            # failure cannot block normal post-execution behavior.
            await _maybe_send_cross_advisor_callback(job, success=True, summary_text=summary, result_data=result_data)
    except Exception as e:
        logger.warning(f"Failed to save execution result to chat history: {e}")


async def _maybe_create_pending_clarification_from_result(db, job: dict, result_data) -> None:
    """Persist a pending clarification action when write-intent task creation needs more info."""
    if not isinstance(result_data, dict):
        return
    if job.get("skill_id") != "tasks_create":
        return
    if not job.get("is_write_operation_task"):
        return

    created_count = result_data.get("created_count")
    summary = (result_data.get("summary") or "").strip()
    if created_count != 0 or not summary:
        return

    now = datetime.utcnow()
    await db.advisor_pending_actions.update_one(
        {
            "user_id": job.get("user_id"),
            "session_id": job.get("session_id") or "default",
            "action_type": "task_create_clarification",
            "status": "awaiting_input",
        },
        {
            "$set": {
                "user_id": job.get("user_id"),
                "session_id": job.get("session_id") or "default",
                "action_type": "task_create_clarification",
                "skill_id": "tasks_create",
                "status": "awaiting_input",
                "original_request": job.get("prompt", ""),
                "clarification_prompt": summary,
                "updated_at": now,
                "expires_at": now + timedelta(hours=2),
            },
            "$setOnInsert": {"created_at": now},
        },
        upsert=True,
    )


async def _fail_job(
    db, job_id: str, error: str, stdout: str = "", stderr: str = "",
) -> None:
    now = format_utc_datetime(datetime.utcnow())
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

    try:
        job = await db.execution_jobs.find_one({"job_id": job_id})
        if job:
            await _maybe_send_cross_advisor_callback(
                job, success=False, summary_text=error, result_data=None
            )
    except Exception as e:
        logger.warning(f"Failed to send cross-advisor failure callback: {e}")


async def _maybe_send_cross_advisor_callback(
    job: dict,
    *,
    success: bool,
    summary_text: str,
    result_data,
) -> None:
    """Post an ``execution_result`` cross-message + collab audits when the
    job was kicked off in response to a cross-advisor approval.
    """
    ctx = job.get("cross_advisor_context")
    if not ctx:
        return

    thread_id = ctx.get("thread_id")
    requester_user_id = ctx.get("requester_user_id")
    approver_user_id = ctx.get("approver_user_id")
    if not (thread_id and requester_user_id and approver_user_id):
        return

    # Local imports to avoid circulars at module load.
    from . import advisor_cross_message_service
    from . import chat_history_service

    sanitized = advisor_cross_message_service.sanitize_summary(
        summary_text or ("Action completed." if success else "Action failed.")
    )

    try:
        await advisor_cross_message_service.create_execution_result(
            thread_id=thread_id,
            from_user_id=approver_user_id,
            to_user_id=requester_user_id,
            success=success,
            summary=sanitized,
            detail={"job_id": job.get("job_id"), "skill_id": job.get("skill_id")},
        )
    except Exception as e:
        logger.warning(f"cross_msg.execution_result write failed: {e}")

    collab_status = "done" if success else "failed"
    metadata = {
        "channel": "advisor_collab",
        "readonly": True,
        "thread_id": thread_id,
        "collab_status": collab_status,
    }
    requester_msg = (
        f"Result: {sanitized}" if success else f"Action failed: {sanitized}"
    )
    approver_msg = (
        f"Result reported back: {sanitized}" if success else f"Reported failure: {sanitized}"
    )
    try:
        await chat_history_service.save_message(
            user_id=requester_user_id,
            session_id=f"collab:{thread_id}",
            role="assistant",
            content=requester_msg,
            metadata={**metadata, "peer_user_id": approver_user_id},
        )
        await chat_history_service.save_message(
            user_id=approver_user_id,
            session_id=f"collab:{thread_id}",
            role="assistant",
            content=approver_msg,
            metadata={**metadata, "peer_user_id": requester_user_id},
        )
    except Exception as e:
        logger.warning(f"Failed to write cross-advisor collab audit: {e}")


def _is_write_confirmed(result_data) -> bool:
    """Infer whether a write operation actually produced changes."""
    if not isinstance(result_data, dict):
        return False

    execution_report = result_data.get("execution_report")
    if isinstance(execution_report, dict):
        if isinstance(execution_report.get("write_confirmed"), bool):
            return execution_report.get("write_confirmed")

    count_keys = (
        "created_count",
        "inserted_count",
        "updated_count",
        "modified_count",
        "upserted_count",
        "sent_count",
    )
    for key in count_keys:
        value = result_data.get(key)
        if isinstance(value, (int, float)) and value > 0:
            return True
    return False


def _sanitize_non_executed_claims(text: str) -> str:
    """Prevent success-claim hallucinations when execution isn't confirmed."""
    lowered = (text or "").lower()
    blocked_markers = (
        "i created",
        "i updated",
        "i sent",
        "done - i created",
        "done — i created",
        "done, i created",
    )
    if any(marker in lowered for marker in blocked_markers):
        return (
            "I could not confirm that the write action completed successfully yet. "
            "Please check the latest status or try again."
        )
    return text


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
    """Cancel a pending, generating, or running job."""
    db = get_database()
    result = await db.execution_jobs.update_one(
        {
            "job_id": job_id,
            "user_id": user_id,
            "status": {"$in": ["pending", "generating", "running", "retrying"]},
        },
        {"$set": {
            "status": "cancelled",
            "finished_at": format_utc_datetime(datetime.utcnow()),
        }},
    )
    return result.modified_count > 0
