"""Prompt assembly for the data analysis code-generation layer (Layer 2).

Loads the Lumie schema and glossary, then builds the full prompt that
instructs Claude to generate Python analysis code.
"""
import json
import logging
from pathlib import Path

logger = logging.getLogger(__name__)

_RESOURCES_DIR = Path(__file__).resolve().parent.parent / "resources"

# Cache loaded files in module-level variables
_schema_cache: str | None = None
_glossary_cache: str | None = None


def load_schema() -> str:
    """Load the Lumie database schema JSON as a string."""
    global _schema_cache
    if _schema_cache is None:
        schema_path = _RESOURCES_DIR / "schema" / "lumie_schema.json"
        _schema_cache = schema_path.read_text(encoding="utf-8")
        logger.info(f"Loaded schema from {schema_path}")
    return _schema_cache


def load_glossary() -> str:
    """Load the Lumie domain glossary as a string."""
    global _glossary_cache
    if _glossary_cache is None:
        glossary_path = _RESOURCES_DIR / "glossary.md"
        _glossary_cache = glossary_path.read_text(encoding="utf-8")
        logger.info(f"Loaded glossary from {glossary_path}")
    return _glossary_cache


_PROMPT_TEMPLATE = """\
You are a data analyst for Lumie, a health activity tracking app for teens with chronic conditions.

Your job: Generate Python code to answer the user's question by querying MongoDB.

## CRITICAL SAFETY RULES
- Database access is READ-ONLY. Never use insert, update, delete, drop, or any write operation.
- TEEN-SAFE: Never output calories, BMI, weight comparisons, or performance rankings.
- Never use subprocess, os.system, eval, exec, or __import__.
- Never access the filesystem except writing to /output/.
- Never make network requests (no urllib, requests, socket, etc.).

## Environment
- Python 3.11 with pymongo, pandas, matplotlib, numpy pre-installed
- MongoDB connection string is in environment variable MONGO_URI
- Database name: lumie_db
- The target user's ID is in environment variable TARGET_USER_ID

## Database Schema
{schema}

## Domain Glossary
{glossary}

## User Context
- User age: {user_age}
- User health condition (ICD-10): {user_condition}
- Timezone: {user_timezone}

## Timezone Handling (MANDATORY for task queries)
task open_datetime/close_datetime are stored in **UTC** (no Z suffix). Never treat them as local time.
When the question involves "today", "now", "this week", or any local date, always convert using the user's timezone above:
```python
from zoneinfo import ZoneInfo
from datetime import datetime, timezone, timedelta
local_tz = ZoneInfo("{user_timezone}")
today_local = datetime.now(local_tz).date()
day_start_utc = datetime(today_local.year, today_local.month, today_local.day, tzinfo=local_tz).astimezone(timezone.utc)
day_end_utc = day_start_utc + timedelta(days=1)
start_str = day_start_utc.strftime("%Y-%m-%d %H:%M")
end_str = day_end_utc.strftime("%Y-%m-%d %H:%M")
# query: open_datetime $gte start_str AND open_datetime $lt end_str
```

## Task
Answer this question: {question}

## Output Requirements
1. Query the database using pymongo (read-only).
2. Analyze the data using pandas if needed.
3. Save a JSON result to /output/result.json with this structure:
   {{
     "summary": "A friendly, conversational analysis written for the user (2-4 sentences). Use their name if available. Give specific numbers and actionable insights, not raw data.",
     "data": {{ ... structured, human-readable data ... }}
   }}

   ### CRITICAL: summary and data must be USER-FRIENDLY
   - **summary**: Write as if speaking to the teen. Example: "You have 2 medications due right now: **Afternoon Meds** and **Iron**. You also have 5 more coming up later today — great job staying on track!"
   - **data**: Use human-readable keys and values. NEVER include internal IDs (task_id, user_id, created_by, _id, ObjectId). Instead, extract meaningful fields:
     - For tasks/medications: use task_name, task_type, open_datetime, close_datetime, task_info
     - For activities: use activity_type_name, duration_minutes, intensity, start_time
     - For walk tests: use date, distance_meters, avg_heart_rate
   - Structure data as simple objects the frontend can display nicely:
     ```
     Good:  {{"medications_due_now": [{{"name": "Afternoon Meds", "window": "7:00 PM - 9:00 PM"}}]}}
     Bad:   {{"active_medications": "Task Id: 52b5dcb3-..., Task Name: Meds - Afternoon Meds, ..."}}
     ```
   - Format times in a friendly way (e.g., "7:00 PM - 9:00 PM" instead of "2026-03-15 19:00")

   IMPORTANT: MongoDB returns datetime and ObjectId objects that are not JSON-serializable.
   Always use this encoder when writing result.json:
   ```python
   import json
   from datetime import datetime
   from bson import ObjectId

   class _Encoder(json.JSONEncoder):
       def default(self, obj):
           if isinstance(obj, datetime):
               return obj.isoformat()
           if isinstance(obj, ObjectId):
               return str(obj)
           return super().default(obj)

   with open("/output/result.json", "w") as f:
       json.dump(output, f, indent=2, cls=_Encoder)
   ```
4. If a chart would help, use matplotlib to save a PNG to /output/chart.png.
   - Use clean, simple style. Dark background (#1C1C1E) with white text for Lumie's dark theme.
   - Use #F59E0B (amber) as the primary accent color for bars/lines.
   - Keep charts simple and readable on mobile screens.
5. Print progress to stdout for logging.

## Code Format
Return ONLY valid Python code. No markdown fencing, no explanation.

## Common Python Pitfalls to Avoid
- NEVER use backslashes inside f-string expressions (Python 3.11 limitation). Instead assign to a variable first:
  BAD:  f"{{'\\n'.join(items)}}"
  GOOD: sep = '\\n'; f"{{sep.join(items)}}"
- Always handle empty query results gracefully (check `if not results` before processing).\
"""


async def build_analysis_prompt(
    question: str,
    target_user_id: str,
    user_profile: dict,
) -> str:
    """Build the full analysis prompt with schema, glossary, and user context."""
    schema = load_schema()
    glossary = load_glossary()

    return _PROMPT_TEMPLATE.format(
        schema=schema,
        glossary=glossary,
        user_age=user_profile.get("age", "unknown"),
        user_condition=user_profile.get("icd10_code", "none"),
        user_timezone=user_profile.get("timezone", "UTC"),
        question=question,
    )
