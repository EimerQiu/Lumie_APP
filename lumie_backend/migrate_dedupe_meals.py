"""
Dedupe historical source-linked meals.

Groups `meals` by (source_type, source_task_id, user_id), keeps the oldest
created_at as canonical, rewrites Dayprint event references to the canonical
meal_id, and deletes the rest. Any leftover duplicate meal_logged events in
the same dayprint that share a meal_id collapse to one entry afterwards.

Manually-logged meals (no source_type) are NEVER merged — even if a user
logged the same name at different times, those rows stay.

Usage
─────
  Dry run (default — prints groups + planned changes, writes nothing):
    python3 migrate_dedupe_meals.py

  Apply (actually delete duplicates and rewrite Dayprint refs):
    python3 migrate_dedupe_meals.py --apply

  Limit to a single source_type / user (useful for staged rollouts):
    python3 migrate_dedupe_meals.py --source-type nutrition_task
    python3 migrate_dedupe_meals.py --user-id user-abc123

The script is idempotent — running it twice is safe.
"""
from __future__ import annotations

import argparse
import asyncio
import logging
import sys
from datetime import datetime
from pathlib import Path
from typing import Any, Optional

logger = logging.getLogger("migrate_dedupe_meals")

# Allow running directly from the lumie_backend dir.
sys.path.insert(0, str(Path(__file__).resolve().parent))


def _meal_age_key(meal: dict) -> tuple:
    """Same canonical ordering used by the live MealService consolidation."""
    created = meal.get("created_at")
    meal_time = meal.get("meal_time")
    if isinstance(meal_time, str):
        try:
            meal_time = datetime.fromisoformat(meal_time.replace("Z", ""))
        except ValueError:
            meal_time = None
    return (
        created is None,
        created or datetime.max,
        meal_time is None,
        meal_time or datetime.max,
    )


async def _find_duplicate_groups(
    db,
    *,
    source_type: Optional[str],
    user_id: Optional[str],
) -> list[list[dict]]:
    """Group meal docs by (user_id, task_id) where task_id is `source_task_id`
    OR `linked_task_id` — broadened from the old (source_type, source_task_id,
    user_id) triple so a legacy `POST /meals` row with only `linked_task_id`
    collapses with the bridge-stamped row for the same task.

    Only returns groups with 2+ members. Manually-logged meals with NO task
    link are NEVER grouped — a user logging "oatmeal" twice manually is two
    distinct meals.
    """
    match: dict[str, Any] = {
        "$or": [
            {"source_task_id": {"$ne": None}},
            {"linked_task_id": {"$ne": None}},
        ],
    }
    if source_type:
        match["source_type"] = source_type
    if user_id:
        match["user_id"] = user_id

    cursor = db.meals.find(match)
    docs = await cursor.to_list(length=None)

    grouped: dict[tuple, list[dict]] = {}
    for doc in docs:
        task_id = doc.get("source_task_id") or doc.get("linked_task_id")
        uid = doc.get("user_id")
        if not (task_id and uid):
            continue
        grouped.setdefault((uid, task_id), []).append(doc)

    return [members for members in grouped.values() if len(members) >= 2]


async def _count_dayprint_refs(db, meal_id: str) -> int:
    """How many dayprint events still reference this meal_id."""
    cursor = db.dayprints.find({"events.data.meal_id": meal_id})
    docs = await cursor.to_list(length=None)
    return sum(
        1
        for doc in docs
        for event in doc.get("events", [])
        if (event.get("data") or {}).get("meal_id") == meal_id
    )


def _format_group(group: list[dict], canonical: dict) -> str:
    canonical_id = canonical.get("meal_id")
    parts = [
        f"  source_type={canonical.get('source_type')!r} "
        f"source_task_id={canonical.get('source_task_id')!r} "
        f"user_id={canonical.get('user_id')!r}",
        f"    canonical: meal_id={canonical_id} "
        f"created_at={canonical.get('created_at')} "
        f"meal_time={canonical.get('meal_time')}",
    ]
    for dup in group:
        if dup.get("meal_id") == canonical_id:
            continue
        parts.append(
            f"    drop:      meal_id={dup.get('meal_id')} "
            f"created_at={dup.get('created_at')} "
            f"meal_time={dup.get('meal_time')}"
        )
    return "\n".join(parts)


