# Lumie APP - Claude Context

Activity tracking app for teens with chronic health conditions.

## Stack

- **Frontend:** Flutter (`lumie_activity_app/lib/`)
- **Backend:** Python FastAPI + Motor (async MongoDB) (`lumie_backend/app/`)
- **Database:** MongoDB (`lumie_db`)
- **Auth:** JWT HS256, 7-day expiry
- **Docs:** `docs/` — read these before working on a feature

## Project Structure

```
lumie_activity_app/lib/
  features/
    teams/          # Team system (screens, providers, widgets)
    tasks/          # Med-Reminder (tasks, templates, batch generation)
    advisory/       # AI advisor chat
  shared/models/    # Dart data models
  core/services/    # API service layer

lumie_backend/app/
  api/              # FastAPI route handlers
  services/         # Business logic
  models/           # Pydantic models
  core/             # DB connection, config, subscription helpers
```

## API

- Base prefix: `/api/v1/`
- All routes require Bearer JWT except public ones
- Public routes: `GET /api/v1/teams/invitations/token/{token}`

## MongoDB Collections

| Collection | Purpose |
|---|---|
| `users` | Auth credentials + subscription |
| `profiles` | Name, age, role, height/weight, ICD-10 |
| `activities` | Activity tracking entries |
| `walk_tests` | 6-minute walk test results |
| `teams` | Team records (soft-deleted with `is_deleted`) |
| `team_members` | Active (`status=member`) + pending (`status=pending`) |
| `pending_invitations` | Email invitations for unregistered users |
| `tasks` | Med-Reminder task records |
| `task_templates` | Reusable task templates for batch generation |

## Key Patterns

### Timestamps
- Backend uses `datetime.utcnow()` — Python's `.isoformat()` does **not** append `Z`
- Flutter **must** parse with `.toUtc()`:
  ```dart
  final date = DateTime.parse(dateStr).toUtc();
  final now = DateTime.now().toUtc();
  ```

### Subscription Tiers
- `free` → 1 team max
- `monthly` or `annual` → both are "Pro" → 100 teams max
- Subscription limit is checked **on accept**, not on invite
- `core/subscription_helpers.py` has `get_team_limit()` and `raise_subscription_limit_error()`
- Limit counts `team_members` where `status == "member"` (pending doesn't count)

### Team Invitation Flow
1. Admin invites by email → `POST /api/v1/teams/{id}/invite`
2. If invitee is **registered** → creates `team_members` row (`status=pending`)
3. If invitee is **unregistered** → creates `pending_invitations` row (by email)
4. JWT invitation token: `{team_id, email, type:"team_invitation"}`, expires 30 days
5. Invitation link: `https://yumo.org/invite/{token}`
6. On registration: `team_service.process_pending_invitations()` auto-converts email invites
7. Invitee accepts → subscription limit checked → `status` updated to `member`

### Subscription Error Response (403)
```json
{
  "error": {
    "code": "SUBSCRIPTION_LIMIT_REACHED",
    "message": "...",
    "detail": "...",
    "subscription": { "current_tier": "free", "required_tier": "pro", "upgrade_required": true },
    "action": { "type": "upgrade", "label": "Upgrade to Pro", "destination": "/subscription/upgrade" }
  }
}
```
Flutter catches this as `SubscriptionLimitException`.

### Team Roles & Status
- `role`: `admin` | `member`
- `status`: `pending` | `member`
- Pending members have **zero** access to team data
- Only admins can invite, remove members, delete team
- Cannot remove another admin; cannot leave if only admin

## Environment Variables (backend)
- `MONGODB_URL` — MongoDB connection string
- `MONGODB_DB_NAME` — defaults to `lumie_db`
- `SECRET_KEY` — JWT signing key
- `ANTHROPIC_API_KEY` — for AI advisor feature

## Development Logs

After completing a feature or significant implementation work, **always** create a dev log in `docs/dev-logs/`.

- **File name:** `YYYY-MM-DD-feature-name.md` (e.g. `2026-03-01-med-reminder.md`)
- **Required sections:**
  - Decisions made (with rationale)
  - New files created (backend + frontend)
  - Modified files
  - API endpoints added
  - New DB collections/indexes
  - Testing checklist
  - Future work / what's deferred
- This is a **team-wide rule** — every developer must log their work so others can understand what was built and how

## Docs to Read Before Working on a Feature
- `docs/PRD.md` — full product requirements
- `docs/TEAM_SYSTEM_DESIGN.md` — team system API + screen design
- `docs/SMART_RING_PROTOCOL.md` — smart ring integration
- `docs/AutoMom_Module_PRD.md` — advisory/parent module
- `docs/dev-logs/` — previous implementation logs (read before modifying existing features)
