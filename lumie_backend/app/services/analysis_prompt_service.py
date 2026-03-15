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

## Task
Answer this question: {question}

## Output Requirements
1. Query the database using pymongo (read-only).
2. Analyze the data using pandas if needed.
3. Save a JSON result to /output/result.json with this structure:
   {{
     "summary": "A concise analysis conclusion (2-4 sentences)",
     "data": {{ ... relevant data ... }}
   }}
4. If a chart would help, use matplotlib to save a PNG to /output/chart.png.
   - Use clean, simple style. Dark background (#1C1C1E) with white text for Lumie's dark theme.
   - Use #F59E0B (amber) as the primary accent color for bars/lines.
   - Keep charts simple and readable on mobile screens.
5. Print progress to stdout for logging.

## Code Format
Return ONLY valid Python code. No markdown fencing, no explanation.\
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
