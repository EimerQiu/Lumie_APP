"""Sleep data service — MongoDB persistence and aggregation."""
import logging
from collections import defaultdict
from datetime import datetime, timedelta
from typing import Optional

from ..core.database import get_database
from ..models.sleep import (
    SleepSessionSync,
    SleepSessionResponse,
    SleepStageData,
    SleepTimelineSegment,
    SleepSummaryResponse,
    SleepTargetResponse,
)

logger = logging.getLogger(__name__)


# ─── Sleep-night helpers ──────────────────────────────────────────────────────

def _sleep_night_key(bedtime: datetime, wake_time: datetime) -> str:
    """Return a YYYY-MM-DD string identifying the 'sleep night' for a session.

    Convention: the date is the calendar day the user woke up, provided
    wake_time is before 1 PM (a normal morning wake).  If wake_time is in the
    afternoon, the session likely started late at night, so we fall back to
    bedtime + 1 day as the night key.
    """
    if wake_time.hour < 13:
        return wake_time.strftime("%Y-%m-%d")
    return (bedtime + timedelta(days=1)).strftime("%Y-%m-%d")


def _is_nighttime_session(bedtime: datetime, wake_time: datetime) -> bool:
    """Return True only if the session looks like a real nighttime sleep.

    Valid window:
      - Bedtime between 8 PM (20:00) and 6 AM (inclusive)
      - Wake time before 12 PM (noon)

    Afternoon naps and mid-day segments are excluded.
    Note: timestamps are treated as local time (as stored from the ring).
    """
    bed_hour = bedtime.hour
    return (bed_hour >= 20 or bed_hour < 6) and wake_time.hour < 12


def _passes_quality_filter(total_minutes: int, quality_score: float,
                            stages: list[dict]) -> bool:
    """Return False for sessions that look like ring noise rather than real sleep.

    Rejected:
      - Shorter than 180 minutes (3 continuous hours) of actual sleep
      - Quality score below 5
      - Completely all-light with zero deep/REM (ring worn on table, not person)
      - No stage data at all
    """
    if total_minutes < 180:
        return False
    if quality_score < 5.0:
        return False
    # All-light with no deep or REM → ring was not being worn (no body temperature
    # / PPG signal variation to produce real sleep staging)
    if stages:
        has_deep_or_rem = any(s.get("stage") in ("deep", "rem") and
                              s.get("duration_minutes", 0) > 0 for s in stages)
        if not has_deep_or_rem:
            return False
    else:
        # No stage data at all — discard
        return False
    return True


def _split_by_wake_boundaries(segs: list[SleepSessionSync]) -> list[list[SleepSessionSync]]:
    """Split same-night segments into sub-sessions based on wake duration rules.

    Session continues (gap treated as awake block within session) if:
      - Gap ≤ 30 minutes at any time of night, OR
      - Gap ≤ 60 minutes before 5 AM

    Session ends (start a new session) if:
      - Gap > 30 minutes AND the gap starts at or after 5:00 AM, OR
      - Gap > 60 minutes at any time
    """
    if not segs:
        return []

    groups: list[list[SleepSessionSync]] = [[segs[0]]]
    for seg in segs[1:]:
        prev_end = groups[-1][-1].wake_time
        gap_minutes = int((seg.bedtime - prev_end).total_seconds() / 60)
        is_past_5am = prev_end.hour >= 5

        if (gap_minutes > 30 and is_past_5am) or gap_minutes > 60:
            groups.append([seg])
        else:
            groups[-1].append(seg)

    return groups


def _build_timeline_segments(segs: list[SleepSessionSync],
                              earliest_bedtime: datetime) -> tuple[list[dict], int]:
    """Build an ordered list of timeline blocks from ring session records.

    Each ring record contributes blocks in this order:
      awake (if any within the record) → light → deep → rem

    Gaps between records (the user was out of bed / awake) are inserted as
    explicit "awake" blocks.  Returns (timeline_segments, wake_count).
    """
    timeline: list[dict] = []
    wake_count = 0
    last_end: datetime | None = None

    stage_order = ["awake", "light", "deep", "rem"]

    for seg in segs:
        # Awake gap between previous segment end and this one's start
        if last_end is not None:
            gap_minutes = int((seg.bedtime - last_end).total_seconds() / 60)
            if gap_minutes > 0:
                gap_offset = int((last_end - earliest_bedtime).total_seconds() / 60)
                timeline.append({
                    "stage": "awake",
                    "start_offset_minutes": gap_offset,
                    "duration_minutes": gap_minutes,
                })
                wake_count += 1

        # Within-segment stage blocks in conventional sleep-architecture order
        stage_map = {s.stage: s.duration_minutes for s in seg.stages}
        awake_mins = stage_map.get("awake", seg.time_awake_minutes)
        block_offset = int((seg.bedtime - earliest_bedtime).total_seconds() / 60)

        for stage_name in stage_order:
            mins = awake_mins if stage_name == "awake" else stage_map.get(stage_name, 0)
            if mins > 0:
                timeline.append({
                    "stage": stage_name,
                    "start_offset_minutes": block_offset,
                    "duration_minutes": mins,
                })
                block_offset += mins

        last_end = seg.wake_time

    return timeline, wake_count


