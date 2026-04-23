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
    previous_results: Optional[dict] = None,
    is_write_operation_task: bool = False,
) -> str:
    """Build the prompt for generating a lumie_db Python query script.

    The generated script will be executed by lumie_db_connector.

    Args:
        previous_results: Dict of skill_id -> ProactiveSkillData from prior tiers in DAG.
    """
    schema = _load_schema()
    glossary = _load_glossary()
    timezone = user_context.get("timezone", "UTC")
    is_tasks_create = "skill_id: tasks_create" in skill_full_text

    # Format previous results for context if available
    prev_results_section = ""
    if previous_results:
        import json
        prev_results_section = f"""
## Previous Skill Results (from DAG execution)

These are the raw results from skills executed in prior tiers. Use them as context:

{json.dumps({k: v.data if hasattr(v, 'data') else v for k, v in previous_results.items()}, indent=2, default=str)}
"""

    task_generation_guardrail = ""
    if is_tasks_create:
        task_generation_guardrail = """
## Task Generation Safety Guardrails (Required)
- For template-mode task creation, enforce `frequency_minutes >= 1440` (daily minimum).
- Also validate `frequency_minutes > template_span_minutes` where template span is the full open→close window range.
- If a provided frequency violates these rules, do not write any task docs; return `_result` with `created_count: 0` and a clear summary message.
- Clarification-first: if critical creation fields are missing/ambiguous (especially open/close time, target member/team, or template identity), do NOT write. Return `_result` with `created_count: 0` and a single concise clarification question.
- Never auto-fill missing schedule with `start now` or `24-hour window`.
"""

    write_receipt_requirements = ""
    if is_write_operation_task:
        write_receipt_requirements = """
## Write Receipt Requirements (Required)
- Include `execution_report` in `_result` as:
  - `write_attempted`: boolean
  - `write_confirmed`: boolean (true only after acknowledged DB write with count > 0)
  - `write_targets`: list of touched collections
- If no write was confirmed, set `write_confirmed: false` and avoid success wording in `summary`.
"""

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

{prev_results_section}

{f"## Conversation Context (summary)" + chr(10) + history_summary if history_summary else ""}
{task_generation_guardrail}
{write_receipt_requirements}

## Script Requirements

Write a Python async script that:

1. Uses the provided `db` variable (Motor AsyncIOMotorDatabase) to query data
2. Uses `target_user_id` (pre-set variable) to filter queries
3. Uses `request_user_id` (pre-set variable) for the requesting user
4. Stores the final result in `_result` as a dict
5. Handles the user's timezone ({timezone}) correctly for date filtering

## Script Rules

- You can use: `db`, `target_user_id`, `request_user_id`, `user_timezone`, `datetime`, `timedelta`, `timezone`, `ZoneInfo`, `asyncio`, `json`, `uuid`, `flush_notification_queue_now`, `print`, `str`, `int`, `float`, `len`, `list`, `dict`, `bool`, `isinstance`, `range`, `enumerate`, `sorted`, `min`, `max`, `sum`, `round`, `abs`, `any`, `all`, `zip`, `map`, `filter`, `set`, `tuple`, `type`
- `user_timezone` is a pre-set string variable (e.g. "America/Los_Angeles") — use it directly: `local_tz = ZoneInfo(user_timezone)`
- `timezone` is the `datetime.timezone` module — use `timezone.utc` for UTC-aware datetimes
- `uuid` is pre-loaded — use `str(uuid.uuid4())` directly for IDs when needed
- `flush_notification_queue_now` is pre-loaded — `await flush_notification_queue_now()` immediately processes pending queued notifications, which is important for time-sensitive ring commands
- All DB calls must use `await` (Motor is async)
- WRITES: Allowed ONLY to `ring_command_requests` and `notification_queue` (for live ring commands) and `tasks` / `task_templates`. All other collections are read-only. No delete operations ever.
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

## Timezone Handling

