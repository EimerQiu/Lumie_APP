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

# Concern & Signal Detection

Before writing the summary, flag these specific signals:

## ⚠️ Concerns to Highlight
- **Powerwall below 50%**: "Battery reserve is low" — may want to reduce usage or prioritize charging
- **AC temperature out of comfort range**: Beyond 24°C (too hot) OR below 20°C (too cold) — comfort issue
- **Tesla Model Y below 50%**: Charging status at risk; may need to plug in soon

## ✅ Good News to Highlight
- **Powerwall beyond 90%**: "Battery is well-charged" — good energy cushion
- **Solar beyond 10 kW**: "Strong solar generation" — excellent renewable production

## Detection Logic
```python
# Parse the API response and check these thresholds:

# Extract powerwall percentage from "94.2%" → 94
# Extract Tesla percentage from "88%" → 88
# Extract indoor temps from "Living 22.1°\nBed 21.5°\nBase 19.0°" → parse each

concerns = []
good_signals = []

# Powerwall checks
powerwall_pct = parse_percentage(elements["powerwall"].get("value"))
if powerwall_pct < 50:
    concerns.append("Powerwall below 50%")
elif powerwall_pct >= 90:
    good_signals.append("Powerwall well-charged (>90%)")

# AC temperature checks (if any room is out of range)
temps = parse_indoor_temps(elements["indoor_temp"].get("status"))  # [22.1, 21.5, 19.0, ...]
for room, temp in temps:
    if temp > 24 or temp < 20:
        concerns.append(f"AC temp {room} {temp}°C (out of comfort range)")

# Tesla checks
tesla_pct = parse_percentage(elements["model_y"].get("value"))
if tesla_pct < 50:
    concerns.append("Tesla Model Y below 50% charge")

# Solar checks
solar_kw = parse_kw(elements["solar"].get("value"))  # "3.2 kW" → 3.2
if solar_kw >= 10:
    good_signals.append("Strong solar generation (>10 kW)")
```

# Output Guidance

Write a concise, friendly 2-4 sentence summary. Use **bold** for key numbers.

**Prioritize concerns and good news in the summary:**
- Lead with any ⚠️ concerns if present
- Highlight ✅ good signals to balance the narrative
- Then provide overall energy status

Examples with signals:

**With Concerns:**
- "⚠️ **Powerwall is at 48%** (below 50% — may want to monitor charging). Solar is generating **3.2 kW** right now, so you're still charging. Home is using **1.8 kW**. ⚠️ **Living room temp is 25°C** — AC might need adjustment. Tesla is at **45%** charge."

**With Good News:**
- "✅ **Powerwall is at 94%** (well-charged) and **solar is producing 11.2 kW** (strong generation!). Home is using **1.8 kW** and you're exporting **9.4 kW** to the grid. AC is maintaining comfort. Tesla is parked at 88%."

**Balanced:**
- "Solar is generating **3.8 kW** right now. **Powerwall at 67%** (mid-range). Home is using **2.1 kW**. ⚠️ **Basement temp is 19°C** (on the cold side). Tesla is idle at **72%** charge."

Rules:
- Always highlight concerns first (user should know)
- Balance with good signals if present
- Skip N/A values (dryer, dishwasher) unless specifically asked
- If both solar and grid status are present, mention energy flow direction
- Show indoor temps as a brief list at the end if relevant or asked

# Proactive Mode Guidance

When this skill runs in **proactive mode** (advisor checking whether to send a nudge):

**Strong nudge signal (act on these):**
- Powerwall < 30% AND solar < 2 kW (low battery + no charging source)
- Tesla < 20% (critically low charge)
- Multiple rooms out of comfort range (AC malfunction or thermostat issue)

**Moderate nudge signal (monitor these):**
- Powerwall 30-50% (trending low)
- Tesla 20-50% (charging needed soon)
- One room consistently < 20°C or > 24°C (comfort issue)

**No nudge needed:**
- Powerwall > 70%
- All indoor temps 20-24°C
- Tesla > 50%
- Solar available and generating

Include the concern flags (`powerwall_pct`, `tesla_pct`, `temp_anomalies`) in the returned data for the decision model.

# Failure Handling
- If HTTP request fails, tell the user the energy dashboard is temporarily unreachable
- If all values are N/A, note that real-time data may be temporarily unavailable
