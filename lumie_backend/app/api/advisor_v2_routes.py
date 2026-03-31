"""Advisor v2 API routes — unified capability + skill execution system.

Endpoints:
  POST /api/v2/advisor/chat           — Main advisor chat (skill-aware)
  GET  /api/v2/advisor/jobs/{job_id}  — Execution job status
  GET  /api/v2/advisor/capabilities   — List capabilities with user state
  PATCH /api/v2/advisor/capabilities/{capability_id} — Toggle capability
  GET  /api/v2/advisor/skills         — List indexed skills
  POST /api/v2/advisor/skills/reindex — Trigger skill rescan
  GET  /api/v2/advisor/skills/{skill_id}/credential — Get credential (sanitized)
  PUT  /api/v2/advisor/skills/{skill_id}/credential — Save credential
  POST /api/v2/advisor/skills/{skill_id}/test       — Test credential
"""
import asyncio
import logging

from fastapi import APIRouter, Depends, HTTPException, status

from ..services.auth_service import get_current_user_id
from ..services import advisor_orchestrator
from ..services import capability_service
from ..services import skill_credential_service
from ..services import execution_service
from ..services.skill_registry_service import skill_registry
from ..services.chat_history_service import save_exchange, save_message
from ..services.dayprint_service import log_advisor_chat
from ..core.database import get_database
from ..models.execution_job import (
    AdvisorChatV2Request,
    AdvisorChatV2Response,
    ExecutionJobResponse,
)
from ..models.advisor_capability import (
    CapabilityResponse,
    CapabilityToggleRequest,
    SkillSummary,
    SkillDetail,
)
from ..models.advisor_skill_credential import (
    CredentialSaveRequest,
    CredentialResponse,
    CredentialTestResponse,
)

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/advisor", tags=["advisor-v2"])


# ── Chat ─────────────────────────────────────────────────────────────────────

@router.post("/chat", response_model=AdvisorChatV2Response)
async def advisor_chat_v2(
    request: AdvisorChatV2Request,
    user_id: str = Depends(get_current_user_id),
):
    """Main v2 advisor chat endpoint with skill execution support."""
    if not request.message.strip():
        raise HTTPException(status_code=400, detail="Message cannot be empty")

    try:
        result = await advisor_orchestrator.handle_chat(
            user_id=user_id,
            message=request.message,
            history=request.history,
            session_id=request.session_id,
            target_user_id=request.target_user_id,
            team_id=request.team_id,
        )

        response_type = result.get("type", "direct")

        # Save to chat history
        if response_type == "direct" or response_type == "guidance":
            await save_exchange(
                user_id=user_id,
                session_id=request.session_id or "default",
                user_message=request.message,
                assistant_reply=result.get("reply", ""),
                metadata={
                    "type": response_type,
                    "nav_hint": result.get("nav_hint"),
                },
            )
            # Log to Dayprint in background
            db = get_database()
            profile = await db.profiles.find_one({"user_id": user_id}, {"name": 1}) or {}
            user_name = profile.get("name", "")
            asyncio.create_task(
                log_advisor_chat(
                    user_id, user_name, request.message, result.get("reply", ""),
                    session_id=request.session_id,
                )
            )
        elif response_type == "execution":
            await save_message(
                user_id=user_id,
                session_id=request.session_id or "default",
                role="user",
                content=request.message,
                metadata={
                    "type": "execution",
                    "job_id": result.get("job_id"),
                    "skill_id": result.get("skill_id"),
                },
            )

        return AdvisorChatV2Response(
            type=response_type,
            reply=result.get("reply", ""),
            job_id=result.get("job_id"),
            skill_id=result.get("skill_id"),
            status=result.get("status"),
            nav_hint=result.get("nav_hint"),
        )

    except RuntimeError as e:
        if "PALEBLUEDOT_API_KEY" in str(e):
            raise HTTPException(status_code=503, detail="AI service not configured")
        raise HTTPException(status_code=502, detail=str(e))
    except Exception as e:
        logger.exception("Advisor v2 chat error")
        raise HTTPException(status_code=500, detail="Internal server error")


# ── Jobs ─────────────────────────────────────────────────────────────────────

