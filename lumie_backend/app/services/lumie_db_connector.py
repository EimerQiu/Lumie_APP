"""Lumie DB Connector — server-side data access with permission enforcement.

This connector validates ping, enforces team/admin permissions,
validates script safety, executes scripts, and returns filtered results.

Phase 1: in-process service calls, not a separate process.
"""
import ast
import io
import json
import logging
import traceback
from contextlib import redirect_stdout, redirect_stderr
from datetime import datetime
from typing import Any, Optional

from ..core.database import get_database
from . import skill_credential_service

logger = logging.getLogger(__name__)

# ── Collections accessible via connector ─────────────────────────────────────

ALLOWED_COLLECTIONS = {
    "profiles", "activities", "walk_tests", "tasks", "task_templates",
    "teams", "team_members", "sleep_sessions", "execution_jobs",
}

# Fields that must never be returned
SENSITIVE_FIELDS = {
    "hashed_password", "verification_token", "device_token",
    "password", "ping", "_id",
}

# Collections where writes are allowed (constrained)
WRITABLE_COLLECTIONS = {"tasks", "task_templates"}

# Forbidden AST node types (security)
FORBIDDEN_AST_NODES = {
    ast.Import, ast.ImportFrom,  # no imports
}


# ── Main entry point ─────────────────────────────────────────────────────────

async def execute(
    request_user_id: str,
    ping: str,
    skill_id: str,
    job_id: str,
    script: str,
    target_user_id: Optional[str] = None,
    request_summary: str = "",
    history_context: Optional[dict] = None,
    user_timezone: str = "UTC",
) -> dict:
    """Execute a data-access script with full permission enforcement.

    Args:
        target_user_id: The intended target user. If None, falls back to
            script analysis or request_user_id (self-access).

    Returns a structured result dict (success or failure).
    """
    db = get_database()

    # ── Step 1: Validate ping ────────────────────────────────────────────
    ping_valid = await skill_credential_service.validate_ping(
        request_user_id, skill_id, ping
    )
    if not ping_valid:
        return _error("ping_invalid", "ping_validation", False,
                       "Invalid or missing ping token")

    logger.info(f"[connector] job={job_id} skill={skill_id} target={target_user_id or request_user_id} tz={user_timezone}")

    # ── Step 2: Parse and validate the script ────────────────────────────
    parse_result = _validate_script(script)
    if not parse_result["valid"]:
        logger.warning(f"[connector] job={job_id} script parse error: {parse_result['error']}")
        return _error("script_parse_error", "script_parse", True,
                       parse_result["error"])

    # ── Step 3: Identify target user and collections from script ─────────
    analysis = _analyze_script(script)

    # Use the explicitly passed target_user_id if available,
    # otherwise fall back to what the script analysis found
    if not target_user_id:
        target_user_id = analysis.get("target_user_id")
    accessed_collections = analysis.get("collections", set())
    has_writes = analysis.get("has_writes", False)
    has_deletes = analysis.get("has_deletes", False)

    logger.info(f"[connector] job={job_id} collections={accessed_collections} writes={has_writes} deletes={has_deletes}")

    # ── Step 4: Check collection access ──────────────────────────────────
    invalid_collections = accessed_collections - ALLOWED_COLLECTIONS
    if invalid_collections:
        logger.warning(f"[connector] job={job_id} DENIED invalid collections: {invalid_collections}")
        await _write_audit_log(db, job_id, request_user_id, skill_id,
                               target_user_id, "denied",
                               f"Invalid collections: {invalid_collections}")
        return _error("invalid_collection", "permission_check", False,
                       f"Access to collections not allowed: {invalid_collections}")

    # ── Step 5: Check write safety ───────────────────────────────────────
    if has_deletes:
        logger.warning(f"[connector] job={job_id} DENIED delete operation attempted")
        await _write_audit_log(db, job_id, request_user_id, skill_id,
                               target_user_id, "denied", "Delete operation attempted")
        return _error("unsafe_write", "permission_check", False,
                       "Delete operations are not allowed")

    if has_writes:
        non_writable = accessed_collections - WRITABLE_COLLECTIONS
        if non_writable and has_writes:
            # Check if write targets are all in writable collections
            write_collections = analysis.get("write_collections", set())
            if write_collections - WRITABLE_COLLECTIONS:
                logger.warning(f"[connector] job={job_id} DENIED write to non-writable: {write_collections - WRITABLE_COLLECTIONS}")
                await _write_audit_log(db, job_id, request_user_id, skill_id,
                                       target_user_id, "denied",
                                       f"Write to non-writable: {write_collections - WRITABLE_COLLECTIONS}")
                return _error("unsafe_write", "permission_check", False,
                               "Write operations only allowed on tasks and task_templates")

    # ── Step 6: Permission check ─────────────────────────────────────────
    if target_user_id and target_user_id != request_user_id:
        has_access = await _check_team_admin_access(
            db, request_user_id, target_user_id
        )
        if not has_access:
            logger.warning(f"[connector] job={job_id} DENIED no team admin access from {request_user_id} to {target_user_id}")
            await _write_audit_log(db, job_id, request_user_id, skill_id,
                                   target_user_id, "denied",
                                   "No team admin relationship")
            return _error("permission_denied", "permission_check", False,
                           "You do not have permission to access this user's data")

    # ── Step 7: Execute the script ───────────────────────────────────────
    logger.info(f"[connector] job={job_id} executing script...")
    try:
        result = await _execute_script(db, script, request_user_id, target_user_id, user_timezone)
    except Exception as e:
        tb = traceback.format_exc()
        logger.error(f"[connector] job={job_id} script execution exception: {e}")
        return _error("script_execute_error", "script_execute", True,
                       str(e), stderr=tb)

    logger.info(f"[connector] job={job_id} script done. stdout_len={len(result.get('stdout',''))} stderr_len={len(result.get('stderr',''))}")

    # ── Step 8: Filter sensitive fields ──────────────────────────────────
    filtered_data = _filter_sensitive(result.get("data"))

    # ── Step 9: Write audit log ──────────────────────────────────────────
    await _write_audit_log(db, job_id, request_user_id, skill_id,
                           target_user_id or request_user_id, "allowed",
                           f"Accessed: {accessed_collections}")

    return {
        "success": True,
        "data": filtered_data,
        "stdout": result.get("stdout", ""),
        "stderr": result.get("stderr", ""),
        "error": None,
        "target_user_id": target_user_id or request_user_id,
        "collections": list(accessed_collections),
    }


