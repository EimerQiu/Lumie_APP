---
skill_id: ring_live_measure
title: Ring Live Measurement
capability_id: lumie_internal_data
runtime_type: lumie_db
requires_ping: true
requires_credentials: true
target_system: lumie_db
tags: [heart rate, temperature, live, real-time, ring]
keywords: [measure my heart rate, check my heart rate, take my heart rate now, live heart rate, current heart rate, measure heart rate, what is my heart rate, my temperature, check my temperature, take my temperature, body temperature now, current temperature, live temperature, measure temperature]
summary: Send a live command to the Lumie Ring to take an on-demand heart rate measurement or body temperature reading, then return the result. Use when the user wants a real-time measurement, not stored history.
proactive_eligible: true
proactive_domain: recovery
proactive_priority: 70
proactive_mode: assessment
allowed_connectors: [lumie_db_connector]
input_schema:
  type: object
  properties:
    command_type:
      type: string
      description: "hr_measure | temperature"
    duration_seconds:
      type: integer
      description: "Duration in seconds for HR measurement (default 10)"
    target_user_hint:
      type: string
output_schema:
  type: object
  properties:
    summary:
      type: string
    data:
      type: object
      description: "For hr_measure: {status, command_type, avg_bpm, min_bpm, max_bpm, duration_seconds}. For temperature: {status, command_type, highest_temp_c, ntc1_c, ntc2_c, ntc3_c}. For timeout/failed: {status, command_type, error?}"
---

# Purpose
Use this skill when the user asks for a **live, on-demand** reading from their ring — not historical data. Examples: "measure my heart rate", "what is my heart rate right now", "check my temperature". This skill sends a command to the ring via push notification and waits for the result. Heart-rate measurements may need up to about 75 seconds end-to-end because the ring protocol requires a 30-second minimum measurement plus wake-up / BLE reconnect / result return time.

# When To Use
- "Measure my heart rate"
- "What's my heart rate right now?"
- "Take my heart rate"
- "Check my temperature"
- "What is my body temperature right now?"
- "Can you measure my HR for 10 seconds?"

# Do NOT Use When
- User asks about *historical* HR, temperature, HRV, SpO2 data → use `health_data_query`
- User asks about sleep, activity, steps → use `health_data_query`
- Ring is not connected (there is no way to know from here — proceed and handle timeout gracefully)

# Runtime Rules
- `user_timezone`, `ZoneInfo`, `timezone`, `timedelta`, `datetime`, `asyncio`, `uuid` are all pre-loaded — do NOT import them
- Use the `db` variable directly
- The `user_id` and `target_user_id` variables are pre-loaded

# Result Data Contract

The ring app posts the completed live-measurement payload into `ring_command_requests.result`.
This skill should assume these result shapes:

- `command_type = "hr_measure"`
  - `avg_bpm`: integer
  - `min_bpm`: integer
  - `max_bpm`: integer
  - `duration_seconds`: integer
- `command_type = "temperature"`
  - `highest_temp_c`: float
  - `ntc1_c`: float
  - `ntc2_c`: float
  - `ntc3_c`: float

Always return `data.status` explicitly:

- `"completed"` for success
- `"timeout"` when the command expired before the app reported back
- `"failed"` when the app reported an execution failure

Always include `data.command_type`.

# Implementation

## Step 1 — Create a ring command request

```python
command_type = skill_input.get("command_type", "hr_measure")
duration_seconds = int(skill_input.get("duration_seconds", 10))
request_id = str(uuid.uuid4())
now_iso = datetime.now(timezone.utc).isoformat()

await db.ring_command_requests.insert_one({
    "request_id": request_id,
    "user_id": target_user_id,
    "command_type": command_type,
    "duration_seconds": duration_seconds,
    "status": "pending",
    "created_at": now_iso,
    "expires_at": (
        datetime.now(timezone.utc)
        + timedelta(seconds=(max(duration_seconds, 30) + 45) if command_type == "hr_measure" else 20)
    ).isoformat(),
    "result": None,
    "completed_at": None,
})
```

## Step 2 — Queue a push notification to wake the app

