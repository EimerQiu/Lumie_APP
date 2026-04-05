---
skill_id: comprehensive_health_assessment
title: Comprehensive Health Assessment
capability_id: lumie_internal_data
runtime_type: lumie_db
requires_ping: true
requires_credentials: true
target_system: lumie_db
tags: [health, sleep, activity, hrv, rhr, medication, tasks, walk_test, comprehensive, overall, report]
keywords: [health summary, recent condition, daughter health, overall health, how is she doing, how am I doing, weekly summary, health report, overall report, full report, comprehensive, everything, all health data, how have I been, how has she been, give me a summary]
summary: Multi-domain health report combining sleep, activity, HRV, medication adherence, and walk tests. Synthesizes data from multiple health_data_query calls using LLM. Use for broad "how am I doing overall" questions.
proactive_eligible: true
proactive_domain: activity
proactive_priority: 80
proactive_mode: assessment
allowed_connectors: [lumie_db_connector]
dependencies:
  - skill_id: health_data_query
    calls:
      - domain: sleep
      - domain: activity
      - domain: hrv
      - domain: steps
      - domain: medications
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
Use this skill when the user asks for an overall health view that spans multiple Lumie data domains. This is the go-to skill for broad health questions like "how has my daughter been doing?" or "give me a health summary."

This skill **depends on** prior execution of `health_data_query` for 5 domains (sleep, activity, hrv, steps, medications). The execution system runs those queries first, then passes their results to this skill for synthesis.

# When To Use
- The user asks how they or their child have been doing recently
- The question requires combining sleep, activity, HRV/RHR, and medication/task adherence
- Parent asks about a team member's overall health
- Any request for a comprehensive or multi-domain health report

# Architecture (DAG Execution)

This skill is part of a **skill dependency chain**:

1. **Tier 1 (parallel)**: Run 5 health_data_query calls
   - `health_data_query(domain=sleep)` → sleep data
   - `health_data_query(domain=activity)` → activity data
   - `health_data_query(domain=hrv)` → HRV/RHR data
   - `health_data_query(domain=steps)` → step data
   - `health_data_query(domain=medications)` → medication adherence data

2. **Tier 2 (after Tier 1)**: Run comprehensive_health_assessment
   - Receives all 5 results from previous tier
   - Aggregates into single health context
   - Uses LLM to synthesize into narrative summary

# Execution Plan

1. Receive `previous_results` dictionary containing:
   ```python
   {
       "health_data_query_sleep": ProactiveSkillData(...),
       "health_data_query_activity": ProactiveSkillData(...),
       "health_data_query_hrv": ProactiveSkillData(...),
       "health_data_query_steps": ProactiveSkillData(...),
       "health_data_query_medications": ProactiveSkillData(...),
   }
   ```

2. Extract data from each skill result:
   ```python
   sleep_data = previous_results.get("health_data_query_sleep", {}).get("data", {})
   activity_data = previous_results.get("health_data_query_activity", {}).get("data", {})
   hrv_data = previous_results.get("health_data_query_hrv", {}).get("data", {})
   steps_data = previous_results.get("health_data_query_steps", {}).get("data", {})
   meds_data = previous_results.get("health_data_query_medications", {}).get("data", {})
   ```

3. Aggregate into single context:
   ```python
   combined_context = {
       "sleep": sleep_data,
       "activity": activity_data,
       "hrv": hrv_data,
       "steps": steps_data,
       "medications": meds_data,
   }
   ```

4. Use LLM to synthesize into comprehensive narrative:
   - Input: combined_context (all health data)
   - LLM task: "Synthesize this health data into a 2-3 paragraph natural language summary"
   - Output: structured `_result` with summary + sections

5. Return structured result:
   ```python
   _result = {
       "summary": "LLM-generated summary",
       "data": combined_context,
   }
   ```

# Output Structure

Return a dict with:
- `summary`: Natural language overview (2-3 sentences) of overall health picture
- `sleep`: Sleep trends and latest session
- `activity`: Activity totals and recent patterns
- `hrv`: Heart rate variability and fatigue signals
- `steps`: Daily step patterns and trends
- `medications`: Task/medication adherence

# How to Implement

**Option 1: Simple LLM Synthesis (Recommended)**

```python
from ..services.llm_client import chat_completion
import json

# Extract data from previous_results (see Execution Plan step 2-3 above)
combined_context = {...}

# Call LLM to synthesize
response = await chat_completion(
    model="openai/gpt-5.4",
    max_tokens=1500,
    messages=[{
        "role": "user",
        "content": f"""Synthesize this health data into a comprehensive health assessment.
        
Health Data:
{json.dumps(combined_context, indent=2, default=str)}

Provide:
1. A 2-3 sentence summary of overall health status
2. Key findings from each domain (sleep, activity, HRV, steps, medications)
3. Any notable trends or concerns
4. Recommendations for follow-up

Format as JSON with fields: summary, sleep_insights, activity_insights, hrv_insights, steps_insights, medications_insights, trends, recommendations"""
    }],
)

result_data = json.loads(response.text)
_result = {
    "summary": result_data.get("summary", ""),
    "data": combined_context,
    **result_data,  # Include all LLM-generated fields
}
```

**Option 2: Simple Aggregation + LLM Call**

```python
# Build simple aggregate
_result = {
    "summary": f"Sleep: {combined_context['sleep'].get('avg_minutes')} min/night. "
               f"Activity: {combined_context['activity'].get('total_minutes')} min this week. "
               f"Medications: {combined_context['medications'].get('adherence')} adherence.",
    "sleep": combined_context.get("sleep", {}),
    "activity": combined_context.get("activity", {}),
    "hrv": combined_context.get("hrv", {}),
    "steps": combined_context.get("steps", {}),
    "medications": combined_context.get("medications", {}),
}
```

# No Database Queries Needed

This skill does **NOT** query the database directly. All data comes from `previous_results` (already fetched by `health_data_query` calls in Tier 1). This eliminates:
- No timezone handling needed (already done in health_data_query)
- No collection queries needed
- No aggregation logic needed
- No complex data parsing needed

The skill's job is purely: **aggregate + synthesize**.

# Proactive Mode Guidance

When used in proactive advisor checks, this skill synthesizes 5 focused health queries into a complete picture. The LLM/decision model then evaluates whether to nudge based on:

- Multiple domains showing concerning patterns simultaneously
- Trends (not single-day fluctuations)
- Contextual thresholds (e.g., lower thresholds for users with chronic conditions)

See downstream LLM decision logic for nudge thresholds.

# Failure Handling
- If any of the 5 health_data_query calls failed, their data will be empty — continue synthesis with available data
- If ALL 5 failed, skill should return "no_data" status
- DB errors in previous_results should be visible in their status field — inspect and aggregate what's available
