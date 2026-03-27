# Lumie Advisor Unified Capability + Skill System

System Design and Development Requirements Document

**Version**: v1.2  
**Date**: 2026-03-26  
**Status**: Draft for Implementation  
**Applies To**: `lumie_backend`, `lumie_activity_app`

---

## 1. Goal

Under the assumption that large-scale refactoring is allowed, upgrade Lumie Advisor from a “chat + analysis” system into a **unified capability + skill execution system**.

The goal is to model the kinds of digital operations a user could manually perform on a phone or computer as skills that Advisor can invoke.

The initial unified scope includes:

- Access to Lumie’s own data and files
- Email queries
- School portal queries
- Third-party health platform reads
- Browser-automation-based access

The unified execution path is:

- capability switch
- skill retrieval and selection
- Advisor orchestration
- AI code execution system
- runtime / connector execution

This design deliberately keeps things simple and prioritizes shipping.

For this phase, we explicitly accept the following product/security tradeoffs:

- We allow storing third-party usernames and passwords first
- We allow storing them in plain text or lightly wrapped form in the user’s credential record first
- The server is allowed to retrieve and use these credentials to execute skills
- Encryption, secret vaulting, and zero-plaintext handling can be added later
- All skills are stored as repository `.md` files in this phase; skills are not stored in MongoDB

---

## 2. Core Idea

When Advisor receives a user message, it makes two decisions:

- If Claude can answer directly and quickly, return a direct answer
- If it cannot answer directly, retrieve candidate skills first, then let Claude select one skill from those candidates

Once the system enters `skill execution`, it handles all of the following through one unified mechanism:

- Lumie’s own database and file access
- Email queries
- School portal queries
- Third-party health platform reads
- Browser automation
- File reads
- Future access to other account systems

Lumie’s own data access is no longer treated as a separate architecture. It is treated as a set of `runtime_type: lumie_db` skills:

- the skill states that it needs to call Lumie DB Connector
- the AI code execution system generates the script from the skill
- Lumie DB Connector performs the actual Lumie data access

---

## 3. Design Principles

### 3.1 Prefer Simplicity

- Do not build an overly abstract connector framework
- Do not build an overly generic plugin system
- Do not overdesign key/secret management for the first version
- Get the `capability + skill + execution` main path working first

### 3.2 Unified Execution

The following are all treated as skill-backed execution tasks:

- `Query Lumie’s own database`
- `Query Lumie files`
- `Create or update a single task/record in Lumie internal systems`
- `Read email`
- `Perform email-related actions within allowed scope`
- `Log into a school website to query schedule`
- `Log into a school website to query homework`
- `Submit or update a single allowed item inside a school website`
- `Read Oura data`
- `Read Apple Health data`
- `Read Inbody data`
- `Read CGM data`

### 3.3 Explicit Capability Gating

Every skill must be bound to a capability.

Examples:

- `capability:web_search`
- `capability:email_read`
- `capability:school_portal`
- `capability:lumie_internal_data`
- `capability:oura_read`

If a capability is not enabled, Advisor must not execute any skill bound to that capability.

### 3.4 Lumie Internal Access Credentials Also Go Through Skill Credentials

The user-specific `ping` is treated as a special credential used by Lumie internal skills.

- The user does not send the ping directly to the execution runtime
- The frontend does not expose the ping
- Only Advisor can read and forward the ping from skill credentials
- Lumie DB Connector must validate the ping

---

## 4. Core Terms

### 4.1 Capability

A capability is a feature switch that controls whether a category of skills can be used by Advisor.

Examples:

- `lumie_internal_data`
- `email_read`
- `browser_portal_access`
- `apple_health_read`
- `oura_read`

### 4.2 Skill

A skill is an executable template that tells the system:

- when to use it
- what inputs it needs
- what system it needs to access
- whether it uses a browser or a connector
- what output shape it should produce

In this phase, all skills are stored as repository `.md` files. At runtime, `skill_registry_service.py` scans the repository, extracts metadata, builds an index, retrieves candidate skills first, and loads full skill text only on demand.

### 4.3 AI Code Execution System

This is the upgraded form of the existing analysis execution system.

It is no longer only for data-analysis code. It is responsible for:

- generating execution scripts from skills
- calling browser runtime
- calling Lumie DB Connector
- receiving runtime errors and retrying with corrected scripts
- consolidating results

### 4.4 Browser Skill Runtime

This runtime is specifically responsible for browser automation.

Examples:

- opening a school website
- logging in
- clicking through navigation
- extracting schedule
- extracting homework

### 4.5 Lumie DB Connector

This is a **server-side process**, not the sandbox.

It has full access to Lumie’s own database and selected file-system resources, but it is not exposed directly to end users.

It is responsible for:

- validating ping
- validating the requested target user
- validating team admin / member access scope
- validating script safety
- executing scripts
- returning results or errors

---

## 5. Overall Architecture

```text
Flutter Advisor Screen
    │
    │ POST /api/v2/advisor/chat
    ▼
advisor_orchestrator.py
    │
    ├── Fast direct reply
    │
    └── Skill path
          │
          ├── capability_registry
          ├── user_capability_service
          ├── skill_registry
          ├── skill_index
          ├── skill_credential_service
          │
          ▼
      execution_service.py
          │
          ├── retrieve top-k skills
          ├── send skill summaries to LLM
          ├── load selected skill full content
          ├── generate execution script
          ├── run browser skill runtime
          ├── call Lumie DB Connector
          ├── call external connector adapters
          ├── retry on script error
          └── return structured result
                │
                └── advisor_orchestrator.py → user-facing answer
```

### 5.1 Backend Processes

This system can still be deployed as a single service initially, but it should be logically split into the following process roles:

- `lumie-api`
  - existing FastAPI process
  - public API entrypoint
  - contains the Advisor orchestrator

- `lumie-execution-worker`
  - new background execution worker
  - responsible for skill execution jobs
  - may initially live in the same codebase and later become a separate systemd process

- `lumie-browser-runtime`
  - new browser execution process
  - responsible for Playwright sessions

- `lumie-db-connector`
  - new Lumie internal data connector process
  - responsible for MongoDB and required file-system access

In the first version, `lumie-execution-worker`, `lumie-browser-runtime`, and `lumie-db-connector` may all live inside the `lumie-api` process as Python services. However, the code boundaries must still be clearly separated.

---

## 6. Main Request Handling Flow

### 6.1 General Flow

1. The user sends a message in Advisor.
2. `advisor_orchestrator.py` loads:
   - the current user profile
   - the user’s enabled capabilities
   - the repository skill index
   - current session history
3. The system retrieves top-k candidate skills from the user’s question.
4. Claude decides:
   - whether the message can be answered directly
   - or, if not, which one of the candidate skills should be used
