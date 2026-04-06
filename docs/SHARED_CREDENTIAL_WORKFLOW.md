# Shared Credential Workflow

## Overview

The Lumie advisor system supports **shared credentials** — where multiple skills use the same credential configuration. This document explains how shared credentials work across the entire system.

## Example: Home Energy System

Two skills share one credential:
- **`ac_control`** — Turn AC on/off, control thermostat
- **`energy_status_query`** — Check solar, Powerwall, Tesla, AC status

Both have:
```yaml
shared_credential_id: home_energy
credential_display_name: Home Energy
requires_credentials: true
```

**Result:** Users configure credentials **once** and both skills can use them.

## Backend Credential Resolution

All three execution paths use the same credential resolution logic:

### 1. Credential Key Resolution

`lumie_backend/app/core/credential_utils.py`:
```python
def resolve_credential_key(skill: SkillIndexItem) -> str:
    """Return the DB key used for credential storage.
    
    Skills with shared_credential_id use a shared pool key (__shared__{id}).
    Other skills use their own skill_id as the key.
    """
    if skill.shared_credential_id:
        return f"__shared__{skill.shared_credential_id}"
    return skill.skill_id
```

**Example:**
```
ac_control (shared_credential_id='home_energy')
    ↓ resolve_credential_key()
    ↓ Returns: "__shared__home_energy"

energy_status_query (shared_credential_id='home_energy')
    ↓ resolve_credential_key()
    ↓ Returns: "__shared__home_energy"

tasks_query (no shared_credential_id)
    ↓ resolve_credential_key()
    ↓ Returns: "tasks_query"
```

## Execution Paths

### Path 1: Regular Advisor Chat

**File:** `lumie_backend/app/services/advisor_orchestrator.py`

Flow:
1. User asks advisor a question
2. LLM routes to a skill (e.g., `ac_control`)
3. Orchestrator loads credential:
   ```python
   cred_key = resolve_credential_key(skill)  # "__shared__home_energy"
   credential = await skill_credential_service.get_credential(user_id, cred_key)
   ```
4. Execution service runs the skill with the credential

### Path 2: Proactive Advisor Check

**File:** `lumie_backend/app/services/proactive_advisor_service.py`

Flow:
1. Scheduled proactive advisor runs for a user
2. Selector picks skills to assess (e.g., `energy_status_query`)
3. Proactive service loads credential:
   ```python
   credential_key = resolve_credential_key(skill)  # "__shared__home_energy"
   cred = await db.advisor_skill_credentials.find_one(
       {"user_id": user_id, "skill_id": credential_key}
   )
   ```
4. Execution service runs the skill with the credential

### Path 3: Settings Screen (Frontend → API)

**File:** `lumie_backend/app/api/advisor_v2_routes.py`

Endpoints:
- `GET /api/v1/advisor/v2/skills/{skill_id}/credential` — Get credential
- `PUT /api/v1/advisor/v2/skills/{skill_id}/credential` — Save credential
- `POST /api/v1/advisor/v2/skills/{skill_id}/test` — Test credential

Flow:
1. User opens advisor settings, clicks on `ac_control` skill
2. Frontend calls `GET /api/v1/advisor/v2/skills/ac_control/credential`
3. Backend resolves key:
   ```python
   cred_key = resolve_credential_key(skill)  # "__shared__home_energy"
   cred = await skill_credential_service.get_credential(user_id, cred_key)
   ```
4. Frontend displays credential form (base_url, password, etc.)
5. User saves credentials → Frontend calls `PUT /api/v1/advisor/v2/skills/ac_control/credential`
6. Backend saves to DB with resolved key:
   ```python
   cred = await skill_credential_service.save_credential(
       user_id=user_id,
       skill_id="__shared__home_energy",  # resolved key
       data={...}
   )
   ```

**Now if user clicks on `energy_status_query` skill:**
7. Frontend calls `GET /api/v1/advisor/v2/skills/energy_status_query/credential`
8. Backend resolves: `energy_status_query` → `__shared__home_energy`
9. **Same credential is returned!** ✅

## Database Storage

**Collection:** `advisor_skill_credentials`

```json
// Shared credential (stored once, used by 2 skills)
{
  "_id": ObjectId("..."),
  "user_id": "bc5e5a99-b8b2-40df-aca8-402db01b4eaf",
  "skill_id": "__shared__home_energy",        // ← shared key
  "credential_id": "cred___shared__home_energy_bc5e5a99",
  "system_name": "Home Energy",
  "base_url": "https://home.yumo.org",
  "password": "10560",
  "status": "valid",
  "last_tested_at": "2026-04-06T04:35:00...",
  "last_test_result": "fields_complete",
  "created_at": "2026-03-28T...",
  "updated_at": "2026-04-06T..."
}

// Non-shared credential (stored separately)
{
  "_id": ObjectId("..."),
  "user_id": "bc5e5a99-b8b2-40df-aca8-402db01b4eaf",
  "skill_id": "gmail_inbox_check",            // ← skill's own key
  "credential_id": "cred_gmail_inbox_check_bc5e5a99",
  "system_name": "Gmail",
  "username": "user@gmail.com",
  "password": "app_password_...",
  "status": "valid",
  ...
}
```

