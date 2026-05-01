# Lumie Advisor Cross-User Messaging & Pending Action Mechanism (MVP)

Version: v1.0  
Date: 2026-04-30  
Scope: `lumie_backend` (primary), `lumie_activity_app` (minimal companion)

## 1. Goals and Current State

### 1.1 Existing System (Already Implemented)
1. `advisor_orchestrator.handle_chat`: handles advisor chat routing and LLM-based skill decisions.
2. `execution_service` + `execution_jobs`: handles actual skill/action execution.
3. `advisor_pending_actions`: already used for "collect missing info and resume" workflows.
4. `chat_history_service`: persists user-advisor conversation messages.

### 1.2 New Goal in This Iteration
Build a foundational "Advisor A <-> Advisor B" communication mechanism so that:
1. One advisor can send a structured request to another user's advisor.
2. The receiving advisor must reason over the request via LLM and decide whether user confirmation is needed.
3. If confirmation is needed, create a pending action and ask the receiving user.
4. After user confirmation is collected, resume and continue execution.

## 2. Core Business Rules (Strict)

1. For any cross-user write operation request, default `require_confirmation=true` (human confirmation required).
2. The confirmer is always the receiving user (`to_user`), never the requesting user.
3. The executor is always the receiving advisor (`receiver advisor`); the requester advisor only sends requests and receives result callbacks.
4. Multi-turn advisor-to-advisor conversation is supported: the same request chain must reuse the same `thread_id`.
5. A hard termination condition is required: end the thread when `max_turns` is reached (default 5) or when thread timeout occurs.

## 3. End-to-End Sequence (Based on Your Example)

Example: `B-advisor -> A-advisor: complete B's task(task_id=xxxxx)`

1. B-advisor creates a cross-advisor request message (status `queued`).
2. The system delivers it to A-advisor (status `delivered`).
3. A-advisor parses and reasons with LLM, and decides this requires A user's confirmation.
4. The system creates a pending action (`awaiting_user_confirm`) and asks A user.
5. A user replies with "agree/yes/okay".
6. The system matches the pending action and records `approved`.
7. A-advisor (receiver advisor) resumes the execution pipeline and calls existing `execution_service` to execute the task completion action.
8. The system sends execution result callback to B-advisor.
9. Execution result is recorded back to A-advisor and B user's session (both success and failure must be auditable).

## 3.1 A-advisor Asks B-advisor and Then Continues Processing (Call Order)

1. A user's message enters `/api/v2/advisor/chat`.  
2. `advisor_orchestrator(A)` determines B-advisor info is needed, then calls `advisor_cross_message_service.create_request(...)`.  
3. On A side, create/update `advisor_pending_actions` as `awaiting_peer_reply`, with `resume_payload`.  
4. After B receives the request, `advisor_orchestrator(B)` reasons with LLM over request + context and generates a reply.  
5. `advisor_cross_message_service.create_reply(...)` writes reply into the same `thread_id`.  
6. A side updates pending action to `peer_replied`.  
7. `advisor_orchestrator(A)` resumes original flow using `resume_payload + B reply`.  
8. If more clarification from B is still needed, continue next turn under the same `thread_id`; otherwise execute or end.

## 4. Data Model (New)

### 4.1 `advisor_cross_messages`
Fields:
1. `message_id` (uuid, unique)
2. `thread_id` (uuid)
3. `from_user_id` / `to_user_id`
4. `from_advisor_id` / `to_advisor_id` (MVP may use fixed value `default` initially)
5. `message_type`: `action_request|decision_reply|execution_result`
6. `payload`:
- `action_type` (e.g., `tasks_complete`)
- `action_params` (task_id, name, opentime, reason, ...)
- `require_confirmation` (bool)
- `decision` (approve/reject/null)
- `execution_result` (success/error/summary)
7. `status`: `queued|delivered|processed|failed|expired`
8. `idempotency_key` (optional)
9. `created_at` / `updated_at` / `expires_at` (optional)

### 4.2 `advisor_pending_actions` (Reuse + Extend)
New/normalized fields:
1. `action_type`: `cross_advisor_action_confirmation`
2. `source_message_id`
3. `thread_id`
4. `requester_user_id` (who initiated)
5. `approver_user_id` (who confirms)
6. `resume_payload` (data needed to resume after confirmation)
7. `status`: `awaiting_user_confirm|approved|rejected|expired|consumed`
8. `turn_count` (current advisor-to-advisor turn count)
9. `max_turns` (default 5)

## 5. State Machines (Strict)

### 5.1 Cross Message State Machine
1. `queued -> delivered -> processed`
2. Any state may transition to `failed`
3. `queued/delivered` may transition to `expired` on timeout

### 5.2 Pending Action State Machine
1. `awaiting_peer_reply -> peer_replied|expired`
2. `peer_replied -> awaiting_peer_reply|awaiting_user_confirm|consumed`
3. `awaiting_user_confirm -> approved|rejected|expired`
4. `approved -> consumed` (execution pipeline has taken over)
5. `rejected/expired/consumed` are terminal states and non-reversible

## 6. Entry and API Strategy (MVP)

### 6.1 Cross-advisor Request Initiation (No New Endpoint)
Cross-advisor requests are not exposed as external APIs.  
Initiation uses internal service calls only:
1. When `advisor_orchestrator` detects cross-advisor write intent in chat, it directly calls `advisor_cross_message_service.create_request(...)`.
2. Any future system-event trigger must also use the same service path; do not add a public endpoint.

