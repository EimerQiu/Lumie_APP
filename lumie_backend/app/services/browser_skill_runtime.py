"""Browser Skill Runtime — Playwright-based browser automation.

Executes LLM-generated browser automation steps using Playwright.
Supports Gmail, school portals, and other web-based services.
Also dispatches specialized skills (e.g., water_usage_monitor) to custom handlers.
"""
import asyncio
import json
import logging
import tempfile
from pathlib import Path
from typing import Optional

try:
    from playwright.async_api import async_playwright, TimeoutError as PlaywrightTimeoutError
except ImportError:
    async_playwright = None

logger = logging.getLogger(__name__)


async def execute_browser_skill(
    skill_id: str,
    job_id: str,
    steps: list[dict],
    credential: dict,
    timeout: int = 60,  # Increased from 30 to handle Gmail login delays
) -> dict:
    """Execute browser automation steps using Playwright.

    Dispatcher: Routes specialized skills to custom handlers (e.g., water_usage_monitor).
    Falls back to LLM-generated step execution for generic skills.

    Args:
        skill_id: The skill being executed (e.g., 'gmail_inbox_check')
        job_id: Unique job identifier for logging
        steps: List of automation steps from LLM (navigate, fill, click, extract)
        credential: Dict with base_url, username, password, etc.
        timeout: Max seconds per step (default 30)

    Returns:
        {
            "success": bool,
            "data": dict (structured result),
            "stdout": str (execution log),
            "stderr": str (error details),
            "screenshot_path": str (path to screenshot on failure),
            "current_url": str,
            "failed_step": int (step index that failed),
        }
    """
    # ── Dispatcher for specialized skills ────────────────────────────────
    if skill_id == "water_usage_monitor":
        try:
            from . import water_monitor_runtime
            username = credential.get("username", "")
            password = credential.get("password", "")
            base_url = credential.get("base_url", "https://myaccount.calwater.com")

            result = await water_monitor_runtime.extract_water_usage(
                username=username,
                password=password,
                base_url=base_url,
                timeout_ms=timeout * 1000,
            )

            stdout = result.pop("html_snapshot", None)  # Remove snapshot before return
            return {
                "success": result.get("success", False),
                "data": result,
                "error": result.get("error"),
                "stdout": json.dumps(result, indent=2, default=str),
                "stderr": "" if result.get("success") else result.get("error", ""),
                "screenshot_path": None,
                "current_url": base_url,
                "failed_step": None,
            }
        except ImportError:
            logger.error("water_monitor_runtime not available")
            return {
                "success": False,
                "data": None,
                "error": "water_monitor_runtime module not found",
                "stdout": "",
                "stderr": "water_monitor_runtime import failed",
                "screenshot_path": None,
                "current_url": None,
                "failed_step": None,
            }
        except Exception as e:
            logger.exception(f"[{job_id}] water_usage_monitor execution failed: {e}")
            return {
                "success": False,
                "data": None,
                "error": str(e),
                "stdout": "",
                "stderr": str(e),
                "screenshot_path": None,
                "current_url": None,
                "failed_step": None,
            }

    # ── Generic LLM-generated browser steps ───────────────────────────────
    if not async_playwright:
        return {
            "success": False,
            "error": "Playwright not installed. Run: pip install playwright && playwright install chromium",
            "stdout": "",
            "stderr": "",
            "screenshot_path": None,
            "current_url": None,
            "failed_step": None,
        }

    browser = None
    page = None
    stdout = []
    stderr = []
    screenshot_path = None
    current_url = None

    try:
        async with async_playwright() as p:
            logger.info(f"[{job_id}] Launching Chromium browser")
            stdout.append(f"[{job_id}] Launching browser...")

            browser = await p.chromium.launch(
                headless=True,
                args=[
                    "--disable-blink-features=AutomationControlled",
                    "--disable-dev-shm-usage",
                    "--no-sandbox",
                    "--disable-gpu",
                ],
            )
            context = await browser.new_context(
                viewport={"width": 1920, "height": 1080},
                user_agent=(
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) "
                    "Chrome/122.0.0.0 Safari/537.36"
                ),
            )
            page = await context.new_page()
            # Remove webdriver flag to avoid bot detection
            await page.add_init_script(
                "Object.defineProperty(navigator, 'webdriver', {get: () => undefined})"
            )

            # Determine base URL by skill type
            if skill_id == "gmail_inbox_check":
                base_url = "https://mail.google.com"
            else:
                base_url = credential.get("base_url", "")

            username = credential.get("username", "")
            password = credential.get("password", "")

            logger.info(f"[{job_id}] Navigating to {base_url}")
            stdout.append(f"Navigating to {base_url}...")

            await page.goto(base_url, wait_until="domcontentloaded", timeout=timeout * 1000)
            await asyncio.sleep(1)  # Give page time to fully render

            current_url = page.url

            # Execute LLM-generated steps
            for step_idx, step in enumerate(steps):
                step_type = step.get("action", "").lower()
                logger.info(f"[{job_id}] Step {step_idx}: {step_type}")
                stdout.append(f"Step {step_idx}: {step_type}")

                try:
                    if step_type in ("navigate", "goto"):  # Support both names
                        url = step.get("url", base_url)
                        await page.goto(url, wait_until="domcontentloaded", timeout=timeout * 1000)
                        await asyncio.sleep(0.5)
                        current_url = page.url

                    elif step_type == "set_viewport":
                        width = step.get("width", 1920)
                        height = step.get("height", 1080)
                        await page.set_viewport_size({"width": width, "height": height})
                        stdout.append(f"Set viewport to {width}x{height}")

                    elif step_type == "fill":
                        selector = step.get("selector", "")
                        value = step.get("value", "")
                        if not selector:
                            stderr.append("Missing selector for fill action")
                            continue
                        # Replace placeholders
                        value = value.replace("{username}", username).replace("{password}", password)
                        await page.fill(selector, value, timeout=timeout * 1000)
                        stdout.append(f"Filled {selector}")

                    elif step_type == "click":
                        selector = step.get("selector", "")
                        if not selector:
                            stderr.append("Missing selector for click action")
                            continue
                        await page.click(selector, timeout=timeout * 1000)
                        stdout.append(f"Clicked {selector}")

                    elif step_type == "press":
                        key = step.get("key", "Enter")
                        await page.press("body", key)
                        stdout.append(f"Pressed {key}")

                    elif step_type == "wait":
                        selector = step.get("selector", "")
                        if selector:
                            await page.wait_for_selector(selector, timeout=timeout * 1000)
                        else:
                            wait_ms = step.get("milliseconds", 1000)
                            await asyncio.sleep(wait_ms / 1000)
                        stdout.append(f"Waited for {selector or 'timeout'}")

                    elif step_type == "extract":
                        selector = step.get("selector", "")
                        extract_type = step.get("extract_type", "text")  # text, html, attribute
                        attribute = step.get("attribute", "")
                        if extract_type == "text":
                            result = await page.text_content(selector)
                        elif extract_type == "html":
                            result = await page.inner_html(selector)
                        elif extract_type == "attribute":
                            result = await page.get_attribute(selector, attribute)
                        else:
                            result = None
                        stdout.append(f"Extracted {extract_type} from {selector}: {result[:100] if result else 'null'}")
                        # Store for return
                        if not hasattr(execute_browser_skill, "_last_extract"):
                            execute_browser_skill._last_extract = result

                    elif step_type == "screenshot":
                        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
                            screenshot_path = f.name
                        await page.screenshot(path=screenshot_path)
                        stdout.append(f"Screenshot saved to {screenshot_path}")

                    else:
                        stderr.append(f"Unknown action: {step_type}")

                    # Wait briefly between steps
                    await asyncio.sleep(0.5)

                except PlaywrightTimeoutError:
                    error_msg = f"Step {step_idx} timed out: {step_type} on {step.get('selector', 'N/A')}"
                    stderr.append(error_msg)
                    logger.error(f"[{job_id}] {error_msg}")

                    # Take screenshot on failure
                    if page:
                        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
                            screenshot_path = f.name
                        try:
                            await page.screenshot(path=screenshot_path)
                        except Exception:
                            pass

                    return {
                        "success": False,
                        "data": None,
                        "error": error_msg,
                        "stdout": "\n".join(stdout),
                        "stderr": "\n".join(stderr),
                        "screenshot_path": screenshot_path,
                        "current_url": current_url,
                        "failed_step": step_idx,
                    }

                except Exception as e:
                    error_msg = f"Step {step_idx} failed: {str(e)}"
                    stderr.append(error_msg)
                    logger.error(f"[{job_id}] {error_msg}")

                    if page:
                        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
                            screenshot_path = f.name
                        try:
                            await page.screenshot(path=screenshot_path)
                        except Exception:
                            pass

                    return {
                        "success": False,
                        "data": None,
                        "error": error_msg,
                        "stdout": "\n".join(stdout),
                        "stderr": "\n".join(stderr),
                        "screenshot_path": screenshot_path,
                        "current_url": current_url,
                        "failed_step": step_idx,
                    }

            # All steps completed successfully
            logger.info(f"[{job_id}] All steps completed")
            stdout.append("✅ All steps completed successfully")

            # Try to extract data from the final page state
            page_text = await page.content()

            return {
                "success": True,
                "data": {"page_content": page_text},
                "error": None,
                "stdout": "\n".join(stdout),
                "stderr": "\n".join(stderr),
                "screenshot_path": None,
                "current_url": current_url,
                "failed_step": None,
            }

    except Exception as e:
        error_msg = f"Browser execution failed: {str(e)}"
        logger.error(f"[{job_id}] {error_msg}")
        stderr.append(error_msg)

        if page:
            with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
                screenshot_path = f.name
            try:
                await page.screenshot(path=screenshot_path)
            except Exception:
                pass

        return {
            "success": False,
            "data": None,
            "error": error_msg,
            "stdout": "\n".join(stdout),
            "stderr": "\n".join(stderr),
            "screenshot_path": screenshot_path,
            "current_url": current_url,
            "failed_step": None,
        }

    finally:
        if browser:
            await browser.close()
            logger.info(f"[{job_id}] Browser closed")
