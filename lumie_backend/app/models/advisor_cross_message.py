"""Pydantic models for advisor <-> advisor cross-user messaging."""
from pydantic import BaseModel, Field
from typing import Optional, Dict, Any
from enum import Enum


class CrossMessageType(str, Enum):
    ACTION_REQUEST = "action_request"
    DECISION_REPLY = "decision_reply"
    EXECUTION_RESULT = "execution_result"


class CrossMessageStatus(str, Enum):
    QUEUED = "queued"
    DELIVERED = "delivered"
    PROCESSED = "processed"
    FAILED = "failed"
    EXPIRED = "expired"


class CrossActionType(str, Enum):
    # MVP supports task completion only.
    TASKS_COMPLETE = "tasks_complete"


class CrossMessagePayload(BaseModel):
    action_type: Optional[CrossActionType] = None
    action_params: Dict[str, Any] = Field(default_factory=dict)
    require_confirmation: Optional[bool] = None
    decision: Optional[str] = None  # approve | reject
    execution_result: Optional[Dict[str, Any]] = None
    summary: Optional[str] = None  # user-facing summary, sanitized


class AdvisorCrossMessage(BaseModel):
    message_id: str
    thread_id: str
    from_user_id: str
    to_user_id: str
    from_advisor_id: str = "default"
    to_advisor_id: str = "default"
    message_type: CrossMessageType
    payload: CrossMessagePayload
    status: CrossMessageStatus
    idempotency_key: Optional[str] = None
    created_at: str
    updated_at: str
    expires_at: Optional[str] = None


class CrossAdvisorPendingActionStatus(str, Enum):
    AWAITING_PEER_REPLY = "awaiting_peer_reply"
    PEER_REPLIED = "peer_replied"
    AWAITING_USER_CONFIRM = "awaiting_user_confirm"
    APPROVED = "approved"
    REJECTED = "rejected"
    EXPIRED = "expired"
    CONSUMED = "consumed"
