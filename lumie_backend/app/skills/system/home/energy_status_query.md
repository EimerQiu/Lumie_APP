---
skill_id: energy_status_query
title: Home Energy Status
capability_id: home_energy_access
runtime_type: external_api
requires_ping: false
requires_credentials: true
target_system: energy_dashboard
api_endpoint: /api/energy-status
shared_credential_id: home_energy
credential_display_name: Home Energy
tags: [energy, solar, powerwall, tesla, home, electricity, battery, ac, temperature]
keywords: [energy, solar, powerwall, battery, charge, tesla, model y, home power, electricity, ac, air conditioning, grid, indoor temperature, energy status, how much solar, battery level, is ac on, is charging, house power, exporting, importing, power usage]
summary: Fetch real-time home energy status including solar generation, Powerwall battery level, home consumption, Tesla Model Y, AC unit, indoor temperatures, and grid import/export.
allowed_connectors: [external_api_connector]
proactive_eligible: true
proactive_domain: energy
proactive_priority: 55
proactive_mode: assessment
---

# Purpose
Use this skill when the user asks about home energy, solar production, Powerwall battery, Tesla car charging status, air conditioning, indoor temperatures, or grid usage.

# When To Use
- "What's the energy status at home?"
- "How much solar is being generated right now?"
- "What's the Powerwall battery level?"
- "Is the AC on?"
- "What's the indoor temperature?"
- "Is the Tesla charging?"
- "Are we importing or exporting to the grid?"
- "How much power is the house using?"
- "What's the home energy situation?"

# Required Inputs
None — the API provides real-time data automatically.

# Credential Setup
- `base_url`: `https://home.yumo.org`
- `password`: `10560` (API key — also used by the AC Control skill)

# Execution Plan
1. GET `{base_url}/api/energy-status`
2. Parse the JSON `elements` object
3. Summarize the key metrics for the user

# API Response Structure

The response has this shape:
```json
{
  "status": "ok",
  "timestamp": "...",
  "elements": {
    "solar":        { "label": "SOLAR",       "value": "3.2 kW",  "status": "Generating" },
    "home":         { "label": "HOME",        "value": "1.8 kW",  "status": "Using" },
    "model_y":      { "label": "Model Y",     "value": "88%",     "status": "272km  88%", "charging": "Idle" },
    "ac_unit":      { "label": "AC UNIT",     "value": "",        "status": "On" },
    "powerwall":    { "label": "POWERWALL·3x","value": "94.2%",   "status": "Charging" },
    "indoor_temp":  { "label": "INDOOR",      "value": "",        "status": "Living 22.1°\nBed 21.5°\nBase 19.0°" },
    "grid":         { "label": "GRID",        "value": "1.4 kW",  "status": "Exporting" },
    "dryer":        { "label": "DRYER",       "value": "N/A",     "status": "N/A" },
    "dishwasher":   { "label": "DISHWASHER",  "value": "N/A",     "status": "N/A" }
  }
}
```

Field notes:
- `solar.value` — current solar generation in kW; `status` is Generating or Idle
- `home.value` — home power consumption in kW (excludes car charging); `status` is Using or Idle
- `model_y.value` — battery % when parked, charging kW when plugged in; `model_y.status` shows range + battery; `model_y.charging` is Charging/Idle/Complete
- `ac_unit.status` — On, Off, or N/A
- `powerwall.value` — battery percentage (3 Powerwalls combined); `status` is Charging/Discharging/Idle/Full
- `indoor_temp.status` — multi-line string: "Living X.X°\nBed X.X°\nBase X.X°" (Celsius)
- `grid.status` — Exporting (sending to grid), Importing (drawing from grid), or Idle
- `dryer` and `dishwasher` — always N/A (not yet monitored)

# Output Guidance

Write a concise, friendly 2-4 sentence summary. Use **bold** for key numbers.

Examples:
- "Your Powerwall is at **94.2%** and charging from **3.2 kW** of solar. Home is consuming **1.8 kW** and you're exporting **1.4 kW** back to the grid. The Tesla Model Y is parked at 88% (**272 km** range). Indoor temps: Living **22.1°**, Bed **21.5°**, Basement **19.0°**."
- "Solar is generating **4.1 kW** right now. Powerwall is at **100%** (full, idle). Home is using **2.3 kW** and you're exporting **1.8 kW** to the grid. AC is off."
- "Powerwall is discharging at night — currently at **67.3%**. Home is using **1.2 kW**. No solar (nighttime). Tesla is charging at **7.2 kW**."

Rules:
- Skip items with N/A values (dryer, dishwasher) unless the user specifically asked
- If both solar and grid status are present, mention energy flow direction
- Show indoor temps as a brief list at the end if relevant or asked

# Failure Handling
- If HTTP request fails, tell the user the energy dashboard is temporarily unreachable
- If all values are N/A, note that real-time data may be temporarily unavailable