async def _rewrite_dayprint_refs(db, dup_id: str, canonical_id: str) -> int:
    """Rewrite every dayprint event whose data.meal_id matches dup_id to point
    at canonical_id. Returns the number of dayprint docs touched."""
    result = await db.dayprints.update_many(
        {"events.data.meal_id": dup_id},
        {"$set": {"events.$[evt].data.meal_id": canonical_id}},
        array_filters=[{"evt.data.meal_id": dup_id}],
    )
    return getattr(result, "modified_count", 0) or 0


async def _dedupe_dayprint_events_for_meal(db, meal_id: str) -> int:
    """After rewriting, multiple events in the same dayprint may now reference
    the canonical meal_id. Keep the earliest one per (date, meal_id) and pull
    the rest. Returns the number of events removed.

    Pulled by event_id so we don't accidentally remove a non-meal_logged event.
    """
    cursor = db.dayprints.find({"events.data.meal_id": meal_id})
    docs = await cursor.to_list(length=None)
    removed = 0
    for doc in docs:
        events = doc.get("events") or []
        seen_first: Optional[str] = None
        ids_to_pull: list[str] = []
        for event in events:
            if event.get("type") != "meal_logged":
                continue
            if (event.get("data") or {}).get("meal_id") != meal_id:
                continue
            if seen_first is None:
                seen_first = event.get("event_id")
                continue
            evt_id = event.get("event_id")
            if evt_id:
                ids_to_pull.append(evt_id)
        if not ids_to_pull:
            continue
        await db.dayprints.update_one(
            {"_id": doc.get("_id")} if "_id" in doc else {
                "user_id": doc.get("user_id"),
                "date": doc.get("date"),
            },
            {"$pull": {"events": {"event_id": {"$in": ids_to_pull}}}},
        )
        removed += len(ids_to_pull)
    return removed


_NUTRITION_TASK_TYPES = {"Nutrition", "nutrition"}


def _event_canonical_source_key(event: dict, *, user_id: str) -> Optional[str]:
    """Mirror dayprint_service.canonical_event_source_key, kept inline so the
    migration script never imports app code with side effects (pydantic/motor)."""
    data = event.get("data") or {}
    event_type = event.get("type")
    source_task_id = data.get("source_task_id")
    source_type = data.get("source_type") or ""
    task_type = data.get("task_type")
    meal_id = data.get("meal_id")

    is_nutrition = (
        source_type.startswith("nutrition_task")
        or (task_type in _NUTRITION_TASK_TYPES if task_type else False)
    )
    if source_task_id and (is_nutrition or event_type == "meal_logged"):
        return f"nutrition_task:{user_id}:{source_task_id}"
    if event_type == "meal_logged" and meal_id:
        return f"meal:{meal_id}"
    if event_type == "task_completed" and source_task_id:
        return f"task:{user_id}:{source_task_id}"
    return None


def _is_meal_visible_event(event: dict) -> bool:
    """Treat both meal_logged AND task_completed-on-nutrition as the "meal"
    surface so legacy task_completed entries collapse against the new
    meal_logged event for the same task.
    """
    if event.get("type") == "meal_logged":
        return True
    if event.get("type") == "task_completed":
        data = event.get("data") or {}
        return data.get("task_type") in _NUTRITION_TASK_TYPES
    return False


async def _scan_dayprint_dupes(
    db,
    *,
    user_id_filter: Optional[str],
) -> list[dict]:
    """Return one entry per dayprint that has duplicate canonical events,
    describing what would be rewritten / pulled. Stable + side-effect-free
    so it can drive the dry-run print and the apply path identically.
    """
    query: dict = {}
    if user_id_filter:
        query["user_id"] = user_id_filter
    cursor = db.dayprints.find(query)
    docs = await cursor.to_list(length=None)
    plans: list[dict] = []
    for doc in docs:
        events = doc.get("events") or []
        groups: dict[str, list[dict]] = {}
        for event in events:
            if not _is_meal_visible_event(event):
                continue
            key = _event_canonical_source_key(
                event, user_id=doc.get("user_id", ""),
            )
            if not key:
                continue
            groups.setdefault(key, []).append(event)
        dup_groups = {k: v for k, v in groups.items() if len(v) >= 2}
        if not dup_groups:
            continue
        plans.append({
            "user_id": doc.get("user_id"),
            "date": doc.get("date"),
            "groups": dup_groups,
        })
    return plans


