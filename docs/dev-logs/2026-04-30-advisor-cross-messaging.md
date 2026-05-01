# Advisor Cross-User Messaging & Pending Action (MVP)

Date: 2026-04-30
Design: [docs/advisor_cross_advisor_pending_action_design.en.md](../advisor_cross_advisor_pending_action_design.en.md)

## Summary

Foundational mechanism for one user's advisor to send a structured action
request to another user's advisor, with mandatory human confirmation on the
receiving side before any write happens. MVP supports a single
`action_type` — `tasks_complete` — so we can validate the end-to-end flow
without building speculative infrastructure for other actions.

End-to-end flow (B requests, A confirms):

1. B chats: "complete Eimer's task xxx"
2. Orchestrator(B) → LLM tool sets `cross_advisor_action_type=tasks_complete` +
   `cross_action_params.task_id` + `target_user_hint`
3. `advisor_cross_message_service.create_request` writes an `action_request`
   row, B's read-only collab thread is seeded
4. Receiver-side processing (inline, MVP) posts a templated confirmation
   question into A's main session and creates an
   `awaiting_user_confirm` pending action
5. A replies "yes" → `_resume_cross_advisor_after_user_reply` classifies,
   marks `approved`, kicks off `tasks_complete` execution job carrying a
   `cross_advisor_context`
6. `execution_service._complete_job` (or `_fail_job`) posts an
   `execution_result` cross-message + collab audits to both sides

## Decisions made

- **No new public endpoints.** Both initiation and confirmation reuse
  `POST /api/v2/advisor/chat`. Avoids permission surface area and keeps the
  flow inside the orchestrator that already owns chat routing.
- **Single LLM tool field, not a separate router.** Added
  `cross_advisor_action_type` + `cross_action_params` fields to the existing
  `route_response` tool rather than a second pre-classification call.
  Simpler, one fewer LLM hop; user explicitly chose option (a) when planning.
- **Receiver-side LLM reasoning skipped for MVP.** §2.1 mandates
  `require_confirmation=true` for any cross-user write, so a templated
  confirmation question is sufficient. The §8 contract is documented for
  later; not needed to test the wiring.
- **Inline delivery instead of a worker.** B and A are served by the same
  process. `create_request` returns `delivered`, then receiver-side
  processing runs synchronously inside B's chat request. We can extract a
  worker later if cross-process delivery becomes real.
- **Read-only guard runs *before* the orchestrator.** Per §13.5 the
  collab-thread guard cannot rely on LLM behavior — it lives in the route
  handler and short-circuits with 409.
- **Collab thread = one chat session per user, channel-tagged.**
  No new collection. `chat_messages` rows with
  `metadata.channel="advisor_collab"` form the audit trail; the session id
  uses the `collab:{thread_id}` convention so it groups correctly under
  the existing `get_sessions` aggregation.
- **Reuse the existing `advisor_pending_actions` collection.** Added a
  `thread_id` index and a new `action_type="cross_advisor_action_confirmation"`
  rather than introducing a parallel pending table.
- **Idempotency key.** `tasks_complete:{requester}:{target}:{task_id}` so a
  user spamming the same request collapses to a single open thread.
- **MVP single action.** Only `tasks_complete` is wired through. Other
  `cross_advisor_action_type` values are rejected with a guidance reply.

## New files (backend)

- [lumie_backend/app/models/advisor_cross_message.py](../../lumie_backend/app/models/advisor_cross_message.py)
  — Pydantic models + enums: `CrossMessageType`, `CrossMessageStatus`,
  `CrossActionType`, `CrossMessagePayload`, `AdvisorCrossMessage`,
  `CrossAdvisorPendingActionStatus`.
- [lumie_backend/app/services/advisor_cross_message_service.py](../../lumie_backend/app/services/advisor_cross_message_service.py)
  — message lifecycle (create_request / create_decision_reply /
  create_execution_result), status transitions with terminal-state guards,
  thread query, idempotency, and a `sanitize_summary` helper for collab
  audit content (§13.6).

## Modified files

