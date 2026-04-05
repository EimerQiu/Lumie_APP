---
skill_id: dayprint_followup
title: Dayprint Follow-up Assessment
capability_id: lumie_internal_data
runtime_type: lumie_db
requires_ping: true
requires_credentials: true
target_system: lumie_db
tags: [dayprint, followup, memory, advisor, concern, unresolved]
keywords: [dayprint, follow up, unresolved concern, advisor chat, important insight, health concern, medication concern, open question, issue mentioned, problem discussed]
summary: Scan recent dayprints to identify unresolved health/medication concerns and follow-up opportunities for proactive advisor outreach. Detects themes repeated across multiple days or marked as concerns by the user.
proactive_eligible: true
proactive_domain: dayprint
proactive_priority: 65
proactive_mode: assessment
allowed_connectors: [lumie_db_connector]
input_schema:
  type: object
  properties:
    days_back:
      type: integer
      description: "How many days back to scan (default 7)"
output_schema:
  type: object
  properties:
    summary:
      type: string
      description: "Natural language summary of unresolved concerns"
    concern_count:
      type: integer
      description: "Number of distinct concerns identified"
    top_concerns:
      type: array
      description: "List of recurring or notable themes"
    recommendation:
      type: string
      description: "Suggested action (follow up, monitor, escalate)"
---

# Purpose
Use this skill to evaluate recent dayprints and identify unresolved health concerns, medication issues, or open questions that deserve proactive follow-up from the advisor.

This skill helps the proactive advisor detect:
- Health concerns mentioned but not resolved across multiple days
- Medication or task adherence issues mentioned by the user
- Emotional or stress themes that recur
- Questions or topics left unanswered in previous advisor chats
- Patterns that suggest the user needs support or clarification

# When To Use (Proactive Mode)
- During proactive check cycles to find follow-up opportunities
- To identify themes that appear 2+ times in recent dayprints (strong signal)
- To detect user-reported concerns that haven't been addressed
- To prioritize which health domains need advisor attention

# Runtime Rules
- Query only the requesting user's `dayprints`
- Default to last 7 days if not specified
- Focus on `important_insight` and `advisor_chat` events
- Mark concerns as "recurring" if they appear on 2+ different days
- Classify concerns by category: health, medication, mood, social, other
- Return structured data suitable for LLM decision-making

# Collection Details
- `dayprints`: One document per day per user
  - `date`: ISO date string (YYYY-MM-DD)
  - `user_id`: The user whose dayprint it is
  - `events`: Array of daily events
    - `event_id`: UUID for this specific event
    - `type`: Event type — focus on "important_insight" events (automatically flagged by advisor when detecting concerns)
    - `timestamp`: ISO datetime (UTC)
    - `data`: Object containing event-specific fields

## Important Insight Events (Priority!)

**`important_insight` events** are automatically created when the advisor detects:
- New or worsening symptoms
- Medication concerns (side effect)
- Emotional distress or health anxiety
- Urgent health signals

