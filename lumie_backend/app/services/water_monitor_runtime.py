"""Water Usage Monitor Runtime — Playwright-based browser automation for Cal Water accounts.

Handles login, navigation, and data extraction from California Water Service portal.
Includes bill calculation, tier prediction, and conservation advice based on the dashboard logic.
"""
import asyncio
import re
import logging
from typing import Optional
from datetime import datetime, timezone

from playwright.async_api import async_playwright, TimeoutError as PlaywrightTimeoutError

logger = logging.getLogger(__name__)

# Cal Water Los Altos Residential rate structure
TIER_RATES = [
    {"limit": 6, "rate": 2.7015},      # Tier 1: 1-6 CCF
    {"limit": 20, "rate": 10.7870},    # Tier 2: 7-20 CCF
    {"limit": 30, "rate": 13.4821},    # Tier 3: 21-30 CCF
    {"limit": float('inf'), "rate": 20.2202},  # Tier 4: 31+ CCF
]
SERVICE_CHARGE = 104.52
PPP_RATE = 0.047056  # Public Purpose Programs: 4.7056%
AS_RATE = 1.0098     # Additional Surcharges: $1.0098/CCF
UF_RATE = 0.007      # CPUC Fee: 0.70%
GAL_PER_CCF = 748

# ── Cal Water browser automation constants ───────────────────────────────────
USAGE_HISTORY_PATH = "/app/water-usage/history"
SELECTOR_HISTORY_GRID = "div[role='grid'].usage-history__table"
SELECTOR_HISTORY_END_READ = "#history-0-2"       # first row, End Read column
SELECTOR_HISTORY_BILLING_PERIOD = "#history-0-0" # first row, Billing Period column
ORDINAL_RE = re.compile(r"(\d+)(st|nd|rd|th)", re.IGNORECASE)


# ────────────────────────────────────────────────────────────────────────────
# Bill Calculation Helpers
# ────────────────────────────────────────────────────────────────────────────

def calculate_tier_breakdown(ccf: float) -> dict:
    """Calculate usage by tier."""
    t1 = min(ccf, 6)
    t2 = min(max(ccf - 6, 0), 14)
    t3 = min(max(ccf - 20, 0), 10)
    t4 = max(ccf - 30, 0)
    return {"t1": t1, "t2": t2, "t3": t3, "t4": t4}


def calculate_bill(ccf: float) -> dict:
    """Calculate total bill for given CCF usage."""
    tiers = calculate_tier_breakdown(ccf)

    # Water charges by tier
    water_charge = (
        tiers["t1"] * TIER_RATES[0]["rate"] +
        tiers["t2"] * TIER_RATES[1]["rate"] +
        tiers["t3"] * TIER_RATES[2]["rate"] +
        tiers["t4"] * TIER_RATES[3]["rate"]
    )

    # Basic charges
    basic = water_charge + SERVICE_CHARGE

    # Additional charges
    ppp = basic * PPP_RATE
    as_charge = ccf * AS_RATE
    uf = (basic + as_charge) * UF_RATE

    # Total bill
    total = basic + ppp + as_charge + uf

    return {
        "tiers": tiers,
        "water_charge": water_charge,
        "basic": basic,
        "ppp": ppp,
        "as_charge": as_charge,
        "uf": uf,
        "total": total,
    }


def get_tier_name(ccf: float) -> str:
    """Get the tier name for given CCF."""
    if ccf <= 6:
        return "Tier 1"
    elif ccf <= 20:
        return "Tier 2"
    elif ccf <= 30:
        return "Tier 3"
    else:
        return "Tier 4"


def _parse_history_date(day_text: str, billing_period_text: str) -> Optional[str]:
    """Combine day text like "Apr 1st" with a year pulled from billing period text
    (e.g. "April, 2026\nFeb 27th - Apr 1st\n33 Days") → "2026-04-01".
    """
    day_clean = ORDINAL_RE.sub(r"\1", day_text).strip()
    year_match = re.search(r"(20\d{2})", billing_period_text)
    if not year_match:
        return None
    year = year_match.group(1)
    for fmt in ("%b %d %Y", "%B %d %Y"):
        try:
            return datetime.strptime(f"{day_clean} {year}", fmt).strftime("%Y-%m-%d")
        except ValueError:
            continue
    return None