# ── Script validation ────────────────────────────────────────────────────────

def _validate_script(script: str) -> dict:
    """Parse the script as Python AST and check for forbidden constructs."""
    try:
        tree = ast.parse(script)
    except SyntaxError as e:
        return {"valid": False, "error": f"Syntax error: {e}"}

    for node in ast.walk(tree):
        if type(node) in FORBIDDEN_AST_NODES:
            return {"valid": False, "error": f"Forbidden construct: {type(node).__name__}"}

        # Check for dangerous function calls
        if isinstance(node, ast.Call):
            func = node.func
            if isinstance(func, ast.Name) and func.id in ("exec", "eval", "compile", "__import__", "open"):
                return {"valid": False, "error": f"Forbidden function: {func.id}"}
            if isinstance(func, ast.Attribute) and func.attr in ("drop", "drop_collection", "drop_database", "drop_index"):
                return {"valid": False, "error": f"Forbidden operation: {func.attr}"}

    return {"valid": True, "error": None}


def _analyze_script(script: str) -> dict:
    """Analyze script to identify target user, collections, and write operations."""
    result = {
        "target_user_id": None,
        "collections": set(),
        "has_writes": False,
        "has_deletes": False,
        "write_collections": set(),
    }

    # Find collection references: db.collection_name or db["collection_name"]
    import re
    # Pattern: db.collection_name
    for match in re.finditer(r'\bdb\.(\w+)', script):
        coll = match.group(1)
        if coll not in ("client", "command", "name", "list_collection_names"):
            result["collections"].add(coll)

    # Pattern: db["collection_name"]
    for match in re.finditer(r'db\[[\"\'](\w+)[\"\']\]', script):
        result["collections"].add(match.group(1))

    # Find target_user_id in script
    for match in re.finditer(r'target_user_id\s*=\s*["\']([^"\']+)["\']', script):
        result["target_user_id"] = match.group(1)

    # Also check for user_id variable assignments
    for match in re.finditer(r'TARGET_USER_ID\s*=\s*["\']([^"\']+)["\']', script):
        result["target_user_id"] = match.group(1)

    # Detect writes
    write_ops = ("insert_one", "insert_many", "update_one", "update_many",
                 "replace_one", "find_one_and_update", "find_one_and_replace")
    delete_ops = ("delete_one", "delete_many", "find_one_and_delete",
                  "drop", "drop_collection")

    for op in write_ops:
        if op in script:
            result["has_writes"] = True
            # Try to find which collection
            for match in re.finditer(rf'db\.(\w+)\.{op}', script):
                result["write_collections"].add(match.group(1))

    for op in delete_ops:
        if op in script:
            result["has_deletes"] = True

    return result


# ── Script execution ─────────────────────────────────────────────────────────