**Fields in important_insight.data:**
- `category`: One of: `symptom`, `medication`, `emotional`, `health_concern`, `urgent`, `other`
- `summary`: Brief description (3rd person, includes user's name)
- `session_id`: Which advisor session detected this

**These are the "重点关注" (priority concern) markers!**
- Scan for `important_insight` events first
- Weight by category: urgent > health_concern > medication > symptom > emotional
- If same category appears on 2+ days → strong follow-up signal

# Execution Plan
1. Parse `days_back` parameter (default 7)
2. Compute date range: today minus `days_back` to today
3. Query `dayprints` collection for user_id in date range
4. Extract all events from `events` array
5. Filter for `important_insight` and `advisor_chat` event types
6. Build a concern map: group by category, track dates seen, check resolved flag
7. Identify "recurring" concerns (appear on 2+ dates)
8. Score each concern by: category + recurrence + days since last mention
9. Rank top 5 concerns by score
10. Generate summary and recommendation

# Query Examples

## Get last 7 days of dayprints
```python
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

local_tz = ZoneInfo(user_timezone)
today_local = datetime.now(local_tz).date()
days_back = 7

start_date = (today_local - timedelta(days=days_back)).isoformat()
end_date = today_local.isoformat()

dayprints = await db.dayprints.find({
    "user_id": target_user_id,
    "date": {"$gte": start_date, "$lte": end_date}
}).sort("date", -1).to_list(7)
```

## Extract and categorize important insights
```python
# Priority: scan for important_insight events first
important_insights = {}  # category -> [dates, summaries]

for dayprint in dayprints:
    date = dayprint.get("date")
    events = dayprint.get("events") or []
    
    for event in events:
        event_type = event.get("type")
        
        # PRIORITY: important_insight events are flagged concerns
        if event_type == "important_insight":
            data = event.get("data") or {}
            category = data.get("category", "other").lower()
            summary = data.get("summary", "").strip()
            
            if not summary:
                continue
            
            if category not in important_insights:
                important_insights[category] = {"dates": [], "summaries": []}
            
            important_insights[category]["dates"].append(date)
            important_insights[category]["summaries"].append(summary)

# Secondary: also scan advisor_chat events for other concerns (lower priority)
other_concerns = {}

for dayprint in dayprints:
    date = dayprint.get("date")
    events = dayprint.get("events") or []
    
    for event in events:
        event_type = event.get("type")
        
        if event_type == "advisor_chat":
            data = event.get("data") or {}
            category = data.get("category", "general").lower()
            summary = data.get("summary", "").strip()
            
            if not summary:
                continue
            
            # Skip if this category already covered by important_insights
            if category in important_insights:
                continue
            
            key = f"{category}:{summary[:50]}"
            if key not in other_concerns:
                other_concerns[key] = {"dates": [], "category": category}
            other_concerns[key]["dates"].append(date)
```

## Identify and categorize concerns
```python
# Identify concerns based on recurrence and freshness
unresolved_concerns = []

for key, info in concern_history.items():
    dates = sorted(set(info["dates"]), reverse=True)
    if not dates:
        continue
    
    days_ago = (today_local - datetime.fromisoformat(dates[0]).date()).days
    occurrences = len(dates)
    
    # Only include concerns that are recent (within last 10 days) OR recurring (2+ days)
    is_recurring = occurrences >= 2
    is_recent = days_ago <= 10
    
    if is_recurring or is_recent:
        unresolved_concerns.append({
            "key": key,
            "category": info["category"],
            "occurrences": occurrences,
            "last_seen": dates[0],
            "days_since_last": days_ago,
            "is_recurring": is_recurring,
            "is_recent": is_recent
        })

# Sort by: recurring first, then by recency
unresolved_concerns.sort(
    key=lambda x: (not x["is_recurring"], x["days_since_last"])
)
```

## Build response
```python
# PRIORITY: important_insight events are more significant than advisor_chat mentions
# Separate by recurrence, let LLM decide based on category and pattern

# Separate important_insights by recurrence (no scoring)
important_recurring = [
    {
        "category": cat,
        "occurrences": len(data["dates"]),
        "dates": sorted(set(data["dates"]), reverse=True),
        "latest_summary": data["summaries"][-1] if data["summaries"] else ""
    }
    for cat, data in important_insights.items()
    if len(set(data["dates"])) >= 2
]

important_recent = [
    {
        "category": cat,
        "date": sorted(set(data["dates"]), reverse=True)[0],
        "summary": data["summaries"][0] if data["summaries"] else ""
    }
    for cat, data in important_insights.items()
    if len(set(data["dates"])) == 1
]

# Sort by recurrence (not by weight) — let LLM judge importance
important_recurring.sort(key=lambda x: x["occurrences"], reverse=True)
important_recent.sort(key=lambda x: x["date"], reverse=True)

# Also include non-important concerns (lower priority)
other_recurring = [
    {
        "category": c["category"],
        "summary": c["key"].split(":")[-1],
        "occurrences": len(c["dates"])
    }
    for c in other_concerns.values()
    if len(set(c["dates"])) >= 2
]

_result = {
    "summary": (
        f"Found {len(important_recurring)} flagged recurring concerns (important_insight)"
        + (f" and {len(important_recent)} recent flagged concerns" if important_recent else "")
        + (f" plus {len(other_recurring)} other recurring patterns" if other_recurring else "")
    ),
    "important_insights_recurring": important_recurring[:5],
    "important_insights_recent": important_recent[:3],
    "other_concerns_recurring": other_recurring[:3],
    "has_priority_signal": len(important_recurring) > 0 or len(important_recent) > 0
}
```

# Proactive Decision Guidance

**Return data structure prioritizes `important_insight` events:**

LLM receives:
- `important_insights_recurring`: Flagged concerns appearing on 2+ days (HIGHEST PRIORITY)
- `important_insights_recent`: Flagged concerns from last 15 days (HIGH PRIORITY)
- `other_concerns_recurring`: Non-flagged patterns (lower priority)
- `has_priority_signal`: Boolean for quick check

**LLM should STRONGLY nudge if:**
- `important_insights_recurring` is non-empty → User flagged same concern appearing 2+ days
- Category is `medication`, `health_concern`, or `urgent` (high-priority categories)
- Multiple days show the pattern

**LLM should nudge if:**
- `important_insights_recent` has items → Advisor detected and flagged concern recently
- Category is health-related even if not recurring

**LLM should NOT nudge if:**
- `has_priority_signal` is false → No flagged concerns at all
- Last mention > 15 days old
- Only very low-weight categories

**Key context for LLM:**
- **`important_insight` events are pre-screened by the advisor — they've already been deemed significant**
- Category indicates concern type, not a score: urgent > health_concern > medication > symptom > emotional > other
- Recurring important_insights (2+ days) should be prioritized much higher than other_concerns
- LLM should combine with sleep/activity data for full context and make holistic decision

# Failure Handling
- If `dayprints` collection empty for range: return summary "No dayprint data available"
- If all events are resolved: return "No unresolved concerns"
- On DB error: return error message for retry
