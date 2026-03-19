"""Analysis API routes — job status, cancellation, and history."""
import asyncio
import logging

from fastapi import APIRouter, Depends, HTTPException, Query, status

from ..core.database import get_database
from ..services.auth_service import get_current_user_id
from ..services.analysis_service import get_job, get_jobs, cancel_job
from ..services.dayprint_service import log_advisor_chat
from ..models.analysis import AnalysisJobResponse, AnalysisJobListResponse, AnalysisResult

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/analysis", tags=["analysis"])


def _format_job(job: dict) -> AnalysisJobResponse:
    """Convert a raw job dict to an AnalysisJobResponse."""
    result = None
    if job.get("result"):
        result = AnalysisResult(
            summary=job["result"].get("summary", ""),
            data=job["result"].get("data"),
            chart_base64=job["result"].get("chart_base64"),
            nav_hint=job["result"].get("nav_hint"),
        )
    return AnalysisJobResponse(
        job_id=job["job_id"],
        status=job["status"],
        prompt=job["prompt"],
        result=result,
        error=job.get("error") or None,
        created_at=job.get("created_at", ""),
        started_at=job.get("started_at"),
        finished_at=job.get("finished_at"),
    )


@router.get("/jobs/{job_id}", response_model=AnalysisJobResponse)
async def get_analysis_job(
    job_id: str,
    user_id: str = Depends(get_current_user_id),
):
    """Query the status and result of an analysis job.

    Only the job creator can view their own jobs.
    """
    job = await get_job(job_id, user_id)
    if not job:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Analysis job not found.",
        )

    # Log to Dayprint once when job first succeeds
    if job.get("status") == "success" and not job.get("dayprint_logged"):
        db = get_database()
        await db.analysis_jobs.update_one(
            {"job_id": job_id}, {"$set": {"dayprint_logged": True}}
        )
        profile = await db.profiles.find_one({"user_id": user_id}, {"name": 1}) or {}
        user_name = profile.get("name", "")
        question = job.get("prompt", "")
        result_summary = (job.get("result") or {}).get("summary", "")
        asyncio.create_task(
            log_advisor_chat(user_id, user_name, question, result_summary)
        )

    return _format_job(job)


@router.get("/jobs", response_model=AnalysisJobListResponse)
async def list_analysis_jobs(
    user_id: str = Depends(get_current_user_id),
    limit: int = Query(default=10, ge=1, le=50),
    offset: int = Query(default=0, ge=0),
):
    """List the current user's analysis job history, sorted by newest first."""
    jobs, has_more = await get_jobs(user_id, limit=limit, offset=offset)
    return AnalysisJobListResponse(
        jobs=[_format_job(j) for j in jobs],
        has_more=has_more,
    )


@router.post("/jobs/{job_id}/cancel")
async def cancel_analysis_job(
    job_id: str,
    user_id: str = Depends(get_current_user_id),
):
    """Cancel a running or pending analysis job.

    Only the job creator can cancel. Jobs that are already completed,
    failed, or cancelled cannot be cancelled again.
    """
    success = await cancel_job(job_id, user_id)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Job not found or cannot be cancelled.",
        )
    return {"status": "cancelled", "job_id": job_id}
