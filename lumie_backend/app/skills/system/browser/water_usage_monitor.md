---
skill_id: water_usage_monitor
title: Water Usage Monitor
capability_id: external_service_integration
runtime_type: browser
requires_ping: false
requires_credentials: true
target_system: cal_water
shared_credential_id: calwater_account
credential_display_name: California Water Service Account
tags: [water, usage, utilities, consumption, monitoring]
keywords: [water usage, water meter, cubic feet, CF, utility, water bill, conservation]
summary: Log into California Water Service account and retrieve current water usage data.
allowed_connectors: [browser_skill_runtime]
input_schema:
  type: object
  properties:
    data_type:
      type: string
      enum: [current_usage, historical, billing_info]
      default: current_usage
output_schema:
  type: object
  properties:
    summary:
      type: string
    water_usage_cf:
      type: number
    water_usage_ccf:
      type: number
    raw_text:
      type: string
    timestamp:
      type: string
    previous_reading_ccf:
      type: number
      nullable: true
    previous_reading_date:
      type: string
      nullable: true
      description: ISO date "YYYY-MM-DD" of the previous cycle's End Read
    previous_raw_text:
      type: string
      nullable: true
---

# Purpose
Access the user's California Water Service account and retrieve current water usage metrics, billing information, and historical consumption data for tracking and conservation purposes.

# When To Use
- User asks about their current water usage
- User wants to monitor water consumption trends
- User needs to check their water bill or usage history
- User is tracking conservation goals

# Required Inputs
- `data_type`: Type of data to retrieve (current_usage, historical, billing_info) — defaults to current_usage

# Runtime Rules
- Use `browser` runtime (Playwright-based headless automation)
- Requires stored credentials (username, password) for California Water Service account
- Current reading page: https://myaccount.calwater.com/app/water-usage
- Previous reading page: https://myaccount.calwater.com/app/water-usage/history
- Extract current usage from: `div.water-usage-header__period-value`
- Extract previous End Read from first row of history grid: `#history-0-2`

# Browser Automation Details
- **Base URL:** https://myaccount.calwater.com
- **Login Page:** Landing page with email/password form
- **Submit Method:** Press Enter on password field (no visible submit button)
- **Current Usage Page:** https://myaccount.calwater.com/app/water-usage
  - Selector: `div.water-usage-header__period-value` (e.g., "77782.997 CF")
  - Parse regex: `([\d,]+\.?\d*)\s*CF`
  - Wait for element text to contain `CF` or `CCF` before reading
- **History Page:** https://myaccount.calwater.com/app/water-usage/history
  - Grid selector: `div[role='grid'].usage-history__table`
  - End Read cell (most recent cycle): `#history-0-2` — multiline text, e.g.:
    ```
    761.003
    Apr 1st
    ```
  - Billing Period cell (most recent cycle): `#history-0-0` — multiline text, e.g.:
    ```
    April, 2026
    Feb 27th - Apr 1st
    33 Days
    ```
  - Parse first line of End Read as CCF reading (float)
  - Combine second line (day, e.g. "Apr 1st") with year pulled from the Billing Period cell (e.g. "2026") → ISO date "2026-04-01"
  - Strip English ordinal suffixes (`st|nd|rd|th`) before date parsing
- **Wait Strategy:** Use `domcontentloaded` + `networkidle` + explicit selector waits (30s timeout)

# Credential Fields
- `username`: Email address for California Water Service account (required)
- `password`: Account password (required)
- `base_url`: https://myaccount.calwater.com (auto-filled, cannot be changed)
- `notes`: Optional navigation hints or account-specific information (optional)