5. Advisor checks whether the selected skill’s capability is enabled.
6. Advisor loads the selected skill’s full `.md` on demand.
7. If the skill requires ping or other credentials, `skill_credential_service` loads the corresponding credential for that user and skill.
8. Advisor creates an `execution_job`.
9. `execution_service.py` generates an execution script from the full skill and the user request.
10. The skill executes according to its `runtime_type`:
   - `lumie_db`
   - `browser`
   - `external_api`
   - `hybrid`
11. The runtime returns either a result or an error.
12. If execution fails in a retryable way, the execution system feeds the error back and retries with a corrected script.
13. On success, the execution system outputs a structured result.
14. Advisor converts that structured result into a user-facing reply.

### 6.3 User Closed-Loop Flow

To form a complete system, it is not enough to define what happens after a user asks something. The design must also cover:

- capability enablement
- skill indexing and availability
- credential entry
- execution launch
- in-progress visibility
- failure repair
- result review
- capability revocation
- credential update
- reindex after skill file updates

The full closed loop should work as follows.

#### Flow A: The User Enables a Capability for the First Time

1. The user enters Advisor Settings.
2. The user sees the list of capabilities.
3. The user enables a capability.
4. The system determines whether that capability still requires:
   - at least one matching skill
   - skill credentials (which may include ping)
5. If configuration is missing, the UI immediately guides the user to the next step.
6. Only after the required setup is complete does the capability enter `ready` state.

Meaning:

- a capability cannot be just `enabled/disabled`
- it also needs a `ready/not_ready` lifecycle

#### Flow B: System Skill Preparation Completes

1. On startup, the service scans repository `.md` skill files.
2. It extracts frontmatter metadata from each file.
3. It builds the skill index.
4. If a skill file is invalid, it is marked unavailable.
5. Advisor only uses skills that were successfully parsed and indexed.

Meaning:

- skills do not use CRUD lifecycle in this phase
- the skill lifecycle comes from repository files plus indexing
- startup scan and reindex behavior are mandatory

#### Flow C: The User Enters Credentials for a Skill for the First Time

1. The user selects a skill.
2. The user sees what that skill requires.
3. The user enters:
   - `base_url`
   - `username`
   - `password`
   - `notes`
4. The system saves the credential.
5. The system automatically performs a `connection test`.
6. On success, the credential becomes usable.
7. On failure, the UI must tell the user what step failed.

Meaning:

- saving credentials alone is not sufficient
- a “test connection / test skill” flow is mandatory

#### Flow D: The User Triggers Execution

1. The user asks something in chat.
2. Advisor decides that a skill is needed.
3. The system checks:
   - capability is enabled
   - capability is ready
   - the selected skill has been indexed and is available
   - required skill credentials exist
4. If any requirement is missing, no execution job is created. Instead, Advisor returns a clear guided reply.
5. Only when all requirements pass does the system create an execution job.

Meaning:

- Advisor must not “let the LLM freely guess any skill”
- the system must retrieve first, then let the LLM choose among candidates
- preflight validation must happen before execution

#### Flow E: User Perception During Execution

1. The frontend shows “working on it...”
2. The job status progresses through `pending → generating → running → retrying → success/failed`
3. For long-running tasks, the frontend should show the current stage.
4. On failure, the user should see whether it failed because:
   - the skill was not configured
   - login failed
   - permission was denied
   - the script still failed after retry

Meaning:

- the frontend cannot only poll `success/failed`
- it needs finer-grained status and error categories

#### Flow F: Result Review and Continued Use

1. When the job completes, the result is written to `execution_jobs`.
2. Advisor writes the resulting reply to chat history.
3. When the user later opens session history, they can see:
   - which skill was used
   - what result was returned
   - whether there were failures
4. If a skill remains broken, the system should guide the user to reconfigure credentials or wait for the skill file to be fixed.

Meaning:

- execution results cannot live only in memory
- they must integrate with chat history and session restore

#### Flow G: The User Revokes a Capability or Updates Configuration

1. The user disables a capability.
2. Skills under that capability can no longer be invoked by Advisor.
3. Existing credentials remain stored, but become unusable while the capability is disabled.
4. The user may also delete or retest credentials.

Meaning:

- capability state, skill-index state, and credential state must remain decoupled

### 6.4 Gap Analysis Based on the Current Codebase

Based on the current repository, the following parts are still missing for a full closed loop.

| Closed-Loop Step | Current State | Missing | Must Be Added |
| --- | --- | --- | --- |
| User enables a capability | No capability system exists | No capability data model, no toggle UI, no ready state | Add capability collections, services, routes, settings UI |
| Skill file preparation | Only fixed backend tools exist; no skill registry | No skill file convention, no skill scan, no index, no top-k retrieval | Add `app/skills/**/*.md`, `skill_registry_service.py`, skill index, skill tests |
| User stores third-party account info | No general credential storage | No credential collection, no credential UI, no update logic | Add `advisor_skill_credentials` and frontend credential screens |
| User configures Lumie internal access | No ping concept yet | No ping field in skill credentials, no generation/rotation logic, no UI guidance | Support `ping` in `advisor_skill_credentials` and add service/UI support |
| Preflight before execution | Current Advisor only handles `direct / analysis / create_task` | No capability checks, no skill retrieval, no skill availability checks, no credential readiness checks | Add retrieval + preflight pipeline in `advisor_orchestrator.py` |
| Long-running task execution | Only `analysis_jobs` exists | No unified `execution_jobs`, no multi-runtime routing | Replace single-purpose `analysis_jobs` with `execution_jobs` |
| Browser execution | No browser runtime exists | No Playwright process, no screenshots, no DOM traces | Add `browser_skill_runtime.py` |
| Unified Lumie internal access | Current analysis sandbox connects to Mongo directly | No dedicated Lumie DB Connector, permissions are scattered | Add `lumie_db_connector.py` and centralize permission enforcement |
| Permission closed loop | Some team permission logic exists, but is scattered across `task_service.py`, `advisor_service.py`, and `team_service.py` | No unified requester→target permission decision layer | Move Lumie permission decisions into DB Connector |
| Error repair during execution | Current analysis has retries, but only for analysis code | No browser-skill-specific error feedback, no connector-level error categories | Add runtime-specific retry logic in `execution_service.py` |
| User feedback during execution | Frontend only shows analysis spinner today | No multi-stage execution UI, no skill names, no error categories | Add job-state UI and error mapping |
| Reviewing past results | Chat history exists, but is not tied to skill-based execution metadata | No `skill_id`, `runtime_type`, `error_type`, etc. in history | Extend chat history metadata |
| Ongoing maintenance | No “test credential / inspect skill state / inspect reindex result” flow | No maintenance UI | Add Advisor Settings + Skill Detail screens |

### 6.5 What Can Be Reused from the Current Codebase

This refactor is not a greenfield rewrite. Several parts of the current project can be directly reused.

#### Reusable

- `lumie_backend/app/services/advisor_service.py`
  - the existing Claude routing approach can be reused
- `lumie_backend/app/services/analysis_service.py`
  - job lifecycle, polling, and retry patterns can be reused
- `lumie_backend/app/services/analysis_prompt_service.py`
  - prompt assembly patterns can be reused
