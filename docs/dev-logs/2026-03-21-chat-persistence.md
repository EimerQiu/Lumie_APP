# Chat Persistence — Dev Log (2026-03-21)

## Problem

Advisor conversations disappeared when users switched away from the Advisor tab. There was no local or server-side persistence of chat messages.

## Decisions

1. **Two-layer persistence** — Local cache (SharedPreferences) for instant display + MongoDB server storage for long-term retention.
2. **Cache-first loading** — On tab init, show cached messages immediately, then sync from server in background. This avoids blank screens on slow networks.
3. **Session dividers** — Since multiple sessions are now visible in a single scrollable history, added visual dividers between sessions with date labels.
4. **Max cache size** — Capped at 500 messages locally to avoid SharedPreferences bloat.
5. **Cursor-based pagination** — Server API uses `before` (ISO timestamp) cursor rather than offset-based pagination for consistency as new messages arrive.

## New Files

### Backend
- `lumie_backend/app/services/chat_history_service.py` — Saves messages to `chat_messages` MongoDB collection. Functions: `save_message()`, `save_exchange()`, `get_history()`, `get_session_messages()`, `ensure_indexes()`.
- `lumie_backend/app/api/chat_history_routes.py` — `GET /api/v1/advisor/history` endpoint with cursor-based pagination (`limit`, `before` params).

### Frontend
- `lumie_activity_app/lib/core/services/chat_history_service.dart` — Two-layer service: `loadFromCache()`, `saveToCache()`, `appendToCache()`, `clearCache()`, `fetchFromServer()`, `loadHistory()`. Model: `PersistedMessage`.

## Modified Files

### Backend
- `lumie_backend/app/api/advisor_routes.py` — Added `session_id` field to request, wired `save_exchange()` via `asyncio.create_task()` for both direct and analysis response paths.
- `lumie_backend/app/main.py` — Registered `chat_history_router`, added `ensure_indexes()` call on startup.

### Frontend
- `lumie_activity_app/lib/core/constants/api_constants.dart` — Added `advisorHistory` constant.
- `lumie_activity_app/lib/features/advisor/screens/advisor_screen.dart` — Rewrote `_ChatTabState` with history loading, `_ChatItem` model (messages + session dividers), `_buildItemsFromHistory()`, `_persistExchange()`, and `_SessionDivider` widget.
- `lumie_activity_app/lib/features/auth/providers/auth_provider.dart` — Added `ChatHistoryService().clearCache()` call in `logout()`.
- `lumie_activity_app/pubspec.yaml` — Added `uuid: ^4.5.1` dependency.

## API Endpoints Added

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/advisor/history` | Paginated chat history (newest-first, cursor-based). Query params: `limit` (default 50, max 200), `before` (ISO timestamp). Returns `{messages, has_more}`. |

## New DB Collections / Indexes

| Collection | Indexes | Purpose |
|------------|---------|---------|
| `chat_messages` | `(user_id, created_at)`, `(user_id, session_id)` | Persisted advisor chat messages |

## Schema: `chat_messages`

```json
{
  "user_id": "string",
  "session_id": "string",
  "role": "user | assistant",
  "content": "string",
  "metadata": {},
  "created_at": "datetime (UTC)"
}
```

## Testing Checklist

- [ ] Send message in advisor → verify it appears in `chat_messages` collection
- [ ] Switch tabs and return → conversation still visible (local cache)
- [ ] Kill app and reopen → conversation still visible (local cache)
- [ ] Scroll up → see older session messages with dividers between sessions
- [ ] Logout and login → cache cleared, fresh history loaded from server
- [ ] `GET /advisor/history?limit=10` returns correct paginated results
- [ ] `GET /advisor/history?before=<timestamp>` returns older messages

## Future Work

- Infinite scroll pagination in the chat UI (currently loads last 200 messages)
- Message search functionality
- Export conversation history