All timestamps are stored in UTC in MongoDB. To query by user's local date (e.g., "today" or "last night"):

```python
# user_timezone, ZoneInfo, timezone, datetime, timedelta are all pre-loaded variables
local_tz = ZoneInfo(user_timezone)          # use user_timezone variable directly
today_local = datetime.now(local_tz).date()

# Today range in UTC:
today_start_utc = datetime(today_local.year, today_local.month, today_local.day, tzinfo=local_tz).astimezone(timezone.utc)
today_end_utc = today_start_utc + timedelta(days=1)

# Yesterday range in UTC (for "last night"):
yesterday_start_utc = today_start_utc - timedelta(days=1)
yesterday_end_utc = today_start_utc
```

**For detailed query examples and data structure documentation, refer to the Database Schema section above.**
- See `sleep_sessions` notes for sleep query guidance and sorting rules
- See `tasks` fields for task query structure
- See other collections for their specific query patterns

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
    skill_id: str = "",
) -> str:
    """Build the prompt for generating browser automation steps."""
    base_url = credential.get('base_url', '')
    if not base_url and skill_id == 'gmail_inbox_check':
        base_url = 'https://mail.google.com (hardcoded for Gmail)'

    return f"""You are generating browser automation instructions for Playwright.

## Skill Definition
{skill_full_text}

## Credential Info
- Base URL: {base_url or 'from skill definition'}
- Username: {credential.get('username', 'not provided')}
- Navigation hints: {credential.get('notes', 'none')}

## User Request
{user_request}

## Instructions

Generate a JSON object with browser automation steps. Use explicit waits between navigation steps:

```json
{{
    "steps": [
        {{"action": "goto", "url": "..."}},
        {{"action": "wait", "milliseconds": 2000}},
        {{"action": "fill", "selector": "...", "value": "..."}},
        {{"action": "click", "selector": "..."}},
        {{"action": "wait", "milliseconds": 3000}},
        {{"action": "wait", "selector": "..."}},
        {{"action": "extract", "selector": "...", "attribute": "text"}}
    ],
    "expected_output": "description of what to extract"
}}
```

**Important action types:**
- `goto`: Navigate to URL
- `fill`: Fill input field (replace {{username}} and {{password}} with actual values)
- `click`: Click element
- `wait` with milliseconds: Wait specified time (e.g., 2000ms = 2 seconds)
- `wait` with selector: Wait for element to appear (max 60 seconds)
- `press`: Press keyboard key (e.g., "Enter")
- `extract`: Extract text/html from element

Generate ONLY the JSON. No explanation. Include explicit millisecond waits after navigation/clicks to allow page transitions."""


def build_external_api_post_body_prompt(
    user_request: str,
    skill_full_text: str,
) -> str:
    """Build the prompt for generating a JSON POST body for an external API call."""
    return f"""You are generating a JSON request body for an external API call.

## Skill Definition
{skill_full_text}

## User Request
{user_request}

## Instructions
Based on the skill's API Request Body section and the user's request, generate the correct JSON body.
- Output ONLY valid JSON, nothing else
- No markdown, no explanation
- Infer all fields from the user's request and the skill definition defaults"""


def build_external_api_summary_prompt(
    user_request: str,
    skill_full_text: str,
    api_data: str,
    user_context: dict,
) -> str:
    """Build the prompt for summarizing an external API response."""
    return f"""You are summarizing real-time data from an external API for a user.

## Skill Definition
{skill_full_text}

## API Response Data
{api_data}

## User Request
{user_request}

## Instructions
Based on the skill's Output Guidance section and the API data above, write a concise, friendly natural language summary for the user.
- Be specific with numbers and values
- Use plain text only (no markdown headers or bullet lists)
- Focus on what the user asked about; include other key metrics briefly
- Keep it to 2-4 sentences unless more detail is warranted
- Bold key numbers with **value**
- Skip items with N/A values unless the user specifically asked about them

Return ONLY the summary text. No explanation, no metadata."""
