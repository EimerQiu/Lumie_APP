# Timezone Issue Investigation — Task Notifications

**Date:** 2026-03-12
**Status:** ⚠️ Root Cause Identified, Fix Pending

## Problem

Notifications display incorrect task expiration times:
- Task: "Morning Meds" closes at 10:00 AM
- Notification shows: "Take it by 5:00 PM" (7-hour offset)

## Root Cause

Tasks are being stored with times in **device local time** rather than UTC:

1. **Flutter App**: When creating a task, times are captured as local time (no conversion to UTC)
2. **Backend Storage**: Times are stored as-is without UTC conversion
3. **Daemon Processing**:
   - Reads times from DB (assumed to be in `TASK_TIMEZONE`)
   - Converts to UTC for processing
   - BUT: If stored times are already in local tz, double-conversion causes offset

Example:
```
Stored in DB:  "2026-03-12 10:00" (actually local time, but labeled as TASK_TIMEZONE)
Daemon reads:  Assumes this is TASK_TIMEZONE
Converts to UTC: Adds 7-hour offset (PDT to UTC)
Result:        17:00 UTC (displayed as 5:00 PM in local time)
```

## Affected Files

- `lumie_activity_app/lib/features/tasks/screens/create_task_screen.dart` — task time creation
- `lumie_activity_app/lib/core/services/task_service.dart` — task time formatting
- `lumie_backend/app/api/task_routes.py` — task storage

## Recommended Fix

### Option A: Store All Times as UTC (Recommended)
**Pros**: Eliminates all timezone confusion, standard practice
**Cons**: Requires migration of existing data

**Implementation**:
```python
# In task creation endpoint
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

# Convert device local time to UTC before storing
device_tz = ZoneInfo(request_timezone)
local_time = datetime.strptime(open_datetime_str, "%Y-%m-%d %H:%M")
local_aware = local_time.replace(tzinfo=device_tz)
utc_time = local_aware.astimezone(timezone.utc)
# Store utc_time.strftime("%Y-%m-%d %H:%M") in DB
```

### Option B: Store Timezone Info with Times
Store both time string AND timezone separately, always do conversions explicitly

## Migration Required

Existing task data in production has wrong times. After fix, run:
```javascript
// MongoDB migration
db.tasks.updateMany({}, [
  {
    $set: {
      open_datetime: { /* convert to UTC */ },
      close_datetime: { /* convert to UTC */ }
    }
  }
])
```

## Testing Checklist

- [ ] Create task at 10:00 AM → verify stored as UTC equivalent
- [ ] Daemon processes task → verify correct timezone conversion
- [ ] Notification displays → verify shows original local time (10:00 AM, not 5:00 PM)
- [ ] Device in different timezone → verify still correct

## Priority

🔴 **High** — Notifications show wrong times to users, affects medication adherence

---

**Blocking**: Proper timezone handling for med reminders
**Next Steps**: Implement Option A (UTC storage) and migrate existing data
