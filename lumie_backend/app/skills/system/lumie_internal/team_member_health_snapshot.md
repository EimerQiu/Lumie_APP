---
skill_id: team_member_health_snapshot
title: Team Member Health Snapshot
capability_id: lumie_internal_data
runtime_type: lumie_db
requires_ping: true
requires_credentials: true
target_system: lumie_db
tags: [team, member, health, parent, admin, snapshot]
keywords: [team member, my daughter, my son, my child, member health, team health, how is my kid]
summary: Quick health snapshot for a specific team member, accessible only by team admins/parents.
allowed_connectors: [lumie_db_connector]
input_schema:
  type: object
  properties:
    target_user_hint:
      type: string
    team_id:
      type: string
output_schema:
  type: object
  properties:
    summary:
      type: string
    member_profile:
      type: object
    recent_activity:
      type: object
    task_adherence:
      type: object
---

# Purpose
Use this skill when a parent or team admin asks about a specific team member's health. This is a lighter version of comprehensive_health_assessment, focused on a quick snapshot.

# When To Use
- Parent asks "how is my daughter doing?"
- Team admin checks on a specific member
- Quick health check for a team member

# Required Inputs
- target user hint (must resolve to a team member)
- team_id (may be inferred from context)

# Runtime Rules
- Use `lumie_db` runtime
- Requester MUST be a team admin of the target user's team
- The connector will verify admin relationship

# Connector Rules
- Allowed connector: `lumie_db_connector`
- Query from: `profiles`, `activities`, `tasks`, `team_members`
- Only access data within the team scope
- Task queries must include team_id filter

# Execution Plan
1. Verify requester is admin of the target user's team
2. Get target user's profile
3. Get recent activities (last 3 days)
4. Get today's task adherence
5. Return a concise snapshot

# Output Guidance
- Keep it brief and parent-friendly
- Highlight any concerns (missed medications, low activity)
- Include task completion rate for recent days

# Failure Handling
- Fail immediately if not a team admin
- Retry on query errors