- `lumie_backend/app/services/analysis_sandbox_service.py`
  - sandbox execution foundation can be reused
- `lumie_backend/app/services/chat_history_service.py`
  - session/history persistence can be reused
- `lumie_backend/app/services/team_service.py`
  - team/member/admin relationship data can be reused
- `lumie_backend/app/services/task_service.py`
  - team-admin decision logic can be used as a reference
- `lumie_activity_app/lib/features/advisor/screens/advisor_screen.dart`
  - unified chat entrypoint and job polling UI structure can be reused

#### Should Not Be Kept As-Is

- `analysis_jobs`
  - too narrow in meaning to support browser / external / hybrid execution
- `advisor_service.py` as the single orchestration owner
  - it will keep growing; orchestration should be split into orchestrator + registry + execution service
- sandbox directly connecting to Lumie Mongo
  - cannot support unified permission enforcement; DB Connector should take over
- allowing the LLM to see all skill full text directly
  - this does not scale to 1000+ skills; retrieve candidates first and load full text on demand

### 6.6 Missing Frontend Pages and Interactions

If only backend work is added, the system still will not form a real product loop. The following UI pieces are required:

- `Advisor Settings`
  - shows capability toggles
  - shows capability readiness

- `Skill List`
  - shows system skills
  - shows each skill’s current state

- `Skill Detail`
  - shows skill description, purpose, required fields, and skill file state

- `Credential Entry` sheet/screen
  - inputs `base_url`, `username`, `password`, `notes`
  - provides a test action

- `Execution Status` UI
  - shows which skill is currently running
  - shows current phase
  - shows failure reason

- `Repair Prompt` guidance
  - when credentials fail, selectors break, or permissions are denied, the UI should guide the user to fix it instead of only showing “failed”

### 6.7 Missing State Definitions

To make the system closed-loop and stable, the state machines must be explicitly defined.

#### Capability States

- `disabled`
- `enabled_not_ready`
- `ready`

#### Skill States

- `indexed`
- `invalid_frontmatter`
- `disabled_by_capability`
- `broken`

#### Credential States

- `missing`
- `saved_not_tested`
- `valid`
- `invalid`

#### Ping States

- `missing`
- `active`
- `rotated`
- `disabled`

#### Execution Job States

- `pending`
- `generating`
- `running`
- `retrying`
- `success`
- `failed`
- `cancelled`

If these states are not persisted and used consistently, frontend and backend will not coordinate reliably.

### 6.2 Lumie Internal Data Access Flow

Example user question:

“How has my daughter been doing recently?”

1. Advisor identifies a matching skill such as `Comprehensive Health Assessment`
2. The skill definition specifies that it needs:
   - sleep
   - activity
   - HRV
   - RHR
   - task / medication
3. The skill also states:
   - `runtime_type = lumie_db`
   - `requires_ping = true`
   - `capability = lumie_internal_data`
4. Advisor verifies that the user has enabled the capability
5. Advisor reads the request user’s ping from the corresponding skill credential
6. Advisor sends the following to `execution_service.py`:
   - original request
   - full skill content
   - ping
   - `requester_user_id = A`
   - target-user hints = B
7. The execution system generates a data-access script
8. The execution system calls `lumie_db_connector.py`
9. Lumie DB Connector:
   - validates A’s ping
   - identifies who the script is trying to access
   - decides whether A is allowed to access B’s data
   - limits data access using team/admin/data-sharing rules
   - executes the script
10. If the script fails, the connector returns an error
11. The execution system receives the error, corrects the script, and retries
12. The connector returns raw data
13. The execution system performs multi-source analysis over that data
14. Advisor returns a combined health assessment to user A

---

## 7. New System Module Design

## 7.1 Advisor Orchestrator

Suggested files:

- `lumie_backend/app/services/advisor_orchestrator.py`
- `lumie_backend/app/api/advisor_v2_routes.py`

Responsibilities:

- handle `/api/v2/advisor/chat`
- load user capabilities
- load available skills
- load required credentials
- perform Layer 1 tool/skill routing
- decide between direct reply and execution job
- return to the frontend:
  - direct
  - executing
  - completed
  - failed

### Inputs

- `user_id`
- `message`
- `history`
- `session_id`

### Outputs

- `type`
- `reply`
- `job_id`
- `skill_id`
- `status`

### `advisor_orchestrator.py` Execution Flow

The execution order inside `advisor_orchestrator.py` must be:

1. Load user base context
   - profile
   - currently enabled capabilities
   - session history

2. Retrieve top-k candidate skills from the skill index
   - only among currently enabled capabilities
   - default `top_k = 8`

3. Ask the LLM to route
   - either return a direct answer
   - or select one skill from the candidate set

4. If the result is a direct answer
   - immediately return `type=direct`
   - do not create an execution job

5. If a skill is selected
   - read that skill’s capability state
   - if the capability is disabled, return a guided response
   - if the capability is `enabled_not_ready`, continue checking what is missing

6. Load the selected skill’s full text on demand
   - only the selected skill is loaded

7. Load skill credentials using `(user_id, skill_id)`
   - if `requires_credentials = false`, empty credential is allowed
   - if `requires_credentials = true`, a credential with `status=valid` must exist
   - if the skill is a Lumie internal skill, `credential.ping` must be present

8. If any precondition fails
   - do not create an execution job
   - return guidance that tells the user to configure capability or credentials

9. If all preconditions pass
   - create an `execution_job`
   - store `skill_id / capability_id / runtime_type / prompt`

10. Start `execution_service` asynchronously
   - pass:
     - full skill text
     - selected skill index item
     - corresponding credential
     - session history

11. Immediately return to the frontend
   - `type=execution`
   - `job_id`
   - `skill_id`
   - `status=pending`

### Orchestrator Credential Decision Logic

1. Retrieve candidate skills first
2. Let the LLM select one skill from those candidates
3. Only after skill selection, load credentials for that selected skill
4. Do not preload all user credentials before a skill has been chosen
5. For Lumie internal skills:
   - `requires_credentials = true`
   - `credential.ping` must exist
6. For browser/email/external skills:
   - read only the fields required by that skill, such as `username`, `password`, or `base_url`
7. Credentials are runtime inputs only and must never be included in user-visible replies

## 7.2 Skill Registry

Suggested file:

- `lumie_backend/app/services/skill_registry_service.py`

Responsibilities:

- scan repository `.md` skill files
- parse frontmatter
- build the skill index
- retrieve top-k skills using keyword/tag/capability signals
- load full skill text on demand

### Retrieval Flow

1. On startup, scan `lumie_backend/app/skills/**/*.md`
2. Parse frontmatter from each skill file and extract:
   - `skill_id`
   - `title`
   - `capability_id`
   - `runtime_type`
   - `tags`
   - `keywords`
   - `summary`
3. Build the in-memory index
4. At request time, filter by capability and keyword relevance
5. Return top-k skill summaries to Advisor LLM
6. The LLM must choose only among those candidates
7. Once selected, load the full `.md` file for execution

