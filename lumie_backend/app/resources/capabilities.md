# Lumie Advisor Capabilities

This document describes the available capabilities for advisor skills and how credentials are managed.

## Capabilities

### lumie_internal_data
**Description:** Access to Lumie's internal user health data (sleep, activities, tasks, etc.)

**Characteristics:**
- Runtime type: `lumie_db`
- Requires credentials: No (uses internal ping token)
- Credential type: `lumie_internal_access` (auto-generated)
- Access level: Read-only to user's own data
- Uses Motor async database access

**Skills using this capability:**
- sleep_quality_summary
- activity_insights
- medication_adherence_check
- And many other lumie_db-based skills

---

### browser_portal_access
**Description:** Access to web portals and online services via browser automation

**Characteristics:**
- Runtime type: `browser`
- Requires credentials: Yes (username, password, base_url)
- Credential fields: `username`, `password`, `base_url`, `notes` (optional)
- Browser: Playwright-based headless Chrome
- Steps: LLM-generated or specialized handlers

**Skills using this capability:**
- school_homework_query (school portal)
- gmail_inbox_check (Gmail)

**Shared credentials:** Schools or services can use `shared_credential_id` to allow multiple skills to share the same login

---

### external_service_integration
**Description:** Integration with external utility and service APIs

**Characteristics:**
- Runtime type: `browser` (specialized) or `external_api`
- Requires credentials: Yes
- Credential fields: `username`, `password`, `base_url`, `notes` (optional)
- Use case: Water, electricity, gas, internet service monitoring
- Shared credentials: Yes, via `shared_credential_id`

**Skills using this capability:**
- water_usage_monitor (California Water Service)
- *Future: Electric usage, gas consumption, internet speed, etc.*

**Shared credential system:** Multiple skills related to the same utility can use the same stored credentials via `shared_credential_id: "calwater_account"` etc.

---

## Credential Storage & Management

### Storage
- **Collection:** `advisor_skill_credentials`
- **Structure:**
  ```json
  {
    "credential_id": "cred_skill_id_user_id",
    "user_id": "...",
    "skill_id": "__shared__calwater_account" or "water_usage_monitor",
    "status": "valid|invalid|saved_not_tested|missing",
    "username": "...",
    "password": "...",
    "base_url": "https://...",
    "ping": "...",
    "notes": "optional navigation hints",
    "created_at": "...",
    "updated_at": "...",
    "last_tested_at": "...",
    "last_test_result": "..."
  }
  ```

### Shared Credentials
- **Key Pattern:** `__shared__{shared_credential_id}`
- **Use case:** Multiple skills sharing login credentials
- **Example:** `water_usage_monitor`, `water_conservation_check`, and `water_bill_summary` all use `shared_credential_id: "calwater_account"`
- **Lookup:** `core/credential_utils.py::resolve_credential_key()` returns the actual DB key

### Credential Status
- `missing`: No credential configured
- `saved_not_tested`: Credential saved but not yet validated
- `valid`: Credential tested and working
- `invalid`: Credential tested and failed

### Security
- Passwords are stored plain-text in Phase 1 (encrypt in future)
- API keys use `password` field
- Credentials are never exposed to frontend except:
  - `credential_id`, `username`, `base_url` (safe fields)
  - `has_password` (boolean flag)
  - `has_ping` (boolean flag)
- Sanitization: `skill_credential_service.py::sanitize_credential_for_response()`

---

## Water Monitor Integration

### Skill Definition
**File:** `lumie_backend/app/skills/system/browser/water_usage_monitor.md`

**Metadata:**
```yaml
skill_id: water_usage_monitor
title: Water Usage Monitor
capability_id: external_service_integration
runtime_type: browser
requires_credentials: true
shared_credential_id: calwater_account
credential_display_name: California Water Service Account
```

### Runtime Handler
**File:** `lumie_backend/app/services/water_monitor_runtime.py`

**Functions:**
- `extract_water_usage(username, password, base_url, timeout_ms)` → Dict with water_usage_cf, timestamp, summary
- `test_credentials(username, password, base_url)` → Dict with success/error for credential validation

**Implementation:**
- Playwright headless browser automation
- Login via email + password (Enter key submission)
- Navigates to `/app/water-usage` endpoint
- Extracts CF number via CSS selector + regex
- Returns structured JSON with usage, timestamp, and user-friendly summary

### Execution Flow
1. **Frontend:** User provides Cal Water credentials via credential form
2. **API:** POST to `/api/v1/credentials/{skill_id}` stores in `advisor_skill_credentials`
3. **Skill invocation:** User asks "What's my water usage?"
4. **Service:** `execution_service.py` routes to `_execute_browser()`
5. **Dispatcher:** `browser_skill_runtime.execute_browser_skill()` detects `skill_id == "water_usage_monitor"`
6. **Handler:** `water_monitor_runtime.extract_water_usage()` called with stored credentials
7. **Result:** Structured data returned → saved to chat history → displayed to user

---

## Future Integrations

### Electricity Usage Monitor
- Skill: `electricity_usage_monitor`
- Service: PG&E, Southern California Edison, etc.
- Shared credential: `electricity_account`
- Similar to water monitor, different portal URL and CSS selectors

### Gas Consumption Monitor
- Skill: `gas_consumption_monitor`
- Service: Gas utility (varies by region)
- Shared credential: `gas_account`

### Internet/ISP Monitor
- Skill: `internet_usage_monitor`
- Service: ISP portal (Comcast, AT&T, etc.)
- Shared credential: `isp_account`

---

## Adding a New Service Integration

### Steps
1. **Create skill MD** in `lumie_backend/app/skills/system/browser/`
   - Set `capability_id: external_service_integration`
   - Set `runtime_type: browser`
   - Define `shared_credential_id` if sharing with other skills
   
2. **Create runtime handler** in `lumie_backend/app/services/`
   - Implement async function: `async def extract_data(username, password, base_url, ...)`
   - Handle login, navigation, data extraction
   - Return structured dict with `success`, `data`, `error`, etc.

3. **Update browser_skill_runtime.py**
   - Add dispatcher case: `if skill_id == "your_skill_id":`
   - Import and call your runtime handler
   - Return properly formatted result dict

4. **Document** in this file and create a dev-log entry

---
