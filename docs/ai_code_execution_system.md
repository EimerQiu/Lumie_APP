# Lumie AI Data Analysis System

Backend Architecture & Development Requirements Specification

**Version**: v3.0
**Updated**: 2026-03-14
**Project**: Lumie Activity App (lumie_backend)

---

## Goal

Upgrade Lumie App's Advisor Chat **from a pure conversation system to an intelligent routing system**.

When a user sends any message in Advisor Chat → the backend calls Claude (with tool_use) → Claude decides on its own:

- **Direct reply**: casual chat, health advice, general questions → immediately return a text reply (same speed as current)
- **Data analysis**: questions requiring user data → Claude calls the `run_data_analysis` tool → backend starts an analysis job → generates code → Docker sandbox execution → returns conclusions + charts

The user does not need to know which path the system takes internally. For the user, chatting with the Advisor is a unified experience.

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

### System Requirements

- Direct reply response time must match the current Advisor (1-3 seconds)
- Data analysis must not block the API (async execution + frontend polling)
- AI-generated code **must not modify** business data (read-only access)
- Execution environment must be fully isolated (Docker container)
- Must comply with Lumie's **teen-safe** design principles (no calories, BMI, weight rankings, etc.)
- Must comply with Lumie's subscription tier limits
- LLM must have complete Lumie database schema and domain glossary context

---

# 1 System Architecture

```
Flutter App (Advisor Chat)
     │
     │  POST /api/v1/advisor/chat  (reuse existing endpoint, upgrade internal logic)
     ▼
FastAPI — advisor_service.py (upgraded)
     │
     ├── Claude API (with tool_use)
     │     │
     │     ├── No tool call → return reply directly (fast path)
     │     │
     │     └── Calls run_data_analysis tool → create analysis job
     │           │
     │           ▼
     │     AsyncIO Task Runner
     │           │
     │           ├── Claude API (code generation, separate call)
     │           │
     │           ▼
     │     Docker Sandbox Container
     │           │
     │           ├── Read-only MongoDB connection
     │           │
     │           ▼
     │     Write results to /output → write back to MongoDB
     │
     ▼
Response → Flutter
     │
     ├── type: "direct"   → display reply directly
     └── type: "analysis" → show "Analyzing...", start polling job status
```

### Component Responsibilities

| Component | Responsibility |
| --- | --- |
| FastAPI | API routing + JWT auth + intelligent routing |
| advisor_service.py (upgraded) | Claude tool_use call + routing decision + job creation |
| MongoDB (lumie_db) | Job metadata storage + business data source |
| AsyncIO Task | Async job execution (replaces Celery, keeps architecture simple) |
| Docker Sandbox | Isolated execution of AI-generated Python code |
| Claude API | Routing decision (tool_use) + code generation (separate call) |

### Key Design Decisions

**Why tool_use instead of two LLM calls?**

No need to call Claude once to "decide whether analysis is needed" and then again to execute. Claude's tool_use natively supports this routing: give it a `run_data_analysis` tool, and it will decide on its own whether to use it. A single call handles both routing and direct answers.

**Why not Celery + Redis?**

Lumie is currently deployed on a single Ubuntu server (54.177.85.124), managed via systemd, without Redis. Introducing Celery + Redis would significantly increase operational complexity. At the current user scale, Python asyncio + `asyncio.create_subprocess_exec` for managing Docker containers can handle concurrency needs. Migration to Celery can happen when the user base grows.

---

# 2 Tech Stack

New additions on top of existing lumie_backend:

```
New Python packages:
  docker          # Docker SDK for Python

Already available (reused directly):
  fastapi
  uvicorn
  motor           # async MongoDB
  pydantic
  anthropic       # Claude API (already used by advisor_service)
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

  "model": "claude-haiku-4-5-20251001",
  "token_usage": {
    "input_tokens": 0,
    "output_tokens": 0
  }
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

Request Body (backward-compatible, new optional fields):

```json
{
  "message": "What's my activity trend this month?",
  "history": [
    {"role": "user", "content": "..."},
    {"role": "assistant", "content": "..."}
  ],
  "target_user_id": "optional, used when parent analyzes child's data",
  "team_id": "optional, needed for parent scenarios"
}
```

### Backend Processing Flow

```python
async def advisor_chat(request, user_id):
    # 1. Get user profile (same as existing logic)
    profile = await get_profile(user_id)

    # 2. Build system prompt (upgraded version, includes tool definitions)
    system_prompt = build_advisor_system_prompt(profile)

    # 3. Define run_data_analysis tool
    tools = [RUN_DATA_ANALYSIS_TOOL]

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
        # Slow path: needs data analysis
        tool_input = extract_tool_input(response)

        # 5a. Check subscription quota (only analysis path needs checking)
        check_analysis_quota(user_id, subscription_tier)

        # 5b. Check parent permissions (if target_user_id specified)
        if target_user_id:
            verify_team_admin_access(user_id, target_user_id, team_id)

        # 5c. Create analysis job
        job_id = create_analysis_job(
            user_id=user_id,
            prompt=tool_input["question"],
            target_user_id=target_user_id or user_id,
        )

        # 5d. Start async execution
        asyncio.create_task(run_analysis_job(job_id))

        # 5e. Return analyzing response
        return {
            "type": "analysis",
            "reply": "Analyzing your data, please wait...",
            "job_id": job_id,
        }