Default:

- `top_k = 8`

This ensures:

- the system still scales when the number of skills becomes large
- the full text of all skills does not need to be placed in model context

### `skill_registry_service.py` Execution Flow

`skill_registry_service.py` must handle four phases:

1. Startup scan
   - scan `lumie_backend/app/skills/**/*.md`
   - identify all skill files

2. Frontmatter parsing
   - read frontmatter from each file
   - extract required fields:
     - `skill_id`
     - `title`
     - `capability_id`
     - `runtime_type`
     - `requires_ping`
     - `requires_credentials`
     - `target_system`
     - `summary`
   - mark the skill as `invalid_frontmatter` if required fields are missing or malformed

3. Index construction
   - build a primary mapping by `skill_id`
   - build capability-level mappings by `capability_id`
   - build inverted indexes from `title / summary / tags / keywords`
   - only skills with `status=indexed` may enter the usable index

4. Runtime retrieval
   - tokenize the user query
   - retrieve candidates by capability + keyword match
   - rank by keyword-hit count
   - return top-k summaries
   - load full skill text only after selection

### Index Structure

Use three layers:

1. `skills_by_id`
   - `skill_id -> SkillIndexItem`
   - used to locate metadata and file paths quickly

2. `skills_by_capability`
   - `capability_id -> set(skill_id)`
   - used for capability-level filtering

3. `inverted_index`
   - `term -> set(skill_id)`
   - used for keyword-based candidate retrieval

Recommended retrieval fields:

- `title`
- `summary`
- `tags`
- `keywords`
- tokenized user query terms

Recommended ranking signals:

- number of matched terms
- `keywords` should weigh more than `summary`
- enabled capabilities should rank first
- only `status == indexed` skills may enter the candidate set

## 7.3 Execution Service

Suggested file:

- `lumie_backend/app/services/execution_service.py`

Responsibilities:

- create execution jobs
- assemble execution prompts from skill + user request
- call the AI code execution system
- dispatch to different runtimes
- handle retries after script errors
- store stdout / stderr / results

## 7.4 Browser Skill Runtime

Suggested file:

- `lumie_backend/app/services/browser_skill_runtime.py`

Responsibilities:

- launch Playwright browser sessions
- read steps and selectors from the skill
- log into websites
- navigate through the site
- extract structured data
- return JSON results

## 7.5 Lumie DB Connector

Suggested file:

- `lumie_backend/app/services/lumie_db_connector.py`

Responsibilities:

- validate ping
- validate requester and target-user relationships
- enforce team permissions and data-sharing scope
- execute DB scripts
- read required Lumie files if needed
- apply output-size and field filtering

Notes:

- Lumie DB Connector is not itself a skill
- it is only invoked through skills
- Lumie internal data read/write operations should therefore be split into multiple skills, for example:
  - `comprehensive_health_assessment`
  - `today_tasks_and_medications`
  - `team_member_health_snapshot`
  - `update_internal_note`
- those skills should consistently declare:
  - `runtime_type: lumie_db`
  - `allowed_connectors: [lumie_db_connector]`
  - `requires_credentials: true` if internal access credentials are needed
  - and credentials may include `ping`

## 7.6 Skill Credential Service

Suggested file:

- `lumie_backend/app/services/skill_credential_service.py`

Responsibilities:

- read and save user credentials for a given skill
- support general credential fields:
  - `base_url`
  - `username`
  - `password`
  - `notes`
- support the special Lumie internal field:
  - `ping`
- only Advisor / execution system may read full credentials

---

## 8. Database Design

All of the following collections are added to `lumie_db`.

## 8.1 `advisor_capabilities`

Defines system-level capabilities.

```json
{
  "capability_id": "lumie_internal_data",
  "display_name": "Lumie Internal Data",
  "description": "Allow Advisor to access Lumie's own data and files for this user",
  "enabled": true,
  "created_at": "ISO datetime",
  "updated_at": "ISO datetime"
}
```

Recommended index:

```python
await db.advisor_capabilities.create_index("capability_id", unique=True)
```

## 8.2 `user_advisor_capabilities`

Stores which capabilities each user has enabled.

```json
{
  "user_id": "uuid",
  "capability_id": "email_read",
  "status": "disabled | enabled_not_ready | ready",
  "granted_at": "ISO datetime",
  "updated_at": "ISO datetime",
  "notes": "optional"
}
```

Recommended index:

```python
await db.user_advisor_capabilities.create_index([("user_id", 1), ("capability_id", 1)], unique=True)
```

## 8.3 Skill File-System Design

All skills are stored as repository files. Suggested directory layout:

```text
lumie_backend/app/skills/
  system/
    lumie_internal/
      comprehensive_health_assessment.md
      today_tasks_and_medications.md
    browser/
      school_schedule_query.md
      school_homework_query.md
    email/
      email_keyword_search.md
```

Each `.md` file must include structured frontmatter. Example:

```md
---
skill_id: comprehensive_health_assessment
title: Comprehensive Health Assessment
capability_id: lumie_internal_data
runtime_type: lumie_db
requires_ping: true
requires_credentials: true
target_system: lumie_db
tags: [health, sleep, activity, hrv, rhr, medication]
keywords: [health summary, daughter health, recent condition, comprehensive]
summary: Query sleep, activity, HRV, RHR, and medication/task adherence for a target user.
allowed_connectors: [lumie_db_connector]
input_schema:
  type: object
output_schema:
  type: object
---

# Skill
...
```

### Standard Skill `.md` Template Format

Each skill file must follow one standard template with two parts:

1. frontmatter
2. body sections

Suggested template:

```md
---
skill_id: unique_skill_id
title: Human Readable Title
capability_id: lumie_internal_data
runtime_type: lumie_db
requires_ping: true
requires_credentials: false
target_system: lumie_db
tags: [tag1, tag2]
keywords: [keyword1, keyword2]
summary: One short summary sentence for retrieval.
allowed_connectors: [lumie_db_connector]
input_schema:
  type: object
  properties:
    target_user_hint:
      type: string
    time_range:
      type: string
output_schema:
  type: object
  properties:
    summary:
      type: string
---

# Purpose
Explain what this skill solves and what kinds of user questions it should handle.

# When To Use
- Trigger condition 1
- Trigger condition 2

# Required Inputs
- Which fields must be extracted from the user’s request

# Runtime Rules
- Which runtime should be used
- Whether ping is required
- Whether credentials must be loaded first

# Connector Rules
- Which connectors are allowed
- What must not be accessed

# Execution Plan
1. First step
2. Second step
3. Third step

# Output Guidance
- Which fields must be returned
- How to shape the final structured JSON

# Failure Handling
- Which failures may be retried
- Which failures should fail immediately
```

### Required Frontmatter Fields

- `skill_id`
- `title`
- `capability_id`
- `runtime_type`
- `requires_ping`
- `requires_credentials`
- `target_system`
- `summary`
- `input_schema`
- `output_schema`

