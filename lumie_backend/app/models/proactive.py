"""Pydantic models for the proactive advisor system."""
from pydantic import BaseModel
from typing import Optional
from enum import Enum


class ProactiveStatus(str, Enum):
    OK = "ok"
    CONCERN = "concern"
    MISSING = "missing"
    INSUFFICIENT_DATA = "insufficient_data"


class ProactiveSkillResult(BaseModel):
    skill_id: str
    domain: str  # descriptive label: sleep | activity | medication | recovery | dayprint | team_followup
    status: ProactiveStatus
    summary: str
    score: float  # 0.0 (no concern) → 1.0 (critical)
    signals: list[str] = []
    recommended_actions: list[str] = []
    evidence: dict = {}


class LastNudgeContext(BaseModel):
    reason: str = ""
    nudged_at: str = ""
    run_id: Optional[str] = None
    primary_domain: Optional[str] = None
    evidence_summary: dict = {}  # domain → {score, status, top_signal}


class ProactiveDecisionInput(BaseModel):
    user_name: str
    role: str = "teen"
    icd10: str = ""
    local_time: str = ""
    skill_results: list[ProactiveSkillResult] = []
    last_round_results: list[dict] = []  # previous round's skill results for comparison
    today_dayprint: Optional[dict] = None  # today's dayprint for context
    last_nudge: Optional[LastNudgeContext] = None


class ProactiveInformationRound(BaseModel):
    round_id: str
    user_id: str
    created_at: str
    skill_results: list[ProactiveSkillResult] = []


class ProactiveDecisionResult(BaseModel):
    should_nudge: bool
    reason_code: str
    message: Optional[str] = None
    primary_domain: Optional[str] = None
    evidence_skills: list[str] = []
    decision_summary: str = ""
    confidence: float = 0.0


class ProactiveRunRecord(BaseModel):
    run_id: str
    user_id: str
    started_at: str
    finished_at: Optional[str] = None
    round_id: Optional[str] = None  # reference to proactive_information_rounds
    selected_skills: list[str] = []
    skill_results: list[ProactiveSkillResult] = []
    decision_result: dict = {}
    delivery_result: dict = {}