async def scrape_previous_reading(page) -> dict:
    """Scrape the most recent End Read (CCF) and its date from the Cal Water
    history page. Must be called on an already-logged-in Playwright page.

    Returns a dict with:
      - previous_reading_ccf (float | None)
      - previous_reading_date (str | None, ISO "YYYY-MM-DD")
      - previous_raw_text (str | None) — raw End Read cell text (or error note)
    """
    try:
        history_url = page.url.split("/app")[0] + USAGE_HISTORY_PATH
        await page.goto(history_url, wait_until="domcontentloaded")
        await page.wait_for_selector(SELECTOR_HISTORY_GRID, timeout=30_000)
        await page.wait_for_selector(SELECTOR_HISTORY_END_READ, timeout=15_000)
        await page.wait_for_load_state("networkidle")

        end_read_text = (
            await page.locator(SELECTOR_HISTORY_END_READ).first.inner_text()
        ).strip()
        billing_text = (
            await page.locator(SELECTOR_HISTORY_BILLING_PERIOD).first.inner_text()
        ).strip()
    except Exception as e:
        logger.warning(f"History page scrape failed: {e}")
        return {
            "previous_reading_ccf": None,
            "previous_reading_date": None,
            "previous_raw_text": f"history scrape failed: {e}",
        }

    # End Read cell looks like:
    #   761.003
    #   Apr 1st
    lines = [ln.strip() for ln in end_read_text.splitlines() if ln.strip()]
    reading_ccf: Optional[float] = None
    date_iso: Optional[str] = None
    if lines:
        num_match = re.search(r"([\d,]+\.?\d*)", lines[0])
        if num_match:
            try:
                reading_ccf = float(num_match.group(1).replace(",", ""))
            except ValueError:
                reading_ccf = None
        if len(lines) >= 2:
            date_iso = _parse_history_date(lines[1], billing_text)

    return {
        "previous_reading_ccf": reading_ccf,
        "previous_reading_date": date_iso,
        "previous_raw_text": end_read_text,
    }


def get_billing_cycle_dates() -> dict:
    """Billing cycle = first day of current month → last day of current month."""
    from datetime import datetime
    from calendar import monthrange

    today = datetime.now().date()
    last_day = monthrange(today.year, today.month)[1]
    cycle_start = today.replace(day=1)
    cycle_end = today.replace(day=last_day)

    return {
        "cycle_start": cycle_start,
        "cycle_end": cycle_end,
        "today": today,
        "days_elapsed": (today - cycle_start).days,
        "days_total": last_day,
        "days_remaining": (cycle_end - today).days,
    }


def generate_prediction_advice(actual_usage: float, projected_usage: float,
                               daily_cf_rate: float, days_remaining: int,
                               days_total: int) -> str:
    """Generate conservation advice based on usage predictions."""

    projected_bill = calculate_bill(projected_usage)
    tier_name = get_tier_name(projected_usage)

    advice = []

    # Tier prediction
    advice.append(f"**Predicted Tier: {tier_name}**")
    advice.append(f"At {daily_cf_rate:.1f} CF/day, you'll use {projected_usage:.1f} CCF this cycle → {tier_name}")

    # Budget targets
    budget_targets = [200, 500, 1000]
    for target in budget_targets:
        projected_total = projected_bill["total"]
        if projected_total > target:
            overage = projected_total - target
            advice.append(f"\n⚠️ **Projected bill ${projected_total:.2f} exceeds ${target} budget by ${overage:.2f}**")
        else:
            headroom = target - projected_total
            advice.append(f"\n✓ **Bill on track for ${target} budget** (${headroom:.2f} headroom)")

    # Tier targets
    tier_targets = [
        (20, "Tier 2", "Stay below Tier 2 (max 20 CCF)"),
        (30, "Tier 3", "Avoid Tier 4 (max 30 CCF)"),
    ]

    for target_ccf, target_tier, label in tier_targets:
        if projected_usage > target_ccf:
            reduction_needed = projected_usage - target_ccf
            daily_reduction_cf = (reduction_needed / days_total) * 100
            new_daily_rate = daily_cf_rate - daily_reduction_cf
            advice.append(f"\n🎯 **{label}** — Need to reduce {daily_reduction_cf:.1f} CF/day to {new_daily_rate:.1f} CF/day")

    return "\n".join(advice)