### Recommended Frontmatter Fields

- `tags`
- `keywords`
- `allowed_connectors`

### Recommended Body Sections

- `# Purpose`
- `# When To Use`
- `# Required Inputs`
- `# Runtime Rules`
- `# Connector Rules`
- `# Execution Plan`
- `# Output Guidance`
- `# Failure Handling`

Missing recommended body sections do not block indexing, but missing required frontmatter fields should place the skill into `invalid_frontmatter` state.

### Three Example Skill Files

#### Example 1: Lumie Internal Data Skill

File path:

```text
lumie_backend/app/skills/system/lumie_internal/comprehensive_health_assessment.md
```

```md
---
skill_id: comprehensive_health_assessment
title: Comprehensive Health Assessment
capability_id: lumie_internal_data
runtime_type: lumie_db
requires_ping: true
requires_credentials: true
target_system: lumie_db
tags: [health, sleep, activity, hrv, rhr, medication]
keywords: [health summary, recent condition, daughter health, overall health]
summary: Query sleep, activity, HRV, RHR, and medication/task adherence for the target user and produce a combined health assessment.
allowed_connectors: [lumie_db_connector]
input_schema:
  type: object
  properties:
    target_user_hint:
      type: string
    time_range:
      type: string
output_schema:
  type: object
  properties:
    summary:
      type: string
    sleep:
      type: object
    activity:
      type: object
    hrv_rhr:
      type: object
    medications:
      type: object
---

# Purpose
Use this skill when the user asks for an overall health view that spans multiple Lumie data domains.

# When To Use
- The user asks how they or their child have been doing recently.
- The question requires combining sleep, activity, HRV, RHR, and medication/task adherence.

# Required Inputs
- target user hint
- requested time range

# Runtime Rules
- Use `lumie_db` runtime.
- Must include the requester’s ping from this skill’s credential record.
- All target-user access must be validated by `lumie_db_connector`.

# Connector Rules
- Allowed connector: `lumie_db_connector`
- Do not access unrestricted files directly from sandbox code.

# Execution Plan
1. Resolve target user from question context.
2. Query sleep, activity, HRV/RHR, and task/medication adherence.
3. Normalize all returned data.
4. Generate a combined assessment with trends and noteworthy issues.

# Output Guidance
- Return structured sections for sleep, activity, hrv_rhr, medications, and summary.

# Failure Handling
- Retry if the DB script fails due to field mismatch or query error.
- Fail immediately on permission denied or invalid ping.
```

#### Example 2: Browser School Portal Skill

File path:

```text
lumie_backend/app/skills/system/browser/school_homework_query.md
```

```md
---
skill_id: school_homework_query
title: School Homework Query
capability_id: school_portal
runtime_type: browser
requires_ping: false
requires_credentials: true
target_system: school_portal
tags: [school, homework, assignments, portal]
keywords: [homework, assignment, due date, school portal, classwork]
summary: Log into the user's school portal and retrieve homework or assignments due soon.
allowed_connectors: [browser_skill_runtime]
input_schema:
  type: object
  properties:
    time_range:
      type: string
output_schema:
  type: object
  properties:
    summary:
      type: string
    assignments:
      type: array
---

# Purpose
Use this skill when the user asks about homework, assignments, or due dates from their school portal.

# When To Use
- The user asks what homework is due.
- The user asks whether they have assignments today or this week.

# Required Inputs
- requested time range

# Runtime Rules
- Use `browser` runtime.
- Requires stored credentials for this skill.

# Connector Rules
- Use Playwright browser session.
- The runtime should log in with saved username/password and follow the selectors defined for this portal.

# Execution Plan
1. Load credential and `base_url`.
2. Open login page.
3. Log in.
4. Navigate to the homework/assignments section.
5. Extract assignment title, course, due date, and status.

# Output Guidance
- Return `assignments` as a list of structured objects.
- Provide a concise user-facing summary.

# Failure Handling
- Retry if selectors are missing or navigation fails.
- Mark the credential invalid if login is rejected by the site.
```

#### Example 3: Email Keyword Search Skill

File path:

```text
lumie_backend/app/skills/system/email/email_keyword_search.md
```

```md
---
skill_id: email_keyword_search
title: Email Keyword Search
capability_id: email_read
runtime_type: external_api
requires_ping: false
requires_credentials: true
target_system: email
tags: [email, inbox, search, message]
keywords: [email, inbox, unread, keyword, school email, reminder email]
summary: Search the user's email inbox for messages matching a keyword or topic and summarize the relevant results.
allowed_connectors: [email_connector]
input_schema:
  type: object
  properties:
    keyword:
      type: string
    time_range:
      type: string
output_schema:
  type: object
  properties:
    summary:
      type: string
    messages:
      type: array
---

# Purpose
Use this skill when the user asks the advisor to check their email for a topic, sender, or recent message.

# When To Use
- The user asks whether they received an email about something.
- The user asks Advisor to search the inbox.

# Required Inputs
- keyword or topic
- optional time range

# Runtime Rules
- Use `external_api` runtime.
- Requires stored credentials or an authorized email connection.

# Connector Rules
- Use the email connector only.
- Return matched messages in structured form.

# Execution Plan
1. Search the inbox using the keyword and optional time constraint.
2. Fetch a small list of relevant messages.
3. Summarize the matching results.

# Output Guidance
- Return sender, subject, date, and short preview for each message.
- Provide a concise summary first.

# Failure Handling
- Retry on transient connector failures.
- Fail directly if credentials are missing or revoked.
```

Runtime behavior:

- skill full text is not stored in Mongo
- the system scans files at startup
- parses frontmatter
- builds an in-memory index
- only loads the full selected skill at execution time

## 8.4 `advisor_skill_index_cache`

Optional cache collection for storing scanned skill metadata and index state.

```json
{
  "skill_id": "comprehensive_health_assessment",
  "path": "lumie_backend/app/skills/system/lumie_internal/comprehensive_health_assessment.md",
  "title": "Comprehensive Health Assessment",
  "capability_id": "lumie_internal_data",
  "runtime_type": "lumie_db",
  "requires_ping": true,
  "requires_credentials": false,
  "target_system": "lumie_db",
  "tags": ["health", "sleep", "activity"],
  "keywords": ["health summary", "recent condition"],
  "summary": "Query sleep, activity, HRV, RHR, and medication/task adherence for a target user.",
  "status": "indexed | invalid_frontmatter | broken",
  "last_scanned_at": "ISO datetime",
  "last_error": null
}
```

Recommended indexes:

```python
await db.advisor_skill_index_cache.create_index("skill_id", unique=True)
await db.advisor_skill_index_cache.create_index([("capability_id", 1), ("status", 1)])
```

## 8.5 `advisor_skill_credentials`

Stores user credentials for a given skill.

In this phase, plain-text storage is allowed.