def _build_merged_doc(user_id: str, night_key: str,
                      segs: list[SleepSessionSync]) -> dict:
    """Merge multiple same-night ring segments into a single DB document."""
    segs = sorted(segs, key=lambda s: s.bedtime)
    earliest_bedtime = segs[0].bedtime
    latest_wake = max(s.wake_time for s in segs)
    total_sleep = sum(s.total_sleep_minutes for s in segs)
    total_awake = sum(s.time_awake_minutes for s in segs)

    # Aggregate stage minutes across all segments
    stage_totals: dict[str, int] = defaultdict(int)
    for seg in segs:
        for stage in seg.stages:
            stage_totals[stage.stage] += stage.duration_minutes

    merged_total = sum(stage_totals.values()) or max(total_sleep, 1)
    merged_stages = [
        {
            "stage": k,
            "duration_minutes": v,
            "percentage": round(v / merged_total * 100, 1),
        }
        for k, v in stage_totals.items() if v > 0
    ]

    # Recompute quality from merged totals
    deep_min = stage_totals.get("deep", 0)
    rem_min = stage_totals.get("rem", 0)
    t = merged_total
    quality = round(
        min(1.0, (deep_min / t * 100) / 25.0) * 40 +
        min(1.0, (rem_min / t * 100) / 25.0) * 35 +
        min(1.0, total_sleep / 480.0) * 25,
        1,
    )

    timeline_segments, wake_count = _build_timeline_segments(segs, earliest_bedtime)

    return {
        "user_id": user_id,
        # Stable session_id per night so re-syncs overwrite cleanly
        "session_id": f"{user_id}_{night_key}",
        "night_key": night_key,
        "bedtime": earliest_bedtime,
        "wake_time": latest_wake,
        "total_sleep_minutes": total_sleep,
        "time_awake_minutes": total_awake,
        "stages": merged_stages,
        "resting_heart_rate": max((s.resting_heart_rate for s in segs), default=0),
        "sleep_quality_score": quality,
        "source": segs[0].source,
        "created_at": latest_wake,
        "timeline_segments": timeline_segments,
        "wake_count": wake_count,
    }


# ─── Service ──────────────────────────────────────────────────────────────────