async def _execute_script(
    db_instance,
    script: str,
    request_user_id: str,
    target_user_id: Optional[str],
    user_timezone: str = "UTC",
) -> dict:
    """Execute the script in a restricted context with DB access.

    The script gets access to `db` (the Motor database) and helper variables.
    It must write its result to `_result`.
    """
    from motor.motor_asyncio import AsyncIOMotorDatabase

    stdout_buf = io.StringIO()
    stderr_buf = io.StringIO()

    # Build the execution namespace
    from datetime import timedelta, timezone
    from zoneinfo import ZoneInfo
    namespace = {
        "db": db_instance,
        "request_user_id": request_user_id,
        "target_user_id": target_user_id or request_user_id,
        "TARGET_USER_ID": target_user_id or request_user_id,
        "REQUEST_USER_ID": request_user_id,
        "user_timezone": user_timezone,
        "_result": None,
        "json": json,
        "datetime": datetime,
        "timedelta": timedelta,
        "timezone": timezone,
        "ZoneInfo": ZoneInfo,
        "str": str,
        "int": int,
        "float": float,
        "len": len,
        "list": list,
        "dict": dict,
        "bool": bool,
        "isinstance": isinstance,
        "range": range,
        "enumerate": enumerate,
        "sorted": sorted,
        "min": min,
        "max": max,
        "sum": sum,
        "round": round,
        "abs": abs,
        "any": any,
        "all": all,
        "zip": zip,
        "map": map,
        "filter": filter,
        "set": set,
        "tuple": tuple,
        "type": type,
        "None": None,
        "True": True,
        "False": False,
        "print": lambda *args, **kwargs: print(*args, file=stdout_buf, **kwargs),
    }

    # Execute async script
    # Wrap script in an async function so it can use await
    wrapped = f"async def _script_main():\n"
    for line in script.split("\n"):
        wrapped += f"    {line}\n"
    wrapped += "\n    return _result\n"

    exec(compile(wrapped, "<skill_script>", "exec"), namespace)
    result_data = await namespace["_script_main"]()

    return {
        "data": result_data,
        "stdout": stdout_buf.getvalue(),
        "stderr": stderr_buf.getvalue(),
    }


# ── Permission helpers ───────────────────────────────────────────────────────

async def _check_team_admin_access(db_instance, request_user_id: str, target_user_id: str) -> bool:
    """Check if request_user is a team admin with access to target_user's data."""
    # Find all teams where request_user is admin
    admin_teams = db_instance.team_members.find({
        "user_id": request_user_id,
        "role": "admin",
        "status": "member",
    })

    async for membership in admin_teams:
        team_id = membership["team_id"]
        # Check if target user is a member of the same team
        target_member = await db_instance.team_members.find_one({
            "team_id": team_id,
            "user_id": target_user_id,
            "status": "member",
        })
        if target_member:
            return True

    return False


# ── Result filtering + serialization ─────────────────────────────────────────

def _filter_sensitive(data: Any) -> Any:
    """Recursively strip sensitive fields and convert non-serializable types."""
    if data is None:
        return None
    if isinstance(data, dict):
        return {
            k: _filter_sensitive(v)
            for k, v in data.items()
            if k not in SENSITIVE_FIELDS
        }
    if isinstance(data, list):
        return [_filter_sensitive(item) for item in data]
    # Convert MongoDB ObjectId to string
    if hasattr(data, '__str__') and type(data).__name__ == 'ObjectId':
        return str(data)
    # Convert datetime to ISO string
    if isinstance(data, datetime):
        return data.isoformat()
    return data


# ── Audit logging ────────────────────────────────────────────────────────────

async def _write_audit_log(
    db_instance,
    job_id: str,
    user_id: str,
    skill_id: str,
    target_user_id: Optional[str],
    decision: str,
    reason: str,
) -> None:
    """Write an audit log entry."""
    try:
        import uuid
        await db_instance.execution_audit_logs.insert_one({
            "log_id": str(uuid.uuid4()),
            "job_id": job_id,
            "user_id": user_id,
            "skill_id": skill_id,
            "target_user_id": target_user_id,
            "decision": decision,
            "reason": reason,
            "created_at": datetime.utcnow().isoformat(),
        })
    except Exception as e:
        logger.error(f"Failed to write audit log: {e}")


# ── Error helper ─────────────────────────────────────────────────────────────

def _error(
    error_type: str,
    error_stage: str,
    retryable: bool,
    error: str,
    stdout: str = "",
    stderr: str = "",
) -> dict:
    return {
        "success": False,
        "error_type": error_type,
        "error_stage": error_stage,
        "retryable": retryable,
        "error": error,
        "stdout": stdout,
        "stderr": stderr,
    }