```json
{
  "credential_id": "uuid",
  "user_id": "uuid",
  "skill_id": "uuid",
  "status": "missing | saved_not_tested | valid | invalid",
  "system_name": "School Portal",
  "base_url": "https://portal.example.edu",
  "username": "student_123",
  "password": "plain-text-for-now",
  "ping": null,
  "notes": "登录后点 Academics > Homework",
  "created_at": "ISO datetime",
  "updated_at": "ISO datetime"
}
```

Notes:

- For browser / email / external skills, the main fields are:
  - `base_url`
  - `username`
  - `password`
  - `notes`
- For Lumie internal skills, the main field is:
  - `ping`
- Unused fields may remain null depending on skill type
- `skill_id` is the primary binding key for credentials

For Lumie internal skills, a credential record may look like:

```json
{
  "credential_id": "uuid",
  "user_id": "user_a",
  "skill_id": "comprehensive_health_assessment",
  "status": "valid",
  "system_name": "Lumie Internal Access",
  "base_url": null,
  "username": null,
  "password": null,
  "ping": "A1B2C3D4",
  "notes": "internal-only",
  "created_at": "ISO datetime",
  "updated_at": "ISO datetime"
}
```

Recommended index:

```python
await db.advisor_skill_credentials.create_index([("user_id", 1), ("skill_id", 1)], unique=True)
```

### `advisor_skill_credentials` Field Specification

This collection stores all secret / credential information a user provides for a given skill.

Recommended field definitions:

| Field | Type | Description |
| --- | --- | --- |
| `credential_id` | string | unique ID |
| `user_id` | string | credential owner |
| `skill_id` | string | bound skill ID |
| `status` | string | `missing | saved_not_tested | valid | invalid` |
| `system_name` | string | human-readable display name |
| `base_url` | string \| null | site entry URL |
| `username` | string \| null | login username |
| `password` | string \| null | login password; plain text is allowed in phase 1 |
| `ping` | string \| null | internal access token for Lumie internal skills |
| `notes` | string \| null | user-provided notes, e.g. “after login, click Academics > Homework” |
| `last_tested_at` | string \| null | last credential test time |
| `last_test_result` | string \| null | summary of the last test result |
| `created_at` | string | created time |
| `updated_at` | string | updated time |

### Example Credentials by Skill Type

#### Example A: Browser School Portal

```json
{
  "credential_id": "cred_school_hw_user_a",
  "user_id": "user_a",
  "skill_id": "school_homework_query",
  "status": "valid",
  "system_name": "School Portal",
  "base_url": "https://portal.example.edu",
  "username": "alice_2026",
  "password": "plain-text-for-now",
  "ping": null,
  "notes": "Login first, then go to Academics > Homework",
  "last_tested_at": "2026-03-26T18:20:00Z",
  "last_test_result": "login_ok",
  "created_at": "2026-03-26T18:00:00Z",
  "updated_at": "2026-03-26T18:20:00Z"
}
```

#### Example B: Lumie Internal Data Skill

```json
{
  "credential_id": "cred_lumie_health_user_a",
  "user_id": "user_a",
  "skill_id": "comprehensive_health_assessment",
  "status": "valid",
  "system_name": "Lumie Internal Access",
  "base_url": null,
  "username": null,
  "password": null,
  "ping": "A1B2C3D4",
  "notes": "internal access only",
  "last_tested_at": "2026-03-26T18:25:00Z",
  "last_test_result": "ping_ok",
  "created_at": "2026-03-26T18:00:00Z",
  "updated_at": "2026-03-26T18:25:00Z"
}
```

#### Example C: Email Read Skill

```json
{
  "credential_id": "cred_email_user_a",
  "user_id": "user_a",
  "skill_id": "email_keyword_search",
  "status": "valid",
  "system_name": "Email Access",
  "base_url": "gmail",
  "username": "alice@example.com",
  "password": "plain-text-for-now-or-app-password",
  "ping": null,
  "notes": "personal inbox",
  "last_tested_at": "2026-03-26T18:30:00Z",
  "last_test_result": "connector_ok",
  "created_at": "2026-03-26T18:00:00Z",
  "updated_at": "2026-03-26T18:30:00Z"
}
```

### Credential Read Rules

Credential access follows these rules at runtime:

1. Determine the final selected `skill_id`
2. Query `advisor_skill_credentials` by `(user_id, skill_id)`
3. If the skill:
   - has `requires_credentials = false`, allow execution without a credential record
   - has `requires_credentials = true`, require a credential record with `status = valid`
4. If the skill is a Lumie internal skill, `ping` must exist
5. Only expose the minimum necessary fields to the target runtime. Never write full credentials into logs, chat history, stdout, or stderr

## 8.6 `execution_jobs`

Unified execution job records, intended to replace the narrow meaning of `analysis_jobs`.

```json
{
  "job_id": "uuid",
  "user_id": "requesting user",
  "session_id": "chat session id",
  "skill_id": "uuid",
  "capability_id": "lumie_internal_data",
  "runtime_type": "lumie_db | browser | external_api | hybrid",
  "prompt": "original user message",
  "normalized_request": {},
  "status": "pending | generating | running | retrying | success | failed | cancelled",
  "generated_script": "python/js text",
  "retry_count": 0,
  "max_retries": 2,
  "stdout": "",
  "stderr": "",
  "error": "",
  "result": {},
  "created_at": "ISO datetime",
  "started_at": "ISO datetime",
  "finished_at": "ISO datetime"
}
```

Recommended indexes:

```python
await db.execution_jobs.create_index("job_id", unique=True)
await db.execution_jobs.create_index([("user_id", 1), ("created_at", -1)])
await db.execution_jobs.create_index("status")
```

## 8.7 `execution_audit_logs`

Audit logs.

```json
{
  "log_id": "uuid",
  "job_id": "uuid",
  "user_id": "uuid",
  "skill_id": "uuid",
  "capability_id": "lumie_internal_data",
  "runtime_type": "lumie_db",
  "request_summary": "access daughter health summary",
  "target_user_id": "uuid",
  "decision": "allowed | denied",
  "reason": "team admin access allowed",
  "created_at": "ISO datetime"
}
```

---

## 9. Lumie DB Connector Design

## 9.1 Why It Must Exist as a Separate Module

Lumie DB Connector is where Lumie-specific business rules should live:

- whether a team admin may access a member’s data
- which collections are sensitive
- which fields may be returned to Advisor
- which writes are allowed

These rules must not be delegated to sandbox code.

Phase-1 hard rules:

- `lumie_db_connector` uses **in-process service calls**
- it does not use HTTP or separate RPC in phase 1
- its input is a **Python query script**
- the connector is responsible for identifying from the script:
  - `request_user_id`
  - `target_user_id`
  - accessed collections
  - operation types

## 9.2 Invocation Mode

Phase 1 is fixed as:

- `execution_service.py` directly calls `lumie_db_connector.py` inside the `lumie-api` process
- the connector does not expose a public API
- it exists only as an internal service used by the execution system

Why:

