# Lumie Advisor AI Execution System

Backend Architecture & Development Requirements Specification

**Version**: v3.1
**Updated**: 2026-03-25
**Project**: Lumie Activity App (lumie_backend)

---

## Goal

Upgrade Lumie App's Advisor Chat from a pure conversation system into an **AI orchestration layer** that can route a user message into the correct execution path.

When a user sends any message in Advisor Chat, the backend calls Claude with tool definitions. Claude then decides whether to:

- **Reply directly**: casual chat, health advice, general questions
- **Run async data analysis**: questions requiring personal data lookup through `run_data_analysis`
- **Execute a direct product action**: currently task creation through `create_task`

The user does not need to know which backend path the system takes internally. For the user, chatting with the Advisor remains a unified experience.

### Typical Scenarios

Direct reply (fast path):

- "Hello" → direct reply
- "What is ICD-10?" → direct reply
- "I don't really feel like exercising today" → encouragement + advice, direct reply
- "What exercises can diabetic patients do?" → health advice, direct reply

Triggers data analysis (slow path):

- "What's my activity trend this month?" → needs to query activities → analysis
- "What was my medication completion rate last week?" → needs to query tasks → analysis
- "Analyze my heart rate data for the last two weeks" → needs to query activities heart rate fields → analysis
- "Am I improving on my 6-minute walk test?" → needs to query walk_tests → analysis
- Parent asks: "How did my child do with their tasks this week?" → needs to query tasks (target user is the child) → analysis

Triggers direct tool execution (non-sandbox write path):

- "Remind me to take my medicine at 8am tomorrow" → `create_task`
- "Set a study reminder every day this week at 6pm" → `create_task`

### System Requirements

- Direct reply response time must match the current Advisor (1-3 seconds)
- Data analysis must not block the API (async execution + frontend polling)
- AI-generated code must remain **read-only**
- Execution environment must be fully isolated (Docker container)
- Must comply with Lumie's **teen-safe** design principles (no calories, BMI, weight rankings, etc.)
- Must comply with Lumie's subscription tier limits
- LLM must have complete Lumie database schema and domain glossary context
- Direct business-operation tools must reuse existing backend services rather than generated code

---

# 1 System Architecture

```
Flutter App (Advisor Chat)
     │
     │  POST /api/v1/advisor/chat
     ▼
FastAPI — advisor_service.py
     │
     ├── Claude API (Layer 1 routing with tool_use)
     │     │
     │     ├── No tool call → direct reply
     │     │
     │     ├── create_task → call TaskService directly
     │     │
     │     └── run_data_analysis → create async analysis job
     │                              │
     │                              ▼
     │                        analysis_service.py
     │                              │
     │                              ├── build analysis prompt
     │                              ├── Claude API (Layer 2 code generation)
     │                              ├── static security scan
     │                              └── Docker sandbox execution
     │                                      │
     │                                      ├── read-only MongoDB access
     │                                      └── write results to analysis_jobs
     │
     ├── chat history persistence
     └── dayprint / notification side effects
     
Response → Flutter
     │
     ├── type: "direct"   → display reply immediately
     └── type: "analysis" → show placeholder, poll /analysis/jobs/{job_id}
```

### Component Responsibilities

| Component | Responsibility |
| --- | --- |
| FastAPI | API routing + JWT auth + Advisor orchestration entrypoint |
| advisor_service.py | Layer 1 Claude routing, tool dispatch, quota/rate checks, permission checks |
| analysis_service.py | Analysis job lifecycle orchestration |
| MongoDB (lumie_db) | Business data source + analysis job metadata + chat history |
| AsyncIO Task | Async execution for analysis jobs and background side effects |
| Docker Sandbox | Isolated execution of AI-generated Python analysis code |
| Claude API | Layer 1 routing + Layer 2 code generation |

### Key Design Decisions

**Why tool_use instead of two LLM calls?**

No need to call Claude once to "decide what kind of request this is" and then again to route it manually. Claude's tool_use can route among direct replies and multiple tools. A single Layer 1 call handles direct answers, analysis requests, and direct business-operation tool calls.

**Why not Celery + Redis?**

Lumie is currently deployed on a single Ubuntu server (54.177.85.124), managed via systemd, without Redis. Introducing Celery + Redis would significantly increase operational complexity. At the current user scale, Python asyncio + `asyncio.create_subprocess_exec` for managing Docker containers can handle concurrency needs. Migration to Celery can happen when the user base grows.

---

# 2 Tech Stack

Actual additions on top of existing `lumie_backend`:

```
Already available (reused directly):
  fastapi
  uvicorn
  motor           # async MongoDB
  pydantic
  anthropic       # Claude API (already used by advisor_service)
```

Implementation note:

```
Docker is invoked through the Docker CLI via asyncio.create_subprocess_exec
The Python Docker SDK is not used in the current implementation
```

Server additions:

```
Docker Engine    # Needs to be installed on 54.177.85.124
```

---

# 3 New MongoDB Collection

### Collection: `analysis_jobs`

```json
{
  "_id": "ObjectId",
  "job_id": "uuid string",
  "user_id": "requesting user ID",
  "team_id": "optional, needed when parent views child's data",
  "target_user_id": "user ID being analyzed (defaults to user_id; in parent scenarios, this is the child's ID)",

  "prompt": "user's natural language question",

  "status": "pending | generating | running | success | failed | cancelled",

  "generated_code": "Python code generated by Claude",

  "result": {
    "summary": "analysis conclusion (text)",
    "data": {},
    "chart_base64": "optional, base64 PNG of chart"
  },

  "stdout": "",
  "stderr": "",
  "error": "",

  "created_at": "datetime (UTC)",
  "started_at": "datetime (UTC)",
  "finished_at": "datetime (UTC)",

  "timeout_sec": 30,
  "docker_container_id": "",

  "model": "claude-sonnet-4-6",
  "token_usage": {
    "input_tokens": 0,
    "output_tokens": 0
  },
  "data_types": [],
  "time_range": "",
  "dayprint_logged": false
}
```

### Indexes

```python
await db.db.analysis_jobs.create_index("job_id", unique=True)
await db.db.analysis_jobs.create_index([("user_id", 1), ("created_at", -1)])
await db.db.analysis_jobs.create_index("status")
```

Add index code to the `create_indexes()` function in `lumie_backend/app/core/database.py`.

---

# 4 API Endpoints

All endpoints use existing JWT auth (`get_current_user_id` dependency injection), following the `/api/v1/` prefix.

## 4.1 Advisor Chat (Upgraded, Intelligent Routing Entry Point)

```
POST /api/v1/advisor/chat  ← reuse existing endpoint URL, upgrade internal logic
```

Headers:

```
Authorization: Bearer {jwt_token}
```

Request Body (backward-compatible, currently implemented fields):

