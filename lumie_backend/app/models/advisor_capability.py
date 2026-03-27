"""Pydantic models for the Advisor capability + skill system."""
from pydantic import BaseModel, Field
from typing import Optional
from enum import Enum


# ── Capability Models ────────────────────────────────────────────────────────

class CapabilityStatus(str, Enum):
    DISABLED = "disabled"
    ENABLED_NOT_READY = "enabled_not_ready"
    READY = "ready"


class CapabilityResponse(BaseModel):
    capability_id: str
    display_name: str
    description: str
    enabled: bool
    status: CapabilityStatus = CapabilityStatus.DISABLED
    missing: Optional[list[str]] = None


class CapabilityToggleRequest(BaseModel):
    enabled: bool


# ── Skill Models ─────────────────────────────────────────────────────────────

class SkillSummary(BaseModel):
    skill_id: str
    title: str
    capability_id: str
    runtime_type: str
    summary: str
    tags: list[str] = []
    status: str = "indexed"


class SkillDetail(BaseModel):
    skill_id: str
    title: str
    capability_id: str
    runtime_type: str
    summary: str
    tags: list[str] = []
    keywords: list[str] = []
    requires_ping: bool = False
    requires_credentials: bool = False
    target_system: str = ""
    status: str = "indexed"
    full_content: Optional[str] = None