async def _apply_dayprint_canonicalization(
    db,
    plan: dict,
    canonical_meal_ids: dict[str, str],
) -> tuple[int, int]:
    """For one dayprint doc's plan, keep the earliest event per canonical key,
    rewrite its data fields to point at the canonical meal_id, and pull the
    rest. Returns (events_kept_updated, events_removed).
    """
    user_id = plan["user_id"]
    date = plan["date"]
    pulls: list[str] = []
    rewrites = 0
    for key, events in plan["groups"].items():
        ordered = sorted(
            events,
            key=lambda e: e.get("timestamp") or "",
        )
        keeper = ordered[0]
        keeper_id = keeper.get("event_id")
        canonical_meal_id = canonical_meal_ids.get(key) or (
            keeper.get("data", {}).get("meal_id")
        )
        # Rewrite the keeper's payload so it converges on the canonical scheme:
        #   - meal_id points at the surviving meal row
        #   - source_key uses the canonical format (so future writes match)
        #   - type forced to meal_logged for nutrition meals (legacy
        #     task_completed events get promoted into the meal slot).
        new_data = dict(keeper.get("data") or {})
        new_data["source_key"] = key
        if canonical_meal_id:
            new_data["meal_id"] = canonical_meal_id
        if key.startswith("nutrition_task:"):
            new_data["source_type"] = "nutrition_task"
        await db.dayprints.update_one(
            {"user_id": user_id, "date": date, "events.event_id": keeper_id},
            {"$set": {
                "events.$[evt].data": new_data,
                "events.$[evt].type": (
                    "meal_logged"
                    if key.startswith("nutrition_task:") or key.startswith("meal:")
                    else keeper.get("type")
                ),
            }},
            array_filters=[{"evt.event_id": keeper_id}],
        )
        rewrites += 1
        for event in ordered[1:]:
            evt_id = event.get("event_id")
            if evt_id:
                pulls.append(evt_id)
    if pulls:
        await db.dayprints.update_one(
            {"user_id": user_id, "date": date},
            {"$pull": {"events": {"event_id": {"$in": pulls}}}},
        )
    return rewrites, len(pulls)


async def _scan_unhydrated_meal_events(
    db,
    *,
    user_id_filter: Optional[str],
) -> list[dict]:
    """Find dayprint meal_logged events with `meal_id` but no
    `source_task_id` whose underlying meal IS source-linked. These are the
    legacy cross-key duplicates that pass-2 alone cannot collapse — pass-1.5
    rewrites them to the canonical identity first.
    """
    query: dict = {}
    if user_id_filter:
        query["user_id"] = user_id_filter
    cursor = db.dayprints.find(query)
    docs = await cursor.to_list(length=None)

    candidates: list[tuple] = []  # (user_id, date, event_id, meal_id)
    for doc in docs:
        for event in doc.get("events") or []:
            if event.get("type") != "meal_logged":
                continue
            data = event.get("data") or {}
            if data.get("source_task_id"):
                continue
            mid = data.get("meal_id")
            if not mid:
                continue
            candidates.append((
                doc.get("user_id"),
                doc.get("date"),
                event.get("event_id"),
                mid,
            ))
    if not candidates:
        return []

    meal_ids = list({c[3] for c in candidates})
    cursor = db.meals.find(
        {"meal_id": {"$in": meal_ids}},
        {
            "_id": 0,
            "meal_id": 1,
            "source_type": 1,
            "source_task_id": 1,
            "linked_task_id": 1,
        },
    )
    rows = await cursor.to_list(length=len(meal_ids))
    by_id = {r["meal_id"]: r for r in rows if r.get("meal_id")}

    plan: list[dict] = []
    for user_id, date, event_id, meal_id in candidates:
        meal = by_id.get(meal_id)
        if not meal:
            continue
        task_id = meal.get("source_task_id") or meal.get("linked_task_id")
        if not task_id:
            continue
        plan.append({
            "user_id": user_id,
            "date": date,
            "event_id": event_id,
            "meal_id": meal_id,
            "source_task_id": task_id,
            "source_type": meal.get("source_type") or "nutrition_task",
        })
    return plan


async def _hydrate_legacy_meal_event(db, entry: dict) -> None:
    new_source_key = (
        f"nutrition_task:{entry['user_id']}:{entry['source_task_id']}"
    )
    await db.dayprints.update_one(
        {
            "user_id": entry["user_id"],
            "date": entry["date"],
            "events.event_id": entry["event_id"],
        },
        {"$set": {
            "events.$[evt].data.source_task_id": entry["source_task_id"],
            "events.$[evt].data.source_type": entry["source_type"],
            "events.$[evt].data.source_key": new_source_key,
        }},
        array_filters=[{"evt.event_id": entry["event_id"]}],
    )


