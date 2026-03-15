# Lumie Domain Glossary

## Activity Related
- activity level = sum of duration_minutes in the activities collection
- active minutes = total daily activity minutes
- daily goal = adaptive goal (calculated by the backend based on health data)
- activity intensity = intensity field: low, moderate, high
- activity source = source field: ring (smart ring), manual (manual entry)

## Task Related
- Med-Reminder = tasks in the tasks collection where task_type = Medicine
- completion rate = completed / total tasks (for a given time period)
- completed tasks = tasks where the `done` field EXISTS in MongoDB (use `{"done": {"$exists": True}}`)
- expired tasks = `done` field absent AND `close_datetime` string < current time string
- pending tasks = `done` field absent AND `close_datetime` string >= current time string
- active tasks = current time is between open_datetime and close_datetime

CRITICAL: The `status` field does NOT exist in MongoDB. Never query `{"status": "completed"}` — it will always return 0 results. Always use `{"done": {"$exists": True}}` for completed tasks.

## Health Data Related
- heart rate = avg_heart_rate or max_heart_rate (BPM)
- 6-minute walk test / 6MWT / walk test = walk_tests collection
- walking distance = walk_tests.distance_meters
- recovery heart rate = walk_tests.recovery_heart_rate

## Team Related
- family / team = teams collection
- admin = team_members.role = admin
- parent = profiles.role = parent
- child / teen = profiles.role = teen

## Time Related
- this week = current calendar week (Monday to Sunday)
- this month = current calendar month
- last N days = past N calendar days (including today)

## CRITICAL: Datetime Filtering for tasks collection

The `open_datetime` and `close_datetime` fields in the `tasks` collection are **plain strings** in
the format `"YYYY-MM-DD HH:mm"` (e.g. `"2026-03-06 16:00"`). They are NOT datetime objects and NOT
ISO 8601 strings. Do NOT compare them with Python `datetime` objects.

**Always filter using string comparisons:**
```python
# Filter for March 2026 (this month):
{"open_datetime": {"$gte": "2026-03-01 00:00", "$lt": "2026-04-01 00:00"}}
# OR using regex prefix:
{"open_datetime": {"$regex": "^2026-03"}}

# Filter for last 7 days (if today is 2026-03-15):
{"open_datetime": {"$gte": "2026-03-08 00:00", "$lt": "2026-03-16 00:00"}}
```

**To get today's date string for filtering**, use:
```python
from datetime import datetime, timedelta
today_str = datetime.utcnow().strftime("%Y-%m-%d")
month_start = datetime.utcnow().strftime("%Y-%m") + "-01 00:00"
next_month = (datetime.utcnow().replace(day=1) + timedelta(days=32)).strftime("%Y-%m") + "-01 00:00"
tasks = list(db.tasks.find({"user_id": TARGET_USER_ID, "open_datetime": {"$gte": month_start, "$lt": next_month}}))
```

## Teen-Safe Rules (LLM Must Comply)
- Never output calories, BMI, or weight rankings
- Never perform weight-related comparisons or rankings
- Never generate performance leaderboards
- Express activity data in "minutes" not "calories burned"
