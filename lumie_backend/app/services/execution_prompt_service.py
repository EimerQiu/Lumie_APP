"""Execution Prompt Service — assembles prompts for skill-based code generation.

Replaces analysis_prompt_service.py for the unified execution system.
"""
import json
import logging
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

# ── Cached resources ─────────────────────────────────────────────────────────

_schema_cache: Optional[str] = None
_glossary_cache: Optional[str] = None

RESOURCES_DIR = Path(__file__).parent.parent / "resources"


def _load_schema() -> str:
    global _schema_cache
    if _schema_cache is None:
        schema_path = RESOURCES_DIR / "schema" / "lumie_schema.json"
        if schema_path.exists():
            _schema_cache = schema_path.read_text(encoding="utf-8")
        else:
            _schema_cache = "{}"
    return _schema_cache


def _load_glossary() -> str:
    global _glossary_cache
    if _glossary_cache is None:
        glossary_path = RESOURCES_DIR / "glossary.md"
        if glossary_path.exists():
            _glossary_cache = glossary_path.read_text(encoding="utf-8")
        else:
            _glossary_cache = ""
    return _glossary_cache


# ── Prompt builders ──────────────────────────────────────────────────────────

def build_lumie_db_execution_prompt(
    user_request: str,
    skill_full_text: str,
    request_user_id: str,
    target_user_id: str,
    user_context: dict,
    history_summary: str = "",
) -> str:
    """Build the prompt for generating a lumie_db Python query script.

    The generated script will be executed by lumie_db_connector.
    """
    schema = _load_schema()
    glossary = _load_glossary()
    timezone = user_context.get("timezone", "UTC")

    return f"""You are generating a Python async script to query Lumie's MongoDB database.

## Database Schema
{schema}

## Domain Glossary
{glossary}

## Skill Definition
{skill_full_text}

## User Context
- Request user ID: {request_user_id}
- Target user ID: {target_user_id}
- User timezone: {timezone}
- User age: {user_context.get('age', 'unknown')}
- Medical condition: {user_context.get('icd10_code', 'none')}

## User Request
{user_request}

{f"## Conversation Context (summary)" + chr(10) + history_summary if history_summary else ""}

## Script Requirements

Write a Python async script that:

1. Uses the provided `db` variable (Motor AsyncIOMotorDatabase) to query data
2. Uses `target_user_id` (pre-set variable) to filter queries
3. Uses `request_user_id` (pre-set variable) for the requesting user
4. Stores the final result in `_result` as a dict
5. Handles the user's timezone ({timezone}) correctly for date filtering

## Script Rules

- You can use: `db`, `target_user_id`, `request_user_id`, `datetime`, `timedelta`, `ZoneInfo`, `json`, `print`, `str`, `int`, `float`, `len`, `list`, `dict`, `bool`, `isinstance`, `range`, `enumerate`, `sorted`, `min`, `max`, `sum`, `round`, `abs`, `any`, `all`, `zip`, `map`, `filter`, `set`, `tuple`, `type`
- All DB calls must use `await` (Motor is async)
- READ ONLY: No insert, update, or delete operations
- CRITICAL: Do NOT use `import` or `from ... import` — ALL modules and builtins are already pre-loaded in the namespace. `datetime`, `timedelta`, `json` are all available directly. Using import will cause your script to be rejected.
- Do NOT use `exec`, `eval`, `open`, `compile`, or `__import__`
- Do NOT access `users` collection (contains auth secrets)
- Always filter by user_id when querying user data
- Store your final result in `_result` as a Python dict with clear keys
- Include a `summary` key with a 2-3 sentence natural language summary

## Critical: Data Type Handling

MongoDB returns ObjectId and datetime objects that are NOT JSON-serializable.
You MUST convert them in your script:

- Convert `_id` fields: `str(doc["_id"])` or simply exclude `_id` from results
- Convert datetime: `doc["field"].isoformat() if isinstance(doc["field"], datetime) else doc["field"]`
- Best practice: build clean result dicts by cherry-picking fields from each document

Example helper pattern:
```python
def clean_task(t):
    return {{
        "task_name": t.get("task_name", ""),
        "task_type": t.get("task_type", ""),
        "status": t.get("status", ""),
        "open_datetime": t["open_datetime"].isoformat() if isinstance(t.get("open_datetime"), datetime) else str(t.get("open_datetime", "")),
        "close_datetime": t["close_datetime"].isoformat() if isinstance(t.get("close_datetime"), datetime) else str(t.get("close_datetime", "")),
    }}
```

## Task Query Rules

Tasks collection fields:
- `task_id`: string unique ID
- `user_id`: string, the task assignee
- `task_name`: string
- `task_type`: "Medicine" | "Life" | "Study" | "Exercise" | "Work" | "Meditation" | "Love"
- `status`: "pending" | "completed" | "expired"
- `open_datetime`: datetime (UTC) — when the task window opens
- `close_datetime`: datetime (UTC) — when the task window closes
- `created_by`: string, who created the task
- `team_id`: string (optional), for team-scoped tasks
- `task_info`: string (optional), extra notes

To query today's tasks for a user in timezone {timezone}:
```python
# timedelta is already available — do NOT import it
# Calculate today boundaries in UTC
# Example for America/Los_Angeles (UTC-7):
# today_start_utc = datetime(2026,3,27,7,0,0)  # midnight PT = 7am UTC
# today_end_utc = datetime(2026,3,28,7,0,0)
now_utc = datetime.utcnow()
# Simplification: query tasks whose windows overlap with the last 24h and next 24h
start_range = now_utc - timedelta(hours=24)
end_range = now_utc + timedelta(hours=24)
tasks = await db.tasks.find({{
    "user_id": target_user_id,
    "open_datetime": {{"$lte": end_range}},
    "close_datetime": {{"$gte": start_range}},
}}).to_list(100)
```

## Output Format

The script must end with:
```python
_result = {{
    "summary": "natural language summary",
    ...structured data sections (all values must be JSON-serializable)...
}}
```

Generate ONLY the Python script. No explanation, no markdown fencing."""


def build_browser_execution_prompt(
    user_request: str,
    skill_full_text: str,
    credential: dict,
    user_context: dict,
) -> str:
    """Build the prompt for generating browser automation steps."""
    return f"""You are generating browser automation instructions for Playwright.

## Skill Definition
{skill_full_text}

## Credential Info
- Base URL: {credential.get('base_url', 'not provided')}
- Username: {credential.get('username', 'not provided')}
- Navigation hints: {credential.get('notes', 'none')}

## User Request
{user_request}

## Instructions

Generate a JSON object with browser automation steps:

```json
{{
    "steps": [
        {{"action": "goto", "url": "..."}},
        {{"action": "fill", "selector": "...", "value": "..."}},
        {{"action": "click", "selector": "..."}},
        {{"action": "wait", "selector": "..."}},
        {{"action": "extract", "selector": "...", "attribute": "text"}}
    ],
    "expected_output": "description of what to extract"
}}
```

Generate ONLY the JSON. No explanation."""