### Backend
- [lumie_backend/app/core/database.py](../../lumie_backend/app/core/database.py)
  — added `advisor_cross_messages` indexes (message_id unique,
  thread_id+created_at, to_user+status, from_user+created_at,
  expires_at, sparse unique idempotency_key) and
  `advisor_pending_actions.thread_id` index.
- [lumie_backend/app/services/advisor_orchestrator.py](../../lumie_backend/app/services/advisor_orchestrator.py)
  — added cross-advisor pending helpers
  (`_get_pending_cross_advisor_action`, `_create_cross_advisor_pending_action`,
  `_set_cross_advisor_pending_status`), a keyword-based confirmation
  classifier (`_classify_user_confirmation`), a collab-audit writer
  (`_post_collab_audit`), three new `handle_chat` branches
  (resume after user confirm; intercept cross-advisor write intent;
  ignored otherwise), and the `_initiate_cross_advisor_request` /
  `_process_incoming_cross_request` / `_resume_cross_advisor_after_user_reply`
  handlers. Extended the `route_response` LLM tool with
  `cross_advisor_action_type` + `cross_action_params`.
- [lumie_backend/app/services/execution_service.py](../../lumie_backend/app/services/execution_service.py)
  — `create_execution_job` now accepts `cross_advisor_context`. New
  `_maybe_send_cross_advisor_callback` is invoked from `_complete_job` and
  `_fail_job` to write the `execution_result` cross-message and update
  both sides' collab audit threads.
- [lumie_backend/app/services/chat_history_service.py](../../lumie_backend/app/services/chat_history_service.py)
  — `get_sessions()` aggregation now surfaces `channel`, `readonly`,
  `thread_id`, `collab_status`, `peer_user_id` from the latest message's
  metadata. Defaults preserve back-compat for legacy sessions.
- [lumie_backend/app/api/advisor_v2_routes.py](../../lumie_backend/app/api/advisor_v2_routes.py)
  — added `_is_session_readonly()` guard that runs before
  `advisor_orchestrator.handle_chat`; returns 409 on read-only collab
  sessions per §13.5.
- [lumie_backend/app/api/chat_history_routes.py](../../lumie_backend/app/api/chat_history_routes.py)
  — extended `SessionSummaryResponse` with collab metadata fields.

### Frontend (Flutter)
- [lumie_activity_app/lib/core/services/chat_history_service.dart](../../lumie_activity_app/lib/core/services/chat_history_service.dart)
  — `SessionSummary` now carries `channel`, `readonly`, `threadId`,
  `collabStatus`, `peerUserId` with `isCollabThread` helper.
- [lumie_activity_app/lib/features/advisor/screens/advisor_screen.dart](../../lumie_activity_app/lib/features/advisor/screens/advisor_screen.dart)
  — `_HistoryPanel` callback signature now passes `readonly`. Collab
  sessions render the fixed label "Advisor Collaboration Record" + a
  `collab_status` subtitle. New `_isReadonlySession` state replaces the
  input area with the fixed message
  "This is an Advisor collaboration record and is view-only." and gates
  `_send()`.

## API surface

No new endpoints. Behavior changes:

- `POST /api/v2/advisor/chat`: now returns **409 Conflict** with
  `detail="This advisor collaboration thread is read-only."` when the
  target session was last written as `metadata.channel=advisor_collab` or
  `metadata.readonly=true`.
- `GET /api/v2/advisor/sessions`: response items gain optional fields
  `channel` (default `"advisor_user"`), `readonly` (default `false`),
  `thread_id`, `collab_status`, `peer_user_id`. Existing clients continue
  to work because new fields default safely.

## DB collections / indexes

New collection: `advisor_cross_messages`. Indexes:

| Index | Purpose |
|---|---|
| `message_id` (unique) | direct lookup |
| `(thread_id, created_at)` | thread reconstruction |
| `(to_user_id, status)` | receiver-side queue scan |
| `(from_user_id, created_at desc)` | requester audit |
| `expires_at` | future TTL/expiry sweep |
| `idempotency_key` (unique, sparse) | dedupe identical requests |

