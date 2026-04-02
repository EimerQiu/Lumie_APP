# Proactive Advisor Workflow Design

## Purpose

This document defines the target system workflow for `proactive advisor`.

It focuses on:

- how proactive checks should be executed
- what parts of the current system can be reused
- what parts must be modified
- what new modules should be added

The intended direction is:

- skills produce structured domain results first
- proactive advisor aggregates those results
- the LLM performs only the final nudge decision

This replaces the current pattern where raw data and full skill text are packed together and interpreted in one final LLM call.

## Current Workflow Summary

The current proactive flow is implemented primarily in [proactive_advisor_service.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/proactive_advisor_service.py).

Current behavior:

1. Load user profile.
2. Load enabled capabilities.
3. Load the full markdown text of every skill under those capabilities.
4. Fetch raw internal data directly from MongoDB.
5. Fetch recent dayprint memory.
6. Load `last_nudge`.
7. Build one large prompt:
   - all loaded skill text
   - raw data text block
   - recent memory
   - last nudge context
8. Send the whole bundle to the configured LLM.
9. Use the returned JSON as the final proactive decision.

Problems with the current workflow:

- skills are treated as prompt text, not executable domain units
- the final LLM has to do data interpretation and decision making together
- irrelevant enabled skills can pollute the decision prompt
- there is no clean skill-level audit trail explaining why a nudge or no-nudge happened
- prompt size grows with enabled skills, not with decision relevance

## What "Raw Data" Means in the Current System

In the current implementation, "raw data" means data fetched directly inside [proactive_advisor_service.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/proactive_advisor_service.py), then converted into a plain text block.

It currently includes:

- `tasks`
  - overdue tasks
  - active tasks
  - upcoming tasks
- `sleep_sessions`
  - the most recent completed sleep session
- `activities`
  - recent activity records
- `daily_steps`
  - recent daily step summaries
- `hr_readings`
  - recent heart-rate points
- `hrv_readings`
  - recent HRV / fatigue points
- `temperature_readings`
  - recent temperature points
- `spo2_readings`
  - recent blood oxygen points
- `dayprints`
  - recent advisor memory / follow-up context

This is not raw Mongo JSON, but it is still only a thin text formatting layer. It is not a proper skill result.

Examples of what the current system produces:

- `Last sleep: 6h 25m...`
- `Daily steps in the last 3 days...`
- `HRV samples in the last 24 hours...`

Examples of what it does not produce:

- `sleep_assessment_result`
- `activity_assessment_result`
- `medication_adherence_result`
- `recovery_assessment_result`

## Target Workflow

The target workflow should be:

1. Trigger proactive run.
2. Initialize a run context.
3. Resolve user capabilities.
4. Select only proactive-relevant skills.
5. Execute each proactive skill independently.
6. Collect structured `skill_results`.
7. Evaluate deterministic guardrails.
8. If still needed, call the LLM with:
   - user profile
   - `skill_results`
   - `last_nudge`
   - compact decision policy
9. Save the final decision.
10. Deliver notification if required.
11. Persist audit records for the full run.

Core principle:

- skills interpret domain data
- orchestrator coordinates
- LLM decides final outreach

## End-State Architecture

### 1. Proactive Scheduler

Responsibility:

- trigger periodic proactive checks
- optionally allow manual internal triggering

Status:

- already exists conceptually through current internal/prod triggering
- no major architectural change required

Classification:

- `already exists`

### 2. Proactive Orchestrator

Responsibility:

- create run context
- load user profile
- load capability state
- select proactive skills
- execute assessment skills
- evaluate guardrails
- build final decision input
- call decision LLM
- persist final result
- trigger delivery

Current implementation:

- mostly handled inside [proactive_advisor_service.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/proactive_advisor_service.py)

Required change:

- keep this file as the orchestration entry point
- remove full-skill-text-driven prompting as the core mechanism
- move domain analysis into explicit skill execution

Classification:

- `already exists`
- `needs modification`

### 3. Capability Resolver

Responsibility:

- determine which capability classes are available for a user

Current implementation:

- [capability_service.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/capability_service.py)
- `get_user_enabled_capability_ids(user_id)`

Required change:

- capability resolution stays
- usage changes from "load all skills under capability" to "filter which proactive skills are allowed"

Classification:

- `already exists`
- `minor modification in usage only`

### 4. Skill Registry

Responsibility:

- parse skill markdown metadata
- index skills
- support proactive skill selection

Current implementation:

- [skill_registry_service.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/skill_registry_service.py)

Current limitation:

- registry knows capability membership
- registry does not know whether a skill is proactive-eligible
- registry does not know proactive domain / proactive role / proactive priority

Required additions to frontmatter parsing:

- `proactive_eligible: true|false`
- `proactive_domain: sleep|activity|medication|recovery|followup|decision`
- `proactive_priority: int`
- `proactive_mode: assessment|decision`

Required service changes:

- extend `SkillIndexItem`
- parse new proactive metadata
- add proactive retrieval helpers

Possible new methods:

- `get_proactive_skills()`
- `get_proactive_skills_by_domain()`
- `get_proactive_assessment_skills_for_capabilities(enabled_capabilities)`

Classification:

- `already exists`
- `needs modification`

### 5. Proactive Skill Selector

Responsibility:

- choose only the proactive-relevant skills for the current run

Inputs:

- enabled capabilities
- skill registry proactive metadata
- optional user role / condition / feature flags

Output:

- ordered list of skill ids to run

Recommended implementation:

- new file: [proactive_skill_selector.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/proactive_skill_selector.py)

Selection rules:

- only use `proactive_eligible = true`
- require compatible capability
- normally choose one assessment skill per domain
- optionally skip domains when no usable data source exists

Classification:

- `needs to be added`

### 6. Proactive Skill Runner

Responsibility:

- execute proactive assessment skills
- normalize output into a unified schema

Recommended implementation:

- new file: [proactive_skill_runner.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/proactive_skill_runner.py)

Inputs:

- `skill_id`
- `user_id`
- run context

Output:

- `ProactiveSkillResult`

Important rule:

- the runner should execute assessment skills
- it should not decide the final proactive nudge

Classification:

- `needs to be added`

### 7. Assessment Skills

Responsibility:

- each skill reads one domain and returns a structured assessment

Recommended location:

- [proactive_skills/](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/proactive_skills)

Recommended assessment modules:

- [sleep_assessment.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/proactive_skills/sleep_assessment.py)
- [activity_assessment.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/proactive_skills/activity_assessment.py)
- [medication_assessment.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/proactive_skills/medication_assessment.py)
- [recovery_assessment.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/proactive_skills/recovery_assessment.py)
- [dayprint_followup_assessment.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/proactive_skills/dayprint_followup_assessment.py)

Suggested responsibilities per module:

`sleep_assessment.py`

- query recent `sleep_sessions`
- determine whether recent sleep is present
- assess duration, quality, recent trend, recovery notes
- output structured sleep assessment

`activity_assessment.py`

- query `activities` and `daily_steps`
- determine whether there is true inactivity vs no activity records
- avoid false "no activity" if steps show movement
- output structured activity assessment

`medication_assessment.py`

- query `tasks`
- identify active medication windows
- identify recent missed medication windows
- derive adherence signals
- output structured medication assessment

`recovery_assessment.py`

- query `hr_readings`, `hrv_readings`, `temperature_readings`, `spo2_readings`
- assess whether there is a meaningful recovery or wellness concern
- output structured recovery assessment

`dayprint_followup_assessment.py`

- query `dayprints`
- determine whether there is a strong follow-up candidate from recent memory
- output structured follow-up assessment

Classification:

- `needs to be added`

### 8. Unified Result Schema

Responsibility:

- make all assessment outputs structurally consistent

Recommended location:

- [proactive.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/models/proactive.py)

Recommended objects:

- `ProactiveSkillResult`
- `ProactiveDecisionInput`
- `ProactiveDecisionResult`
- `ProactiveRunRecord`

Suggested shape for `ProactiveSkillResult`:

```json
{
  "skill_id": "proactive_sleep_assessment",
  "domain": "sleep",
  "status": "ok|concern|missing|insufficient_data",
  "summary": "Last sleep was 6h25m with quality 92.",
  "score": 0.18,
  "signals": [],
  "recommended_actions": [],
  "evidence": {
    "collections_used": ["sleep_sessions"],
    "record_counts": {"sleep_sessions": 1},
    "latest_timestamps": {"wake_time": "2026-04-01T06:59:01Z"}
  }
}
```

Classification:

- `needs to be added`

### 9. Guardrail Layer

Responsibility:

- apply deterministic decision rules before the LLM is called

Recommended location:

- [proactive_guardrails.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/proactive_guardrails.py)

Suggested guardrails:

- cooldown
  - do not re-nudge too soon
- no material change
  - if the domain evidence has not changed enough, do not re-nudge
- hard no-nudge
  - all domains are stable and no follow-up candidate exists
- hard nudge
  - severe medication adherence failure or multi-domain concern

Why this layer is needed:

- reduce unnecessary LLM calls
- improve determinism
- stop repeated nudges caused by similar inputs

Classification:

- `needs to be added`

### 10. Last Nudge Context

Responsibility:

- carry prior proactive decision state into current decision making

Current implementation:

- `advisor_checkins.last_nudge`
- stringified last-nudge context inside [proactive_advisor_service.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/proactive_advisor_service.py)

Limitations:

- no structured material-change comparison
- no decision hash / evidence hash
- no run-level history

Recommended extension:

- preserve current `last_nudge`
- add structured fields such as:
  - `last_decision`
  - `last_evidence_summary`
  - `last_decision_inputs_hash`
  - `cooldown_until`

Classification:

- `already exists`
- `needs modification`

### 11. LLM Decision Layer

Responsibility:

- decide whether to nudge
- generate final message if needed
- explain decision in a compact structured form

Current implementation:

- final `chat_completion(...)` call inside [proactive_advisor_service.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/proactive_advisor_service.py)

