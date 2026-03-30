"""Layer 2 LLM service — calls Claude to generate Python analysis code."""
import logging
import re
from typing import Optional

import anthropic

from ..core.config import settings

logger = logging.getLogger(__name__)

_MODEL = "claude-haiku-4-5-20251001"
_MAX_TOKENS = 4000
_TEMPERATURE = 0

_client: Optional[anthropic.AsyncAnthropic] = None


def _get_client() -> anthropic.AsyncAnthropic:
    global _client
    if _client is None:
        if not settings.ANTHROPIC_API_KEY:
            raise RuntimeError("ANTHROPIC_API_KEY is not set.")
        _client = anthropic.AsyncAnthropic(api_key=settings.ANTHROPIC_API_KEY)
    return _client


def _strip_markdown_fences(text: str) -> str:
    """Remove markdown code block fences if present."""
    text = text.strip()
    # Remove ```python ... ``` or ``` ... ```
    if text.startswith("```"):
        # Remove first line (```python or ```)
        text = re.sub(r"^```(?:python)?\s*\n?", "", text)
        # Remove trailing ```
        text = re.sub(r"\n?```\s*$", "", text)
    return text.strip()


async def generate_analysis_code(prompt: str) -> tuple[str, dict]:
    """Generate Python analysis code using Claude.

    Args:
        prompt: The full analysis prompt (schema + glossary + question).

    Returns:
        Tuple of (generated_code, token_usage_dict).

    Raises:
        ValueError: If Claude's output is not valid Python.
        RuntimeError: If API key is missing.
    """
    client = _get_client()

    response = await client.messages.create(
        model=_MODEL,
        max_tokens=_MAX_TOKENS,
        temperature=_TEMPERATURE,
        messages=[{"role": "user", "content": prompt}],
    )

    raw_text = response.content[0].text
    code = _strip_markdown_fences(raw_text)

    token_usage = {
        "input_tokens": response.usage.input_tokens,
        "output_tokens": response.usage.output_tokens,
    }

    # Basic validation: check it looks like Python
    if not code or len(code) < 20:
        raise ValueError("Generated code is too short or empty.")

    # Check for obvious non-Python output
    if code.startswith("{") or code.startswith("<"):
        raise ValueError("Generated output is not Python code.")

    logger.info(
        f"Generated analysis code: {len(code)} chars, "
        f"tokens: {token_usage['input_tokens']}in/{token_usage['output_tokens']}out"
    )

    return code, token_usage