@router.get("/jobs/{job_id}")
async def get_execution_job(
    job_id: str,
    user_id: str = Depends(get_current_user_id),
):
    """Get execution job status and result."""
    job = await execution_service.get_job(job_id, user_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")

    return job


@router.post("/jobs/{job_id}/cancel")
async def cancel_execution_job(
    job_id: str,
    user_id: str = Depends(get_current_user_id),
):
    """Cancel a pending or generating execution job."""
    cancelled = await execution_service.cancel_job(job_id, user_id)
    if not cancelled:
        raise HTTPException(status_code=400, detail="Job cannot be cancelled")
    return {"status": "cancelled"}


# ── Capabilities ─────────────────────────────────────────────────────────────

@router.get("/capabilities")
async def list_capabilities(
    user_id: str = Depends(get_current_user_id),
):
    """List all capabilities with user-specific state."""
    caps = await capability_service.get_user_capabilities(user_id)
    return {"capabilities": caps}


@router.patch("/capabilities/{capability_id}")
async def toggle_capability(
    capability_id: str,
    request: CapabilityToggleRequest,
    user_id: str = Depends(get_current_user_id),
):
    """Enable or disable a capability for the current user."""
    result = await capability_service.toggle_capability(
        user_id, capability_id, request.enabled
    )

    # Auto-provision Lumie internal credentials when enabling
    if request.enabled and capability_id == "lumie_internal_data":
        skills = skill_registry.get_skills_by_capability("lumie_internal_data")
        for skill in skills:
            if skill.requires_ping:
                await skill_credential_service.ensure_lumie_internal_credential(
                    user_id, skill.skill_id
                )

    return result


# ── Skills ───────────────────────────────────────────────────────────────────

@router.get("/skills")
async def list_skills(
    user_id: str = Depends(get_current_user_id),
):
    """List all indexed system skills."""
    all_skills = skill_registry.get_all_skills()
    return {
        "skills": [
            {
                "skill_id": s.skill_id,
                "title": s.title,
                "capability_id": s.capability_id,
                "runtime_type": s.runtime_type,
                "summary": s.summary,
                "tags": s.tags,
                "requires_credentials": s.requires_credentials,
                "requires_ping": s.requires_ping,
                "shared_credential_id": s.shared_credential_id,
                "credential_display_name": s.credential_display_name,
                "status": s.status,
            }
            for s in all_skills
        ],
    }


@router.get("/skills/{skill_id}")
async def get_skill_detail(
    skill_id: str,
    user_id: str = Depends(get_current_user_id),
):
    """Get detailed info about a specific skill."""
    skill = skill_registry.get_skill(skill_id)
    if not skill:
        raise HTTPException(status_code=404, detail="Skill not found")
    return {
        "skill_id": skill.skill_id,
        "title": skill.title,
        "capability_id": skill.capability_id,
        "runtime_type": skill.runtime_type,
        "summary": skill.summary,
        "tags": skill.tags,
        "keywords": skill.keywords,
        "requires_credentials": skill.requires_credentials,
        "requires_ping": skill.requires_ping,
        "target_system": skill.target_system,
        "status": skill.status,
    }


@router.post("/skills/reindex")
async def reindex_skills(
    user_id: str = Depends(get_current_user_id),
):
    """Trigger a full skill rescan and reindex."""
    result = skill_registry.scan_and_index()
    return {"message": "Reindex complete", **result}


# ── Credential helpers ───────────────────────────────────────────────────────

def _resolve_credential_key(skill) -> str:
    """Return the DB key used to store/retrieve a skill's credential.

    Skills with a shared_credential_id use a shared pool key
    (__shared__{id}) that is independent of any skill_id.
    """
    if skill.shared_credential_id:
        return f"__shared__{skill.shared_credential_id}"
    return skill.skill_id


# ── Credentials ──────────────────────────────────────────────────────────────

@router.get("/skills/{skill_id}/credential")
async def get_skill_credential(
    skill_id: str,
    user_id: str = Depends(get_current_user_id),
):
    """Get the credential for a skill (sanitized — no passwords or pings)."""
    skill = skill_registry.get_skill(skill_id)
    cred_key = _resolve_credential_key(skill) if skill else skill_id
    cred = await skill_credential_service.get_credential(user_id, cred_key)
    if not cred:
        return {"status": "missing", "skill_id": cred_key}
    return skill_credential_service.sanitize_credential_for_response(cred)


@router.put("/skills/{skill_id}/credential")
async def save_skill_credential(
    skill_id: str,
    request: CredentialSaveRequest,
    user_id: str = Depends(get_current_user_id),
):
    """Save or update credentials for a skill."""
    # Verify skill exists
    skill = skill_registry.get_skill(skill_id)
    if not skill:
        raise HTTPException(status_code=404, detail="Skill not found")

    cred = await skill_credential_service.save_credential(
        user_id=user_id,
        skill_id=_resolve_credential_key(skill),
        data=request.model_dump(exclude_none=True),
    )

    # Refresh capability status
    await capability_service.refresh_capability_status(user_id, skill.capability_id)

    return skill_credential_service.sanitize_credential_for_response(cred)


@router.post("/skills/{skill_id}/test")
async def test_skill_credential(
    skill_id: str,
    user_id: str = Depends(get_current_user_id),
):
    """Test whether credentials for a skill are usable."""
    skill = skill_registry.get_skill(skill_id)
    if not skill:
        raise HTTPException(status_code=404, detail="Skill not found")

    cred_key = _resolve_credential_key(skill)
    cred = await skill_credential_service.get_credential(user_id, cred_key)
    if not cred:
        return CredentialTestResponse(
            success=False, status="missing",
            message="No credentials configured for this skill",
        )

    # For Lumie internal skills, test ping validity
    if skill.requires_ping:
        ping = cred.get("ping")
        if not ping:
            await skill_credential_service.update_credential_status(
                user_id, cred_key, "invalid", "ping_missing"
            )
            return CredentialTestResponse(
                success=False, status="invalid",
                message="Internal access token is missing",
            )
        # Ping is auto-generated and always valid if it exists
        await skill_credential_service.update_credential_status(
            user_id, cred_key, "valid", "ping_ok"
        )
        return CredentialTestResponse(
            success=True, status="valid",
            message="Internal access credentials are valid",
        )

    # For external_api skills, test reachability (GET skills) or key presence (POST skills)
    if skill.runtime_type == "external_api":
        base_url = cred.get("base_url", "").rstrip("/")
        if not base_url:
            await skill_credential_service.update_credential_status(
                user_id, cred_key, "saved_not_tested", "fields_incomplete"
            )
            return CredentialTestResponse(
                success=False, status="saved_not_tested",
                message="Base URL is required",
            )
        # POST skills: just verify base_url + api_key are present (can't safely test-fire a write action)
        if skill.api_method == "POST":
            if not cred.get("password"):
                await skill_credential_service.update_credential_status(
                    user_id, cred_key, "saved_not_tested", "fields_incomplete"
                )
                return CredentialTestResponse(
                    success=False, status="saved_not_tested",
                    message="API key (password field) is required",
                )
            await skill_credential_service.update_credential_status(
                user_id, cred_key, "valid", "fields_complete"
            )
            return CredentialTestResponse(
                success=True, status="valid",
                message="Credentials saved.",
            )
        # GET skills: live reachability test
        import httpx
        endpoint = skill.api_endpoint or ""
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.get(base_url + endpoint)
                resp.raise_for_status()
            await skill_credential_service.update_credential_status(
                user_id, cred_key, "valid", "reachable"
            )
            return CredentialTestResponse(
                success=True, status="valid",
                message="Connection successful — API is reachable.",
            )
        except httpx.HTTPStatusError as e:
            await skill_credential_service.update_credential_status(
                user_id, cred_key, "invalid", f"http_{e.response.status_code}"
            )
            return CredentialTestResponse(
                success=False, status="invalid",
                message=f"API returned HTTP {e.response.status_code}",
            )
        except Exception as e:
            await skill_credential_service.update_credential_status(
                user_id, cred_key, "invalid", "unreachable"
            )
            return CredentialTestResponse(
                success=False, status="invalid",
                message=f"Could not reach API: {e}",
            )

    # For browser/email skills, we can't fully test yet (Phase 1)
    # Mark as saved_not_tested or valid based on completeness
    # Gmail doesn't need base_url (hardcoded to https://mail.google.com)
    has_required = bool(cred.get("username") and cred.get("password"))
    if skill_id == "gmail_inbox_check":
        # Gmail only needs username and password
        pass
    else:
        # Other browser skills need base_url as well
        has_required = bool(cred.get("base_url") and has_required)

    if has_required:
        await skill_credential_service.update_credential_status(
            user_id, cred_key, "valid", "fields_complete"
        )
        return CredentialTestResponse(
            success=True, status="valid",
            message="Credentials saved. Full connection test will be available in a future update.",
        )
    else:
        await skill_credential_service.update_credential_status(
            user_id, cred_key, "saved_not_tested", "fields_incomplete"
        )
        required_msg = "base_url, username, or password" if skill_id != "gmail_inbox_check" else "username or password"
        return CredentialTestResponse(
            success=False, status="saved_not_tested",
            message=f"Some required fields are missing ({required_msg})",
        )
