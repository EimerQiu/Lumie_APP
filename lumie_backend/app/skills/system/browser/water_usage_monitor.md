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
    timestamp:
      type: string
    billing_period:
      type: string
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
- Navigate to: https://myaccount.calwater.com/app/water-usage
- Extract usage from: `div.water-usage-header__period-value` element

# Browser Automation Details
- **Base URL:** https://myaccount.calwater.com
- **Login Page:** Landing page with email/password form
- **Submit Method:** Press Enter on password field (no visible submit button)
- **Target Page:** https://myaccount.calwater.com/app/water-usage
- **Data Extraction:** CSS selector `div.water-usage-header__period-value` contains the current usage (e.g., "77782.997 CF")
- **Wait Strategy:** Use network idle waits (2-3 seconds) after navigation for JS rendering

# Credential Fields
- `username`: Email address for California Water Service account (required)
- `password`: Account password (required)
- `base_url`: https://myaccount.calwater.com (auto-filled, cannot be changed)
- `notes`: Optional navigation hints or account-specific information (optional)

# Execution Plan
1. Navigate to base_url (https://myaccount.calwater.com)
2. Fill in email (username field) and password fields
3. Press Enter on password field to submit form
4. Wait for network idle and navigation to /app
5. Navigate to /app/water-usage endpoint
6. Wait for water usage header to load
7. Extract CF number from `.water-usage-header__period-value` using regex pattern `([\d,]+\.?\d*)\s*CF`
8. Return structured data with usage amount and timestamp

# Output Guidance

**Primary Fields:**
- `water_usage_cf`: Current meter reading in cubic feet (CF)
- `water_usage_ccf`: Current usage converted to CCF (100 CF = 1 CCF)
- `timestamp`: ISO timestamp when data was retrieved
- `billing_period`: Current billing period timestamp

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
- If water usage page doesn't load: Check for network errors, retry once
- If extraction regex doesn't match: Log page HTML for debugging, retry with updated selector
- Timeout after 30 seconds of page navigation

# Proactive Use
Not currently eligible for proactive execution. Add if periodic water usage monitoring is needed in future.

# Security Notes
- Passwords are stored encrypted in advisor_skill_credentials collection
- Browser sessions are isolated and closed immediately after data extraction
- No screenshots or sensitive data are persisted
- Shared credential system allows multiple water-related skills to reuse the same account