Current issue:

- it receives:
  - all skill markdown text
  - raw data block
  - last nudge context

Target behavior:

- it should receive:
  - `user_profile`
  - `last_nudge`
  - `skill_results`
  - `guardrail_summary`
  - a short proactive decision policy

Recommended output:

```json
{
  "should_nudge": false,
  "reason_code": "recent_nudge_no_material_change",
  "message": null,
  "primary_domain": "medication",
  "evidence_skills": [
    "proactive_medication_assessment",
    "proactive_sleep_assessment",
    "proactive_activity_assessment"
  ],
  "decision_summary": "Recent ring data is present and the last nudge was recent; no stronger concern has emerged.",
  "confidence": 0.91
}
```

Classification:

- `already exists`
- `needs modification`

### 12. Delivery Layer

Responsibility:

- save proactive message to chat history
- queue notification if needed
- update `advisor_checkins`

Current implementation:

- [chat_history_service.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/chat_history_service.py)
- [notification_service.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/notification_service.py)
- update logic already exists inside [proactive_advisor_service.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/proactive_advisor_service.py)

Recommended change:

- preserve this layer
- add stronger linkage to run-level audit records

Classification:

- `already exists`
- `minor modification`

### 13. Audit and Observability Layer

Responsibility:

- store structured records explaining each proactive run

Current implementation:

- journald logs
- `chat_messages`
- `notification_queue`
- `advisor_checkins`

Current limitation:

- no structured per-run record
- no stored skill-result breakdown
- no clean answer to "which domain caused the decision"

Recommended additions:

- new service: [proactive_audit_service.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/proactive_audit_service.py)
- new collections:
  - `proactive_runs`
  - `proactive_skill_results`
  - `proactive_decisions`

Suggested run record:

```json
{
  "run_id": "uuid",
  "user_id": "uuid",
  "started_at": "ISO",
  "finished_at": "ISO",
  "selected_skills": [],
  "guardrail_result": {},
  "decision_result": {},
  "delivery_result": {}
}
```

Classification:

- `needs to be added`

## File-Level Change Map

### Files that already exist and should remain central

- [proactive_advisor_service.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/proactive_advisor_service.py)
- [skill_registry_service.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/skill_registry_service.py)
- [capability_service.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/capability_service.py)
- [chat_history_service.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/chat_history_service.py)
- [notification_service.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/notification_service.py)
- [llm_client.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/llm_client.py)

### Files that already exist and need modification

- [proactive_advisor_service.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/proactive_advisor_service.py)
  - remove full-skill-text orchestration
  - orchestrate structured proactive skill execution
  - invoke guardrails
  - send compact structured decision input to LLM

- [skill_registry_service.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/skill_registry_service.py)
  - parse proactive metadata
  - expose proactive skill retrieval methods

- proactive-relevant skill markdown files under `lumie_backend/app/skills/system/...`
  - add proactive metadata to frontmatter
  - define clear assessment output contracts

### Files recommended to be added

- [proactive_skill_selector.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/proactive_skill_selector.py)
- [proactive_skill_runner.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/proactive_skill_runner.py)
- [proactive_guardrails.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/proactive_guardrails.py)
- [proactive_audit_service.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/proactive_audit_service.py)
- [proactive.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/models/proactive.py)
- proactive assessment modules under [proactive_skills/](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/proactive_skills)

## Recommended Migration Path

### Phase 1: Replace raw-data prompting with structured domain results

Scope:

- keep [proactive_advisor_service.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/proactive_advisor_service.py) as the entry point
- split current raw data fetching into domain-level assessment functions
- stop sending all skill markdown text into the final decision prompt
- build the final LLM input from structured `skill_results`

Why first:

- this removes the most serious architectural problem immediately

Status:

- `needs implementation`

### Phase 2: Add proactive metadata to skill registry and skill docs

Scope:

- extend [skill_registry_service.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/skill_registry_service.py)
- update proactive-relevant skill frontmatter

Why second:

- it enables clean selection logic and avoids hardcoding forever

Status:

- `needs implementation`

### Phase 3: Add guardrails and audit records

Scope:

- create [proactive_guardrails.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/proactive_guardrails.py)
- create [proactive_audit_service.py](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/proactive_audit_service.py)
- add structured collections

Why third:

- after the main flow is correct, observability and cooldown correctness become straightforward

Status:

- `needs implementation`

### Phase 4: Move to a fully explicit proactive skill runtime

Scope:

- make proactive assessment skills first-class executable units
- use selector + runner instead of service-local helper functions

Why fourth:

- this gives the cleanest long-term architecture

Status:

- `needs implementation`

## Final Design Principle

The correct long-term design is:

- domain skills first interpret the data
- proactive advisor then decides whether outreach is warranted

In other words:

- do not send full skill text plus raw data to the LLM as the primary workflow
- do execute proactive-relevant skills first
- do send structured skill outputs to the LLM for the final decision

This changes the system from a prompt-driven interpretation workflow into a skill-result-driven decision workflow.