Extended collection: `advisor_pending_actions` — added `thread_id` index for
resume lookups by thread.

Schema additions on `chat_messages.metadata`:
`channel`, `readonly`, `thread_id`, `collab_status`, `peer_user_id`.
No migration needed — legacy rows fall back to `channel="advisor_user"`,
`readonly=false`.

`execution_jobs` documents now optionally carry `cross_advisor_context`
(thread_id, source_message_id, requester_user_id, approver_user_id,
action_type, action_params).

## Testing checklist

Acceptance criteria (§11):

- [ ] Before A confirms, A-advisor does not run any write — verified by
      checking that no `tasks_complete` execution job exists with
      `cross_advisor_context` until the user replies "yes".
- [ ] After A confirms, A-advisor executes and posts result back into the
      collab thread on both sides.
- [ ] Execution result reaches B-advisor's thread with the same
      `thread_id`.
- [ ] Full chain traceable:
      `advisor_cross_messages` row → `advisor_pending_actions` row →
      `execution_jobs` row → audit messages in `chat_messages`.
- [ ] `max_turns=5` terminates the thread cleanly with a user-facing
      explanation written into both collab audits.

End-to-end manual scenarios:

1. **Happy path.** B (admin) chats "complete Eimer's task abc-123". B sees
   "I've passed your request to that user's advisor…". A's main session
   shows the confirmation question. A replies "yes". B's collab thread
   updates to `done` with the result summary; A's main session shows the
   completion summary.
2. **Reject path.** Same setup, A replies "no". A sees "Understood…".
   B's collab thread shows "The peer declined the request." with status
   `done`.
3. **Self-target rejection.** B chats "complete my task abc". LLM should
   not set `cross_advisor_action_type`; if it does, the orchestrator
   short-circuits with a guidance reply.
4. **Read-only guard.** Open the collab thread on either side; sending a
   message returns 409 from the API and the input box is hidden in the
   Flutter UI.
5. **Idempotency.** B sends the same complete-task request twice in a
   row. Only one cross-message row appears; only one pending action is
   created.
6. **History list rendering.** B and A both see the collab session in
   their history list with the "Advisor Collaboration Record" label and
   the latest `collab_status`.

Backend: `python3 -m py_compile` passes on all modified files.
Frontend: `flutter analyze` passes (only pre-existing warnings).

## Future work / what's deferred

- **LLM-based receiver reasoning (§8 contract).** Currently the receiver
  uses a templated question. When we expand beyond `tasks_complete`, swap
  in a structured-tool LLM call that produces `needs_confirmation`,
  `question_to_user`, `decision_hint`, `reason`.
- **Push notifications on confirmation request.** §3 step 4 mentions
  push; we write the chat message, but wiring through APNs is left for
  the existing notifications pipeline to pick up via the assistant write.
- **A-advisor → B-advisor outbound clarification (§3.1).** The helper
  scaffolding (`create_decision_reply` with `decision="ask_more"`) is in
  place but no LLM path triggers it yet.
- **Background expiry sweeper.** `expires_at` indexes exist on both
  `advisor_cross_messages` and `advisor_pending_actions` but no scheduled
  job transitions them to `expired`. Add when we have a scheduler.
- **Additional `action_type` values.** `tasks_create_for_peer`,
  `event_schedule_for_peer`, etc. The model and routing branch are
  ready; each new action_type needs a skill mapping in
  `_resume_cross_advisor_after_user_reply`.
- **Per-team admin permission check (§9.1).** Today `_resolve_target_user_hint`
  already restricts hints to teammates the requester admins. The
  cross-advisor path inherits that, but we should add an explicit check
  in `_initiate_cross_advisor_request` for clarity once we expand
  action_types.
- **Audit-log row.** §11 lists "audit logs" but the existing
  `execution_audit_logs` collection is not yet written from the
  cross-advisor path. The collab thread + cross-message + execution_job
  rows already cover traceability; a dedicated audit row can be added if
  needed for compliance reporting.
