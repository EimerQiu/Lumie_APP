"""Static security scanning for AI-generated analysis code.

Scans Python code for prohibited patterns before execution in the sandbox.
"""
import re
import logging
from typing import Optional

logger = logging.getLogger(__name__)

# ── Prohibited patterns ──────────────────────────────────────────────────────

_DB_WRITE_PATTERNS = [
    r"insert_one", r"insert_many",
    r"update_one", r"update_many",
    r"delete_one", r"delete_many",
    r"replace_one",
    r"\.drop\b", r"drop_collection", r"drop_database",
    r"create_index", r"drop_index",
    r"bulk_write",
    r"aggregate.*\$out", r"aggregate.*\$merge",
]

_SYSTEM_CALL_PATTERNS = [
    r"\bsubprocess\b", r"\bos\.system\b", r"\bos\.popen\b",
    r"\beval\s*\(", r"\bexec\s*\(", r"\bcompile\s*\(",
    r"__import__",
    r"\bimportlib\b",
]

_NETWORK_PATTERNS = [
    r"\burllib\b", r"\brequests\b", r"\bhttpx\b", r"\baiohttp\b",
    r"\bsocket\b", r"\bhttp\.client\b",
]

_SENSITIVE_COLLECTION_PATTERNS = [
    r"\.users[\.\[]",
    r"\.pending_invitations[\.\[]",
    r"\bpassword\b", r"\bhashed_password\b",
    r"\bdevice_token\b",
]

_FILE_PATTERNS = [
    r"\bos\.remove\b", r"\bos\.unlink\b",
    r"\bshutil\.rmtree\b", r"\bshutil\.move\b",
]

ALL_PATTERNS: list[tuple[str, str]] = []
for p in _DB_WRITE_PATTERNS:
    ALL_PATTERNS.append((p, "db_write_operation"))
for p in _SYSTEM_CALL_PATTERNS:
    ALL_PATTERNS.append((p, "system_call"))
for p in _NETWORK_PATTERNS:
    ALL_PATTERNS.append((p, "network_access"))
for p in _SENSITIVE_COLLECTION_PATTERNS:
    ALL_PATTERNS.append((p, "sensitive_collection_access"))
for p in _FILE_PATTERNS:
    ALL_PATTERNS.append((p, "file_manipulation"))


def scan_code(code: str) -> Optional[str]:
    """Scan generated code for security violations.

    Returns None if code is safe, or a description of the violation found.
    """
    for pattern, category in ALL_PATTERNS:
        match = re.search(pattern, code)
        if match:
            violation = f"{category}: {match.group()}"
            logger.warning(f"Security violation in generated code: {violation}")
            return violation

    # Check that file writes only target /output/
    # Find all open() calls with write mode
    open_writes = re.finditer(r"open\s*\(([^)]+)\)", code)
    for m in open_writes:
        args = m.group(1)
        # If it contains a write mode flag and doesn't reference /output
        if re.search(r"['\"]w", args) and "/output" not in args:
            violation = f"file_write_outside_output: {m.group()}"
            logger.warning(f"Security violation in generated code: {violation}")
            return violation

    return None