```json
{
  "message": "What's my activity trend this month?",
  "history": [
    {"role": "user", "content": "..."},
    {"role": "assistant", "content": "..."}
  ],
  "target_user_id": "optional, used when parent analyzes child's data",
  "team_id": "optional, needed for parent scenarios",
  "session_id": "optional, used for chat persistence and session restore"
}
```

### Backend Processing Flow

```python
async def advisor_chat(request, user_id):
    # 1. Get user profile (same as existing logic)
    profile = await get_profile(user_id)

    # 2. Build system prompt (upgraded version, includes tool definitions)
    system_prompt = build_advisor_system_prompt(profile)

    # 3. Define available tools
    tools = [RUN_DATA_ANALYSIS_TOOL, CREATE_TASK_TOOL]

    # 4. Call Claude (with tool_use)
    response = await client.messages.create(
        model="claude-sonnet-4-20250514",
        system=system_prompt,
        messages=[...history, {"role": "user", "content": message}],
        tools=tools,
        max_tokens=800,
    )

    # 5. Check response: did Claude answer directly or call a tool?
    if response.stop_reason == "end_turn":
        # Fast path: direct answer
        return {"type": "direct", "reply": extract_text(response)}

    elif response.stop_reason == "tool_use":
        # Tool path: analysis or task creation
        tool_input = extract_tool_input(response)

        if tool_name == "create_task":
            return handle_create_task(tool_input)

        # run_data_analysis path
        check_analysis_quota(user_id, subscription_tier)
        if target_user_id:
            verify_team_admin_access(user_id, target_user_id, team_id)
        job_id = create_analysis_job(...)
        asyncio.create_task(run_analysis_job(job_id))
        return {"type": "analysis", "reply": "Analyzing your data, please wait...", "job_id": job_id}
```

### Response Format (Currently Implemented)

**Direct reply (fast path):**

```json
{
  "type": "direct",
  "reply": "Hello! I'm your Lumie health advisor..."
}
```

Possible direct replies currently include:

- normal conversational answers
- quota/rate-limit responses
- task-creation success/failure replies

Direct responses may also include:

```json
{
  "type": "direct",
  "reply": "Done! I've created **Take Metformin** for you.",
  "nav_hint": "task_list"
}
```

**Data analysis (slow path):**

```json
{
  "type": "analysis",
  "reply": "Analyzing your data, please wait...",
  "job_id": "uuid"
}
```

### Backward Compatibility

When older Flutter clients don't recognize the `type` field, they will simply read the `reply` field and display it — behavior identical to before. The upgraded Flutter checks the `type` field to decide whether to start polling.

### Tool Definitions

#### run_data_analysis

```python
RUN_DATA_ANALYSIS_TOOL = {
    "name": "run_data_analysis",
        "description": (
        "Call this tool when the user's question requires querying their personal health data to answer. "
        "Examples: activity trends, medication completion rates, heart rate analysis, walk test comparisons, "
        "upcoming task reminders, or what tasks are due now/today. "
        "Do NOT use for general health knowledge questions that can be answered directly."
    ),
    "input_schema": {
        "type": "object",
        "properties": {
            "question": {
                "type": "string",
                "description": "The specific data question to analyze, passed to the data analysis system"
            },
            "data_types": {
                "type": "array",
                "items": {"type": "string", "enum": [
                    "activities", "tasks", "walk_tests", "profile"
                ]},
                "description": "Types of data to query"
            },
            "time_range": {
                "type": "string",
                "description": "Time range description, e.g., 'last 7 days', 'this month', 'past 30 days'"
            }
        },
        "required": ["question"]
    }
}
```

#### create_task

The current implementation also registers a `create_task` tool for task/reminder creation. This tool:

- is used for write operations such as creating tasks from natural language
- does not use generated code or the Docker sandbox
- delegates to existing backend business logic in `TaskService`
- returns a normal direct response with `nav_hint: "task_list"`

### Subscription Limits (Analysis Path Only)

Direct replies do not consume analysis quota. Only triggering the `run_data_analysis` tool is checked:

| Tier | Daily Analysis Limit |
| --- | --- |
| free | 200 |
| monthly (Pro) | 200 |
| annual (Pro) | 200 |

