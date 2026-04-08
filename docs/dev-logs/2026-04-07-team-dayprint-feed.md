# Team Dayprint Feed

**Date:** 2026-04-07

## What Was Built

A waterfall 2-column activity feed ("Dayprint") inside the team detail screen. Shows teammates' recent activity — task completions and daily sleep scores — in a social-feed style layout inspired by Xiaohongshu (RED).

## Decisions

- **3 feed item types** — `task_with_photo`, `task_text`, `sleep_score`. Chosen to cover all relevant team activity without requiring new data collection.
- **Team tasks only** — the feed queries tasks where `team_id` matches, so personal tasks of members are never shown. Sleep scores respect each member's `data_sharing.sleep` flag.
- **14-day lookback** — balances freshness with enough content for new teams.
- **Cursor pagination** — `before` ISO timestamp instead of offset/page; avoids missing items when new posts are inserted between pages.
- **One sleep entry per member per day** — deduplicated in the service layer to avoid flooding the feed when multiple sync sessions are stored for the same night.
- **Alternating column distribution** — items distributed left/right by index (even→left, odd→right). Simple to implement without a staggered grid package. No package added to pubspec.
- **Image loading fallback** — shows thumbnail while full image loads; shows grey placeholder on error.

## New Files

### Backend
- No new files — all added to existing team module.

### Frontend
- `lumie_activity_app/lib/features/teams/screens/team_dayprint_screen.dart` — main screen + all card widgets

## Modified Files

### Backend
- `lumie_backend/app/models/team.py` — added `FeedItemType`, `FeedAttachment`, `TeamFeedItem`, `TeamFeedResponse`
- `lumie_backend/app/services/team_service.py` — added `get_team_feed()` method
- `lumie_backend/app/api/team_routes.py` — added `GET /{team_id}/feed` endpoint

### Frontend
- `lumie_activity_app/lib/shared/models/team_models.dart` — added `TeamFeedItemType`, `FeedAttachment`, `TeamFeedItem`, `TeamFeedResponse`
- `lumie_activity_app/lib/core/services/team_service.dart` — added `getTeamFeed()` method
- `lumie_activity_app/lib/features/teams/screens/team_detail_screen.dart` — expanded from 2 to 3 tabs; added "Dayprint" tab

## API Endpoints Added

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/teams/{team_id}/feed` | Paginated team activity feed |

**Query params:** `limit` (1–50, default 20), `before` (ISO timestamp cursor)

**Response:**
```json
{
  "items": [
    {
      "item_id": "...",
      "type": "task_with_photo | task_text | sleep_score",
      "member_user_id": "...",
      "member_name": "Alice",
      "timestamp": "2026-04-07T08:30:00",
      "task_name": "Take medication",
      "task_type": "Medicine",
      "attachments": [{"url": "...", "thumbnail_url": "..."}],
      "sleep_score": 82,
      "sleep_hours": 7.5
    }
  ],
  "has_more": true,
  "next_before": "2026-04-06T22:10:00"
}
```

## New DB Collections / Indexes

None. Queries hit existing `tasks` and `sleep_sessions` collections.

**Recommended indexes (not yet added):**
- `tasks`: `{ team_id: 1, status: 1, completed_at: -1 }` — for feed query performance
- `sleep_sessions`: `{ user_id: 1, wake_time: -1, source: 1 }` — already likely exists from sleep feature

## Testing Checklist

- [ ] Team with completed tasks (with photos) shows image cards
- [ ] Team with completed tasks (no photos) shows text cards with correct color per task type
- [ ] Member with `data_sharing.sleep = true` shows sleep score card
- [ ] Member with `data_sharing.sleep = false` does NOT show sleep score
- [ ] Multiple photos on one task: swipe left shows next photo, page indicator updates
- [ ] Scroll to bottom triggers pagination (loads next page)
- [ ] Pull-to-refresh resets feed
- [ ] Non-member gets 403
- [ ] Empty team shows empty state illustration
- [ ] `before` cursor returns correct page without duplicates

## Future Work / Deferred

- Add performance indexes to MongoDB for the feed query
- Consider caching the feed in the provider so switching tabs doesn't re-fetch
- Sleep score cards could show a mini stage chart (light/deep/rem breakdown)
- Like/react interactions on feed items
- Filter feed by member or by type
