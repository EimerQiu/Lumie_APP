# AI Data Analysis System Implementation

**Date:** 2026-03-15
**Feature:** Upgrade Advisor Chat from pure conversation to intelligent routing with data analysis

## Overview

Implemented the complete AI Data Analysis System as designed in `docs/ai_code_execution_system.md`. The system upgrades the Advisor Chat to intelligently route between direct replies (fast path) and data analysis (slow path) using Claude's tool_use capability.

## Key Decisions

1. **Model change: Opus → Sonnet for Layer 1** — Sonnet provides accurate tool_use judgment, faster response (~1s vs ~3s), and ~5x cheaper. Conversation quality is sufficient at Sonnet level.
2. **Haiku for Layer 2 (code generation)** — Fast, cost-effective, sufficient for generating Python analysis code.
3. **asyncio instead of Celery** — Single server deployment, asyncio.Semaphore(3) for concurrency control. Can migrate to Celery when user base grows.
4. **Docker CLI via subprocess instead of Docker SDK** — Uses `asyncio.create_subprocess_exec` to call `docker run/kill` directly, avoiding extra pip dependency.
5. **MongoDB auth deferred** — Auth is not currently enabled on the server. Sandbox security is enforced through code scanning + prompt instructions + Docker isolation. Read-only MongoDB user created but will only be enforced when auth is enabled globally.
6. **Sandbox connection without auth** — `SANDBOX_MONGO_URI=mongodb://172.17.0.1:27017/lumie_db` uses Docker bridge network without credentials (matching current no-auth setup).

## New Files Created

### Backend (`lumie_backend/app/`)
- `models/analysis.py` — Pydantic models (AnalysisJobStatus, AnalysisJobResponse, etc.)
- `services/analysis_service.py` — Job lifecycle management, async execution, quota/rate limiting
- `services/analysis_llm_service.py` — Layer 2 Claude code generation (Haiku)
- `services/analysis_prompt_service.py` — Schema + glossary + profile prompt assembly
- `services/analysis_sandbox_service.py` — Docker container creation/monitoring/cleanup
- `services/analysis_security_service.py` — Static code security scanning (prohibited patterns)
- `api/analysis_routes.py` — 3 endpoints: GET job, GET jobs list, POST cancel
- `resources/schema/lumie_schema.json` — Lumie database schema for LLM context
- `resources/glossary.md` — Domain glossary for LLM context

### Frontend (`lumie_activity_app/lib/`)
- `shared/models/analysis_models.dart` — AnalysisResult, AnalysisJob models
- `core/services/analysis_service.dart` — Job polling service (2s interval, 60s max)
- `features/advisor/widgets/analysis_result_card.dart` — Rich result card (summary + chart + expandable data)

### Infrastructure
- `lumie_backend/sandbox/Dockerfile` — Python 3.11 sandbox image with pymongo, pandas, matplotlib, numpy

## Modified Files

### Backend
- `services/advisor_service.py` — Complete rewrite: tool_use routing, Sonnet model, subscription quota check, parent permission check
- `api/advisor_routes.py` — Request model adds `target_user_id` + `team_id`; response model adds `type` + `job_id`
- `core/database.py` — Added `analysis_jobs` collection indexes (job_id unique, user_id+created_at, status)
- `core/config.py` — Added `SANDBOX_MONGO_URI` setting
- `main.py` — Registered analysis_routes router

### Frontend
- `core/services/advisor_service.dart` — Returns `AdvisorResponse` (type: direct/analysis) instead of plain String
- `core/constants/api_constants.dart` — Added `analysisJobs` endpoint
- `features/advisor/screens/advisor_screen.dart` — `_Message` class extended with `isAnalyzing`, `jobId`, `analysisResult`, `isAnalysisFailed`; `_send()` handles dual response paths; `_ChatBubble` renders 4 states (normal, analyzing spinner, result card, failed)

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/v1/advisor/chat` | **Modified** — now returns `{type, reply, job_id?}` |
| GET | `/api/v1/analysis/jobs/{job_id}` | **New** — query job status/result |
| GET | `/api/v1/analysis/jobs` | **New** — list user's job history |
| POST | `/api/v1/analysis/jobs/{job_id}/cancel` | **New** — cancel running job |

## New DB Collection

### `analysis_jobs`
- Indexes: `job_id` (unique), `(user_id, created_at desc)`, `status`
- Status flow: `pending → generating → running → success/failed`
- Can be `cancelled` at any stage

## Deployment

1. Docker installed on server (54.177.85.124)
2. Sandbox image `lumie-analysis-sandbox` built
3. MongoDB bind address updated to include `172.17.0.1` (Docker bridge)
4. MongoDB read-only user `analysis_reader` created (for future auth enablement)
5. `SANDBOX_MONGO_URI` added to `.env`
6. Backend deployed and restarted successfully

## Subscription Limits (Analysis Path Only)

| Tier | Daily Analysis Limit |
|------|---------------------|
| free | 3 |
| monthly/annual (Pro) | 20 |

Direct replies do not consume quota. Quota exceeded returns a friendly message through chat, not a 403 error.

## Security Layers

1. **Code scanning** — Blocks DB writes, system calls, network access, sensitive collection access, file manipulation
2. **Docker isolation** — 256MB memory, 0.5 CPU, 32 PIDs, read-only filesystem, non-root user
3. **Timeout** — 30s default, 60s max, container killed on timeout
4. **Prompt instructions** — Read-only, teen-safe rules
5. **Concurrency** — Max 3 simultaneous sandboxes via asyncio.Semaphore

## Testing Checklist

- [ ] Direct reply works (greetings, health questions) — should be faster than before (Sonnet vs Opus)
- [ ] Data analysis triggers on data questions ("What's my activity trend?")
- [ ] Analysis result displays with summary text
- [ ] Chart renders inline when generated
- [ ] "Analyzing..." spinner shows during polling
- [ ] Failed analysis shows error message
- [ ] Quota limit message appears after daily limit exceeded
- [ ] Parent can analyze child's data via team_id
- [ ] Job cancellation works
- [ ] Old clients (without `type` field handling) still work via `reply` field

## Future Work

- Enable MongoDB auth and enforce read-only user for sandbox
- Add retry button for failed analyses
- Analysis history UI screen
- Consider WebSocket for real-time status updates (vs polling)
- Migrate to Celery + Redis when user scale requires it