- lower deployment complexity
- lower internal-protocol design cost
- faster implementation of the permission + script execution chain

## 9.2 Input

Suggested internal request structure:

```json
{
  "request_user_id": "A",
  "ping": "user-A-ping",
  "skill_id": "skill-uuid",
  "job_id": "job-uuid",
  "script": "generated script text",
  "history_context": {},
  "request_summary": "health summary for daughter",
  "expected_output_schema": {}
}
```

Notes:

- phase 1 does not depend on a declared `target_user_id`
- phase 1 also does not depend on an explicit `mode`
- the connector identifies `request_user`, `target_user`, collections, and operation types directly from the script

## 9.3 Script Format

The phase-1 script format is fixed as:

- Python query scripts

However, this does **not** mean arbitrary Python. The script must comply with these constraints:

- it may only be used for connector-allowed Lumie data operations
- deletion is not allowed
- batch modification is not allowed
- reads are allowed
- constrained single-record create/update is allowed
- all task queries and task creates must be constrained by `team_id`

Script source:

- the script is generated by `execution_service.py` from:
  - full skill text
  - user request
  - history
  - credentials

The connector does not generate the script. It is responsible for:

- parsing the script
- validating the script
- executing the script
- rejecting non-compliant scripts

## 9.4 Execution Flow

The execution order inside `lumie_db_connector.py` must be:

1. Receive the internal call from the execution system
2. Validate `request_user_id`
3. Validate `ping`
   - ping must come from the selected skill’s credential
   - ping must belong to `request_user_id`
4. Parse the Python script and identify:
   - request user
   - target user
   - accessed collections
   - whether any write is attempted
5. If the script cannot clearly identify the target user, fail immediately
6. Check whether `request_user_id == target_user_id`
7. If not equal, check whether:
   - the request user is the target user’s team admin
8. Enforce write rules:
   - Rule 1: deletion is forbidden
   - Rule 2: batch modification is forbidden
   - Rule 3: if `request_user != target_user`, then `request_user` must be the target user’s team admin
   - Rule 4: for task queries or task creates, even if the request user is a team admin, only tasks with the matching `team_id` may be queried or created
9. Check whether the script touches forbidden sensitive fields
10. Build a restricted execution context
11. Execute the script
12. Apply field filtering to the result
13. Write audit logs
14. Return either a structured result or a structured error

## 9.5 Phase-1 Write Rules

Phase 1 does not expose separate read-mode and write-mode interfaces. However, writes must remain heavily constrained.

Allowed:

- read Lumie data
- perform constrained single-record create/update on allowlisted collections

Forbidden:

- any deletion
- any batch modification
- writing someone else’s data without team-admin permission
- querying or writing team tasks without the correct `team_id`

For `tasks` specifically:

- if `request_user_id != target_user_id`
- and the request user is a team admin of the target user
- then task queries or task creates must still include the correct `team_id`
- tasks outside that team must not be accessed or written

## 9.6 Return Format

Success:

```json
{
  "success": true,
  "data": {},
  "stdout": "",
  "stderr": "",
  "error": null,
  "target_user_id": "B",
  "collections": ["sleep_sessions", "activities", "tasks"]
}
```

Failure:

```json
{
  "success": false,
  "error_type": "permission_denied | ping_invalid | script_parse_error | script_execute_error | invalid_collection | unsafe_write",
  "error_stage": "ping_validation | permission_check | script_parse | script_execute | result_filter",
  "retryable": false,
  "error": "detailed message",
  "stdout": "",
  "stderr": "traceback text"
}
```

Error return rules:

- `ping_invalid`
  - `retryable = false`
- `permission_denied`
  - `retryable = false`
- `invalid_collection`
  - `retryable = false`
- `unsafe_write`
  - `retryable = false`
- `script_parse_error`
  - `retryable = true`
- `script_execute_error`
  - `retryable = true`

The execution system must use:

- `error_type`
- `error_stage`
- `retryable`

to decide whether to:

- fail immediately and return to Advisor
- or feed the error back and retry with a corrected script

## 9.7 Lumie DB Connector Accessible Scope

Accessible collections:

- `users`
- `profiles`
- `activities`
- `walk_tests`
- `tasks`
- `task_templates`
- `teams`
- `team_members`
- `sleep_sessions` or the actual sleep collection used in production
- `analysis_jobs` / `execution_jobs`
- required Lumie internal files when explicitly allowed

Field filtering must happen before returning results.

Examples of fields that must not be returned directly:

- `hashed_password`
- `verification_token`
- `device_token`
- unnecessary internal `_id`

---

## 10. Browser Skill Runtime Design

## 10.1 Technical Choice

Recommended:

- Playwright Python

Suggested file:

- `lumie_backend/app/services/browser_skill_runtime.py`

## 10.2 Required Skill Definition Content

A browser skill must include at least:

- `base_url`
- `login_url`
- `username_selector`
- `password_selector`
- `submit_selector`
- `post_login_wait_selector`
- `navigation_steps`
- `extraction_selectors`

## 10.3 Execution Flow

1. Load the skill definition
2. Load the user’s credential for that skill
3. Open the browser
4. Log in
5. Execute the navigation steps
6. Extract page content
7. Return structured JSON

## 10.4 Error Recovery

When browser execution fails, the runtime must return the following to the execution system:

- current URL
- screenshot path
- failed step
- DOM summary
- error text

The execution system may then regenerate and retry a corrected script.

---

## 11. AI Code Execution System Upgrade Requirements

The current `analysis_service.py`, `analysis_prompt_service.py`, and `analysis_sandbox_service.py` need to be refactored into a more general execution system.

Suggested new files:

- `lumie_backend/app/services/execution_service.py`
- `lumie_backend/app/services/execution_prompt_service.py`
- `lumie_backend/app/services/execution_runtime_router.py`
- `lumie_backend/app/services/execution_security_service.py`

### 11.1 New Responsibilities

- handle all skill execution
- no longer be analysis-only
- support multiple runtimes
- support retry after script correction

### 11.2 Runtime Routing

Choose execution location based on a skill’s `runtime_type`:

- `lumie_db`
  - call `lumie_db_connector.py`

- `browser`
  - call `browser_skill_runtime.py`

- `external_api`
  - call the matching adapter

- `hybrid`
  - combine browser + lumie_db or multiple stages as needed

### 11.3 Script Generation

The execution prompt must include:

- the original user request
- the full skill definition
- capability name
- runtime constraints
- target output schema
- allowed connector names
- if the skill needs Lumie internal access, `ping` from that skill’s credential may be supplied and may only be used with the designated connector

### 11.4 Automatic Retry

When the runtime returns one of the following:

- `script_error`
- `selector_not_found`
- `target_not_found`
- `missing_field`

the execution system must feed that error back to the LLM and ask for a corrected script.

Default:

- `max_retries = 2`

---

## 12. Permission Model

## 12.1 External Permission

Users grant permission through capability switches.

## 12.2 Internal Permission

Lumie DB Connector makes the final decision.