When the limit is exceeded, instead of returning a 403 error (since we're inside the existing chat endpoint), return:

```json
{
  "type": "direct",
  "reply": "You've used all your data analysis quota for today. I can still help you with questions that don't require data lookup."
}
```

This provides a more natural user experience — the Advisor communicates the limit through conversation rather than returning an error.

---

## 4.2 Query Analysis Job Status

```
GET /api/v1/analysis/jobs/{job_id}
```

Response:

```json
{
  "job_id": "uuid",
  "status": "success",
  "prompt": "What's my activity trend this month?",
  "result": {
    "summary": "Your activity this month shows an upward trend...",
    "data": { "dates": ["..."], "minutes": ["..."] },
    "chart_base64": "iVBORw0KGgo..."
  },
  "created_at": "2026-03-14T10:00:00",
  "finished_at": "2026-03-14T10:00:12"
}
```

Permissions: Only the job creator (matching user_id) can query.

Flutter uses polling to check status (every 2 seconds, up to 60 seconds max).

---

## 4.3 Cancel Analysis Job

```
POST /api/v1/analysis/jobs/{job_id}/cancel
```

Logic:

```
1. Verify JWT + permissions (only creator can cancel)
2. If Docker container is running → docker kill
3. Update status = cancelled
```

---

## 4.4 Query Historical Analysis Jobs

```
GET /api/v1/analysis/jobs
```

Query Params:

```
limit: int (default 10, max 50)
offset: int (default 0)
```

Returns the current user's analysis history, sorted by created_at descending.

---

# 5 Job Status Flow

```
pending → generating → running → success
                                → failed
                   → failed (code generation failure)
         → cancelled (can be cancelled at any stage)
```

Status transitions are one-directional only, no rollbacks allowed.

---

# 6 Async Execution Mechanism

Uses `asyncio.create_task` + `asyncio.create_subprocess_exec` instead of Celery.

```python
# In analysis_service.py
async def run_analysis_job(job_id: str):
    """Async analysis job execution, scheduled via create_task"""
    try:
        # 1. Update status → generating
        # 2. Assemble prompt, call Claude
        # 3. Security scan the generated code
        # 4. Update status → running
        # 5. Start Docker sandbox
        # 6. Wait for execution to complete (with timeout)
        # 7. Read results, update status → success
    except Exception as e:
        # Update status → failed
```

### Concurrency Limits

Use `asyncio.Semaphore` to control the number of simultaneously running sandboxes:

```python
_sandbox_semaphore = asyncio.Semaphore(3)  # Max 3 concurrent sandboxes

async def run_analysis_job(job_id: str):
    async with _sandbox_semaphore:
        ...
```

---

# 7 Worker Execution Flow

```
1. Read job record from MongoDB

2. status → generating

3. Load Lumie schema (resources/schema/lumie_schema.json)
4. Load glossary (resources/glossary.md)
5. Load user profile (from profiles collection)

6. Assemble prompt (schema + glossary + profile context + user question)

7. Call Claude API to generate Python code

8. Security scan the code (see Section 15)

9. Write code to temp directory /tmp/lumie_sandbox/{job_id}/main.py

10. status → running

11. Start Docker sandbox container

12. Wait for container to exit (with timeout monitoring)

13. Read /tmp/lumie_sandbox/{job_id}/output/result.json

14. Write results to analysis_jobs.result

15. status → success (or failed)

16. Clean up temp directory
```

---

# 8 Prompt Context Assembly (Two Layers)

This system has two layers of LLM calls, each requiring a different prompt.

## 8.1 Layer 1: Advisor Chat (Routing Layer)

Assembled by the upgraded `advisor_service.py`. This layer's system prompt extends the existing advisor prompt with tool usage guidance.

```python
async def build_advisor_system_prompt(profile: dict) -> str:
    name = profile.get("name", "the user")
    age = profile.get("age")
    icd10 = profile.get("icd10_code")
    advisor_name = profile.get("advisor_name")

    return f"""You are Lumie, a compassionate AI health advisor built into the Lumie app.
Lumie helps teens and young adults with chronic health conditions stay active safely.

User profile:
- Name: {name}
- Age: {age or 'unknown'}
- Medical condition (ICD-10): {icd10 or 'No condition on file'}
{f'- Their healthcare advisor/coach is {advisor_name}' if advisor_name else ''}

## When to use the run_data_analysis tool
Call `run_data_analysis` when the user asks a question that requires querying their personal data:
- Activity trends, totals, or comparisons over time
- Task/medication completion rates or statistics
- Heart rate analysis
- Walk test progress
- Any question that asks about specific numbers/trends in their data
- Questions about what tasks/medications are due now, today, or later

Do NOT call the tool for:
- General health advice or tips
- Greetings or small talk
- Questions about medical conditions (answer from knowledge)
- Emotional support or encouragement
- Questions you can answer without data
- Creating or adding new tasks (use `create_task` instead)

## Response guidelines
- Keep replies concise: 2–4 sentences unless a detailed explanation is clearly needed.
- Always acknowledge the user's condition and energy levels.
- Encourage consistency over intensity.
- Never replace medical advice — remind the user to check with their care team for anything clinical.
- Use warm, supportive language. Avoid being preachy.
- TEEN-SAFE: Never output calories, BMI, weight comparisons, or performance rankings.
- You may use **bold** to emphasise key words, but do not use bullet points, numbered lists, or headers.

## Context
- Right now (user's local time): ...
- User's timezone: ..."""
```

**Model choice**: Layer 1 currently uses `claude-sonnet-4-20250514`.

**max_tokens**: 800 (slightly higher than the current 400, since tool_use responses may include tool call JSON).

## 8.2 Layer 2: Code Generation (Analysis Layer)

Assembled by `analysis_prompt_service.py`. Only triggered on the analysis path.

```python
async def build_analysis_prompt(
    question: str,
    target_user_id: str,
    user_profile: dict
) -> str:
    schema = load_schema()       # Read from file
    glossary = load_glossary()   # Read from file
    return PROMPT_TEMPLATE.format(
        schema=schema,
        glossary=glossary,
        user_age=user_profile.get("age", "unknown"),
        user_condition=user_profile.get("icd10_code", "none"),
        user_timezone=user_profile.get("timezone", "UTC"),
        question=question
    )
```

**Model choice**: Layer 2 currently uses `claude-sonnet-4-6`.

**The schema and glossary are maintained by the backend. The LLM must not explore the database structure on its own.**

---

# 9 Lumie Database Schema File

Storage location:

```
lumie_backend/app/resources/schema/lumie_schema.json
```

Content (based on actual Lumie collections):

```json
{
  "database": "lumie_db",
  "collections": [
    {
      "name": "profiles",
      "description": "User profiles containing age, height/weight, ICD-10 diagnosis code",
      "fields": {
        "user_id": "string, unique user identifier",
        "name": "string, user name",
        "age": "number, age",
        "role": "string, teen or parent",
        "height": "object, {value: number, unit: 'cm'|'ft'}",
        "weight": "object, {value: number, unit: 'kg'|'lbs'}",
        "icd10_code": "string, ICD-10 diagnosis code (e.g., E10 = Type 1 Diabetes)",
        "advisor_name": "string, AI advisor nickname",
        "timezone": "string, user timezone (e.g., America/Los_Angeles)",
        "created_at": "string, ISO datetime"
      }
    },
    {
      "name": "activities",
      "description": "Activity records (from smart ring or manual entry)",
      "fields": {
        "user_id": "string",
        "activity_type_id": "string, activity type ID (see activity_types)",
        "activity_type_name": "string, e.g., walking, running, yoga",
        "times": "number, activity count",
        "duration_minutes": "number, duration in minutes",
        "intensity": "string, low|moderate|high",
        "source": "string, ring|manual",
        "avg_heart_rate": "number, average heart rate BPM",
        "max_heart_rate": "number, maximum heart rate BPM",
        "start_time": "string, ISO datetime (UTC)",
        "created_at": "string, ISO datetime"
      },
      "notes": "13 activity types: walking, running, cycling, swimming, yoga, stretching, dancing, basketball, soccer, tennis, hiking, gym, other"
    },
    {
      "name": "walk_tests",
      "description": "6-minute walk test results for assessing cardiopulmonary function",
      "fields": {
        "user_id": "string",
        "date": "string, test date YYYY-MM-DD",
        "distance_meters": "number, walking distance (meters)",
        "duration_seconds": "number, duration in seconds",
        "avg_heart_rate": "number",
        "max_heart_rate": "number",
        "recovery_heart_rate": "number, recovery heart rate",
        "created_at": "string, ISO datetime"
      }
    },
    {
      "name": "tasks",
      "description": "Med-Reminder tasks (medication reminders, lifestyle habits, etc.)",
      "fields": {
        "task_id": "string, unique task ID",
        "user_id": "string, task assignee",
        "created_by": "string, creator ID",
        "team_id": "string, optional, used for team tasks",
        "task_name": "string, task name",
        "task_type": "string, Medicine|Life|Study|Exercise|Work|Meditation|Love",
        "status": "string, pending|completed|expired",
        "open_datetime": "string, start time 'YYYY-MM-DD HH:mm' stored in UTC (no Z suffix)",
        "close_datetime": "string, end time",
        "completed_at": "string, completion time ISO datetime (optional)",
        "rpttask_id": "string, associated template ID (optional)",
        "task_info": "string, notes (optional)",
        "created_at": "string, ISO datetime"
      },
      "notes": "Status is dynamically computed at query time: if close_datetime has passed and not completed → expired"
    },
    {
      "name": "task_templates",
      "description": "Reusable task templates for batch task generation",
      "fields": {
        "id": "string, unique template ID",
        "created_by": "string, creator ID",
        "template_name": "string",
        "template_type": "string, Medicine|Life|Study|Exercise|Work|Meditation|Love",
        "description": "string, optional",
        "time_window_list": "array of TimeWindow objects",
        "min_interval": "number, minimum interval in minutes",
        "created_at": "string, ISO datetime"
      }
    },
    {
      "name": "teams",
      "description": "Family/team records",
      "fields": {
        "team_id": "string",
        "name": "string, team name",
        "description": "string",
        "created_by": "string, creator user_id",
        "is_deleted": "boolean, soft delete flag",
        "created_at": "string, ISO datetime"
      }
    },
    {
      "name": "team_members",
      "description": "Team membership relationships",
      "fields": {
        "team_id": "string",
        "user_id": "string",
        "role": "string, admin|member",
        "status": "string, pending|member",
        "invited_by": "string",
        "invited_at": "string, ISO datetime",
        "joined_at": "string, ISO datetime"
      }
    }
  ]
}
```

---

# 10 Lumie Domain Glossary

Storage location:

```
lumie_backend/app/resources/glossary.md
```

Content:

```markdown
# Lumie Domain Glossary

## Activity Related
- activity level = sum of duration_minutes in the activities collection
- active minutes = total daily activity minutes
- daily goal = adaptive goal (calculated by the backend based on health data)
- activity intensity = intensity field: low, moderate, high
- activity source = source field: ring (smart ring), manual (manual entry)

## Task Related
- Med-Reminder = tasks in the tasks collection where task_type = Medicine
- completion rate = completed / total tasks (for a given time period)
- expired tasks = close_datetime has passed and status != completed
- active tasks = current time is between open_datetime and close_datetime
- pending = open_datetime hasn't arrived, or arrived but not completed and not expired

## Health Data Related
- heart rate = avg_heart_rate or max_heart_rate (BPM)
- 6-minute walk test / 6MWT / walk test = walk_tests collection
- walking distance = walk_tests.distance_meters
- recovery heart rate = walk_tests.recovery_heart_rate

## Team Related
- family / team = teams collection
- admin = team_members.role = admin
- parent = profiles.role = parent
- child / teen = profiles.role = teen

## Time Related
- this week = current calendar week (Monday to Sunday)
- this month = current calendar month
- last N days = past N calendar days (including today)

## Teen-Safe Rules (LLM Must Comply)
- Never output calories, BMI, or weight rankings
- Never perform weight-related comparisons or rankings
- Never generate performance leaderboards
- Express activity data in "minutes" not "calories burned"
```

---

# 11 Prompt Template

The worker uses a fixed prompt template when calling Claude:

```
You are a data analyst for Lumie, a health activity tracking app for teens with chronic conditions.

Your job: Generate Python code to answer the user's question by querying MongoDB.

## CRITICAL SAFETY RULES
- Database access is READ-ONLY. Never use insert, update, delete, drop, or any write operation.
- TEEN-SAFE: Never output calories, BMI, weight comparisons, or performance rankings.
- Never use subprocess, os.system, eval, exec, or __import__.
- Never access the filesystem except writing to /output/.
- Never make network requests (no urllib, requests, socket, etc.).

## Environment
- Python 3.11 with pymongo, pandas, matplotlib, numpy pre-installed
- MongoDB connection string is in environment variable MONGO_URI
- Database name: lumie_db
- The target user's ID is in environment variable TARGET_USER_ID

## Database Schema
{schema}

## Domain Glossary
{glossary}

## User Context
- User age: {user_age}
- User health condition (ICD-10): {user_condition}
- Timezone: {user_timezone}

## Timezone Handling (MANDATORY for task queries)
task open_datetime/close_datetime are stored in UTC (no Z suffix). Convert user-local concepts such as "today", "now", and "this week" using the user's timezone before querying.

## Task
Answer this question: {question}

## Output Requirements
1. Query the database using pymongo (read-only).
2. Analyze the data using pandas if needed.
3. Save a JSON result to /output/result.json with this structure:
   {{
     "summary": "A concise analysis conclusion (2-4 sentences)",
     "data": {{ ... relevant data ... }}
   }}
4. If a chart would help, use matplotlib to save a PNG to /output/chart.png.
   - Use clean, simple style. Dark background (#1C1C1E) with white text for Lumie's dark theme.
5. Print progress to stdout for logging.

## Code Format
Return ONLY valid Python code. No markdown fencing, no explanation.
```

---

# 12 Claude API Calls (Two-Layer Model Strategy)

Reuses the existing `ANTHROPIC_API_KEY` environment variable.

### Layer 1: Routing Decision (advisor_service.py, upgraded)

```python
model = "claude-sonnet-4-20250514"     # Accurate tool_use judgment + fast response
temperature = 0.3                       # Conversation needs some variation
max_tokens = 800
tools = [RUN_DATA_ANALYSIS_TOOL, CREATE_TASK_TOOL]
```

### Layer 2: Code Generation (analysis_llm_service.py, new)

```python
model = "claude-sonnet-4-6"            # Current code-generation model
temperature = 0                         # Deterministic output
max_tokens = 4000                       # Analysis code tends to be long
```

Output must be **pure Python code**. The worker must strip markdown code block markers (` ```python `, etc.).

If Claude's output is not valid Python code, job status → failed, error = "code_generation_failed".

### Cost Estimate

| Path | Model | Estimated tokens/call | Cost/call |
| --- | --- | --- | --- |
| Direct reply / tool routing | Sonnet | varies | implementation-dependent |
| Data analysis | Sonnet + Sonnet | varies | implementation-dependent |

Exact cost estimates should be recalculated from current model pricing before using this document for budgeting.

---

# 13 LLM Call Rate Limiting

Uses in-memory rate counters (per user_id):

```python
# Max 2 LLM calls per user per minute
# Max 5 LLM calls globally per second (to protect Anthropic API quota)
```

In the current implementation, analysis rate-limit exhaustion is converted into a conversational direct reply rather than a raw 429 response.

---

# 14 Docker Sandbox

### Sandbox Image

Image name: `lumie-analysis-sandbox`

Dockerfile (new file at `lumie_backend/sandbox/Dockerfile`):

```dockerfile
FROM python:3.11-slim

RUN pip install --no-cache-dir \
    pymongo==4.7.0 \
    pandas==2.2.0 \
    matplotlib==3.9.0 \
    numpy==1.26.0

RUN adduser --disabled-password --no-create-home sandbox

RUN mkdir -p /app /output && chown sandbox:sandbox /output

WORKDIR /app

USER sandbox

CMD ["python", "main.py"]
```

### Build Image

```bash
cd lumie_backend/sandbox
docker build -t lumie-analysis-sandbox .
```

This operation is performed once during deployment; the image is cached on the server.

---

# 15 Docker Security Policy

Starting a container:

```python
docker_cmd = [
    "docker", "run",
    "--rm",
    "--name", f"lumie-analysis-{job_id[:12]}",
    "--memory", "256m",
    "--cpu-quota", "50000",
    "--pids-limit", "32",
    "--network", "bridge",
    "--read-only",
    "--tmpfs", "/tmp:size=64m,noexec",
    "-v", f"{code_path}:/app/main.py:ro",
    "-v", f"{output_dir}:/output:rw",
    "-e", f"MONGO_URI={SANDBOX_MONGO_URI}",
    "-e", f"TARGET_USER_ID={target_user_id}",
    "lumie-analysis-sandbox",
]

process = await asyncio.create_subprocess_exec(
    *docker_cmd,
    stdout=asyncio.subprocess.PIPE,
    stderr=asyncio.subprocess.PIPE,
)
```

### Network Policy

The container needs access to MongoDB (via Docker bridge network), but must use a **read-only MongoDB user** (see Section 16).

Prohibited:

```
--privileged
--network=host
```

Container must have:

```
non-root user (sandbox)
read-only root filesystem
resource limits (memory, CPU, PIDs)
```

---

# 16 MongoDB Read-Only Access Policy

This remains the intended security model for sandbox access. In the current deployed implementation, MongoDB auth enablement may still be deferred depending on environment, so prompt rules, static scanning, and Docker isolation remain important enforcement layers.

### Create Read-Only User

Create a dedicated read-only user in MongoDB for sandbox use:

```javascript
use lumie_db
db.createUser({
  user: "analysis_reader",
  pwd: "generate a strong password",
  roles: [{ role: "read", db: "lumie_db" }]
})
```

### Sandbox Connection String

```
SANDBOX_MONGO_URI = "mongodb://analysis_reader:password@host.docker.internal:27017/lumie_db?authSource=lumie_db"
```

Note: Use `host.docker.internal` (Docker Desktop) or the container host IP (Linux) to access the host machine's MongoDB.

### Allowlisted Collections

Sandbox code should only query the following collections:

```
profiles          (user profiles)
activities        (activity records)
walk_tests        (walk test results)
tasks             (task records)
task_templates    (task templates)
```

The following collections are **prohibited** from sandbox access:

```
users             (contains password hashes and tokens)
teams             (team management data)
team_members      (membership relationships)
pending_invitations (invitation data)
```

While MongoDB's `read` role grants read access to all collections, actual access to collections is restricted through prompt instructions and code security scanning.

### Data Scope Restrictions

All queries in sandbox code must include a `user_id` filter condition (equal to `TARGET_USER_ID`), ensuring only the target user's data can be accessed. This is enforced through both prompt instructions and code security scanning.

---

# 17 Sandbox Directory Structure

```
/tmp/lumie_sandbox/
   /{job_id}/
       main.py              # AI-generated analysis code (read-only mount)
       output/
           result.json      # Analysis results (required)
           chart.png        # Chart (optional)
           stdout.log       # Standard output
           stderr.log       # Standard error
```

Rules:

```
main.py     → read-only
/output     → writable for current job
all other   → not writable (read-only root filesystem)
```

Clean up temp directory after job completes:

```python
import shutil
shutil.rmtree(f"/tmp/lumie_sandbox/{job_id}", ignore_errors=True)
```

---

# 18 Code Security Scanning

The worker performs static security checks before placing code in the sandbox.

### Prohibited Keywords/Patterns

**Database write operations:**

```
insert_one, insert_many
update_one, update_many
delete_one, delete_many
replace_one
drop, drop_collection, drop_database
create_index, drop_index
bulk_write
aggregate.*\$out, aggregate.*\$merge
```

**File deletion/overwrite:**

```
os.remove, os.unlink
shutil.rmtree, shutil.move
open(.*['\"]w['\"])    # Only allow writes to /output paths
```

**System calls:**

```
subprocess, os.system, os.popen
eval, exec, compile
__import__
importlib
```

**Network access:**

```
urllib, requests, httpx, aiohttp
socket, http.client
```

**Access to sensitive collections:**

```
\.users[.\[]
\.pending_invitations[.\[]
password, hashed_password
device_token
```

On any violation:

```python
status = "failed"
error = "security_violation: {matched_pattern}"
```

---

# 19 Timeout Control

```python
timeout_sec = job["timeout_sec"]  # Default 30 seconds, max 60 seconds

try:
    result = await asyncio.wait_for(
        wait_container(container),
        timeout=timeout_sec
    )
except asyncio.TimeoutError:
    container.kill()
    # status → failed, error = "timeout"
```

---

# 20 Concurrency Control

```python
# Maximum number of simultaneously running sandbox containers
MAX_CONCURRENT_SANDBOXES = 3

_sandbox_semaphore = asyncio.Semaphore(MAX_CONCURRENT_SANDBOXES)
```

When all slots are occupied, new jobs remain in pending status and wait.

---

# 21 Backend Directory Structure

New and modified files integrated into the existing `lumie_backend/app/` structure:

```
lumie_backend/app/
 ├── api/
 │   ├── advisor_routes.py           ← Modified: upgraded response model
 │   ├── analysis_routes.py          ← New: analysis job query/cancel routes
 │   └── chat_history_routes.py      ← New: advisor history + session routes
 │
 ├── services/
 │   ├── advisor_service.py          ← Modified: add tool_use + routing logic
 │   ├── analysis_service.py         ← New: job management + execution flow
 │   ├── analysis_llm_service.py     ← New: Claude code generation (Layer 2)
 │   ├── analysis_prompt_service.py  ← New: prompt context assembly
 │   ├── analysis_sandbox_service.py ← New: Docker container management
 │   ├── analysis_security_service.py← New: code security scanning
 │   └── chat_history_service.py     ← New: chat persistence
 │
 ├── models/
 │   └── analysis.py                 ← New: analysis job Pydantic models
 │
 ├── resources/
 │   ├── schema/
 │   │   └── lumie_schema.json       ← New: Lumie database schema
 │   └── glossary.md                 ← New: domain glossary
 │
 └── main.py                         ← Modified: register analysis/chat history routes + startup index hooks

lumie_backend/sandbox/
 └── Dockerfile                      ← New: sandbox image definition
```

---

# 22 Pydantic Models

File: `lumie_backend/app/models/analysis.py`

```python
from pydantic import BaseModel, Field
from typing import Optional, Dict, Any
from enum import Enum
from datetime import datetime


class AnalysisJobStatus(str, Enum):
    PENDING = "pending"
    GENERATING = "generating"
    RUNNING = "running"
    SUCCESS = "success"
    FAILED = "failed"
    CANCELLED = "cancelled"


class AnalysisJobCreate(BaseModel):
    prompt: str = Field(..., min_length=2, max_length=500)
    target_user_id: Optional[str] = None
    team_id: Optional[str] = None
    timeout: int = Field(default=30, ge=10, le=60)


class AnalysisResult(BaseModel):
    summary: str
    data: Optional[Dict[str, Any]] = None
    chart_base64: Optional[str] = None
    nav_hint: Optional[str] = None


class AnalysisJobResponse(BaseModel):
    job_id: str
    status: AnalysisJobStatus
    prompt: str
    result: Optional[AnalysisResult] = None
    error: Optional[str] = None
    created_at: str
    started_at: Optional[str] = None
    finished_at: Optional[str] = None


class AnalysisJobListResponse(BaseModel):
    jobs: list[AnalysisJobResponse]
    has_more: bool
```

---

# 23 Route Registration

Modify `lumie_backend/app/main.py`:

```python
from app.api.analysis_routes import router as analysis_router

# Add after existing route registrations:
app.include_router(analysis_router, prefix="/api/v1")
```

---

# 24 Flutter Frontend Integration

### Design Principle

Minimize frontend changes. User experience goes from "chatting with Advisor" to "chatting with a smarter Advisor" — the UI flow stays the same.

### Modified Files

```
lumie_activity_app/lib/
 ├── core/services/
 │   ├── advisor_service.dart         ← Modified: handle new response type
 │   └── analysis_service.dart        ← New: analysis job polling
 │
 ├── shared/models/
 │   └── analysis_models.dart         ← New: analysis-related Dart models
 │
 └── features/advisor/
     ├── screens/
     │   └── advisor_screen.dart      ← Modified: support analyzing state + result display
     └── widgets/
         └── analysis_result_card.dart ← New: analysis result card widget
```

### advisor_service.dart Modifications

```dart
class AdvisorService {
  /// Send message, returns either a direct reply or an analysis job
  Future<AdvisorResponse> sendMessage(
    String message, {
    List<ChatMessage> history = const [],
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}${ApiConstants.advisorChat}'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_authService.token}',
      },
      body: json.encode({
        'message': message,
        'history': history.map((m) => m.toJson()).toList(),
        'session_id': sessionId,
      }),
    ).timeout(const Duration(seconds: 15));

    final data = json.decode(response.body);
    final type = data['type'] ?? 'direct';  // Backward compatible

    if (type == 'analysis') {
      return AdvisorResponse.analysis(
        reply: data['reply'],
        jobId: data['job_id'],
      );
    } else {
      return AdvisorResponse.direct(
        reply: data['reply'],
        navHint: data['nav_hint'],
      );
    }
  }
}

/// Unified Advisor response type
class AdvisorResponse {
  final String type;     // "direct" or "analysis"
  final String reply;
  final String? jobId;
  final String? navHint;

  AdvisorResponse.direct({required this.reply, this.navHint})
      : type = 'direct', jobId = null;

  AdvisorResponse.analysis({required this.reply, required this.jobId})
      : type = 'analysis', navHint = null;
}
```

### advisor_screen.dart Modifications

Upgrade the Chat tab's `_send()` method:

```dart
Future<void> _send() async {
  final text = _input.text.trim();
  if (text.isEmpty) return;

  // 1. Add user message
  setState(() {
    _messages.add(_Message(text: text, isUser: true));
    _isTyping = true;
  });

  // 2. Send to backend
  final response = await _advisor.sendMessage(text, history: _history);

  if (response.type == 'direct') {
    // Fast path: display reply directly
    setState(() {
        _messages.add(_Message(
          text: response.reply,
          isUser: false,
          navHint: response.navHint,
        ));
      _isTyping = false;
    });
  } else if (response.type == 'analysis') {
    // Slow path: show "analyzing", start polling
    setState(() {
      _messages.add(_Message(
        text: response.reply,  // "Analyzing your data..."
        isUser: false,
        isAnalyzing: true,
        jobId: response.jobId,
      ));
      _isTyping = false;
    });

    // 3. Poll for analysis result
    final result = await _analysisService.pollJobResult(response.jobId!);

    // 4. Replace "analyzing" message with result
    setState(() {
      final idx = _messages.lastIndexWhere((m) => m.jobId == response.jobId);
      if (idx >= 0) {
        _messages[idx] = _Message(
          text: result.summary,
          isUser: false,
          analysisResult: result,  // Contains data + chart_base64
        );
      }
    });
  }
}
```

### _Message Class Upgrade

```dart
class _Message {
  final String text;
  final bool isUser;
  final bool isAnalyzing;        // New: whether analysis is in progress
  final String? jobId;            // New: associated job ID
  final AnalysisResult? analysisResult;  // New: analysis result
  final String? navHint;         // New: optional navigation affordance

  _Message({
    required this.text,
    required this.isUser,
    this.isAnalyzing = false,
    this.jobId,
    this.analysisResult,
    this.navHint,
  });
}
```

### Chat Display

Message bubbles render different UI based on `_Message` state:

- **Normal message**: same as current (Markdown-rendered text bubble)
- **Analyzing**: display reply text + spinning animation indicator
- **Analysis complete**:
  - Summary text displayed normally in the bubble
  - If `chart_base64` exists, display as inline image (`Image.memory(base64Decode(...))`)
  - If `data` exists, display as a collapsible compact data card
- **Analysis failed**: show error message + "Retry" button

---

# 25 Deployment Steps

### 25.1 Install Docker on Server

```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124

# Install Docker
sudo apt-get update
sudo apt-get install -y docker.io
sudo systemctl enable docker
sudo systemctl start docker

# Add ubuntu user to docker group
sudo usermod -aG docker ubuntu
# Re-login for group permissions to take effect
```

### 25.2 Build Sandbox Image

```bash
cd /home/ubuntu/lumie_backend/sandbox
sudo docker build -t lumie-analysis-sandbox .
```

### 25.3 Create MongoDB Read-Only User

Recommended when MongoDB auth is enabled in production. If auth is still disabled in the current environment, this step becomes part of a later hardening pass rather than a prerequisite for the basic architecture.

```bash
mongosh lumie_db

db.createUser({
  user: "analysis_reader",
  pwd: "generate strong password and record in .env",
  roles: [{ role: "read", db: "lumie_db" }]
})
```

### 25.4 Update Environment Variables

Add to `/home/ubuntu/lumie_backend/.env`:

```
SANDBOX_MONGO_URI=mongodb://analysis_reader:password@172.17.0.1:27017/lumie_db?authSource=lumie_db
```

Note: `172.17.0.1` is Docker's default host IP (docker0 bridge).

### 25.5 Configure MongoDB Listening Address

Ensure MongoDB listens on the Docker bridge network:

```bash
# Edit /etc/mongod.conf
# bindIp: 127.0.0.1,172.17.0.1
sudo systemctl restart mongod
```

### 25.6 Deploy Backend Code

Use the existing `deploy.sh` script to deploy the updated backend:

```bash
cd lumie_backend
bash deploy.sh
```

### 25.7 Restart Service

```bash
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.177.85.124
sudo systemctl restart lumie-api
```

---

# 26 Teen-Safe Safety Constraints

All analysis output must comply with Lumie's teen-safe principles:

**Prohibited output:**

- Calorie counts
- BMI calculations
- Weight comparisons or rankings
- Performance leaderboards ("who completed the most tasks")
- MET values
- Any content that could trigger eating disorders or excessive exercise

**Must use:**

- "Active minutes" instead of "calories"
- "Activity trends" instead of "weight changes"
- Positive, encouraging tone
- Concise analysis conclusions

These constraints are enforced through the CRITICAL SAFETY RULES section in the prompt template and checked during code security scanning.

---

# 27 Required Feature Checklist

### Backend (Python / FastAPI)

```
Modified existing files:
1.  advisor_service.py      — Upgrade: add tool_use + intelligent routing logic
2.  advisor_routes.py       — Upgrade: response model adds type + job_id
3.  chat_history_routes.py  — Added advisor history and session endpoints
4.  database.py             — Add analysis_jobs indexes
5.  main.py                 — Register analysis_routes
6.  main.py                 — Register chat_history_routes and ensure chat history indexes on startup

New files:
7.  analysis_routes.py      — Analysis API endpoints (query/cancel/history)
8.  analysis_service.py     — Job lifecycle management + asyncio execution
9.  analysis_llm_service.py — Claude code generation (Layer 2 LLM call)
10. analysis_prompt_service.py — Schema + Glossary + Profile assembly
11. analysis_sandbox_service.py — Docker container creation/monitoring/cleanup
12. analysis_security_service.py — Static code security scanning
13. chat_history_service.py — Chat persistence in MongoDB
14. analysis.py (models)    — Analysis job Pydantic models
15. lumie_schema.json       — Lumie database schema definition
16. glossary.md             — Domain glossary mapping
17. sandbox/Dockerfile      — Sandbox image definition
18. Subscription limit check — Currently implemented as 200/day for all tiers on the analysis path
19. Permission check        — Parent viewing child's data requires team admin role
20. Task tool support       — `create_task` direct business-operation path
```

### Frontend (Flutter / Dart)

```
Modified existing files:
1.  advisor_service.dart    — Handle new response type (direct / analysis)
2.  advisor_screen.dart     — _send() upgrade: support direct, analysis, nav hints, and session flow
3.  chat_history_service.dart — Session/history fetch + local cache
4.  _Message class          — Add isAnalyzing, jobId, analysisResult, navHint fields

New files:
5.  analysis_service.dart   — Analysis job polling logic
6.  analysis_models.dart    — AnalysisResult, AnalysisJob Dart models
7.  analysis_result_card.dart — Analysis result card widget (text + chart + data)
```

### Deployment

```
1.  Install Docker on server
2.  Build sandbox image
3.  Create MongoDB read-only user (recommended hardening step when auth is enabled)
4.  Update .env environment variables
5.  Configure MongoDB network
6.  Deploy backend code
```

### User Experience After Completion

```
User chats with Advisor → system automatically decides:
  → General questions: direct reply within 1-3 seconds (same speed as current)
  → Create-task requests: execute immediately through backend service logic
  → Data questions: show "Analyzing..." → 10-30 seconds later, return analysis conclusions + charts
User doesn't need to manually trigger analysis, switch screens, or understand the underlying mechanism.
```

---

# 28 Development Priority

| Priority | Feature | Description |
| --- | --- | --- |
| P0 | advisor_service.py upgrade (tool_use routing) | System entry point |
| P0 | analysis_service.py + execution flow | Analysis job core |
| P0 | Code generation + security scanning | Security baseline |
| P0 | Docker sandbox | Isolated execution |
| P0 | Schema + Glossary | LLM context |
| P1 | Flutter advisor_screen upgrade | Frontend dual-path support |
| P1 | Flutter analysis result display | Charts + data cards |
| P1 | Subscription limits | Business logic |
| P1 | Parent permission check | Team data access |
| P2 | Analysis history query | User experience |

---

# 29 Relationship with Existing System

| Existing Module | Relationship |
| --- | --- |
| Advisor Chat (`advisor_service.py`) | **Direct upgrade**: now a multi-tool orchestration layer and core file of this change |
| Advisor Routes (`advisor_routes.py`) | **Modified**: response model extended, endpoint URL unchanged |
| AI Tips (`ai_tips_service.py`) | Complementary: Tips provide simple statistics (fast, lightweight); analysis system handles custom questions |
| Team System (`team_service.py`) | Reuses team permission check logic; parents can analyze child data |
| Task System (`task_service.py`) | Reused directly for `create_task` tool execution |
| Auth (`security.py`) | Reuses JWT auth and `get_current_user_id` |
| Profile (`profile_service.py`) | Reads user profile as context for both LLM layers |
| Chat History (`chat_history_service.py`) | Persists sessions and supports Advisor continuity |

### Model Usage Changes

| Scenario | Before | After |
| --- | --- | --- |
| Advisor conversation | Older single-model advisor | Sonnet (`claude-sonnet-4-20250514`), max_tokens=800, with tool_use |
| AI Tips | Haiku, max_tokens=150 | Unchanged |
| Data analysis code generation | Did not exist | Sonnet (`claude-sonnet-4-6`), max_tokens=4000 |

The current implementation uses Sonnet for both Layer 1 routing and Layer 2 code generation. If pricing or capability priorities change later, this document should be updated alongside the code.

---

# 30 Implementation Reality and Architecture Evolution

This section records the current implemented state of the system as of the latest code review, including places where the implementation has intentionally evolved beyond the original scope of this document.

## 30.1 What Was Actually Built

The original design in this document described an **AI data analysis system** attached to Advisor Chat. That system was implemented, but the production architecture has since evolved into a broader **multi-tool Advisor platform**.

Current implemented behavior:

- Advisor Chat still uses a **single entrypoint**: `POST /api/v1/advisor/chat`
- Claude still performs **Layer 1 routing** using tool calls
- `run_data_analysis` still triggers the **async analysis job + code generation + security scan + Docker sandbox** flow
- The frontend Advisor screen still presents this as one unified chat experience with:
  - direct replies
  - analysis placeholders (`Analyzing...`)
  - final analysis result cards
  - failure states

However, the system no longer only routes between:

- direct reply
- read-only data analysis

It now also supports additional tool-driven execution paths and adjacent product behaviors.

## 30.2 The System Is Now a Multi-Tool Advisor Platform

In the current backend implementation, `advisor_service.py` registers **multiple Claude tools**, not just `run_data_analysis`.

Implemented tools / execution paths:

- `run_data_analysis`
  - For questions requiring personal data lookup
  - Creates an `analysis_jobs` record
  - Executes asynchronously through prompt assembly, code generation, security scan, and Docker sandbox execution

- `create_task`
  - For creating reminders/tasks from natural language
  - Does **not** use the Docker sandbox
  - Calls the existing `TaskService` directly because this is a write operation
  - Returns a normal direct response plus `nav_hint: "task_list"`

This is an important architectural update:

- The sandboxed analysis system is now one execution path inside Advisor, not the entire Advisor execution model
- Advisor should now be understood as an orchestration layer that can dispatch to multiple backend capabilities
- New future capabilities should likely follow this same pattern:
  - direct answer path
  - direct business-operation tool path
  - async/sandboxed analysis path

## 30.3 Current Backend Responsibility Split

The codebase currently reflects the following practical architecture:

### `advisor_service.py` = intent routing and orchestration

Responsibilities now include:

- building the Layer 1 system prompt
- passing conversation history into Claude
- registering available tools
- deciding whether the outcome is:
  - direct reply
  - task creation
  - async analysis job creation
- enforcing analysis rate limits and quota checks
- enforcing parent/team permission checks for cross-user analysis

### `analysis_service.py` = async analysis job orchestrator

Responsibilities currently include:

- creating `analysis_jobs`
- managing job status transitions
- assembling prompts for code generation
- retrying failed generations / executions
- invoking static security checks
- executing code inside the Docker sandbox
- storing final result payloads
- queuing analysis-complete notifications

### `analysis_prompt_service.py` + `analysis_llm_service.py` + `analysis_security_service.py` + `analysis_sandbox_service.py`

These now form the concrete **AI code execution subsystem**:

- prompt assembly
- code generation
- static security policy enforcement
- isolated runtime execution
- output loading and chart packaging

### Flutter Advisor screen = unified presentation layer

The Advisor UI in Flutter now handles:

- normal direct replies
- async analysis pending state
- completed analysis rendering
- task-navigation hint chips
- session restore and history browsing

This means the screen has evolved from a basic chat view into a UI shell for multiple backend execution modes.

## 30.4 Drift Between Original Design and Current Code

Several implementation details no longer match the older text above.

### Layer 2 model drift

Earlier sections of this document describe Layer 2 code generation as using Haiku.

Current code reality:

- `analysis_llm_service.py` uses `claude-sonnet-4-6`

Implication:

- The architecture remains the same, but the code-generation model choice changed after implementation
- Any future documentation or planning should treat Sonnet as the current source of truth unless the code changes again

### Analysis quota drift

Earlier sections of this document describe:

- Free: 3 analyses/day
- Pro: 20 analyses/day

Current code reality in `analysis_service.py`:

- Free: 200/day
- Pro: 200/day

Implication:

- The business rule implemented in code is currently much looser than the original design
- The document should not be used as the source of truth for quota behavior without checking code
- If product intends to restore stricter limits, code and documentation need to be realigned

### Tool scope drift

Original design scope:

- direct reply
- read-only data analysis

Current implemented scope additionally includes:

- task creation through Claude tool use
- chat history persistence
- analysis-complete push notifications
- advisor session support

Implication:

- Advisor is no longer just an analysis front-end
- It has become a general AI entrypoint for multiple app capabilities

## 30.5 Additional Capabilities Added After the Original Design

The following capabilities exist in code but were not part of the original document's core scope.

### A. Task creation through Advisor chat

Implemented behavior:

- User can ask Advisor to create reminders/tasks in natural language
- Claude emits a `create_task` tool call
- Backend creates one or more tasks through `TaskService`
- Frontend renders a navigation chip to open the task list

Architectural significance:

- This established the pattern for **non-sandboxed write tools**
- It proves the Advisor platform can safely branch into business operations that should not be handled by generated code

### B. Chat persistence and session model

Implemented behavior:

- Advisor exchanges are stored in `chat_messages`
- Messages are grouped by `session_id`
- Frontend can restore the active session and browse older sessions
- Local cache is used for fast perceived loading

Architectural significance:

- Advisor is no longer stateless per request
- Session continuity is now part of the product and should be considered in all future tool additions
- New capabilities may need to decide whether they store intermediate state, final state, or both in chat history

### C. Analysis-complete notifications

Implemented behavior:

- When an async analysis job succeeds, the backend queues a push notification
- This allows the user to leave the chat and return when results are ready

Architectural significance:

- Async analysis is now integrated into the broader app notification model
- Long-running future tools can likely reuse the same completion-notification pattern

## 30.6 How the Frontend Actually Integrates the System

The original design correctly predicted the high-level UX, and the current Flutter implementation confirms it:

- The Advisor screen does not expose internal execution types to the user
- The user always interacts with a single chat surface
- Analysis jobs are represented as a placeholder assistant message first
- Polling replaces that placeholder with a result card or an error
- Direct tool outcomes such as task creation appear as normal assistant replies with optional navigation affordances

This is an important product truth:

- Advisor is a **unified interaction shell**
- Execution mode differences are mostly hidden behind message rendering and follow-up UI affordances

## 30.7 Updated Architectural Interpretation Going Forward

For future design discussions, the most accurate framing is:

> Lumie's Advisor is now an AI orchestration layer with multiple execution backends.

Those backends currently include:

- direct LLM response
- async read-only AI code execution in Docker
- direct business-operation tool calls into existing services

So the original "AI Code Execution System" remains valid, but it is now best understood as:

- a major subsystem inside Advisor
- not the complete definition of the Advisor architecture

## 30.8 Practical Guidance for Future Extensions

Based on the code as implemented, new Advisor capabilities will likely fit into one of three categories:

### 1. Direct reply capability

Use when:

- no user data lookup is required
- no app-side state mutation is required

### 2. Direct tool / business-operation capability

Use when:

- the operation writes or mutates business data
- existing backend services already contain the domain validation rules
- generated code would be the wrong abstraction or too risky

Examples:

- task creation
- future task edit/delete flows
- preference updates

### 3. Async analysis / sandbox capability

Use when:

- the user asks an open-ended question over personal data
- the operation benefits from flexible query + analysis logic
- the task should remain read-only
- latency of several seconds is acceptable

Examples:

- trends
- summaries
- comparisons
- custom statistics

This classification is a more accurate extension model than the original document's binary direct-vs-analysis framing.

## 30.9 Source of Truth Note

Because the implementation has evolved after this document was first written:

- treat this document as architecture guidance, not a guaranteed exact snapshot
- for model names, quotas, and tool inventory, check the current code
- especially use these files as source of truth:
  - `lumie_backend/app/services/advisor_service.py`
  - `lumie_backend/app/services/analysis_service.py`
  - `lumie_backend/app/services/analysis_llm_service.py`
  - `lumie_backend/app/api/advisor_routes.py`
  - `lumie_backend/app/api/analysis_routes.py`
  - `lumie_activity_app/lib/features/advisor/screens/advisor_screen.dart`