### 6.2 User Confirmation Entry (Chat Only, No New Endpoint)
1. After pending action is created, A-advisor sends a chat message to A user (and triggers push).  
2. User taps push and enters existing chat UI, then replies in chat with "approve/reject/clarify".  
3. `advisor_orchestrator.handle_chat` matches the reply to pending action, writes `approved/rejected`, then continues or terminates execution flow.  
4. No dedicated confirmation API is introduced in this workflow.

### 6.3 Thread Query
No new external thread-query endpoint is introduced. Thread content is viewed via existing chat history plus internal audit records (internal tools/DB).

## 7. Execution Orchestration (Aligned with Existing Code)

1. New service: `advisor_cross_message_service.py`
- create message
- deliver message
- transition status
- persist audit records

2. In `advisor_orchestrator.handle_chat`, add pending-action resume branches:
- similar to existing `task_create_clarification` resume pattern
- trigger resume when `cross_advisor_action_confirmation` is approved
- receiver advisor executes skill; do not switch back to requester advisor

3. Execution remains on existing `execution_service.create_execution_job/run_execution_job`
- do not rebuild execution framework
- only add "resume input construction" and "post-execution cross-message callback"

## 8. LLM Decision Contract (Receiving Advisor)

Prompt output must be structured JSON:
1. `needs_confirmation` (bool)
2. `question_to_user` (string)
3. `decision_hint` (`approve|reject|ask_more`)
4. `reason` (string)

Rules:
1. For cross-user write requests, `needs_confirmation` must be `true`.
2. `question_to_user` must be directly sendable to end user, max length <= 200 characters.
3. User confirmation intents (agree/yes/okay) map to `approve`.

## 9. Security and Permissions

1. Cross-advisor requests are allowed only between users in the same team.
2. Before action execution, re-check that `task_id` ownership matches action target.
3. The approver must match `pending_action.approver_user_id`.
4. All write operations must record `write_confirmed` in execution result (reuse existing constraint).

## 10. Development Breakdown (Directly Schedulable)

### P0 (Required)
1. Add collections/indexes: `advisor_cross_messages` + extended indexes for `advisor_pending_actions`.
2. Add model: `models/advisor_cross_message.py`.
3. Do not add new `advisor_message` public routes; initiation and confirmation both reuse existing `/api/v2/advisor/chat`.
4. Add service: `services/advisor_cross_message_service.py`.
5. Extend `advisor_orchestrator` with three logic branches: internal initiation on cross-advisor intent, resume on peer reply arrival, resume after user confirmation.
6. Extend `execution_service` to send post-execution cross-result callback, and have receiver advisor reflect result in user chat.
7. Add multi-turn control: increment `turn_count` per turn; auto-terminate with user-facing explanation when `max_turns` is reached.

## 11. Acceptance Criteria (All Required)

1. Before A user confirms, A-advisor does not execute write actions.
2. After A user confirms, A-advisor can trigger and complete execution.
3. Execution results are returned to B-advisor request thread.
4. Full chain is traceable (`message + pending + execution job + audit logs`).
5. The same `thread_id` supports multi-turn advisor conversation and terminates safely by `max_turns` or timeout.

## 12. Non-Goals (Out of Scope)

1. Multi-level approval (e.g., require C after A).
2. Automatic approval policy engine.
3. Cross-team / unknown-user advisor messaging.

## 13. Frontend Display Constraints (Precise)

### 13.1 Data Contract (Backend)
1. Reuse existing `chat_messages` collection; do not create a frontend-only conversation table.
2. Collaboration-thread messages must populate these `metadata` fields:
- `channel`: `advisor_user` | `advisor_collab` (collab thread uses `advisor_collab`)
- `readonly`: bool (collab thread always `true`)
- `thread_id`: string (maps to `advisor_cross_messages.thread_id`)
- `collab_status`: `in_progress|waiting_user_confirm|done|failed|expired`
- `peer_user_id`: string (the peer user)
3. For legacy/normal messages missing these fields, treat as `channel=advisor_user` (backward compatible).

### 13.2 Session List API Contract (`GET /advisor/sessions`)
1. Extend existing `SessionSummaryResponse` with:
- `channel` (default `advisor_user`)
- `readonly` (default `false`)
- `thread_id` (nullable)
- `collab_status` (nullable)
- `peer_user_id` (nullable)
2. In `chat_history_service.get_sessions()`, aggregate these fields from metadata of the latest message in each `session_id`.
3. Keep sorting unchanged: mixed list ordered by `last_message_at` desc (do not split collab and normal sessions).

### 13.3 History List UI Rules (`_HistoryPanel` in `advisor_screen.dart`)
1. Use one shared list for all sessions (keep current behavior).
2. When `channel=advisor_collab`, render a fixed label above title: `Advisor Collaboration Record`.
3. For collab sessions, subtitle shows: `last updated + collab_status`; normal sessions keep `x messages`.
4. Collab preview must use backend-sanitized summary; do not show raw internal reasoning.

### 13.4 Session Detail Read-Only Rules (Chat Page)
1. When entering `readonly=true` session:
- hide input box and send button
- disable keyboard input and submit actions
2. Fixed UI text: `This is an Advisor collaboration record and is view-only.`

### 13.5 Backend Hard Guard (Required)
1. Add validation in `POST /api/v2/advisor/chat` (`advisor_v2_routes.advisor_chat_v2`):
- if `request.session_id` maps to session with `readonly=true`, reject user write.
2. Rejection response: `409 Conflict`, `detail="This advisor collaboration thread is read-only."`
3. This guard must run before LLM routing and execution logic (must not enter `advisor_orchestrator.handle_chat`).

### 13.6 Content Boundary (Collab Thread)
1. Allowed: request summary, decision outcome, execution result, user-readable failure reason.
2. Forbidden: LLM chain-of-thought, full internal prompts, sensitive credentials/tokens.
