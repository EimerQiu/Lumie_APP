# Advisor Unified Capability + Skill System

**Date:** 2026-03-27
**Scope:** Backend + Flutter frontend
**Status:** MVP deployed

## Decisions Made

1. **Unified execution path**: All data access (Lumie DB, browser, email, external API) goes through the same skill -> execution pipeline
2. **Skills as .md files**: All skills stored as repo files with YAML frontmatter, indexed at startup — no MongoDB storage for skill definitions
3. **Capability gating**: Every skill is bound to a capability; capabilities must be enabled per-user before skills can execute
4. **Auto-provisioned Lumie internal credentials**: Ping tokens auto-generated when `lumie_internal_data` capability is enabled
5. **Phase 1 tradeoffs accepted**: Plain-text credential storage, browser runtime stubbed, email connector not yet implemented
6. **v2 API alongside v1**: New `/api/v2/advisor/*` endpoints; v1 advisor endpoint preserved for backward compatibility
7. **LLM routes to skills**: Orchestrator retrieves top-k candidate skills, passes them as a tool enum to Claude, which selects one

## New Backend Files

### Models
- `app/models/advisor_capability.py` — Capability, skill summary/detail models
- `app/models/advisor_skill_credential.py` — Credential save/response/test models
- `app/models/execution_job.py` — ExecutionJob models, v2 chat request/response

### Services
- `app/services/advisor_orchestrator.py` — Main v2 orchestrator (replaces advisor_service for v2)
- `app/services/capability_service.py` — System capability CRUD + per-user state
- `app/services/skill_registry_service.py` — Scans .md files, builds inverted index, top-k retrieval
- `app/services/skill_credential_service.py` — Credential CRUD, ping auto-generation
- `app/services/execution_service.py` — Job lifecycle, LLM script generation, runtime dispatch
- `app/services/execution_prompt_service.py` — Prompt assembly for code generation
- `app/services/lumie_db_connector.py` — Permission enforcement, script validation, audit logging
- `app/services/browser_skill_runtime.py` — Stub (returns not-implemented)

### Routes
- `app/api/advisor_v2_routes.py` — All v2 endpoints

### Skills (5 MVP)
- `app/skills/system/lumie_internal/comprehensive_health_assessment.md`
- `app/skills/system/lumie_internal/today_tasks_and_medications.md`
- `app/skills/system/lumie_internal/team_member_health_snapshot.md`
- `app/skills/system/browser/school_homework_query.md`
- `app/skills/system/email/email_keyword_search.md`

## Modified Files

- `app/main.py` — Added v2 router, skill registry scan, capability seeding on startup
- `app/core/database.py` — Added indexes for 5 new collections
- `requirements.txt` — Added PyYAML dependency

## New Flutter Files

### Services
- `lib/core/services/advisor_v2_service.dart` — v2 chat + job polling
- `lib/core/services/advisor_capability_service.dart` — Capability CRUD
- `lib/core/services/advisor_skill_service.dart` — Skill list + credential management

### Screens
- `lib/features/advisor/screens/advisor_settings_screen.dart` — Capability toggles
- `lib/features/advisor/screens/advisor_skill_list_screen.dart` — Skill browser
- `lib/features/advisor/screens/advisor_credential_screen.dart` — Credential entry/test

### Constants
- `lib/core/constants/api_constants.dart` — Added v2 endpoint constants

## API Endpoints Added

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/v2/advisor/chat` | Main v2 chat (skill-aware) |
| GET | `/api/v2/advisor/jobs/{job_id}` | Execution job status |
| POST | `/api/v2/advisor/jobs/{job_id}/cancel` | Cancel job |
| GET | `/api/v2/advisor/capabilities` | List capabilities |
| PATCH | `/api/v2/advisor/capabilities/{id}` | Toggle capability |
| GET | `/api/v2/advisor/skills` | List skills |
| GET | `/api/v2/advisor/skills/{id}` | Skill detail |
| POST | `/api/v2/advisor/skills/reindex` | Rescan skills |
| GET | `/api/v2/advisor/skills/{id}/credential` | Get credential |
| PUT | `/api/v2/advisor/skills/{id}/credential` | Save credential |
| POST | `/api/v2/advisor/skills/{id}/test` | Test credential |

## New DB Collections/Indexes

| Collection | Indexes |
|---|---|
| `advisor_capabilities` | `capability_id` (unique) |
| `user_advisor_capabilities` | `(user_id, capability_id)` (unique) |
| `advisor_skill_credentials` | `(user_id, skill_id)` (unique) |
| `execution_jobs` | `job_id` (unique), `(user_id, created_at)`, `status` |
| `execution_audit_logs` | `log_id` (unique), `(user_id, created_at)` |

## Testing Checklist

- [x] All Python files pass syntax check
- [x] All 5 skill files parse with valid YAML frontmatter
- [x] deploy.sh succeeds
- [x] Service starts without errors
- [x] 5 skills indexed, 0 invalid in startup logs
- [x] System capabilities seeded
- [x] v2 routes respond with 403 (auth required) — routes correctly registered
- [x] v1 health check still works
- [x] Notification daemon still running

## Future Work / Deferred

- **Browser runtime**: Playwright implementation (Phase 3)
- **Email connector**: IMAP/Gmail API integration (Phase 4)
- **Encrypted credentials**: Secret vault / encryption at rest
- **Flutter v2 integration**: Wire advisor_screen.dart to use v2 service (currently v1 still active)
- **Merge analysis system**: Gradually replace analysis_jobs with execution_jobs (Phase 5)
- **Execution result in chat**: Save skill results back to chat_messages with metadata
- **Connection testing**: Full end-to-end credential test for browser/email skills
