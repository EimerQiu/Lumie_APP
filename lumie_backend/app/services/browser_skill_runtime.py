"""Browser Skill Runtime — Playwright-based browser automation.

Phase 1: Stub implementation. Returns not-implemented error.
Full implementation requires Playwright installation on the server.
"""
import logging
from typing import Optional

logger = logging.getLogger(__name__)


async def execute_browser_skill(
    skill_id: str,
    job_id: str,
    steps: list[dict],
    credential: dict,
    timeout: int = 30,
) -> dict:
    """Execute browser automation steps using Playwright.

    Phase 1: Returns a structured error indicating browser runtime
    is not yet available. This stub ensures the execution pipeline
    can route to browser skills without crashing.
    """
    logger.warning(f"Browser skill runtime invoked for skill={skill_id}, job={job_id} — not yet implemented")

    return {
        "success": False,
        "error_type": "runtime_not_available",
        "error_stage": "browser_launch",
        "retryable": False,
        "error": (
            "Browser skill runtime is not yet available. "
            "Playwright-based browser automation will be enabled in a future update. "
            "Please configure credentials and try again later."
        ),
        "stdout": "",
        "stderr": "",
        "screenshot_path": None,
        "current_url": None,
        "failed_step": None,
    }