For Lumie’s own data:

- your own data: allowed by default
- parent/admin accessing a member: evaluated by team rules
- no team relationship: denied

## 12.3 Ping Rules

- ping exists as a special credential field inside `advisor_skill_credentials` for some Lumie internal skills
- ping must not be exposed in plain text through the frontend
- ping must not be written into chat history
- ping only flows through the internal chain: Advisor → execution system → Lumie DB Connector

---

## 13. API Design

## 13.1 Advisor Chat

New endpoint:

```http
POST /api/v2/advisor/chat
```

Request:

```json
{
  "message": "How has my daughter been doing recently?",
  "history": [],
  "session_id": "uuid"
}
```

Response — direct:

```json
{
  "type": "direct",
  "reply": "..."
}
```

Response — executing:

```json
{
  "type": "execution",
  "reply": "I’m checking that now.",
  "job_id": "uuid",
  "skill_id": "uuid"
}
```

## 13.2 Execution Job Status

```http
GET /api/v2/advisor/jobs/{job_id}
```

Response:

```json
{
  "job_id": "uuid",
  "status": "pending | generating | running | retrying | success | failed",
  "result": {},
  "error": null
}
```

## 13.3 Capability Management

```http
GET /api/v2/advisor/capabilities
PATCH /api/v2/advisor/capabilities/{capability_id}
```

Used by the frontend capability-toggle UI.

## 13.4 Skill Management

```http
GET /api/v2/advisor/skills
POST /api/v2/advisor/skills/reindex
```

Meaning:

- `GET /api/v2/advisor/skills` returns indexed system skills and their states
- `POST /api/v2/advisor/skills/reindex` triggers a repository skill rescan

## 13.5 Skill Credential Management

```http
GET /api/v2/advisor/skills/{skill_id}/credential
PUT /api/v2/advisor/skills/{skill_id}/credential
```

## 13.6 Skill Test

```http
POST /api/v2/advisor/skills/{skill_id}/test
```

Purpose:

- test whether credentials are usable
- test whether browser selectors still work
- update credential state to `valid` or `invalid`

---

## 14. Code Structure Recommendations

### New Backend Files

```text
lumie_backend/app/api/
  advisor_v2_routes.py
  advisor_capability_routes.py
  advisor_skill_routes.py

lumie_backend/app/services/
  advisor_orchestrator.py
  capability_service.py
  skill_registry_service.py
  skill_index_service.py
  skill_credential_service.py
  execution_service.py
  execution_prompt_service.py
  execution_runtime_router.py
  execution_security_service.py
  browser_skill_runtime.py
  lumie_db_connector.py
  external_connector_service.py

lumie_backend/app/models/
  advisor_capability.py
  advisor_skill_credential.py
  execution_job.py
```

### Existing Files to Refactor

- `advisor_service.py`
  - keep temporarily as a compatibility layer, but eventually replace with `advisor_orchestrator.py`

- `analysis_service.py`
  - refactor and merge into `execution_service.py`

- `analysis_prompt_service.py`
  - refactor into `execution_prompt_service.py`

- `analysis_sandbox_service.py`
  - retain as one of the runtime implementations

### New / Updated Frontend Files

```text
lumie_activity_app/lib/core/services/
  advisor_service.dart              # upgrade to /api/v2/advisor/chat
  advisor_capability_service.dart   # capability toggles
  advisor_skill_service.dart        # skill list and state display
  advisor_credential_service.dart   # credential save/test
  advisor_job_service.dart          # execution job polling

lumie_activity_app/lib/features/advisor/screens/
  advisor_settings_screen.dart
  advisor_skill_list_screen.dart
  advisor_credential_screen.dart

lumie_activity_app/lib/features/advisor/widgets/
  capability_toggle_tile.dart
  skill_card.dart
  skill_credential_sheet.dart
```

---

## 15. Prompt Design Requirements

Advisor-layer system prompt must add:

- current user capability list
- summaries of currently available skills
- skill-selection principles
- direct-vs-execution decision rules

Execution-layer prompt must add:

- full skill definition
- runtime environment rules
- allowed connectors
- error-repair mechanism
- output schema

Lumie DB Connector-side prompt or script policy must add:

- no out-of-scope access
- target user must be explicit in effect
- Lumie team/data-sharing rules must be respected

---

## 16. Error Handling

### 16.1 Advisor Layer

- capability not enabled
- skill not found
- credential not configured
- required ping missing for the selected skill

### 16.2 Execution Layer

- LLM failed to generate a script
- runtime routing failed
- runtime timed out
- runtime returned an unparsable result

### 16.3 Lumie DB Connector

- invalid ping
- permission denied
- invalid collection
- unsafe write
- script execution error

### 16.4 Browser Runtime

- login failure
- selector not found
- page structure changed
- captcha / 2FA

---

## 17. MVP Scope

Phase-1 recommended capabilities:

1. `lumie_internal_data`
2. `browser_portal_access`
3. `email_read`
4. `web_read`

Phase-1 recommended skills:

1. `comprehensive_health_assessment`
2. `today_tasks_and_medications`
3. `school_schedule_query`
4. `school_homework_query`
5. `email_keyword_search`

Do not include in MVP:

- encrypted credential vaulting
- writing to third-party platforms beyond strictly limited internal rules
- open-ended multi-step web exploration

---

## 18. Development Phases

### Phase 1

- build data models for capabilities, skill credentials, and execution jobs
- create `advisor_orchestrator.py`
- add `/api/v2/advisor/chat`

### Phase 2

- create `lumie_db_connector.py`
- implement Lumie internal data skills
- complete ping validation through skill credentials

### Phase 3

- create `browser_skill_runtime.py`
- support school-portal skills
- support credential storage

### Phase 4

- add `email_read` skill support
- connect user email access

### Phase 5

- merge the current analysis system into the unified execution system
- gradually deprecate legacy `analysis_jobs`

---

## 19. Acceptance Criteria

The implementation is complete only if all of the following are true:

1. The user can enable capabilities individually in settings
2. The user can save `base_url`, `username`, `password`, and `notes` for a given skill
3. Advisor automatically chooses a skill when it cannot answer directly
4. Lumie internal data access must always go through skill-credential ping + Lumie DB Connector
5. Lumie DB Connector correctly identifies requester and target user
6. A team admin can access only the member data they are allowed to access
7. Unauthorized access is rejected and written to audit logs
8. When a browser skill fails, the execution system retries at least once when appropriate
9. Execution results are ultimately returned through the unified Advisor chat surface

---

## 20. Key Decisions Summary

This design is built around five core decisions:

1. Model everything a user could manually do as a skill
2. Gate skill availability through capabilities
3. Treat Lumie internal data access as skill-based execution as well
4. Protect Lumie internal access using user-specific ping stored in skill credentials
5. Make Lumie DB Connector the final authority for Lumie-specific permission enforcement

This design does not aim for perfect security in version one. It aims for:

- unified shape
- simple implementation
- fast delivery
- room for later hardening

