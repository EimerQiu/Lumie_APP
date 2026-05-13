"""
Centralized datetime utilities for consistent timestamp formatting across Lumie.

All UTC timestamps in API responses must use ISO 8601 format with Z suffix for clarity.
"""

from datetime import datetime
from typing import Optional


def format_utc_datetime(dt) -> str:
    """
    Format a datetime to ISO 8601 string with Z suffix.

    This utility ensures consistent timestamp formatting across all Lumie services.
    All UTC datetimes should use this function for API responses.

    Args:
        dt: A datetime object (naive or aware), or an ISO 8601 string. If naive, assumed to be UTC.

    Returns:
        ISO 8601 formatted string with Z suffix, e.g. "2026-04-11T04:46:33Z"

    Examples:
        >>> from datetime import datetime
        >>> now = datetime.utcnow()
        >>> format_utc_datetime(now)
        '2026-04-11T04:46:33Z'

        >>> from datetime import datetime, timezone
        >>> now_tz = datetime.now(timezone.utc)
        >>> format_utc_datetime(now_tz)
        '2026-04-11T04:46:33Z'
    """
    if isinstance(dt, str):
        parsed = parse_utc_datetime(dt)
        if parsed is None:
            raise ValueError(f"Cannot parse datetime string: {dt!r}")
        dt = parsed
    return dt.strftime("%Y-%m-%dT%H:%M:%S") + "Z"


def format_utc_datetime_with_ms(dt: datetime) -> str:
    """
    Format a datetime to ISO 8601 string with milliseconds and Z suffix.

    Use this when millisecond precision is needed (e.g., for audit logs).

    Args:
        dt: A datetime object (naive or aware). If naive, assumed to be UTC.

    Returns:
        ISO 8601 formatted string with milliseconds and Z suffix,
        e.g. "2026-04-11T04:46:33.123Z"
    """
    return dt.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def parse_utc_datetime(date_str: Optional[str]) -> Optional[datetime]:
    """
    Parse an ISO 8601 datetime string (with or without Z suffix) to datetime.

    Handles both formats:
    - With Z: "2026-04-11T04:46:33Z"
    - With +00:00: "2026-04-11T04:46:33+00:00"
    - Without suffix: "2026-04-11T04:46:33"

    Args:
        date_str: ISO 8601 formatted datetime string or None

    Returns:
        datetime object in UTC, or None if input is None
    """
    if not date_str:
        return None

    # Remove Z suffix if present
    if date_str.endswith("Z"):
        date_str = date_str[:-1] + "+00:00"

    try:
        return datetime.fromisoformat(date_str)
    except (ValueError, TypeError):
        return None
