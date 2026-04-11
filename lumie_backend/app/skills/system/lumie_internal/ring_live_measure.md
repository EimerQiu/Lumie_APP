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
Use this skill in two modes:

1. **User-Triggered** (user asks "measure my heart rate", "check my temperature"): Send a live command to the ring and return the result.

2. **Proactive Mode** (run during automated health checks): Check if the ring is connected. If connected, take a live measurement and detect medical concerns based on vital sign thresholds.

Heart-rate measurements may need up to about 75 seconds end-to-end because the ring protocol requires a 30-second minimum measurement plus wake-up / BLE reconnect / result return time.

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

# Schema

See [`RingCommandRequest` in models/ring_command.py](../../models/ring_command.py) for request structure and stored data model.

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

# Proactive Mode Vital Sign Concern Detection

When running in proactive mode (automated health checks), after measuring vital signs, detect medical concerns:

## Heart Rate Thresholds (Medical Science Based)

- **Resting HR 60–100 bpm**: Normal for most adults
- **Athletic 45–65 bpm**: Expected if the user is athletic (check profile activity level)
- **Elevated (>100 bpm)**: May indicate stress, illness, or anxiety; flag for monitoring
- **Low (<50 bpm)**: Normal if athletic; otherwise may warrant monitoring
- **Critically elevated (>120 bpm at rest)**: Flag as concern; suggest check-in
- **Critically low (<40 bpm)**: Flag as concern; may indicate bradycardia

**Action in Proactive Mode:**
- Compare measured avg_bpm against user's baseline (if available from recent history)
- Trend detection: if elevated compared to user's normal, flag it
- If resting HR >110 bpm → strong nudge signal
- If resting HR <45 bpm and not athletic → moderate nudge signal

## Temperature Thresholds (Medical Science Based)

- **Normal: 36.0–37.4°C** (98.6°F ± 1°F)
- **Low-grade: 37.5–38.0°C** (99.5–100.4°F) — monitor, suggest rest/hydration
- **Fever: >38.0°C** (100.4°F+) — flag clearly; suggest contact with parent/doctor
- **Hypothermia: <36.0°C** — unusual for ring measurement; check for sensor error

**Action in Proactive Mode:**
- If temp 37.5–38.0°C → moderate nudge (monitor and rest)
- If temp >38.0°C → strong nudge (suggest medical check-in)

# Implementation

## Step 0 — Check Ring Connection (Proactive Mode Only)

In proactive mode, before measuring, verify the ring is connected and the app is active:

```python
# Check if we're in proactive mode (proactive_check flag set by framework)
if skill_input.get("proactive_mode", False):
    # Query recent ring_command_requests to check if the ring responds
    # If last 2-3 commands all timed out, ring is likely disconnected
    recent_timeouts = await db.ring_command_requests.count_documents({
        "user_id": target_user_id,
        "status": "expired",
        "created_at": {"$gte": (datetime.now(timezone.utc) - timedelta(hours=2)).isoformat()}
    })
    
    if recent_timeouts >= 2:
        # Ring appears disconnected — return early with no_data status
        _result = {
            "summary": "Ring is not currently connected or the app is not open. Measurements require the Lumie app running and ring in range.",
            "data": {
                "status": "no_data",
                "command_type": "none",
                "reason": "ring_not_connected"
            }
        }
        return
```

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
        
        # Detect concerns for proactive mode
        is_athletic = False  # TODO: check user profile activity level
        is_proactive = skill_input.get("proactive_mode", False)
        
        concern_flags = None
        if is_proactive:
            concern_flags = {
                "elevated_resting": avg > 110,
                "critically_low": avg < 45 and not is_athletic,
                "moderately_elevated": 100 < avg <= 110,
                "moderately_low": 45 <= avg < 50 and not is_athletic,
            }
            
            # Determine severity and recommendation
            if concern_flags["critically_low"] or concern_flags["elevated_resting"]:
                severity = "strong"
                if concern_flags["elevated_resting"]:
                    concern_type = "elevated_hr"
                    recommendation = "Elevated resting heart rate detected. Suggest check-in to discuss stress, activity level, or potential health concerns."
                else:
                    concern_type = "low_hr"
                    recommendation = "Critically low heart rate detected. Suggest medical check-in if unusual for the user."
            elif concern_flags["moderately_elevated"] or concern_flags["moderately_low"]:
                severity = "moderate"
                concern_type = "moderately_elevated_hr" if concern_flags["moderately_elevated"] else "moderately_low_hr"
                recommendation = "Heart rate is slightly elevated. Monitor and suggest adequate rest." if concern_flags["moderately_elevated"] else "Heart rate is slightly low. May be normal if athletic, but worth monitoring."
            else:
                severity = "none"
                concern_type = None
                recommendation = None
        
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
        
        if is_proactive and concern_flags:
            result_data["proactive_concerns"] = {
                "has_concern": any(concern_flags.values()),
                "concern_type": concern_type,
                "severity": severity,
                "recommendation": recommendation,
            }

    elif command_type == "temperature":
        highest = data.get("highest_temp_c")
        ntc1 = data.get("ntc1_c")
        
        # Detect concerns for proactive mode
        is_proactive = skill_input.get("proactive_mode", False)
        
        concern_flags = None
        if is_proactive and highest:
            concern_flags = {
                "fever": highest >= 38.0,
                "low_grade_fever": 37.5 <= highest < 38.0,
                "elevated": highest >= 37.5,
            }
            
            # Determine severity and recommendation
            if concern_flags["fever"]:
                severity = "strong"
                concern_type = "fever"
                recommendation = "Temperature indicates fever (>38.0°C). Suggest contact with parent or doctor for evaluation."
            elif concern_flags["low_grade_fever"]:
                severity = "moderate"
                concern_type = "low_grade_fever"
                recommendation = "Temperature is slightly elevated (37.5–38.0°C). Suggest monitoring, rest, and hydration. Recheck if symptoms develop."
            else:
                severity = "none"
                concern_type = None
                recommendation = None
        
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
        
        if is_proactive and concern_flags:
            result_data["proactive_concerns"] = {
                "has_concern": any(concern_flags.values()),
                "concern_type": concern_type,
                "severity": severity,
                "recommendation": recommendation,
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

## User-Triggered Mode (Standard Responses)

### HR Measurement
- Normal resting: **60–100 bpm** for most people; athletic teens may be 45–65 bpm
- Elevated (>100 bpm at rest): mention it briefly without alarming; suggest resting before re-measuring
- Low (<50 bpm): normal if athletic; worth noting if unusual for the user

### Temperature
- Normal: **36.0–37.4°C**
- Low-grade fever: **37.5–38.0°C** — mention it; suggest monitoring
- Fever: **>38.0°C** — flag clearly; suggest the user check with a parent or doctor
- Note: ring skin temperature runs slightly lower than core body temperature

### Timeout / Failed
- Be reassuring — don't suggest anything is wrong with the ring
- Common cause: app was in background and push notification delayed
- Suggest: open Lumie, keep ring on finger, try again

## Proactive Mode (Concern Detection & Nudge Signals)

### HR Measurement Response
Include concern flags in data for LLM decision:
```python
concern_flags = {
    "elevated_resting": avg_bpm > 110,  # Strong nudge signal
    "critically_low": avg_bpm < 45 and not is_athletic,  # Strong nudge signal
    "moderately_elevated": 100 < avg_bpm <= 110,  # Moderate nudge signal
    "moderately_low": 45 <= avg_bpm < 50 and not is_athletic,  # Moderate nudge signal
    "baseline_comparison": {
        "compared_to_recent_average": avg_bpm,
        "deviation_from_baseline": avg_bpm - user_recent_avg if user_recent_avg else None,
        "is_trending_up": avg_bpm > (user_recent_avg + 10) if user_recent_avg else False
    }
}
```

**Nudge Decision Logic:**
- Strong nudge: elevated >110 OR critically low <45 (non-athletic)
- Moderate nudge: 100–110 bpm OR upward trend (+10+ bpm from recent average)
- No nudge: within normal range AND stable or trending down

### Temperature Response
Include concern flags in data:
```python
concern_flags = {
    "elevated": highest_temp_c >= 37.5,
    "fever": highest_temp_c >= 38.0,  # Strong nudge signal
    "low_grade_fever": 37.5 <= highest_temp_c < 38.0,  # Moderate nudge signal
}
```

**Nudge Decision Logic:**
- Strong nudge: temp >38.0°C (potential fever)
- Moderate nudge: temp 37.5–38.0°C (low-grade, suggest monitoring)
- No nudge: <37.5°C (normal)

### Data Structure for Proactive Decisions
Include concern flags in the returned data object:
```python
result_data = {
    "status": "completed",
    "command_type": "hr_measure" or "temperature",
    # ... standard fields (avg_bpm, min_bpm, max_bpm, highest_temp_c, etc.)
    
    # NEW: Concern flags for LLM decision
    "proactive_concerns": {
        "has_concern": bool,  # True if any threshold triggered
        "concern_type": str,  # "elevated_hr", "low_hr", "fever", "low_grade_fever", None
        "severity": str,  # "strong", "moderate", "none"
        "recommendation": str,  # "Suggest check-in", "Monitor and rest", etc.
    }
}
```

# Failure Handling
- Always return a friendly message even on timeout or failure
- Never leave the user with a raw error string
- If DB insert fails, return an error message explaining the service is temporarily unavailable
- Keep the returned `data` object structurally valid even on error (`status`, `command_type`, optional `error`)