```

### Response Format (Upgraded, Two Types)

**Direct reply (fast path):**

```json
{
  "type": "direct",
  "reply": "Hello! I'm your Lumie health advisor..."
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

### run_data_analysis Tool Definition

```python
RUN_DATA_ANALYSIS_TOOL = {
    "name": "run_data_analysis",
    "description": (
        "Call this tool when the user's question requires querying their personal health data to answer. "
        "Examples: activity trends, medication completion rates, heart rate analysis, walk test comparisons, etc. "
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

### Subscription Limits (Analysis Path Only)

Direct replies do not consume analysis quota. Only triggering the `run_data_analysis` tool is checked:

| Tier | Daily Analysis Limit |
| --- | --- |
| free | 3 |
| monthly (Pro) | 20 |
| annual (Pro) | 20 |

When the limit is exceeded, instead of returning a 403 error (since we're inside the existing chat endpoint), return:

```json
{
  "type": "direct",
  "reply": "You've used all your data analysis quota for today (3/3). Upgrade to Pro for 20 analyses per day. I can still help you with questions that don't require data lookup."
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
10. Write connection config to /tmp/lumie_sandbox/{job_id}/config.json

11. status → running

12. Start Docker sandbox container

13. Wait for container to exit (with timeout monitoring)

14. Read /tmp/lumie_sandbox/{job_id}/output/result.json

15. Write results to analysis_jobs.result

16. status → success (or failed)

17. Clean up temp directory
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
Call run_data_analysis ONLY when the user asks a question that requires querying their personal data:
- Activity trends, totals, or comparisons over time
- Task/medication completion rates or statistics
- Heart rate analysis
- Walk test progress
- Any question that asks about specific numbers/trends in their data

Do NOT call the tool for:
- General health advice or tips
- Greetings or small talk
- Questions about medical conditions (answer from knowledge)
- Emotional support or encouragement
- Questions you can answer without data

## Response guidelines
- Keep replies concise: 2–4 sentences unless a detailed explanation is clearly needed.
- Always acknowledge the user's condition and energy levels.
- Encourage consistency over intensity.
- Never replace medical advice — remind the user to check with their care team for anything clinical.
- Use warm, supportive language. Avoid being preachy.
- TEEN-SAFE: Never output calories, BMI, weight comparisons, or performance rankings.
- You may use **bold** to emphasise key words, but do not use bullet points, numbered lists, or headers."""
```

**Model choice**: Layer 1 uses `claude-sonnet-4-20250514` (needs tool_use capability + fast response; Sonnet is the best balance. The current advisor uses Opus which is too slow; Haiku's tool_use judgment is not accurate enough).

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
        target_user_id=target_user_id,
        question=question
    )
```

**Model choice**: Layer 2 uses `claude-haiku-4-5-20251001` (only needs to generate Python code; Haiku is fast and cost-effective).

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
        "open_datetime": "string, start time 'YYYY-MM-DD HH:mm' (note: no Z suffix, stored as local time)",
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
tools = [RUN_DATA_ANALYSIS_TOOL]
```

### Layer 2: Code Generation (analysis_llm_service.py, new)

```python
model = "claude-haiku-4-5-20251001"    # Sufficient for code generation, fast, cost-effective
temperature = 0                         # Deterministic output
max_tokens = 4000                       # Analysis code tends to be long
```

Output must be **pure Python code**. The worker must strip markdown code block markers (` ```python `, etc.).

If Claude's output is not valid Python code, job status → failed, error = "code_generation_failed".

### Cost Estimate

| Path | Model | Estimated tokens/call | Cost/call |
| --- | --- | --- | --- |
| Direct reply | Sonnet | ~1500 input + ~200 output | ~$0.006 |
| Data analysis | Sonnet + Haiku | ~1500 + ~3000 input, ~100 + ~2000 output | ~$0.015 |

The direct reply path is actually cheaper compared to the current Advisor (Opus) — Sonnet is roughly 5x cheaper than Opus.

---

# 13 LLM Call Rate Limiting

Uses in-memory rate counters (per user_id):

```python
# Max 2 LLM calls per user per minute
# Max 5 LLM calls globally per second (to protect Anthropic API quota)
```

Exceeding rate limits returns 429 Too Many Requests.

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
container = docker_client.containers.run(
    image="lumie-analysis-sandbox",
    command=["python", "main.py"],
    detach=True,
    mem_limit="256m",
    cpu_quota=50000,          # 0.5 CPU
    pids_limit=32,
    network_mode="bridge",    # Needs MongoDB access, but restrict other network
    read_only=True,
    volumes={
        f"/tmp/lumie_sandbox/{job_id}/main.py": {
            "bind": "/app/main.py", "mode": "ro"
        },
        f"/tmp/lumie_sandbox/{job_id}/output": {
            "bind": "/output", "mode": "rw"
        }
    },
    environment={
        "MONGO_URI": SANDBOX_MONGO_URI,       # Read-only user connection
        "TARGET_USER_ID": target_user_id,
    },
    tmpfs={"/tmp": "size=64m,noexec"},
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
 │   └── analysis_routes.py          ← New: analysis job query/cancel routes
 │
 ├── services/
 │   ├── advisor_service.py          ← Modified: add tool_use + routing logic
 │   ├── analysis_service.py         ← New: job management + execution flow
 │   ├── analysis_llm_service.py     ← New: Claude code generation (Layer 2)
 │   ├── analysis_prompt_service.py  ← New: prompt context assembly
 │   ├── analysis_sandbox_service.py ← New: Docker container management
 │   └── analysis_security_service.py← New: code security scanning
 │
 ├── models/
 │   ├── advisor.py                  ← Modified: upgraded response model (add type + job_id)
 │   └── analysis.py                 ← New: analysis job Pydantic models
 │
 ├── resources/
 │   ├── schema/
 │   │   └── lumie_schema.json       ← New: Lumie database schema
 │   └── glossary.md                 ← New: domain glossary
 │
 └── main.py                         ← Modified: register analysis_routes

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
app.include_router(analysis_router, prefix="/api/v1/analysis", tags=["analysis"])
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
      return AdvisorResponse.direct(reply: data['reply']);
    }
  }
}

/// Unified Advisor response type
class AdvisorResponse {
  final String type;     // "direct" or "analysis"
  final String reply;
  final String? jobId;

  AdvisorResponse.direct({required this.reply})
      : type = 'direct', jobId = null;

  AdvisorResponse.analysis({required this.reply, required this.jobId})
      : type = 'analysis';
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
      _messages.add(_Message(text: response.reply, isUser: false));
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

  _Message({
    required this.text,
    required this.isUser,
    this.isAnalyzing = false,
    this.jobId,
    this.analysisResult,
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
3.  advisor.py (models)     — Upgrade: AdvisorChatResponse adds new fields
4.  database.py             — Add analysis_jobs indexes
5.  main.py                 — Register analysis_routes

New files:
6.  analysis_routes.py      — 3 API endpoints (query/cancel/history)
7.  analysis_service.py     — Job lifecycle management + asyncio execution
8.  analysis_llm_service.py — Claude code generation (Layer 2 LLM call)
9.  analysis_prompt_service.py — Schema + Glossary + Profile assembly
10. analysis_sandbox_service.py — Docker container creation/monitoring/cleanup
11. analysis_security_service.py — Static code security scanning
12. analysis.py (models)    — Analysis job Pydantic models
13. lumie_schema.json       — Lumie database schema definition
14. glossary.md             — Domain glossary mapping
15. sandbox/Dockerfile      — Sandbox image definition
16. Subscription limit check — Free: 3/day, Pro: 20/day (analysis path only)
17. Permission check        — Parent viewing child's data requires team admin role
```

### Frontend (Flutter / Dart)

```
Modified existing files:
1.  advisor_service.dart    — Handle new response type (direct / analysis)
2.  advisor_screen.dart     — _send() upgrade: support two response paths
3.  _Message class          — Add isAnalyzing, jobId, analysisResult fields

New files:
4.  analysis_service.dart   — Analysis job polling logic
5.  analysis_models.dart    — AnalysisResult, AnalysisJob Dart models
6.  analysis_result_card.dart — Analysis result card widget (text + chart + data)
```

### Deployment

```
1.  Install Docker on server
2.  Build sandbox image
3.  Create MongoDB read-only user
4.  Update .env environment variables
5.  Configure MongoDB network
6.  Deploy backend code
```

### User Experience After Completion

```
User chats with Advisor → system automatically decides:
  → General questions: direct reply within 1-3 seconds (same speed as current)
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
| Advisor Chat (`advisor_service.py`) | **Direct upgrade**: from pure conversation to intelligent routing; core file of this change |
| Advisor Routes (`advisor_routes.py`) | **Modified**: response model extended, endpoint URL unchanged |
| AI Tips (`ai_tips_service.py`) | Complementary: Tips provide simple statistics (fast, lightweight); analysis system handles custom questions |
| Team System (`team_service.py`) | Reuses team permission check logic; parents can analyze child data |
| Subscription (`subscription_helpers.py`) | Reuses subscription tier check (only analysis path counts) |
| Auth (`security.py`) | Reuses JWT auth and `get_current_user_id` |
| Profile (`profile_service.py`) | Reads user profile as context for both LLM layers |

### Model Usage Changes

| Scenario | Before | After |
| --- | --- | --- |
| Advisor conversation | Opus (`claude-opus-4-6`), max_tokens=400 | Sonnet (`claude-sonnet-4-20250514`), max_tokens=800, with tool_use |
| AI Tips | Haiku, max_tokens=150 | Unchanged |
| Data analysis code generation | Did not exist | Haiku, max_tokens=4000 |

The Advisor downgrade from Opus to Sonnet is intentional: Sonnet's tool_use judgment is accurate enough, response time is faster (~1s vs ~3s), and cost is lower (~1/5). Conversation quality at the Sonnet level is already sufficient.