```python
await db.notification_queue.insert_one({
    "notification_id": str(uuid.uuid4()),
    "type": "ring_command",
    "recipient_user_id": target_user_id,
    "title": "Lumie Ring",
    "body": "Taking a live reading from your ring...",
    "data": {
        "type": "ring_command",
        "request_id": request_id,
        "command_type": command_type,
    },
    "status": "pending",
    "created_at": now_iso,
    "sent_at": None,
})

# Ring commands are time-sensitive; flush the queue immediately instead of
# waiting for the notification daemon's next poll cycle.
await flush_notification_queue_now()
```

## Step 3 — Poll for the result

For heart-rate measurements, allow extra time for push delivery, app wake-up,
possible BLE reconnect, and the ring's 30-second minimum measurement window.
Total window is 30s measurement + 45s buffer = 75s.

```python
wait_seconds = duration_seconds + 45 if command_type == "hr_measure" else 20
poll_attempts = max(10, (wait_seconds + 1) // 2)

for _ in range(poll_attempts):
    await asyncio.sleep(2)
    doc = await db.ring_command_requests.find_one({"request_id": request_id})
    if doc and doc.get("status") in ("completed", "failed"):
        break
```

## Step 4 — Parse and return result

```python
if not doc or doc.get("status") == "pending":
    await db.ring_command_requests.update_one(
        {"request_id": request_id, "status": "pending"},
        {"$set": {
            "status": "expired",
            "error": "Command expired before the app executed it",
            "completed_at": datetime.now(timezone.utc).isoformat(),
        }},
    )
    # Timeout — ring may be out of range or app is not open
    result_summary = (
        "I sent the measurement request to your ring, but it didn't respond in time. "
        "Make sure the Lumie app is open and your ring is nearby, then try again."
    )
    result_data = {"status": "timeout", "command_type": command_type}

elif doc.get("status") == "failed":
    result_summary = (
        f"Your ring couldn't complete the measurement: {doc.get('error', 'unknown error')}. "
        "Make sure the ring is on your finger and try again."
    )
    result_data = {"status": "failed", "error": doc.get("error")}

else:
    data = doc.get("result", {})

    if command_type == "hr_measure":
        avg = data.get("avg_bpm")
        mn  = data.get("min_bpm")
        mx  = data.get("max_bpm")
        dur = data.get("duration_seconds", duration_seconds)
        result_summary = (
            f"Your heart rate over {dur} seconds: "
            f"**{avg} bpm** average (range {mn}–{mx} bpm)."
        )
        result_data = {
            "status": "completed",
            "command_type": command_type,
            "avg_bpm": avg,
            "min_bpm": mn,
            "max_bpm": mx,
            "duration_seconds": dur,
        }

    elif command_type == "temperature":
        highest = data.get("highest_temp_c")
        ntc1 = data.get("ntc1_c")
        result_summary = (
            f"Your ring temperature reading: **{highest}°C** "
            f"(sensor 1: {ntc1}°C). "
            + ("That's within a normal range." if highest and highest < 37.5
               else "That may be slightly elevated — monitor it if you feel unwell." if highest and highest >= 37.5
               else "")
        )
        result_data = {
            "status": "completed",
            "command_type": command_type,
            "highest_temp_c": highest,
            "ntc1_c": ntc1,
            "ntc2_c": data.get("ntc2_c"),
            "ntc3_c": data.get("ntc3_c"),
        }

    else:
        result_summary = f"Live measurement completed: {data}"
        result_data = {
            "status": "completed",
            "command_type": command_type,
            "raw_result": data,
        }
```

# Output Guidance

## HR Measurement
- Normal resting: **60–100 bpm** for most people; athletic teens may be 45–65 bpm
- Elevated (>100 bpm at rest): mention it briefly without alarming; suggest resting before re-measuring
- Low (<50 bpm): normal if athletic; worth noting if unusual for the user

## Temperature
- Normal: **36.0–37.4°C**
- Low-grade fever: **37.5–38.0°C** — mention it; suggest monitoring
- Fever: **>38.0°C** — flag clearly; suggest the user check with a parent or doctor
- Note: ring skin temperature runs slightly lower than core body temperature

## Timeout / Failed
- Be reassuring — don't suggest anything is wrong with the ring
- Common cause: app was in background and push notification delayed
- Suggest: open Lumie, keep ring on finger, try again

# Failure Handling
- Always return a friendly message even on timeout or failure
- Never leave the user with a raw error string
- If DB insert fails, return an error message explaining the service is temporarily unavailable
- Keep the returned `data` object structurally valid even on error (`status`, `command_type`, optional `error`)
