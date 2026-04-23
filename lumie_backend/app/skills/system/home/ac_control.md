---
skill_id: ac_control
title: AC Control
capability_id: home_energy_access
runtime_type: external_api
requires_ping: false
requires_credentials: true
target_system: energy_dashboard
api_endpoint: /api/ac/control
api_method: POST
shared_credential_id: home_energy
credential_display_name: Home Energy
tags: [ac, air conditioning, nest, thermostat, home, temperature, cooling, heating]
keywords: [turn on ac, turn off ac, ac on, ac off, air conditioning, cool down, heat up, thermostat, bedroom ac, living room ac, basement ac, all ac, shut off ac, start ac, stop ac, set temperature, cool bedroom, cool living room]
summary: Turn the AC (Nest thermostats) on or off for any room — bedroom, living room, basement, or all rooms at once. Optionally set mode (cool/heat) and temperature.
allowed_connectors: [external_api_connector]
---

# Purpose
Use this skill when the user wants to turn the AC on or off, control a specific room's thermostat, or set a cooling/heating temperature via Nest.

# When To Use
- "Turn on the AC"
- "Turn off the AC"
- "Turn on the bedroom AC"
- "Shut off all the AC"
- "Cool down the living room to 21°C"
- "Turn on heating in the basement"
- "Turn off the bedroom and living room AC"
- "Set the AC to 23 degrees"

# Do NOT Use When
- User is just asking about AC status (use `energy_status_query` instead)

# Credential Setup
- `base_url`: `https://home.yumo.org`
- `password`: API key (required for write access)

# API Request Body

```json
{
  "action": "on" | "off",
  "room": "bedroom" | "living_room" | "basement" | "all",
  "mode": "cool" | "heat",
  "temp_c": 22.0
}
```

Field rules:
- `action` — **required**: `"on"` or `"off"`
- `room` — which room to control; use `"all"` if user says "all" or doesn't specify a room
- `mode` — only relevant when `action` is `"on"`; default `"cool"` unless user says heat/warm
- `temp_c` — setpoint in Celsius; default `22.0` for cool, `20.0` for heat; infer from user if specified (e.g. "21 degrees" → `21.0`)

## Clarification Rules (required)
- If user intent is ambiguous (for example: "adjust AC", "fix the AC"), ask what they want (`on` or `off`) before acting.
- If user says `off` without room and does NOT clearly mean all rooms, ask which room.
- If user says `on` without room, room may default to `all` only when user intent clearly implies whole-home control; otherwise ask.
- If user asks to set temperature but gives no value, ask for target temperature.
- Never execute a write action when `action` is unclear.

Room name mapping:
- "bedroom" / "bed room" / "master bedroom" → `"bedroom"`
- "living room" / "lounge" / "downstairs" → `"living_room"`
- "basement" / "downstairs" → `"basement"`
- no room specified / "everywhere" / "all" → `"all"`

# Output Guidance

Write a short, friendly confirmation. Examples:
- "Done — bedroom AC is now on, cooling to **22°C**."
- "All AC units have been turned off."
- "Living room AC is on, set to heat at **20°C**."
- "Bedroom and living room AC are now off."

If the API returns an error, report it plainly: "Couldn't control the AC — [error message]."

# Failure Handling
- 401 Unauthorized → "AC control failed: invalid API key."
- 400 Bad Request → report the error message from the API
- Network error → "Could not reach the home system. Please try again."
