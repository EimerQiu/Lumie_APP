# Advisor Multi-Turn Skill Retrieval Fix — 2026-04-27

## Summary
Fixed a bug where the advisor would claim "task creation isn't available in my current tools" mid-conversation. Root cause: skill candidate retrieval scored only the latest user message, so multi-turn flows where a follow-up reply contained no skill keywords (e.g., user replying "Yumo Family team") dropped `tasks_create` out of the candidate list. The LLM then truthfully reported the missing capability.

## Decisions Made

### 1. Score retrieval against recent user turns + current message
- **Decision:** Build the `retrieve_top_k` query from the last 3 user messages plus the current message, joined as a single string.
- **Reason:** Skill keyword scoring needs the original-intent words ("create task", "reminder") that live in earlier turns. Without them, a clarification reply like "Yumo Family team" tokenizes only to `{yumo, family, team}` and surfaces `team_member_health_snapshot` instead of `tasks_create`.
- **Why user turns only (not assistant turns):** The assistant's own clarification questions ("What team?") would re-introduce the same biasing tokens that broke retrieval in the first place. User turns reflect actual intent.
- **Why 3 turns:** Empirically enough to cover a typical clarification chain without diluting the most recent message's signal.

### 2. Pending-flow guard for `tasks_create`
- **Decision:** When `pending_task_create` is set (a clarification round is awaiting input) and `tasks_create` is missing from the candidate set, prepend it from the registry.
- **Reason:** Belt-and-braces. Even if scoring still drops `tasks_create`, the orchestrator already knows we're mid-flow on a task-create clarification — that's strictly stronger evidence than keyword overlap.
- **Truncation:** Cap candidates at 8 (`[tasks_create, *candidates[:7]]`) to preserve the existing top-k size.

### 3. Did NOT change `tool_choice` to `"required"`
- **Considered:** Forcing the LLM to call `route_response` every turn so it can't escape into freeform prose claiming missing capabilities.
- **Why deferred:** The two changes above address the root cause (visibility of `tasks_create`). Forcing tool calls is a guardrail for a different failure mode and worth doing separately if we see prose-only replies recur.

### 4. Did NOT add `team`/`family` to `tasks_create.md` keywords
- **Considered:** Adding multi-turn-signal words as a band-aid.
- **Why rejected:** Treats the symptom. The real fix is using conversation context for retrieval, which generalizes across all multi-turn skills (not just `tasks_create`).

## New Files Created
None.

## Modified Files

### `lumie_backend/app/services/advisor_orchestrator.py`
- `handle_chat()` Step 2: replaced `query=message` with a query built from up to 3 recent user turns + the current message.
- Added a post-retrieval guard: if `pending_task_create` is set and `tasks_create` is not in candidates, fetch it from `skill_registry` and prepend.

## API Endpoints Added
None.

## New DB Collections / Indexes
None.

## Testing Checklist
- [ ] Single-turn task creation (e.g., "Add a medicine task tomorrow at 8 AM") still routes to `tasks_create`.
- [ ] Multi-turn flow: ask "create a task", supply task details, then supply only "Yumo Family team" — `tasks_create` stays in candidates and the assistant proceeds instead of claiming missing tools.
- [ ] Non-task multi-turn flows (e.g., health queries) are not biased toward `tasks_create` by the new retrieval query.
- [ ] Sessions with no history (first message) behave identically to before.
- [ ] Pending guard does not double-insert `tasks_create` when scoring already includes it.

## Future Work / Deferred
- **`tool_choice="required"`** — Forces the LLM to always call `route_response` instead of returning prose. Would prevent any future hallucinated "I don't have that tool" replies regardless of candidate scoring. Not done yet because the current fix should remove the trigger; revisit if prose-only replies recur in production.
- **Generalize the pending-flow guard** — Right now it's hard-coded for `tasks_create`. If other skills grow multi-turn clarification flows, factor this into a generic mechanism keyed on `pending_action.skill_id`.
- **Broaden `_looks_like_schedule_detail`** — Currently only matches time-related words; a follow-up that names a team/member is also a "more detail" signal. Worth revisiting once we see real-world traces.