# Execution Plan
1. Navigate to base_url (https://myaccount.calwater.com)
2. Fill in email (username field) and password fields
3. Press Enter on password field to submit form
4. Wait for URL to match `/app` and for network idle
5. **Current reading:**
   - Navigate to `/app/water-usage`
   - Wait for `div.water-usage-header__period-value` selector
   - Wait for its innerText to contain `CF` or `CCF` (content may hydrate after DOM paint)
   - Extract text and parse CF with regex `([\d,]+\.?\d*)\s*CF`
   - Compute CCF = CF / 100
6. **Previous reading (history page):**
   - Navigate to `/app/water-usage/history`
   - Wait for `div[role='grid'].usage-history__table`
   - Wait for `#history-0-2` (first row End Read cell)
   - Read inner text of `#history-0-2` → split into lines; first line = CCF reading, second line = day text (e.g. "Apr 1st")
   - Read inner text of `#history-0-0` (billing period) → extract 4-digit year via regex `(20\d{2})`
   - Strip ordinal suffix from day and combine with year → parse as `%b %d %Y` (fallback `%B %d %Y`) → format `YYYY-MM-DD`
   - If the history page or any selector fails, return `previous_reading_ccf=None`, `previous_reading_date=None` (previous reading is optional — do not fail the whole skill)
7. Stamp `timestamp` with current time in `America/Los_Angeles` timezone (ISO 8601)
8. Return structured data: current CF/CCF + previous CCF/date + raw texts

# Output Guidance

**Primary Fields:**
- `water_usage_cf`: Current meter reading in cubic feet (CF)
- `water_usage_ccf`: Current usage converted to CCF (100 CF = 1 CCF)
- `raw_text`: Raw text scraped from the current-usage element (for debugging)
- `timestamp`: ISO 8601 timestamp (America/Los_Angeles) when data was retrieved
- `previous_reading_ccf`: End Read (CCF) of the most recent completed billing cycle, or `null` if unavailable
- `previous_reading_date`: ISO date (`YYYY-MM-DD`) of that End Read, or `null`
- `previous_raw_text`: Raw text scraped from the history End Read cell (for debugging), or an error note if the scrape failed

**Summary:**
Comprehensive markdown summary including:
- Current usage and CCF conversion
- Current bill amount
- Predicted tier (Tier 1-4 based on usage)
- Key metrics (daily average, cost per CCF)
- Billing breakdown (water charges, service charge, surcharges)

**Bill Data:**
- `bill.current_bill`: Total bill amount (float)
- `bill.water_charge`: Tiered water charges
- `bill.service_charge`: Service charge ($104.52 per period)
- `bill.surcharges`: Public purpose programs + surcharges + CPUC fees

**Tier Data:**
- `tier.name`: Tier name (Tier 1, 2, 3, or 4)
- `tier.usage_ccf`: Usage in CCF
- `tier.breakdown`: Breakdown by tier (t1, t2, t3, t4 amounts)

**Example Output:**
```
📊 **Water Usage Summary**

**Current Usage:** 16.00 CCF (1600 CF)
**Current Bill:** $257.23

**Predicted Tier:** Tier 3
At current pace, you're in Tier 3.

**Key Metrics:**
- Daily average: 80.0 CF/day
- Cost per CCF: $16.08

**Billing Breakdown:**
- Water charges: $152.71
- Service charge: $104.52
- Surcharges & fees: $0.00
```

# Failure Handling
- If login fails: Return credential invalid status, ask user to verify credentials
- If current-usage page doesn't load: Check for network errors, retry once (this is a hard failure — skill must return current reading)
- If current-usage regex doesn't match: Log page HTML for debugging, retry with updated selector
- If history page or previous-reading selectors fail: **soft failure** — return `previous_reading_ccf=null`, `previous_reading_date=null`, `previous_raw_text="history scrape failed: <error>"`, and still return a successful result with the current reading
- Timeout after 30 seconds per page navigation / selector wait

# Proactive Use
Not currently eligible for proactive execution. Add if periodic water usage monitoring is needed in future.

# Security Notes
- Passwords are stored encrypted in advisor_skill_credentials collection
- Browser sessions are isolated and closed immediately after data extraction
- No screenshots or sensitive data are persisted
- Shared credential system allows multiple water-related skills to reuse the same account