async def run(
    db,
    *,
    apply: bool = False,
    source_type: Optional[str] = None,
    user_id: Optional[str] = None,
    out=print,
) -> dict:
    """Execute the migration. Returns a stats dict; safe to call from tests.

    Two passes run in order:

    1. **Meals pass** — group source-linked meals by (source_type,
       source_task_id, user_id), pick the earliest as canonical, rewrite
       Dayprint refs to the canonical meal_id, then drop the duplicate
       meal rows. (Same behavior as before this revision.)
    2. **Dayprint pass** — independently scan every Dayprint document for
       events that share a canonical source_key (e.g. legacy
       `meal_logged:meal:<id>` + `meal_logged:nutrition_task_meal:<task>:<id>`
       + `task_completed:task:<id>` for the SAME nutrition task). Keep the
       earliest event, rewrite its payload to canonical, and pull the rest.
       This catches the case where the meals collection is already clean
       but the dayprint still shows N duplicate rows.
    """
    groups = await _find_duplicate_groups(
        db, source_type=source_type, user_id=user_id,
    )

    stats = {
        "groups": len(groups),
        "duplicates": 0,
        "dayprints_rewritten": 0,
        "dayprint_events_removed": 0,
        "meals_deleted": 0,
        "dayprint_dup_groups": 0,
        "dayprint_event_canonicalizations": 0,
        "applied": apply,
    }

    canonical_meal_for_key: dict[str, str] = {}

    # ── Pass 1: meals collection ──────────────────────────────────────────
    if groups:
        out(f"Pass 1: found {len(groups)} duplicate meal group(s):")
        for group in groups:
            ordered = sorted(group, key=_meal_age_key)
            canonical = ordered[0]
            canonical_id = canonical.get("meal_id")
            dups = [d for d in ordered[1:] if d.get("meal_id") != canonical_id]
            stats["duplicates"] += len(dups)
            out(_format_group(group, canonical))

            # Pre-populate the dayprint pass so it can rewrite event meal_ids
            # using the same canonical we picked here.
            key = (
                f"nutrition_task:{canonical.get('user_id')}:"
                f"{canonical.get('source_task_id')}"
            )
            if canonical_id:
                canonical_meal_for_key[key] = canonical_id

            for dup in dups:
                ref_count = await _count_dayprint_refs(db, dup.get("meal_id"))
                out(
                    f"      dayprint refs to {dup.get('meal_id')}: {ref_count}"
                )

            if not apply:
                continue

            # Merge richer payload onto canonical BEFORE deleting duplicates,
            # so the surviving row carries the picture and structured food
            # data even when the canonical (oldest) was a manual save.
            display = next((d for d in dups if d.get("images")), None)
            merged_fields: dict = {}
            if display and display.get("images") and not (canonical.get("images") or []):
                merged_fields["images"] = display["images"]
            if display and display.get("food_items") and not (canonical.get("food_items") or []):
                merged_fields["food_items"] = display["food_items"]
            if not canonical.get("source_type"):
                merged_fields["source_type"] = "nutrition_task"
            if not canonical.get("source_task_id"):
                for d in dups:
                    tid = d.get("source_task_id") or d.get("linked_task_id")
                    if tid:
                        merged_fields["source_task_id"] = tid
                        break
            if not canonical.get("note"):
                for d in dups:
                    if d.get("note"):
                        merged_fields["note"] = d["note"]
                        break
            if merged_fields:
                await db.meals.update_one(
                    {"meal_id": canonical_id},
                    {"$set": merged_fields},
                )

            for dup in dups:
                dup_id = dup.get("meal_id")
                if not dup_id:
                    continue
                stats["dayprints_rewritten"] += await _rewrite_dayprint_refs(
                    db, dup_id, canonical_id,
                )

            if canonical_id:
                stats["dayprint_events_removed"] += await _dedupe_dayprint_events_for_meal(
                    db, canonical_id,
                )

            for dup in dups:
                dup_id = dup.get("meal_id")
                if not dup_id:
                    continue
                result = await db.meals.delete_one({"meal_id": dup_id})
                stats["meals_deleted"] += getattr(result, "deleted_count", 0) or 0
    else:
        out("Pass 1: no duplicate source-linked meals found.")

    # ── Pass 1.5: rewrite legacy meal-linked dayprint events ──────────────
    # Legacy `meal_logged` events written before create_meal learned to
    # canonicalize task-linked meals: payload has `meal_id` but no
    # `source_task_id`, even though the meal in storage IS source-linked.
    # Look up each such event's meal; if the meal has source_task_id (or
    # linked_task_id), grafts the canonical identity onto the event so a
    # subsequent pass-2 collapses it with any sibling bridge event.
    legacy_meal_events = await _scan_unhydrated_meal_events(
        db, user_id_filter=user_id,
    )
    if legacy_meal_events:
        out(
            f"\nPass 1.5: {len(legacy_meal_events)} legacy meal_logged event(s) "
            f"missing source_task_id (will resolve via meal lookup):"
        )
        for entry in legacy_meal_events:
            out(
                f"  user_id={entry['user_id']} date={entry['date']} "
                f"event_id={entry['event_id']} meal_id={entry['meal_id']} "
                f"→ source_task_id={entry['source_task_id']}"
            )
        if apply:
            for entry in legacy_meal_events:
                await _hydrate_legacy_meal_event(db, entry)
                stats["dayprint_event_canonicalizations"] += 1
    else:
        out("\nPass 1.5: no legacy meal_logged events need hydration.")

    # ── Pass 2: dayprint events ───────────────────────────────────────────
    plans = await _scan_dayprint_dupes(db, user_id_filter=user_id)
    stats["dayprint_dup_groups"] = sum(len(p["groups"]) for p in plans)
    if plans:
        out(
            f"\nPass 2: {stats['dayprint_dup_groups']} dayprint group(s) "
            f"with duplicate canonical events across {len(plans)} doc(s):"
        )
        for plan in plans:
            out(f"  user_id={plan['user_id']!r} date={plan['date']!r}")
            for key, events in plan["groups"].items():
                ordered = sorted(
                    events, key=lambda e: e.get("timestamp") or "",
                )
                keeper = ordered[0]
                out(f"    canonical_key={key}")
                out(
                    f"      keep:  event_id={keeper.get('event_id')} "
                    f"type={keeper.get('type')} "
                    f"timestamp={keeper.get('timestamp')}"
                )
                for dup in ordered[1:]:
                    out(
                        f"      drop:  event_id={dup.get('event_id')} "
                        f"type={dup.get('type')} "
                        f"timestamp={dup.get('timestamp')}"
                    )
            if not apply:
                continue
            rewrites, removed = await _apply_dayprint_canonicalization(
                db, plan, canonical_meal_for_key,
            )
            stats["dayprint_event_canonicalizations"] += rewrites
            stats["dayprint_events_removed"] += removed
    else:
        out("\nPass 2: no duplicate dayprint events found.")

    if apply:
        out(
            f"\nApplied: deleted {stats['meals_deleted']} duplicate meal(s); "
            f"rewrote refs in {stats['dayprints_rewritten']} dayprint doc(s); "
            f"canonicalized {stats['dayprint_event_canonicalizations']} keeper event(s); "
            f"removed {stats['dayprint_events_removed']} duplicate dayprint event(s)."
        )
    else:
        out(
            f"\nDry-run only. Would drop {stats['duplicates']} duplicate meal(s) "
            f"across {stats['groups']} group(s) + collapse "
            f"{stats['dayprint_dup_groups']} dayprint group(s). "
            f"Re-run with --apply to commit."
        )
    return stats


async def _main_async(args: argparse.Namespace) -> int:
    from app.core.database import connect_to_mongo, close_mongo_connection, get_database

    await connect_to_mongo()
    try:
        db = get_database()
        await run(
            db,
            apply=args.apply,
            source_type=args.source_type,
            user_id=args.user_id,
        )
    finally:
        await close_mongo_connection()
    return 0


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Actually delete duplicates and rewrite refs. Default is dry-run.",
    )
    parser.add_argument(
        "--source-type",
        default=None,
        help="Limit to a single source_type (e.g. nutrition_task).",
    )
    parser.add_argument(
        "--user-id",
        default=None,
        help="Limit to a single user_id.",
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true", help="Verbose logging.",
    )
    args = parser.parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    return asyncio.run(_main_async(args))


if __name__ == "__main__":
    sys.exit(main())
