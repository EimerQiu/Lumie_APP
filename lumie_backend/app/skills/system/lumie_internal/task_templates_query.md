---
skill_id: task_templates_query
title: Query Task Templates
capability_id: lumie_internal_data
runtime_type: lumie_db
requires_ping: true
requires_credentials: true
target_system: lumie_db
tags: [tasks, templates, list, query, template, search, recurring]
keywords: [what templates, my templates, show templates, template list, find template, search template, task templates, template for, which templates, template named, do I have templates, any templates, all templates]
summary: List all saved task templates with full details (time windows, intervals, descriptions) or search for a specific template by keyword.
allowed_connectors: [lumie_db_connector]
input_schema:
  type: object
  properties:
    keyword:
      type: string
      description: "Optional keyword to search templates by name or description"
    scope:
      type: string
      enum: [all, recent]
      description: "all = show all templates, recent = show last 5 (default: all)"
output_schema:
  type: object
  properties:
    summary:
      type: string
      description: "Human-readable summary"
    templates:
      type: array
      items:
        type: object
        properties:
          id:
            type: string
          template_name:
            type: string
          template_type:
            type: string
          description:
            type: string
          time_windows:
            type: integer
          min_interval:
            type: integer
          created_at:
            type: string

---

# Purpose
Query and list the user's saved task templates. Show template details including name, type, time windows, and when it was created. Support searching by keyword to find specific templates.

# When To Use
- "What templates do I have?"
- "Show me my task templates"
- "Do I have a Phosphate template?"
- "Search for medicine templates"
- "List all my templates"
- "Tell me about my Daily Med template"

# Required Inputs
- Either no input (list all) or optional `keyword` to search

# Runtime Rules
- Use `lumie_db` runtime
- `db`, `target_user_id`, `datetime` are pre-loaded — do NOT import them
- Search is case-insensitive

# Connector Rules
- Allowed connector: `lumie_db_connector`
- Query from: `task_templates`

# Data Model

## Template document schema
```python
{
    "id": str,  # UUID
    "template_name": str,
    "template_type": str,  # "Medicine", "Study", "Exercise", etc.
    "description": str or None,
    "time_windows": int,  # Number of time windows
    "min_interval": int,  # Minimum interval in minutes between tasks
    "time_window_list": [
        {
            "id": str,
            "name": str,
            "open_time": "HH:MM",
            "close_time": "HH:MM",
            "is_next_day": bool,
        },
        ...
    ],
    "created_by": str,  # User ID
    "created_at": datetime,
    "updated_at": datetime,
}
```

# Execution Plan

## Step 1: Retrieve templates
```python
import re

keyword = input_data.get("keyword", "").strip()
scope = input_data.get("scope", "all")

if keyword:
    # Search: case-insensitive regex match on name or description
    pattern = re.compile(keyword, re.IGNORECASE)
    all_templates = await db.task_templates.find(
        {"created_by": target_user_id}
    ).to_list(500)
    templates = [
        t for t in all_templates
        if pattern.search(t.get("template_name", "") or "") 
           or pattern.search(t.get("description", "") or "")
    ]
    # Sort by recency
    templates = sorted(templates, key=lambda t: t.get("created_at"), reverse=True)
else:
    # List all templates, sorted by recency
    cursor = db.task_templates.find({"created_by": target_user_id}).sort("created_at", -1)
    templates = await cursor.to_list(500)

# Apply scope limit
if scope == "recent":
    templates = templates[:5]
```

## Step 2: Format for display
```python
def format_time_window(tw):
    """Format a time window for display."""
    open_t = tw.get("open_time", "08:00")
    close_t = tw.get("close_time", "09:00")
    next_day = " (next day)" if tw.get("is_next_day", False) else ""
    return f"{open_t}–{close_t}{next_day}"

template_list = []
for t in templates:
    time_windows = t.get("time_window_list", [])
    window_times = [format_time_window(tw) for tw in time_windows]
    
    template_list.append({
        "id": t.get("id"),
        "template_name": t.get("template_name", "Unnamed"),
        "template_type": t.get("template_type", "Unknown"),
        "description": t.get("description"),
        "time_windows": t.get("time_windows", 0),
        "time_window_details": window_times,
        "min_interval": t.get("min_interval", 0),
        "created_at": t.get("created_at").isoformat() if t.get("created_at") else None,
    })
```

## Step 3: Build summary with all template names in one sentence
```python
if not templates:
    if keyword:
        summary = f"No templates found matching '{keyword}'."
    else:
        summary = "You don't have any task templates yet."
else:
    count = len(templates)
    template_names = [t.get("template_name", "Unnamed") for t in template_list]
    
    # Format names as comma-separated list with "and" before last (no markdown)
    if count == 1:
        names_str = template_names[0]
    elif count == 2:
        names_str = f"{template_names[0]} and {template_names[1]}"
    else:
        # Join all but last with commas, then add "and" before last
        names_str = ", ".join(template_names[:-1])
        names_str += f", and {template_names[-1]}"
    
    # Build summary with all names in one sentence (no markdown)
    if keyword:
        summary = f"Found {count} template(s) matching '{keyword}': {names_str}."
    elif scope == "recent":
        summary = f"Your {count} most recent templates: {names_str}."
    else:
        summary = f"You have {count} task template(s): {names_str}."

_result = {
    "summary": summary,
    "templates": template_list,
}
```

# Output Format

For each template, show:
- **Name** — template_name
- **Type** — template_type (Medicine, Study, etc.)
- **Time windows** — count + details (e.g., "3 windows: 8:00–9:00, 12:00–1:00 PM, 6:00–7:00 PM")
- **Min interval** — if > 0 (in minutes)
- **Description** — if present
- **ID** — for use in task creation

Example outputs (plain text, no markdown):

**All templates:**
```
You have 5 task template(s): Daily Meds, Phosphate Schedule, Weekly Exercise, Study Sessions, and Sleep Tracking.
```

**Search results:**
```
Found 2 template(s) matching 'medicine': Daily Meds and Phosphate Schedule.
```

**Recent templates:**
```
Your 3 most recent templates: Study Sessions, Weekly Exercise, and Daily Meds.
```

The `templates` array also includes full details (type, time windows, intervals, descriptions, ID, created_at, etc.) for programmatic use if needed.

# Failure Handling
- Retry on DB connection errors
- Return empty list if no templates found (not an error)
- Fail immediately on invalid regex pattern (bad keyword)