class SleepService:
    async def sync_sessions(self, user_id: str, sessions: list[SleepSessionSync]) -> None:
        """Upsert sleep sessions uploaded from the ring.

        Segments belonging to the same sleep night are merged into one record
        so the DB contains exactly one document per night (identified by
        night_key YYYY-MM-DD).  This prevents the ring's multi-segment output
        from creating duplicate "last night" entries.
        """
        db = get_database()

        # Group incoming segments by sleep night
        nights: dict[str, list[SleepSessionSync]] = defaultdict(list)
        for s in sessions:
            key = _sleep_night_key(s.bedtime, s.wake_time)
            nights[key].append(s)

        for night_key, segs in nights.items():
            sorted_segs = sorted(segs, key=lambda s: s.bedtime)
            sub_sessions = _split_by_wake_boundaries(sorted_segs)
            for i, sub in enumerate(sub_sessions):
                # Use bedtime timestamp suffix for any split sub-sessions so that
                # re-syncs still upsert to the same document.
                sub_key = night_key if i == 0 else f"{night_key}_{sub[0].bedtime.strftime('%H%M')}"
                merged = _build_merged_doc(user_id, sub_key, sub)
                await db.sleep_sessions.update_one(
                    {"user_id": user_id, "session_id": merged["session_id"]},
                    {"$set": merged},
                    upsert=True,
                )

        logger.info("[sleep] synced %d night(s) for user %s", len(nights), user_id)

    async def get_latest(self, user_id: str) -> Optional[SleepSessionResponse]:
        """Return the most recent *valid nighttime* sleep session.

        Filters applied (all must pass):
          1. Bedtime in nighttime window (8 PM – 6 AM)
          2. Wake time before 1 PM
          3. At least 30 minutes of sleep
          4. Sleep quality score ≥ 5
          5. Not all-light with zero deep/REM and under 60 min (ring noise)
        """
        db = get_database()
        three_days_ago = datetime.utcnow() - timedelta(days=3)
        cursor = db.sleep_sessions.find(
            {"user_id": user_id, "bedtime": {"$gte": three_days_ago}},
            sort=[("bedtime", -1)],
            limit=20,
        )
        docs = [doc async for doc in cursor]

        for doc in docs:
            if (
                _is_nighttime_session(doc["bedtime"], doc["wake_time"])
                and _passes_quality_filter(
                    doc["total_sleep_minutes"],
                    doc["sleep_quality_score"],
                    doc.get("stages", []),
                )
            ):
                return self._doc_to_response(doc)

        return None

    async def get_history(
        self, user_id: str, start: datetime, end: datetime
    ) -> list[SleepSessionResponse]:
        """Return nighttime sleep sessions in the given date range, newest first."""
        db = get_database()
        cursor = db.sleep_sessions.find(
            {"user_id": user_id, "bedtime": {"$gte": start, "$lte": end}},
            sort=[("bedtime", -1)],
        )
        return [
            self._doc_to_response(doc)
            async for doc in cursor
            if _is_nighttime_session(doc["bedtime"], doc["wake_time"])
            and _passes_quality_filter(
                doc["total_sleep_minutes"],
                doc["sleep_quality_score"],
                doc.get("stages", []),
            )
        ]

    async def get_summary(
        self, user_id: str, start: datetime, end: datetime
    ) -> SleepSummaryResponse:
        """Aggregate sleep stats for the given date range."""
        sessions = await self.get_history(user_id, start, end)
        n = len(sessions)

        if n == 0:
            return SleepSummaryResponse(
                start_date=start,
                end_date=end,
                average_sleep_hours=0.0,
                average_resting_hr=0.0,
                average_sleep_quality=0.0,
                sleep_consistency=0.0,
                average_stage_percentages={},
            )

        avg_sleep_hours = sum(s.total_sleep_minutes for s in sessions) / n / 60
        avg_resting_hr = sum(s.resting_heart_rate for s in sessions) / n
        avg_quality = sum(s.sleep_quality_score for s in sessions) / n

        stage_sums: dict[str, float] = {}
        for s in sessions:
            for stage in s.stages:
                stage_sums[stage.stage] = stage_sums.get(stage.stage, 0.0) + stage.percentage
        avg_stages = {k: round(v / n, 1) for k, v in stage_sums.items()}

        if n > 1:
            bedtime_minutes = [s.bedtime.hour * 60 + s.bedtime.minute for s in sessions]
            mean_bt = sum(bedtime_minutes) / n
            variance = sum((bt - mean_bt) ** 2 for bt in bedtime_minutes) / n
            std_dev = variance ** 0.5
            consistency = round(max(0.0, 1.0 - std_dev / 60.0), 2)
        else:
            consistency = 1.0

        return SleepSummaryResponse(
            start_date=start,
            end_date=end,
            average_sleep_hours=round(avg_sleep_hours, 2),
            average_resting_hr=round(avg_resting_hr, 1),
            average_sleep_quality=round(avg_quality, 1),
            sleep_consistency=consistency,
            average_stage_percentages=avg_stages,
        )

    async def get_target(self, user_id: str) -> SleepTargetResponse:
        """Return age-appropriate sleep target (CDC recommendations)."""
        db = get_database()
        profile = await db.profiles.find_one({"user_id": user_id})
        age: int = ((profile or {}).get("age") or 16)

        if age < 18:
            return SleepTargetResponse(
                min_duration_minutes=8 * 60,
                max_duration_minutes=10 * 60,
                target_duration_minutes=9 * 60,
                target_stage_percentages={"light": 45.0, "deep": 25.0, "rem": 25.0},
            )
        else:
            return SleepTargetResponse(
                min_duration_minutes=7 * 60,
                max_duration_minutes=9 * 60,
                target_duration_minutes=8 * 60,
                target_stage_percentages={"light": 45.0, "deep": 25.0, "rem": 25.0},
            )

    def _doc_to_response(self, doc: dict) -> SleepSessionResponse:
        return SleepSessionResponse(
            session_id=doc["session_id"],
            user_id=doc["user_id"],
            bedtime=doc["bedtime"],
            wake_time=doc["wake_time"],
            total_sleep_minutes=doc["total_sleep_minutes"],
            time_awake_minutes=doc["time_awake_minutes"],
            stages=[SleepStageData(**s) for s in doc["stages"]],
            resting_heart_rate=doc.get("resting_heart_rate", 0),
            sleep_quality_score=doc["sleep_quality_score"],
            created_at=doc["created_at"],
            source=doc.get("source", "ring"),
            timeline_segments=[
                SleepTimelineSegment(**seg)
                for seg in doc.get("timeline_segments", [])
            ],
            wake_count=doc.get("wake_count", 0),
        )


sleep_service = SleepService()