async def extract_water_usage(
    username: str,
    password: str,
    base_url: str = "https://myaccount.calwater.com",
    timeout_ms: int = 30000,
) -> dict:
    """Extract current water usage from California Water Service account.

    Args:
        username: Cal Water email address
        password: Cal Water account password
        base_url: Base URL for Cal Water portal (defaults to myaccount.calwater.com)
        timeout_ms: Timeout for browser operations in milliseconds

    Returns:
        Dict with keys:
        - success (bool)
        - water_usage_cf (float): Current usage in cubic feet
        - timestamp (str): ISO datetime when data was retrieved
        - summary (str): User-friendly summary
        - error (str, optional): Error message if extraction failed
        - html_snapshot (str, optional): Page HTML for debugging on failure
    """
    async with async_playwright() as p:
        browser = None
        try:
            # Launch headless browser
            browser = await p.chromium.launch(headless=True)
            page = await browser.new_page()

            # ── Step 1: Navigate to login page ────────────────────────────────
            logger.info(f"Navigating to {base_url}")
            try:
                await page.goto(base_url, wait_until="networkidle", timeout=timeout_ms)
            except PlaywrightTimeoutError:
                logger.warning(f"Timeout navigating to {base_url}, continuing anyway")

            # ── Step 2: Login ────────────────────────────────────────────────
            logger.info("Attempting login...")
            try:
                # Wait for email field
                await page.wait_for_selector('input#email', timeout=10000)
                logger.info("✓ Email field found")

                # Fill credentials
                await page.fill('input#email', username)
                logger.info("✓ Email filled")

                await page.fill('input#password', password)
                logger.info("✓ Password filled")

                # Submit form by pressing Enter on password field
                password_field = await page.query_selector('input#password')
                if password_field:
                    await password_field.press('Enter')
                    logger.info("✓ Form submitted (Enter pressed)")

                # Wait for navigation to complete
                await page.wait_for_timeout(2000)  # Brief pause for redirect
                try:
                    await page.wait_for_load_state("networkidle", timeout=15000)
                except PlaywrightTimeoutError:
                    logger.warning("Timeout waiting for page load after login")

                current_url = page.url
                logger.info(f"Post-login URL: {current_url}")

                # Check if still on login page
                if "login" in current_url.lower() or current_url == base_url:
                    return {
                        "success": False,
                        "error": "Login failed or not completed",
                        "url": current_url,
                        "html_snapshot": await page.content(),
                    }

                logger.info("✓ Login successful")

            except Exception as e:
                logger.error(f"Login failed: {e}")
                return {
                    "success": False,
                    "error": f"Login error: {str(e)}",
                    "html_snapshot": await page.content() if page else None,
                }

            # ── Step 3: Navigate to water usage page ──────────────────────────
            water_usage_url = f"{base_url}/app/water-usage"
            logger.info(f"Navigating to {water_usage_url}")
            try:
                await page.goto(water_usage_url, wait_until="networkidle", timeout=timeout_ms)
                logger.info(f"✓ Water usage page loaded")
            except Exception as e:
                logger.error(f"Failed to navigate to water usage page: {e}")
                return {
                    "success": False,
                    "error": f"Failed to navigate to water usage page: {str(e)}",
                    "html_snapshot": await page.content() if page else None,
                }

            # ── Step 4: Extract water usage data ─────────────────────────────
            logger.info("Extracting water usage data...")
            try:
                # Wait for the water usage header to be visible
                await page.wait_for_selector('.water-usage-header__period-value', timeout=10000)
                logger.info("✓ Water usage header found")

                # Get the HTML content for inspection
                period_value_html = await page.inner_html('.water-usage-header__period-value')
                logger.debug(f"Raw HTML:\n{period_value_html}")

                # Get text content
                period_value_text = await page.inner_text('.water-usage-header__period-value')
                logger.debug(f"Full text:\n{period_value_text}")

                # Extract CF number using regex: matches patterns like "77782.997 CF" or "77,782.997 CF"
                match = re.search(r'([\d,]+\.?\d*)\s*CF', period_value_text)

                if not match:
                    logger.error(f"Could not extract CF number from text: {period_value_text}")
                    return {
                        "success": False,
                        "error": "CF number not found in expected format",
                        "text_found": period_value_text,
                        "html_snapshot": period_value_html,
                    }

                # Parse the number (remove commas if present)
                cf_number_str = match.group(1).replace(',', '')
                try:
                    water_usage_cf = float(cf_number_str)
                except ValueError:
                    logger.error(f"Failed to parse CF number: {cf_number_str}")
                    return {
                        "success": False,
                        "error": f"Failed to parse CF number: {cf_number_str}",
                    }

                logger.info(f"✓ Successfully extracted: {water_usage_cf} CF")

                # Extract timestamp info (e.g., "7:00 PM, Apr 20th")
                lines = period_value_text.strip().split('\n')
                timestamp_str = lines[0] if lines else "unknown"

                # Convert current meter reading from CF to CCF
                current_meter_reading_ccf = water_usage_cf / 100.0
                logger.info(f"✓ Current meter reading: {current_meter_reading_ccf:.3f} CCF")

                # Scrape previous meter reading from Cal Water history page
                prev_data = await scrape_previous_reading(page)
                logger.info(f"Previous meter data: {prev_data}")

                prev_meter_reading_ccf = prev_data.get("previous_reading_ccf")
                if prev_meter_reading_ccf is None:
                    return {
                        "success": False,
                        "error": (
                            "Cannot calculate usage: Previous meter reading not found "
                            f"on history page. Raw: {prev_data.get('previous_raw_text')}"
                        ),
                    }

                # Calculate actual usage as difference between current and previous
                actual_usage_ccf = current_meter_reading_ccf - prev_meter_reading_ccf
                logger.info(f"✓ Calculated usage: {actual_usage_ccf:.3f} CCF (from {prev_meter_reading_ccf:.1f} to {current_meter_reading_ccf:.1f})")

                # Calculate bills based on actual usage
                bill_data = calculate_bill(actual_usage_ccf)
                tier_name = get_tier_name(actual_usage_ccf)

                # Get current time for logging
                retrieval_time = datetime.now(timezone.utc).isoformat()

                # Get billing cycle information
                prev_date_str = prev_data.get("previous_reading_date")
                if not prev_date_str:
                    return {
                        "success": False,
                        "error": (
                            "Cannot calculate usage: Previous reading date not found "
                            f"on history page. Raw: {prev_data.get('previous_raw_text')}"
                        ),
                    }
                cycle_info = get_billing_cycle_dates()
                logger.info(f"Billing cycle: {cycle_info['cycle_start']} to {cycle_info['cycle_end']}")

                # Calculate daily average and projected usage
                days_elapsed = cycle_info["days_elapsed"]
                days_total = cycle_info["days_total"]
                days_remaining = cycle_info["days_remaining"]

                if days_elapsed <= 0:
                    return {
                        "success": False,
                        "error": f"Invalid billing cycle: days_elapsed={days_elapsed}",
                    }

                daily_ccf_avg = actual_usage_ccf / days_elapsed
                daily_cf_avg = daily_ccf_avg * 100
                projected_usage_ccf = daily_ccf_avg * days_total
                projected_bill = calculate_bill(projected_usage_ccf)
                projected_tier = get_tier_name(projected_usage_ccf)

                logger.info(f"Daily rate: {daily_cf_avg:.1f} CF/day, Projected: {projected_usage_ccf:.2f} CCF")

                # Generate structured plain text summary
                summary_lines = [
                    "Water Usage Summary",
                    "",
                    f"Billing Cycle: {cycle_info['cycle_start']} to {cycle_info['cycle_end']} ({days_total} days)",
                    f"Today: {cycle_info['today']} ({days_elapsed} days elapsed, {days_remaining} days remaining)",
                    "",
                    "Current Usage (To Date)",
                    f"Previous Reading: {prev_meter_reading_ccf:.3f} CCF on {prev_date_str}",
                    f"Current Reading: {current_meter_reading_ccf:.3f} CCF",
                    f"Usage: {actual_usage_ccf:.2f} CCF ({actual_usage_ccf * 100:,.0f} CF)",
                    f"Bill So Far: ${bill_data['total']:.2f}",
                    "",
                    "Projected Usage (Full Month)",
                    f"Predicted Usage: {projected_usage_ccf:.2f} CCF ({projected_usage_ccf * 100:,.0f} CF)",
                    f"Predicted Bill: ${projected_bill['total']:.2f}",
                    f"Predicted Tier: {projected_tier}",
                    "",
                    "Key Metrics",
                    f"Daily Rate: {daily_cf_avg:.1f} CF/day",
                    f"Cost per CCF: ${bill_data['water_charge'] / actual_usage_ccf:.2f} (current), ${projected_bill['water_charge'] / projected_usage_ccf:.2f} (projected)",
                ]
                summary = "\n".join(summary_lines)

                return {
                    "success": True,
                    "current_meter_reading_cf": water_usage_cf,
                    "current_meter_reading_ccf": current_meter_reading_ccf,
                    "previous_meter_reading_ccf": prev_meter_reading_ccf,
                    "usage_ccf": actual_usage_ccf,
                    "usage_cf": actual_usage_ccf * 100,
                    "timestamp": retrieval_time,
                    "billing_period": timestamp_str,
                    "summary": summary,
                    "current": {
                        "bill": bill_data["total"],
                        "water_charge": bill_data["water_charge"],
                        "service_charge": SERVICE_CHARGE,
                        "surcharges": bill_data["ppp"] + bill_data["as_charge"] + bill_data["uf"],
                        "tier": tier_name,
                        "usage_ccf": actual_usage_ccf,
                    },
                    "projected": {
                        "bill": projected_bill["total"],
                        "water_charge": projected_bill["water_charge"],
                        "service_charge": SERVICE_CHARGE,
                        "surcharges": projected_bill["ppp"] + projected_bill["as_charge"] + projected_bill["uf"],
                        "tier": projected_tier,
                        "usage_ccf": projected_usage_ccf,
                    },
                    "billing_cycle": {
                        "start_date": str(cycle_info["cycle_start"]),
                        "end_date": str(cycle_info["cycle_end"]),
                        "days_total": days_total,
                        "days_elapsed": days_elapsed,
                        "days_remaining": days_remaining,
                    },
                    "daily_metrics": {
                        "average_cf_per_day": daily_cf_avg,
                        "average_ccf_per_day": daily_ccf_avg,
                    },
                    "tier": {
                        "name": projected_tier,
                        "usage_ccf": projected_usage_ccf,
                        "breakdown": projected_bill["tiers"],
                    },
                }

            except PlaywrightTimeoutError:
                logger.error("Timeout waiting for water usage header")
                return {
                    "success": False,
                    "error": "Water usage header did not load within timeout",
                    "html_snapshot": await page.content() if page else None,
                }
            except Exception as e:
                logger.error(f"Data extraction failed: {e}")
                return {
                    "success": False,
                    "error": f"Data extraction error: {str(e)}",
                    "html_snapshot": await page.content() if page else None,
                }

        except Exception as e:
            logger.exception(f"Unexpected error in water usage extraction: {e}")
            return {
                "success": False,
                "error": f"Unexpected error: {str(e)}",
            }
        finally:
            if browser:
                await browser.close()
                logger.info("Browser session closed")


async def test_credentials(
    username: str,
    password: str,
    base_url: str = "https://myaccount.calwater.com",
) -> dict:
    """Test Cal Water credentials by attempting login.

    Returns:
        Dict with keys:
        - success (bool)
        - message (str)
        - error (str, optional)
    """
    logger.info(f"Testing credentials for {username}...")

    try:
        result = await extract_water_usage(username, password, base_url)
        if result["success"]:
            return {
                "success": True,
                "message": f"Credentials are valid. Current usage: {result['water_usage_cf']:.3f} CF",
            }
        else:
            return {
                "success": False,
                "error": result.get("error", "Login failed"),
                "message": "Credential test failed",
            }
    except Exception as e:
        logger.error(f"Credential test error: {e}")
        return {
            "success": False,
            "error": str(e),
            "message": "Credential test encountered an error",
        }