## User Interface

**Advisor Skills List Screen** (`lumie_activity_app/lib/features/advisor/screens/advisor_skill_list_screen.dart`):

Shows all skills but indicates shared credentials:
- **AC Control** 🔗 "Uses 'Home Energy' credential"
- **Energy Status Query** 🔗 "Uses 'Home Energy' credential"
- **Gmail Inbox Check** 🔑 "Uses 'Gmail Inbox Check' credential"

The 🔗 icon indicates a **shared** credential pool.
The 🔑 icon indicates a **non-shared** (skill-specific) credential.

When user taps either skill, both navigate to the same credential configuration (due to backend resolution).

## Configuration Propagation

**Scenario:** User adds home energy credentials via `ac_control` skill

1. ✅ **Regular Advisor:** When user asks "turn on the AC" → `ac_control` executes with credential
2. ✅ **Advisor Settings:** When user clicks on `energy_status_query` → shows the same credential  
3. ✅ **Proactive Advisor:** When checking home energy status → `energy_status_query` executes with credential
4. ✅ **Credential Testing:** Test passes for both skills (tests same credential)

**Scenario:** User removes the credential

1. ✅ Both skills immediately show "Setup needed"
2. ✅ Both return no_data in proactive checks until reconfigured

## Code Consistency

All three execution paths now use the **same resolution function** from `core/credential_utils.py`:

| Component | Import | Function | Location |
|-----------|--------|----------|----------|
| Advisor v2 API | ✅ | `resolve_credential_key()` | `advisor_v2_routes.py:28` |
| Advisor Orchestrator | ✅ | `resolve_credential_key()` | `advisor_orchestrator.py:18` |
| Proactive Advisor | ✅ | `resolve_credential_key()` | `proactive_advisor_service.py:26` |

**Before refactoring:** Each had its own copy or inline logic (inconsistency risk).
**After refactoring:** Single source of truth — easier to maintain and debug.

## Adding a New Shared Credential

To make two skills share credentials:

1. **In both skill markdown files:**
   ```yaml
   shared_credential_id: your_system_id
   credential_display_name: Your System
   requires_credentials: true
   ```

2. **No backend changes needed** — the resolution logic handles it automatically.

3. Example:
   ```yaml
   # skill1.md
   shared_credential_id: spotify
   credential_display_name: Spotify
   
   # skill2.md
   shared_credential_id: spotify
   credential_display_name: Spotify
   
   # Both will use "__shared__spotify" as the DB key
   ```

## Troubleshooting

### Problem: "Setup needed" but credentials are saved

**Check:** Is `shared_credential_id` correctly defined in both skill markdowns?
```bash
grep -n "shared_credential_id" lumie_backend/app/skills/system/home/*.md
```

**Fix:** Ensure the value is identical in all skills that should share credentials.

### Problem: Changing one skill's credential doesn't affect the other

**Check:** Are the skills using the same `shared_credential_id`?

**Debug:**
```bash
# Check MongoDB directly
db.advisor_skill_credentials.find({user_id: "..."}).pretty()
# Look for one document with skill_id: "__shared__home_energy"
# (not separate ones for "ac_control" and "energy_status_query")
```

### Problem: Proactive advisor can't find credentials that settings shows as valid

**Check:** Is the credential status "valid" or "saved_not_tested"?
```bash
# In MongoDB
db.advisor_skill_credentials.findOne({user_id: "...", skill_id: "__shared__home_energy"})
# Check the "status" field — should be "valid" for external_api skills
```

**Common cause:** POST skills (like ac_control) only require fields_complete, not actual connectivity test.
If status is "saved_not_tested", proactive may skip it if validation is too strict.

## Testing

Run proactive advisor for a user with shared credentials configured:

```bash
curl -X POST http://localhost:8000/api/v1/internal/advisor/proactive/run/{user_id} \
  -H "Authorization: Bearer {token}"
```

Check logs for credential resolution:
```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124 \
  "sudo journalctl -u lumie-api -n 100 --no-pager | grep -E 'resolve|credential'"
```

Expected output:
```
2026-04-06 04:35:18 - INFO - Skill energy_status_query skipped: required credential not found
                       ↑ or successful execution if credential exists
```
