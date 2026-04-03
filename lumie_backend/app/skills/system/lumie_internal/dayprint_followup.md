---
skill_id: dayprint_followup
title: Dayprint Follow-up
capability_id: lumie_internal_data
runtime_type: lumie_db
requires_ping: true
requires_credentials: true
target_system: lumie_db
tags: [dayprint, followup, memory, advisor]
keywords: [dayprint, follow up, unresolved concern, advisor chat, important insight]
summary: Assess recent dayprint memory for unresolved concerns and follow-up opportunities.
proactive_eligible: true
proactive_domain: dayprint
proactive_priority: 65
proactive_mode: assessment
allowed_connectors: [lumie_db_connector]
input_schema:
  type: object
  properties:
    user_id:
      type: string
output_schema:
  type: object
  properties:
    summary:
      type: string
    concern_score:
      type: number
---

# Purpose
Use this skill to evaluate recent `dayprints` and identify whether there is a strong follow-up reason for proactive outreach.

# Runtime Rules
- Query only the requesting user's `dayprints`.
- Focus on recent unresolved health or medication concerns.
- Return concise structured signals suitable for proactive decision input.
