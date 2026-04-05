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
      description: "Natural language synthesis of overall health picture from all domains"
    data:
      type: object
      description: "Raw aggregated data from all domains (for reference)"
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

4. Use LLM to synthesize AGGREGATE insights:
   - Input: combined_context (all health data)
   - LLM task: "Analyze combined data for cross-domain patterns and aggregate insights"
   - Focus: NOT "here's sleep, here's activity" but "sleep is low AND activity is low, suggesting fatigue"
   - Output: structured `_result` with summary (no domain-by-domain fields)

5. Return structured result:
   ```python
   _result = {
       "summary": "LLM-generated summary",
       "data": combined_context,
   }
   ```

# Output Structure

Return a dict with only:
- `summary`: 2-4 paragraph natural language synthesis analyzing the **combined** health picture
  - Focus on **aggregate insights** (patterns that emerge from all domains together)
  - NOT a domain-by-domain breakdown (that's what health_data_query provides)
  - Highlight how domains interact: e.g., "Low activity combined with poor sleep suggests fatigue"
  - Flag multi-domain concerns: e.g., "Elevated fatigue + inconsistent activity + medication gaps"
  - Include trend observations and any anomalies
- `data`: Raw aggregated data structure (for reference/debugging)

# How to Implement

**LLM Synthesis Approach**

```python
from ..services.llm_client import chat_completion
import json

# Extract data from previous_results
combined_context = {
    "sleep": {...},
    "activity": {...},
    "hrv": {...},
    "steps": {...},
    "medications": {...},
}

# Call LLM to synthesize AGGREGATE insights only
response = await chat_completion(
    model="openai/gpt-5.4",
    max_tokens=1000,
    messages=[{
        "role": "user",
        "content": f"""Analyze this multi-domain health data and provide a comprehensive synthesis.

IMPORTANT: Focus on AGGREGATE insights only, not domain-by-domain findings.

Analyze:
- Overall health picture combining all domains
- Patterns and relationships that emerge across domains
- How domains interact (e.g., does poor sleep explain low activity?)
- Multi-domain concerns or anomalies
- Health trajectory (improving/declining/stable)

Do NOT provide separate findings for each domain. Instead, synthesize into 
a cohesive narrative of overall health status and cross-domain patterns.

Health Data:
{json.dumps(combined_context, indent=2, default=str)}

Provide a 2-4 paragraph natural language synthesis."""
    }],
)

_result = {
    "summary": response.text,
    "data": combined_context,
}
```
```

# No Database Queries, No Domain-by-Domain Breakdown

This skill does **NOT**:
- Query the database directly (all data comes from `previous_results`)
- Provide domain-by-domain insights (that's health_data_query's job)
- Need timezone handling (already done in health_data_query)
- Need complex aggregation logic

The skill's **only job**: **Synthesize aggregate insights using LLM**

The LLM receives raw data from all 5 domains and identifies cross-domain patterns:
- What does the combined picture tell us?
- How do domains interact?
- What anomalies stand out across all data?
- What is the overall health trajectory?

# Proactive Mode Guidance

When used in proactive advisor checks, this skill synthesizes 5 focused health queries into aggregate insights. The result feeds into the proactive decision LLM, which evaluates whether to nudge based on:

- Multi-domain concerns (e.g., poor sleep + low activity together)
- Cross-domain patterns that suggest a trend (e.g., fatigue manifesting across HRV + activity)
- Anomalies in the combined picture (not just single-domain outliers)
- Overall health trajectory from the aggregate data

The comprehensive summary allows the decision LLM to see the "whole person" health status, not just isolated metrics.

# Failure Handling
- If any of the 5 health_data_query calls failed, their data will be empty — continue synthesis with available data
- If ALL 5 failed, skill should return "no_data" status
- DB errors in previous_results should be visible in their status field — inspect and aggregate what's available
