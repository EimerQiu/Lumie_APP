---
skill_id: team_membership_query
title: Team Membership Query
capability_id: lumie_internal_data
runtime_type: lumie_db
requires_ping: true
requires_credentials: true
target_system: lumie_db
tags: [team, teams, membership, family, group, role, admin, member]
keywords: [which team I belong, what team am I in, my teams, team membership, what families am I in, am I in a team, which family group, my role in team, team role]
summary: Query which team(s) the user belongs to, including role and member status.
allowed_connectors: [lumie_db_connector]
input_schema:
  type: object
  properties:
    include_inactive:
      type: boolean
      description: "Whether to include non-member/inactive team memberships (default false)"
    team_name_hint:
      type: string
      description: "Optional team name filter. Matching must be case-insensitive using lowercase normalization."
output_schema:
  type: object
  properties:
    summary:
      type: string
    teams:
      type: array
      items:
        type: object
        properties:
          team_id:
            type: string
          team_name:
            type: string
          role:
            type: string
          status:
            type: string
---

# Purpose
Answer questions about which team(s) the user belongs to, with role and status.

# When To Use
- "Which team do I belong to?"
- "What teams am I in?"
- "Am I in a family team?"
- "What is my role in my team?"

# Runtime Rules
- Use `lumie_db` runtime
- `db`, `target_user_id` are pre-loaded — do NOT import

# Connector Rules
- Allowed connector: `lumie_db_connector`
- Query from: `team_members`, `teams`
- READ-ONLY only. Never insert/update/delete.

# Execution Plan

## Step 1: Read memberships
```python
include_inactive = bool(input_data.get("include_inactive", False))
membership_query = {"user_id": target_user_id}
if not include_inactive:
    membership_query["status"] = "member"

memberships = await db.team_members.find(membership_query).to_list(200)
```

## Step 2: Resolve team names
```python
team_ids = [m.get("team_id") for m in memberships if m.get("team_id")]
teams_by_id = {}
if team_ids:
    team_docs = await db.teams.find(
        {"team_id": {"$in": team_ids}},
        {"_id": 0, "team_id": 1, "team_name": 1}
    ).to_list(200)
    teams_by_id = {t.get("team_id"): t for t in team_docs}
```

## Step 3: Optional team-name filter (case-insensitive, lowercase)
```python
team_name_hint = (input_data.get("team_name_hint") or "").strip().lower()
```

## Step 4: Build result
```python
items = []
for m in memberships:
    tid = m.get("team_id")
    tdoc = teams_by_id.get(tid, {})
    team_name = (tdoc.get("team_name") or "Unknown Team")
    if team_name_hint:
        # Case-insensitive compare via lowercase normalization.
        if team_name.lower() != team_name_hint:
            continue
    items.append({
        "team_id": tid,
        "team_name": team_name,
        "role": m.get("role") or "member",
        "status": m.get("status") or "unknown",
    })
```

## Step 5: Summary
```python
if not items:
    if team_name_hint:
        summary = f"You are not currently a member of a team named '{team_name_hint}'."
    else:
        summary = "You are not currently an active member of any team."
else:
    names = [i["team_name"] for i in items]
    if len(names) == 1:
        summary = f"You belong to 1 team: {names[0]}."
    elif len(names) == 2:
        summary = f"You belong to 2 teams: {names[0]} and {names[1]}."
    else:
        summary = f"You belong to {len(names)} teams: " + ", ".join(names[:-1]) + f", and {names[-1]}."

_result = {
    "summary": summary,
    "teams": items,
}
```

# Failure Handling
- If permission is denied, fail immediately
- If team documents are missing, still return membership rows with `team_name="Unknown Team"`
