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
    - `type`: "important_insight", "advisor_chat", "mood_entry", etc.
    - `data`: Object containing event-specific fields
      - `category`: Health topic (sleep, activity, mood, medication, etc.)
      - `summary`: Natural language description of the event
      - `concern_flag`: Boolean (true if user marked as concern)
      - `resolved`: Boolean (true if concern was addressed)

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

## Extract and categorize concerns
```python
concerns_by_category = {}
concern_history = {}  # track dates mentioned

for dayprint in dayprints:
    date = dayprint.get("date")
    events = dayprint.get("events") or []
    
    for event in events:
        event_type = event.get("type")
        if event_type not in ("important_insight", "advisor_chat"):
            continue
        
        data = event.get("data") or {}
        category = data.get("category", "general").lower()
        summary = data.get("summary", "").strip()
        resolved = data.get("resolved", False)
        concern_flag = data.get("concern_flag", False)
        
        if not summary:
            continue
        
        # Only track unresolved or flagged concerns
        if not resolved or concern_flag:
            if category not in concerns_by_category:
                concerns_by_category[category] = []
            
            concerns_by_category[category].append({
                "date": date,
                "summary": summary,
                "resolved": resolved,
                "concern_flag": concern_flag
            })
            
            # Track recurrence
            key = f"{category}:{summary[:50]}"
            if key not in concern_history:
                concern_history[key] = {"dates": [], "category": category}
            concern_history[key]["dates"].append(date)
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
# Separate recurring vs recent concerns
recurring = [c for c in unresolved_concerns if c["is_recurring"]]
recent_only = [c for c in unresolved_concerns if not c["is_recurring"] and c["is_recent"]]

_result = {
    "summary": (
        f"Found {len(recurring)} recurring concerns and {len(recent_only)} recent concerns"
        if recurring and recent_only
        else f"Found {len(recurring)} recurring concerns"
        if recurring
        else f"Found {len(recent_only)} recent unresolved concerns"
        if recent_only
        else "No unresolved concerns"
    ),
    "recurring_concerns": [
        {
            "category": c["category"],
            "summary": c["key"].split(":")[-1],
            "occurrences": c["occurrences"],
            "last_seen": c["last_seen"],
            "days_since_last": c["days_since_last"]
        }
        for c in recurring[:5]
    ],
    "recent_concerns": [
        {
            "category": c["category"],
            "summary": c["key"].split(":")[-1],
            "days_since_last": c["days_since_last"]
        }
        for c in recent_only[:3]
    ],
    "has_follow_up_signal": len(recurring) > 0 or len(recent_only) > 0
}
```

# Proactive Decision Guidance

**Return data for LLM to decide. LLM should nudge if:**
- `recurring_concerns` list is non-empty (concern appeared 2+ days)
- `recent_concerns` list has health/medication categories
- `has_follow_up_signal` is true

**LLM should NOT nudge if:**
- Both `recurring_concerns` and `recent_concerns` are empty
- Last mention is > 10 days old
- All concerns already marked as resolved

**LLM decision context:**
- Recurring concerns are higher priority (user mentioned same issue multiple times)
- Recent-only concerns should be considered but with lower weight
- Category matters: health/medication > mood > social > other
- Let LLM combine this with other skill data to decide overall nudge

# Failure Handling
- If `dayprints` collection empty for range: return summary "No dayprint data available"
- If all events are resolved: return "No unresolved concerns"
- On DB error: return error message for retry
