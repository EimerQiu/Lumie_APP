"""Pydantic models for advisor skill credentials."""
from pydantic import BaseModel, Field
from typing import Optional
from enum import Enum


class CredentialStatus(str, Enum):
    MISSING = "missing"
    SAVED_NOT_TESTED = "saved_not_tested"
    VALID = "valid"
    INVALID = "invalid"


class CredentialSaveRequest(BaseModel):
    system_name: Optional[str] = None
    base_url: Optional[str] = None
    username: Optional[str] = None
    password: Optional[str] = None
    notes: Optional[str] = None


class CredentialResponse(BaseModel):
    credential_id: str
    user_id: str
    skill_id: str
    status: CredentialStatus
    system_name: Optional[str] = None
    base_url: Optional[str] = None
    username: Optional[str] = None
    has_password: bool = False
    has_ping: bool = False
    notes: Optional[str] = None
    last_tested_at: Optional[str] = None
    last_test_result: Optional[str] = None
    created_at: str
    updated_at: str


class CredentialTestResponse(BaseModel):
    success: bool
    status: CredentialStatus
    message: str
