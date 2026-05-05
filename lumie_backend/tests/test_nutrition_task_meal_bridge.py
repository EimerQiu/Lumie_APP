import asyncio
import json
import os
import sys
from datetime import datetime
from pathlib import Path
from types import SimpleNamespace

import pytest
from pymongo.errors import DuplicateKeyError

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ["DEBUG"] = "false"

from app.services import dayprint_service as dayprint_module
from app.services.dayprint_service import get_dayprint, log_meal_logged
from app.services import meal_service as meal_module
from app.services.meal_service import MealService


class FakeCollection:
    def __init__(self, *, unique_source: bool = False):
        self.docs = []
        self.lock = asyncio.Lock()
        self.unique_source = unique_source

    def _matches(self, doc, query):
        # Top-level `$or` plus other top-level keys must ALL hold (Mongo
        # combines them implicitly with AND). The previous shortcut only
        # checked $or and ignored siblings — broke filtering by user_id
        # when the query also has an $or branch on task fields.
        if "$or" in query:
            if not any(self._matches(doc, part) for part in query["$or"]):
                return False
        for key, expected in query.items():
            if key == "$or":
                continue
            values = list(self._walk_dotted(doc, key.split(".")))
            actual = values[0] if values else None
            if isinstance(expected, dict):
                # Operator-style query — every operator must hold for actual.
                operator_keys = {
                    "$ne", "$not", "$elemMatch",
                    "$gte", "$gt", "$lte", "$lt",
                    "$in", "$nin", "$exists",
                }
                if any(k in expected for k in operator_keys):
                    if not self._matches_operators(actual, expected):
                        return False
                    continue
            # When the dotted path crossed an array, match if ANY element does.
            if "." in key and len(values) > 1:
                if not any(v == expected for v in values):
                    return False
                continue
            if actual != expected:
                return False
        return True

    def _matches_operators(self, actual, expected: dict) -> bool:
        for op, target in expected.items():
            if op == "$ne":
                if actual == target:
                    return False
            elif op == "$not":
                if self._matches_not(actual, target):
                    return False
            elif op == "$elemMatch":
                if not isinstance(actual, list):
                    return False
                if not any(
                    self._matches(item, target)
                    for item in actual if isinstance(item, dict)
                ):
                    return False
            elif op == "$gte":
                if actual is None or actual < target:
                    return False
            elif op == "$gt":
                if actual is None or actual <= target:
                    return False
            elif op == "$lte":
                if actual is None or actual > target:
                    return False
            elif op == "$lt":
                if actual is None or actual >= target:
                    return False
            elif op == "$in":
                if actual not in target:
                    return False
            elif op == "$nin":
                if actual in target:
                    return False
            elif op == "$exists":
                exists = actual is not None
                if bool(target) != exists:
                    return False
        return True

    def _walk_dotted(self, value, parts):
        if not parts:
            yield value
            return
        head, *rest = parts
        if isinstance(value, list):
            for item in value:
                yield from self._walk_dotted(item, parts)
        elif isinstance(value, dict):
            if head in value:
                yield from self._walk_dotted(value[head], rest)

    def _get_value(self, doc, dotted_key):
        values = list(self._walk_dotted(doc, dotted_key.split(".")))
        return values[0] if values else None

    def _matches_not(self, actual, condition):
        if "$elemMatch" in condition:
            if not isinstance(actual, list):
                return False
            return any(self._matches(item, condition["$elemMatch"]) for item in actual)
        return False

    def _pull_matches(self, item, criteria):
        if not isinstance(criteria, dict):
            return item == criteria
        for key, expected in criteria.items():
            actual = item.get(key) if isinstance(item, dict) else None
            if isinstance(expected, dict) and "$in" in expected:
                if actual not in expected["$in"]:
                    return False
                continue
            if actual != expected:
                return False
        return True

    def _enforce_unique_source(self, candidate):
        if not self.unique_source or candidate.get("source_type") != "nutrition_task":
            return
        for doc in self.docs:
            if (
                doc.get("source_type") == "nutrition_task"
                and doc.get("source_task_id") == candidate.get("source_task_id")
                and doc.get("user_id") == candidate.get("user_id")
                and doc.get("meal_id") != candidate.get("meal_id")
            ):
                raise DuplicateKeyError("duplicate nutrition task source")

    async def find_one(self, query, *args, **kwargs):
        async with self.lock:
            for doc in self.docs:
                if self._matches(doc, query):
                    return dict(doc)
        return None

    def find(self, query=None, *args, **kwargs):
        query = query or {}
        # Capture a snapshot so callers can iterate while we mutate `self.docs`
        # via consolidation (delete_one) without raising RuntimeError.
        matched = [dict(doc) for doc in self.docs if self._matches(doc, query)]
        return _FakeCursor(matched)

    async def insert_one(self, doc):
        async with self.lock:
            self._enforce_unique_source(doc)
            self.docs.append(dict(doc))
        return SimpleNamespace(inserted_id=doc.get("_id"))

    async def delete_one(self, query):
        async with self.lock:
            for idx, doc in enumerate(self.docs):
                if self._matches(doc, query):
                    self.docs.pop(idx)
                    return SimpleNamespace(deleted_count=1)
        return SimpleNamespace(deleted_count=0)

    async def update_one(self, query, update, *args, upsert=False, array_filters=None, **kwargs):
        async with self.lock:
            for doc in self.docs:
                if self._matches(doc, query):
                    if "$setOnInsert" in update:
                        pass
                    if "$set" in update:
                        for key, value in update["$set"].items():
                            if "$[" in key and array_filters:
                                self._apply_positional_set(
                                    doc, key, value, array_filters,
                                )
                            else:
                                doc[key] = value
                    if "$push" in update:
                        for key, value in update["$push"].items():
                            doc.setdefault(key, []).append(value)
                    if "$pull" in update:
                        for key, criteria in update["$pull"].items():
                            arr = doc.get(key)
                            if not isinstance(arr, list):
                                continue
                            doc[key] = [
                                item for item in arr
                                if not self._pull_matches(item, criteria)
                            ]
                    return SimpleNamespace(modified_count=1, upserted_id=None)

            if not upsert:
                return SimpleNamespace(modified_count=0, upserted_id=None)

            new_doc = {
                key: value
                for key, value in query.items()
                if not key.startswith("$") and not isinstance(value, dict)
            }
            new_doc.update(update.get("$setOnInsert", {}))
            new_doc.update(update.get("$set", {}))
            self._enforce_unique_source(new_doc)
            self.docs.append(new_doc)
            return SimpleNamespace(modified_count=0, upserted_id=new_doc.get("meal_id"))

    async def update_many(self, query, update, *args, array_filters=None, **kwargs):
        modified = 0
        async with self.lock:
            for doc in self.docs:
                if not self._matches(doc, query):
                    continue
                if "$set" in update:
                    for key, value in update["$set"].items():
                        if "$[" in key and array_filters:
                            self._apply_positional_set(doc, key, value, array_filters)
                        else:
                            doc[key] = value
                modified += 1
        return SimpleNamespace(modified_count=modified)

    @staticmethod
    def _apply_positional_set(doc, key, value, array_filters):
        # Only supports the single-array `events.$[evt].data.<field>` shape used
        # by meal-consolidation dayprint rewrites.
        try:
            array_field, _, tail = key.partition(".$[")
            placeholder, _, sub_path = tail.partition("].")
        except ValueError:
            return
        if not sub_path:
            return
        events = doc.get(array_field) or []
        filt = next(
            (f for f in array_filters if any(k.startswith(f"{placeholder}.") for k in f)),
            {},
        )
        for event in events:
            ok = True
            for fk, fv in filt.items():
                _, _, leaf = fk.partition(".")
                actual = event
                for part in leaf.split("."):
                    if not isinstance(actual, dict):
                        actual = None
                        break
                    actual = actual.get(part)
                if actual != fv:
                    ok = False
                    break
            if not ok:
                continue
            target = event
            parts = sub_path.split(".")
            for part in parts[:-1]:
                target = target.setdefault(part, {})
            target[parts[-1]] = value


class _FakeCursor:
    def __init__(self, docs):
        self._docs = docs

    def sort(self, *args, **kwargs):
        return self

    def limit(self, n):
        self._docs = self._docs[:n]
        return self

    async def to_list(self, length=None):
        if length is None:
            return list(self._docs)
        return list(self._docs[:length])


class FakeDb:
    def __init__(self):
        self.meals = FakeCollection(unique_source=True)
        self.dayprints = FakeCollection()
        self.profiles = FakeCollection()


@pytest.fixture
def fake_db(monkeypatch):
    db = FakeDb()
    monkeypatch.setattr(meal_module, "get_database", lambda: db)
    monkeypatch.setattr(dayprint_module, "get_database", lambda: db)
    return db


@pytest.fixture
def service(monkeypatch):
    svc = MealService()

    async def fake_structure(text, user_id=None):
        await asyncio.sleep(0)
        return {
            "food_items": [{"name": text or "Meal"}],
            "macro_ratio": {
                "protein": "moderate",
                "carbs": "moderate",
                "fat": "moderate",
                "fiber": "low",
            },
            "meal_name": text or "Meal",
        }

    async def fake_resolve_tz(user_id):
        return "UTC"

    monkeypatch.setattr(svc, "_structure_text_to_meal", fake_structure)
    monkeypatch.setattr(svc, "_resolve_user_timezone", fake_resolve_tz)
    return svc


def nutrition_task(**overrides):
    task = {
        "task_id": "task-nutrition-1",
        "user_id": "user-1",
        "team_id": "team-1",
        "note": "eggs and toast",
        "attachments": [],
        "open_datetime": "2026-05-05 08:00",
    }
    task.update(overrides)
    return task


def meal_logged_events(db):
    return [
        event
        for dayprint in db.dayprints.docs
        for event in dayprint.get("events", [])
        if event.get("type") == "meal_logged"
    ]


async def dayprint_meal_items(user_id="user-1"):
    doc = await get_dayprint(user_id)
    return [
        event for event in (doc or {}).get("events", [])
        if event.get("type") == "meal_logged"
    ]


def print_dayprint_state(db, label):
    print(f"\nDAYPRINT_STATE {label}")
    print(json.dumps(db.dayprints.docs, default=str, indent=2, sort_keys=True))


@pytest.mark.asyncio
async def test_completing_one_nutrition_task_creates_one_meal_and_dayprint(fake_db, service):
    meal_id = await service.create_meal_from_nutrition_task(
        nutrition_task(),
        emit_dayprint=True,
    )

    assert meal_id
    assert len(fake_db.meals.docs) == 1
    print_dayprint_state(fake_db, "single_complete")
    assert len(meal_logged_events(fake_db)) == 1
    assert len(await dayprint_meal_items()) == 1


@pytest.mark.asyncio
async def test_note_attachment_and_complete_flow_still_results_in_one_dayprint(fake_db, service):
    await service.create_meal_from_nutrition_task(nutrition_task(note="first note"))
    await service.create_meal_from_nutrition_task(
        nutrition_task(
            note="first note",
            attachments=[{
                "attachment_id": "att-1",
                "content_type": "image/jpeg",
                "url": "https://example.test/meal.jpg",
            }],
        )
    )
    await service.create_meal_from_nutrition_task(
        nutrition_task(
            note="final note",
            attachments=[{
                "attachment_id": "att-1",
                "content_type": "image/jpeg",
                "url": "https://example.test/meal.jpg",
            }],
        ),
        emit_dayprint=True,
    )

    assert len(fake_db.meals.docs) == 1
    assert fake_db.meals.docs[0]["note"] == "final note"
    assert fake_db.meals.docs[0]["images"][0]["attachment_id"] == "att-1"
    print_dayprint_state(fake_db, "note_attachment_complete")
    assert len(meal_logged_events(fake_db)) == 1
    items = await dayprint_meal_items()
    assert len(items) == 1
    assert items[0]["data"]["source_type"] == "nutrition_task"
    assert items[0]["data"]["source_task_id"] == "task-nutrition-1"
    assert items[0]["data"]["source_key"] == "nutrition_task:user-1:task-nutrition-1"


@pytest.mark.asyncio
async def test_repeated_complete_bridge_calls_are_idempotent(fake_db, service):
    first = await service.create_meal_from_nutrition_task(
        nutrition_task(),
        emit_dayprint=True,
    )
    second = await service.create_meal_from_nutrition_task(
        nutrition_task(note="eggs and toast with fruit"),
        emit_dayprint=True,
    )

    assert first == second
    assert len(fake_db.meals.docs) == 1
    assert fake_db.meals.docs[0]["note"] == "eggs and toast with fruit"
    print_dayprint_state(fake_db, "repeated_complete")
    assert len(meal_logged_events(fake_db)) == 1
    assert len(await dayprint_meal_items()) == 1


@pytest.mark.asyncio
async def test_concurrent_bridge_calls_do_not_create_duplicates(fake_db, service):
    meal_ids = await asyncio.gather(*[
        service.create_meal_from_nutrition_task(
            nutrition_task(note=f"concurrent note {idx}"),
            emit_dayprint=True,
        )
        for idx in range(10)
    ])

    assert len(set(meal_ids)) == 1
    assert len(fake_db.meals.docs) == 1
    print_dayprint_state(fake_db, "concurrent_bridge")
    assert len(meal_logged_events(fake_db)) == 1
    assert len(await dayprint_meal_items()) == 1


@pytest.mark.asyncio
async def test_existing_source_linked_meal_is_updated_instead_of_duplicated(fake_db, service):
    await fake_db.meals.insert_one({
        "meal_id": "existing-meal",
        "user_id": "user-1",
        "source_type": "nutrition_task",
        "source_task_id": "task-nutrition-1",
        "linked_task_id": "task-nutrition-1",
        "food_items": [{"name": "old"}],
        "macro_ratio": {
            "protein": "low",
            "carbs": "low",
            "fat": "low",
            "fiber": "low",
        },
        "visibility": "team",
        "team_id": "team-1",
        "user_edited": False,
        "created_at": None,
        "updated_at": None,
    })

    meal_id = await service.create_meal_from_nutrition_task(
        nutrition_task(note="updated meal"),
        emit_dayprint=True,
    )

    assert meal_id == "existing-meal"
    assert len(fake_db.meals.docs) == 1
    assert fake_db.meals.docs[0]["food_items"][0]["name"] == "updated meal"
    print_dayprint_state(fake_db, "existing_updated")
    assert len(meal_logged_events(fake_db)) == 1
    assert len(await dayprint_meal_items()) == 1


@pytest.mark.asyncio
async def test_normal_meal_logging_still_shows_one_dayprint_item(fake_db):
    await log_meal_logged(
        user_id="user-1",
        meal_id="manual-meal-1",
        food_preview="yogurt",
        image_url=None,
        visibility="private",
    )

    print_dayprint_state(fake_db, "normal_meal")
    assert len(meal_logged_events(fake_db)) == 1
    items = await dayprint_meal_items()
    assert len(items) == 1
    assert items[0]["data"]["source_type"] == "meal"
    assert items[0]["data"]["source_key"] == "meal:manual-meal-1"


@pytest.mark.asyncio
async def test_dayprint_api_dedupes_legacy_duplicate_meal_events(fake_db):
    await fake_db.dayprints.insert_one({
        "user_id": "user-1",
        "date": dayprint_module._today_utc_str(),
        "events": [
            {
                "event_id": "legacy-1",
                "type": "meal_logged",
                "timestamp": "2026-05-05T10:00:00Z",
                "data": {"meal_id": "meal-legacy", "food_preview": "toast"},
            },
            {
                "event_id": "legacy-2",
                "type": "meal_logged",
                "timestamp": "2026-05-05T10:00:01Z",
                "data": {"meal_id": "meal-legacy", "food_preview": "toast"},
            },
            {
                "event_id": "legacy-3",
                "type": "meal_logged",
                "timestamp": "2026-05-05T10:00:02Z",
                "data": {"meal_id": "meal-legacy", "food_preview": "toast"},
            },
        ],
    })

    print_dayprint_state(fake_db, "legacy_duplicates_raw")
    assert len(meal_logged_events(fake_db)) == 3
    items = await dayprint_meal_items()
    print("DAYPRINT_API_DEDUPED", json.dumps(items, default=str, indent=2))
    assert len(items) == 1
    assert items[0]["event_id"] == "legacy-1"


# ──────────────────────────────────────────────────────────────────────────
# Re-analyze / edit: same meal_id, original meal_time preserved, dayprint
# stays anchored to the canonical meal.
# ──────────────────────────────────────────────────────────────────────────

from app.models.meal import (
    FoodItem as _FoodItem,
    MacroLevel as _MacroLevel,
    MacroRatio as _MacroRatio,
    MealUpdate as _MealUpdate,
    NutritionLevel as _NutritionLevel,
)


def _seed_meal(
    db,
    meal_id="m1",
    user_id="user-1",
    food_name="oatmeal",
    meal_time="2026-05-05T11:00:00Z",
    created_at=None,
    *,
    source_type=None,
    source_task_id=None,
    linked_task_id=None,
):
    if created_at is None:
        created_at = datetime(2026, 5, 5, 11, 0, 0)
    doc = {
        "meal_id": meal_id,
        "user_id": user_id,
        "images": [],
        "food_items": [{"name": food_name, "portion_weight": 1}],
        "macro_ratio": {
            "protein": "moderate",
            "carbs": "moderate",
            "fat": "moderate",
            "fiber": "low",
        },
        "note": None,
        "visibility": "private",
        "team_id": None,
        "linked_task_id": linked_task_id,
        "meal_name": food_name.title(),
        "meal_type": "Breakfast",
        "meal_time": meal_time,
        "nutrition_level": "Good",
        "advisor_insight": None,
        "processing_level": "low",
        "added_sugar": "low",
        "user_edited": False,
        "created_at": created_at,
        "updated_at": created_at,
    }
    if source_type:
        doc["source_type"] = source_type
    if source_task_id:
        doc["source_task_id"] = source_task_id
    db.meals.docs.append(doc)
    return doc


@pytest.mark.asyncio
async def test_reanalyze_existing_meal_keeps_same_meal_id_and_meal_time(fake_db, service):
    seeded = _seed_meal(fake_db)
    original_created = seeded["created_at"]

    # The detail screen sends a fresh "now" value for meal_time. The backend
    # must IGNORE it during re-analyze and keep 11:00am.
    update = _MealUpdate(
        food_items=[
            _FoodItem(name="steel-cut oats with berries", portion_weight=2),
        ],
        meal_time="2026-05-05T11:20:00Z",
    )

    response = await service.update_meal("m1", "user-1", update)

    assert response.meal_id == "m1"
    assert len(fake_db.meals.docs) == 1, "no new meal row may be inserted"
    stored = fake_db.meals.docs[0]
    assert stored["meal_time"] == "2026-05-05T11:00:00Z", \
        "meal_time must stay anchored to the original logged time"
    assert stored["created_at"] == original_created, \
        "created_at must never move on re-analyze"
    assert stored["updated_at"] != original_created, \
        "updated_at must advance on re-analyze"
    # The structuring fixture echoes the food name back as meal_name —
    # confirm re-analysis fields actually moved.
    assert stored["food_items"][0]["name"] == "steel-cut oats with berries"


@pytest.mark.asyncio
async def test_reanalyze_does_not_create_new_dayprint_item(fake_db, service):
    _seed_meal(fake_db)
    # Pre-existing dayprint event from when the meal was first logged.
    today = dayprint_module._today_utc_str()
    fake_db.dayprints.docs.append({
        "user_id": "user-1",
        "date": today,
        "events": [
            {
                "event_id": "evt-1",
                "type": "meal_logged",
                "timestamp": "2026-05-05T11:00:00Z",
                "data": {
                    "meal_id": "m1",
                    "food_preview": "oatmeal",
                    "source_type": "meal",
                    "source_key": "meal_logged:meal:m1",
                },
            },
        ],
    })

    update = _MealUpdate(
        food_items=[_FoodItem(name="oats with banana", portion_weight=1)],
    )
    await service.update_meal("m1", "user-1", update)

    items = await dayprint_meal_items()
    assert len(items) == 1, "re-analyze must not append a new dayprint item"
    assert items[0]["data"]["meal_id"] == "m1", \
        "dayprint must keep pointing at the canonical meal_id"


@pytest.mark.asyncio
async def test_duplicate_source_linked_meals_are_consolidated_to_one_canonical(fake_db, service):
    # Two duplicates inserted via direct doc append to bypass the unique
    # source guard (this simulates legacy data that pre-dates the index).
    canonical_created = datetime(2026, 5, 5, 11, 0, 0)
    dup_created = datetime(2026, 5, 5, 11, 5, 0)
    _seed_meal(
        fake_db,
        meal_id="canonical",
        food_name="eggs",
        meal_time="2026-05-05T11:00:00Z",
        created_at=canonical_created,
        source_type="nutrition_task",
        source_task_id="task-nutrition-1",
        linked_task_id="task-nutrition-1",
    )
    _seed_meal(
        fake_db,
        meal_id="duplicate",
        food_name="eggs and toast",
        meal_time="2026-05-05T11:05:00Z",
        created_at=dup_created,
        source_type="nutrition_task",
        source_task_id="task-nutrition-1",
        linked_task_id="task-nutrition-1",
    )

    # Dayprint events that point at BOTH the canonical and the duplicate.
    today = dayprint_module._today_utc_str()
    fake_db.dayprints.docs.append({
        "user_id": "user-1",
        "date": today,
        "events": [
            {
                "event_id": "evt-canonical",
                "type": "meal_logged",
                "timestamp": "2026-05-05T11:00:00Z",
                "data": {
                    "meal_id": "canonical",
                    "food_preview": "eggs",
                    "source_type": "nutrition_task_meal",
                    "source_task_id": "task-nutrition-1",
                    "source_key": "meal_logged:nutrition_task_meal:task-nutrition-1:canonical",
                },
            },
            {
                "event_id": "evt-duplicate",
                "type": "meal_logged",
                "timestamp": "2026-05-05T11:05:00Z",
                "data": {
                    "meal_id": "duplicate",
                    "food_preview": "eggs and toast",
                    "source_type": "nutrition_task_meal",
                    "source_task_id": "task-nutrition-1",
                    "source_key": "meal_logged:nutrition_task_meal:task-nutrition-1:duplicate",
                },
            },
        ],
    })

    meal_id = await service.create_meal_from_nutrition_task(
        nutrition_task(note="eggs and toast"),
        emit_dayprint=True,
    )

    assert meal_id == "canonical"
    assert len(fake_db.meals.docs) == 1
    assert fake_db.meals.docs[0]["meal_id"] == "canonical"
    assert fake_db.meals.docs[0]["meal_time"] == "2026-05-05T11:00:00Z"

    # All dayprint events that referenced "duplicate" must be rewritten to
    # the canonical meal_id, then collapsed by the source_key dedupe pass.
    print_dayprint_state(fake_db, "after_consolidation")
    items = await dayprint_meal_items()
    assert all(it["data"]["meal_id"] == "canonical" for it in items), \
        "no dayprint event may still point at the dropped duplicate"


@pytest.mark.asyncio
async def test_normal_meals_at_different_times_are_not_merged(fake_db, service):
    # Two manually-logged meals with the same name but different times; no
    # source_type so they should never trigger consolidation.
    _seed_meal(
        fake_db,
        meal_id="manual-1",
        food_name="oatmeal",
        meal_time="2026-05-05T08:00:00Z",
        created_at=datetime(2026, 5, 5, 8, 0, 0),
    )
    _seed_meal(
        fake_db,
        meal_id="manual-2",
        food_name="oatmeal",
        meal_time="2026-05-05T15:00:00Z",
        created_at=datetime(2026, 5, 5, 15, 0, 0),
    )

    # An unrelated nutrition task bridge call must NOT touch them.
    await service.create_meal_from_nutrition_task(
        nutrition_task(task_id="other-task", note="apple"),
    )

    meal_ids = sorted(d["meal_id"] for d in fake_db.meals.docs if not d.get("source_type"))
    assert meal_ids == ["manual-1", "manual-2"], \
        "manual meals at different times must never be merged"


# ──────────────────────────────────────────────────────────────────────────
# Historical-duplicate migration (migrate_dedupe_meals.py)
# Runs against a populated DB that pre-dates the unique partial index.
# ──────────────────────────────────────────────────────────────────────────

import importlib.util as _importlib_util


def _load_migration():
    spec = _importlib_util.spec_from_file_location(
        "migrate_dedupe_meals",
        Path(__file__).resolve().parents[1] / "migrate_dedupe_meals.py",
    )
    mod = _importlib_util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _seed_dup_pair(db, *, source_task_id, canonical_id, dup_id, today):
    """Insert a canonical+duplicate meal pair and matching dayprint events."""
    canonical_created = datetime(2026, 5, 5, 11, 0, 0)
    dup_created = datetime(2026, 5, 5, 11, 5, 0)
    _seed_meal(
        db,
        meal_id=canonical_id,
        food_name="canonical food",
        meal_time="2026-05-05T11:00:00Z",
        created_at=canonical_created,
        source_type="nutrition_task",
        source_task_id=source_task_id,
        linked_task_id=source_task_id,
    )
    _seed_meal(
        db,
        meal_id=dup_id,
        food_name="duplicate food",
        meal_time="2026-05-05T11:05:00Z",
        created_at=dup_created,
        source_type="nutrition_task",
        source_task_id=source_task_id,
        linked_task_id=source_task_id,
    )
    db.dayprints.docs.append({
        "user_id": "user-1",
        "date": today,
        "events": [
            {
                "event_id": f"evt-{canonical_id}",
                "type": "meal_logged",
                "timestamp": "2026-05-05T11:00:00Z",
                "data": {
                    "meal_id": canonical_id,
                    "food_preview": "canonical food",
                },
            },
            {
                "event_id": f"evt-{dup_id}",
                "type": "meal_logged",
                "timestamp": "2026-05-05T11:05:00Z",
                "data": {
                    "meal_id": dup_id,
                    "food_preview": "duplicate food",
                },
            },
        ],
    })


@pytest.mark.asyncio
async def test_migration_dry_run_does_not_mutate_db(fake_db):
    today = dayprint_module._today_utc_str()
    _seed_dup_pair(
        fake_db,
        source_task_id="task-1",
        canonical_id="canonical-1",
        dup_id="dup-1",
        today=today,
    )

    migration = _load_migration()
    output_lines: list[str] = []
    stats = await migration.run(fake_db, apply=False, out=output_lines.append)

    assert stats["groups"] == 1
    assert stats["duplicates"] == 1
    assert stats["meals_deleted"] == 0, "dry-run must not delete anything"
    assert stats["dayprints_rewritten"] == 0
    assert len(fake_db.meals.docs) == 2, "dry-run leaves both meals"
    raw_events = fake_db.dayprints.docs[0]["events"]
    assert len(raw_events) == 2, "dry-run leaves dayprint untouched"
    # The dry-run output should at least show canonical + dropped meal_ids so an
    # operator can review the plan before re-running with --apply.
    output = "\n".join(output_lines)
    assert "canonical-1" in output
    assert "dup-1" in output
    assert "Dry-run only" in output


@pytest.mark.asyncio
async def test_migration_apply_collapses_duplicates_and_rewrites_dayprint(fake_db):
    today = dayprint_module._today_utc_str()
    _seed_dup_pair(
        fake_db,
        source_task_id="task-1",
        canonical_id="canonical-1",
        dup_id="dup-1",
        today=today,
    )

    migration = _load_migration()
    stats = await migration.run(fake_db, apply=True, out=lambda *_: None)

    assert stats["meals_deleted"] == 1
    assert stats["dayprints_rewritten"] >= 1
    # Canonical survives, with original 11:00 meal_time intact.
    assert len(fake_db.meals.docs) == 1
    surviving = fake_db.meals.docs[0]
    assert surviving["meal_id"] == "canonical-1"
    assert surviving["meal_time"] == "2026-05-05T11:00:00Z"

    # Dayprint events are rewritten to the canonical meal_id and the duplicate
    # event collapses to one entry per (date, meal_id).
    events = fake_db.dayprints.docs[0]["events"]
    assert len(events) == 1, f"expected 1 event, got: {events}"
    assert events[0]["data"]["meal_id"] == "canonical-1"


@pytest.mark.asyncio
async def test_migration_apply_handles_three_way_duplicates(fake_db):
    today = dayprint_module._today_utc_str()
    canonical_created = datetime(2026, 5, 5, 9, 0, 0)
    mid_created = datetime(2026, 5, 5, 10, 0, 0)
    late_created = datetime(2026, 5, 5, 11, 0, 0)
    _seed_meal(
        fake_db,
        meal_id="oldest",
        meal_time="2026-05-05T09:00:00Z",
        created_at=canonical_created,
        source_type="nutrition_task",
        source_task_id="task-x",
        linked_task_id="task-x",
    )
    _seed_meal(
        fake_db,
        meal_id="middle",
        meal_time="2026-05-05T10:00:00Z",
        created_at=mid_created,
        source_type="nutrition_task",
        source_task_id="task-x",
        linked_task_id="task-x",
    )
    _seed_meal(
        fake_db,
        meal_id="newest",
        meal_time="2026-05-05T11:00:00Z",
        created_at=late_created,
        source_type="nutrition_task",
        source_task_id="task-x",
        linked_task_id="task-x",
    )
    fake_db.dayprints.docs.append({
        "user_id": "user-1",
        "date": today,
        "events": [
            {
                "event_id": f"evt-{mid}",
                "type": "meal_logged",
                "timestamp": "2026-05-05T10:00:00Z",
                "data": {"meal_id": mid, "food_preview": "x"},
            }
            for mid in ("oldest", "middle", "newest")
        ],
    })

    migration = _load_migration()
    await migration.run(fake_db, apply=True, out=lambda *_: None)

    # Oldest wins, both younger duplicates removed.
    surviving_ids = sorted(d["meal_id"] for d in fake_db.meals.docs)
    assert surviving_ids == ["oldest"]
    events = fake_db.dayprints.docs[0]["events"]
    assert len(events) == 1
    assert events[0]["data"]["meal_id"] == "oldest"


@pytest.mark.asyncio
async def test_migration_apply_does_not_merge_normal_manual_meals(fake_db):
    # Two manually-logged meals (no source_type) at different times. The
    # migration must leave them alone — same name + same user is NOT a
    # duplicate signal for normal logs.
    _seed_meal(
        fake_db,
        meal_id="manual-1",
        food_name="oatmeal",
        meal_time="2026-05-05T08:00:00Z",
        created_at=datetime(2026, 5, 5, 8, 0, 0),
    )
    _seed_meal(
        fake_db,
        meal_id="manual-2",
        food_name="oatmeal",
        meal_time="2026-05-05T15:00:00Z",
        created_at=datetime(2026, 5, 5, 15, 0, 0),
    )

    migration = _load_migration()
    stats = await migration.run(fake_db, apply=True, out=lambda *_: None)

    assert stats["groups"] == 0
    assert stats["meals_deleted"] == 0
    surviving = sorted(d["meal_id"] for d in fake_db.meals.docs)
    assert surviving == ["manual-1", "manual-2"]


@pytest.mark.asyncio
async def test_migration_apply_does_not_merge_meals_from_different_tasks(fake_db):
    today = dayprint_module._today_utc_str()
    # Two meals, each their OWN canonical from different source tasks. The
    # migration should leave both standing — they're not a duplicate group.
    _seed_meal(
        fake_db,
        meal_id="task-a-meal",
        meal_time="2026-05-05T08:00:00Z",
        created_at=datetime(2026, 5, 5, 8, 0, 0),
        source_type="nutrition_task",
        source_task_id="task-a",
        linked_task_id="task-a",
    )
    _seed_meal(
        fake_db,
        meal_id="task-b-meal",
        meal_time="2026-05-05T15:00:00Z",
        created_at=datetime(2026, 5, 5, 15, 0, 0),
        source_type="nutrition_task",
        source_task_id="task-b",
        linked_task_id="task-b",
    )

    migration = _load_migration()
    stats = await migration.run(fake_db, apply=True, out=lambda *_: None)

    assert stats["groups"] == 0
    surviving = sorted(d["meal_id"] for d in fake_db.meals.docs)
    assert surviving == ["task-a-meal", "task-b-meal"]


@pytest.mark.asyncio
async def test_migration_is_idempotent(fake_db):
    today = dayprint_module._today_utc_str()
    _seed_dup_pair(
        fake_db,
        source_task_id="task-1",
        canonical_id="canonical-1",
        dup_id="dup-1",
        today=today,
    )

    migration = _load_migration()
    await migration.run(fake_db, apply=True, out=lambda *_: None)
    # Running a second time should be a no-op.
    stats = await migration.run(fake_db, apply=True, out=lambda *_: None)
    assert stats["groups"] == 0
    assert stats["meals_deleted"] == 0
    assert len(fake_db.meals.docs) == 1


@pytest.mark.asyncio
async def test_migration_supports_filters(fake_db):
    today = dayprint_module._today_utc_str()
    # Two duplicate groups: one for user-1, one for user-2. With user-id
    # filter, only the targeted group should be touched.
    _seed_dup_pair(
        fake_db,
        source_task_id="task-1",
        canonical_id="u1-canonical",
        dup_id="u1-dup",
        today=today,
    )
    fake_db.meals.docs.append({
        "meal_id": "u2-canonical",
        "user_id": "user-2",
        "source_type": "nutrition_task",
        "source_task_id": "task-2",
        "linked_task_id": "task-2",
        "food_items": [{"name": "x", "portion_weight": 1}],
        "macro_ratio": {
            "protein": "low", "carbs": "low", "fat": "low", "fiber": "low",
        },
        "visibility": "private",
        "team_id": None,
        "meal_time": "2026-05-05T08:00:00Z",
        "created_at": datetime(2026, 5, 5, 8, 0, 0),
        "updated_at": datetime(2026, 5, 5, 8, 0, 0),
    })
    fake_db.meals.docs.append({
        "meal_id": "u2-dup",
        "user_id": "user-2",
        "source_type": "nutrition_task",
        "source_task_id": "task-2",
        "linked_task_id": "task-2",
        "food_items": [{"name": "x", "portion_weight": 1}],
        "macro_ratio": {
            "protein": "low", "carbs": "low", "fat": "low", "fiber": "low",
        },
        "visibility": "private",
        "team_id": None,
        "meal_time": "2026-05-05T08:30:00Z",
        "created_at": datetime(2026, 5, 5, 8, 30, 0),
        "updated_at": datetime(2026, 5, 5, 8, 30, 0),
    })

    migration = _load_migration()
    stats = await migration.run(
        fake_db, apply=True, user_id="user-1", out=lambda *_: None,
    )
    assert stats["meals_deleted"] == 1
    surviving = sorted(d["meal_id"] for d in fake_db.meals.docs)
    assert surviving == ["u1-canonical", "u2-canonical", "u2-dup"], \
        "user-2 group must be untouched when --user-id targets user-1"


# ──────────────────────────────────────────────────────────────────────────
# Full Nutrition-task lifecycle: assertions on Dayprint output, not just
# meals count. This is the core regression suite for the "3 dayprint rows"
# bug — every lifecycle trigger must collapse to one canonical visible event.
# ──────────────────────────────────────────────────────────────────────────


from app.services.dayprint_service import (
    canonical_event_source_key,
    log_task_completed,
)


@pytest.mark.asyncio
async def test_full_lifecycle_create_update_upload_complete_yields_one_dayprint_item(
    fake_db, service,
):
    """Mirrors the real route flow: create + updateNote + uploadAttachments +
    completeTask. Every trigger fires a bridge call; only the completion
    emits to dayprint. Must end with 1 meal + 1 dayprint event."""
    # Create-time bridge (no images yet, no completion).
    await service.create_meal_from_nutrition_task(
        nutrition_task(note="initial"),
    )
    # updateNote bridge.
    await service.create_meal_from_nutrition_task(
        nutrition_task(note="eggs and toast"),
    )
    # uploadAttachments bridge.
    await service.create_meal_from_nutrition_task(
        nutrition_task(
            note="eggs and toast",
            attachments=[{
                "attachment_id": "att-1",
                "content_type": "image/jpeg",
                "url": "https://example.test/m.jpg",
            }],
        ),
    )
    # completeTask: emit_dayprint=True for the first and ONLY dayprint write.
    await service.create_meal_from_nutrition_task(
        nutrition_task(
            note="eggs and toast with fruit",
            attachments=[{
                "attachment_id": "att-1",
                "content_type": "image/jpeg",
                "url": "https://example.test/m.jpg",
            }],
        ),
        emit_dayprint=True,
    )

    assert len(fake_db.meals.docs) == 1, "exactly one meal across the lifecycle"
    print_dayprint_state(fake_db, "full_lifecycle")
    items = await dayprint_meal_items()
    assert len(items) == 1
    assert items[0]["data"]["source_key"] == "nutrition_task:user-1:task-nutrition-1"
    assert items[0]["data"]["source_type"] == "nutrition_task"


@pytest.mark.asyncio
async def test_repeated_complete_task_yields_one_dayprint_item(fake_db, service):
    """Calling completeTask twice (e.g. flaky network retry) must not produce
    two dayprint rows."""
    for _ in range(3):
        await service.create_meal_from_nutrition_task(
            nutrition_task(note="eggs"),
            emit_dayprint=True,
        )

    assert len(fake_db.meals.docs) == 1
    items = await dayprint_meal_items()
    assert len(items) == 1


@pytest.mark.asyncio
async def test_concurrent_bridge_calls_yield_one_dayprint_item(fake_db, service):
    await asyncio.gather(*[
        service.create_meal_from_nutrition_task(
            nutrition_task(note=f"concurrent {i}"),
            emit_dayprint=True,
        )
        for i in range(8)
    ])

    assert len(fake_db.meals.docs) == 1
    items = await dayprint_meal_items()
    assert len(items) == 1


@pytest.mark.asyncio
async def test_log_task_completed_skipped_for_nutrition_tasks(fake_db):
    """The route fires log_task_completed for every task. For Nutrition
    tasks, the bridge's meal_logged subsumes it; log_task_completed must
    no-op so the dayprint never gains a parallel task_completed entry."""
    today = dayprint_module._today_utc_str()
    fake_db.dayprints.docs.append({
        "user_id": "user-1",
        "date": today,
        "events": [],
    })

    await log_task_completed(
        user_id="user-1",
        task_name="Lunch log",
        task_type="Nutrition",
        source_task_id="task-nutrition-1",
    )

    raw_events = fake_db.dayprints.docs[0]["events"]
    assert raw_events == [], \
        "log_task_completed must skip nutrition tasks"


@pytest.mark.asyncio
async def test_log_task_completed_still_fires_for_non_nutrition_tasks(fake_db):
    today = dayprint_module._today_utc_str()
    fake_db.dayprints.docs.append({
        "user_id": "user-1",
        "date": today,
        "events": [],
    })

    await log_task_completed(
        user_id="user-1",
        task_name="Take meds",
        task_type="Medication",
        source_task_id="med-1",
    )

    raw_events = fake_db.dayprints.docs[0]["events"]
    assert len(raw_events) == 1
    assert raw_events[0]["type"] == "task_completed"
    assert raw_events[0]["data"]["source_key"] == "task:user-1:med-1"


@pytest.mark.asyncio
async def test_legacy_mixed_source_keys_collapse_at_read_time(fake_db):
    """The real "3 dayprints" bug: pre-dedupe-index data left three events
    for the same nutrition task in one dayprint —

      • two bridge writes from different meal_ids (the bridge created a new
        meal row on every lifecycle trigger before the unique index)
      • one task_completed from the route firing alongside the bridge

    All three carry `source_task_id`, so the canonical scheme buckets them
    on `nutrition_task:<user>:<task>` and the read-time dedupe collapses
    them to one visible item — without mutating the underlying document.
    """
    today = dayprint_module._today_utc_str()
    fake_db.dayprints.docs.append({
        "user_id": "user-1",
        "date": today,
        "events": [
            {
                "event_id": "legacy-bridge-A",
                "type": "meal_logged",
                "timestamp": "2026-05-05T10:59:00Z",
                "data": {
                    "meal_id": "old-meal-A",
                    "source_type": "nutrition_task_meal",
                    "source_task_id": "task-nutrition-1",
                    "source_key": "meal_logged:nutrition_task_meal:task-nutrition-1:old-meal-A",
                },
            },
            {
                "event_id": "legacy-task-completed",
                "type": "task_completed",
                "timestamp": "2026-05-05T11:00:00Z",
                "data": {
                    "task_name": "Nutrition log",
                    "task_type": "Nutrition",
                    "source_task_id": "task-nutrition-1",
                    "source_key": "task_completed:task:task-nutrition-1",
                },
            },
            {
                "event_id": "legacy-bridge-B",
                "type": "meal_logged",
                "timestamp": "2026-05-05T11:00:01Z",
                "data": {
                    "meal_id": "old-meal-B",
                    "source_type": "nutrition_task_meal",
                    "source_task_id": "task-nutrition-1",
                    "source_key": "meal_logged:nutrition_task_meal:task-nutrition-1:old-meal-B",
                },
            },
        ],
    })

    raw_doc = await get_dayprint("user-1")
    print_dayprint_state(fake_db, "legacy_mixed")
    print("ITEMS RETURNED:", json.dumps(raw_doc["events"], default=str, indent=2))
    # Three legacy events collapse to ONE visible entry. The keeper is the
    # earliest meal_logged — task_completed loses to meal_logged on tie.
    assert len(raw_doc["events"]) == 1
    keeper = raw_doc["events"][0]
    assert keeper["type"] == "meal_logged"
    assert keeper["event_id"] == "legacy-bridge-A"


@pytest.mark.asyncio
async def test_canonical_source_key_for_nutrition_task_meal():
    key = canonical_event_source_key(
        user_id="u1",
        event_type="meal_logged",
        source_task_id="task-1",
        source_type="nutrition_task",
        meal_id="anything",
    )
    assert key == "nutrition_task:u1:task-1"


@pytest.mark.asyncio
async def test_canonical_source_key_collapses_task_completed_for_nutrition_task():
    """task_completed event for a nutrition task must produce the SAME key
    as the meal_logged event for that task — that's how the legacy
    task_completed entries dedupe at read time."""
    meal_key = canonical_event_source_key(
        user_id="u1",
        event_type="meal_logged",
        source_task_id="task-1",
        source_type="nutrition_task",
        meal_id="m1",
    )
    completed_key = canonical_event_source_key(
        user_id="u1",
        event_type="task_completed",
        source_task_id="task-1",
        task_type="Nutrition",
    )
    assert meal_key == completed_key == "nutrition_task:u1:task-1"


@pytest.mark.asyncio
async def test_canonical_source_key_for_manual_meal_uses_meal_id():
    key = canonical_event_source_key(
        user_id="u1",
        event_type="meal_logged",
        source_task_id=None,
        source_type="meal",
        meal_id="m1",
    )
    assert key == "meal:m1"


@pytest.mark.asyncio
async def test_re_bridge_after_food_edit_refreshes_dayprint_event_in_place(
    fake_db, service,
):
    """When the bridge runs again after the user edits the task note, the
    existing dayprint event must update its food_preview — NOT push a new
    row alongside the old one."""
    await service.create_meal_from_nutrition_task(
        nutrition_task(note="eggs"),
        emit_dayprint=True,
    )
    items_before = await dayprint_meal_items()
    assert len(items_before) == 1
    # Capture immutable scalars — the FakeCollection returns shallow copies,
    # so dict references would otherwise mutate under us when the second
    # bridge call replaces `event["data"]` in place.
    first_event_id = items_before[0]["event_id"]
    first_timestamp = items_before[0]["timestamp"]
    first_preview = items_before[0]["data"]["food_preview"]

    # User edits the note; bridge fires again with the same source identity.
    await service.create_meal_from_nutrition_task(
        nutrition_task(note="eggs and avocado toast"),
        emit_dayprint=True,
    )
    items_after = await dayprint_meal_items()
    assert len(items_after) == 1
    # Same event row, refreshed payload.
    assert items_after[0]["event_id"] == first_event_id, \
        "the original event_id must be preserved across re-bridges"
    assert items_after[0]["timestamp"] == first_timestamp, \
        "original logged-at timestamp must be preserved on the dayprint row"
    assert items_after[0]["data"]["food_preview"] != first_preview, \
        "food_preview should refresh to reflect the edited foods"
    assert "avocado" in items_after[0]["data"]["food_preview"]


@pytest.mark.asyncio
async def test_migration_dayprint_pass_collapses_legacy_three_event_pattern(fake_db):
    """Real-world legacy state: three events for the same nutrition task
    written before the unified scheme. The migration's pass-2 must keep
    one canonical event and pull the other two — even when there's no
    duplicate in the meals collection to trigger pass-1."""
    today = dayprint_module._today_utc_str()
    fake_db.dayprints.docs.append({
        "user_id": "user-1",
        "date": today,
        "events": [
            {
                "event_id": "legacy-1",
                "type": "meal_logged",
                "timestamp": "2026-05-05T10:59:00Z",
                "data": {
                    "meal_id": "old-meal",
                    "source_type": "nutrition_task_meal",
                    "source_task_id": "task-nutrition-1",
                    "source_key": "meal_logged:nutrition_task_meal:task-nutrition-1:old-meal",
                },
            },
            {
                "event_id": "legacy-2",
                "type": "task_completed",
                "timestamp": "2026-05-05T11:00:00Z",
                "data": {
                    "task_name": "Nutrition log",
                    "task_type": "Nutrition",
                    "source_task_id": "task-nutrition-1",
                    "source_key": "task_completed:task:task-nutrition-1",
                },
            },
            {
                "event_id": "legacy-3",
                "type": "meal_logged",
                "timestamp": "2026-05-05T11:00:01Z",
                "data": {
                    "meal_id": "old-meal-other",
                    "source_type": "nutrition_task_meal",
                    "source_task_id": "task-nutrition-1",
                    "source_key": "meal_logged:nutrition_task_meal:task-nutrition-1:old-meal-other",
                },
            },
        ],
    })
    # Manual canonical meal that the legacy events should converge on.
    fake_db.meals.docs.append({
        "meal_id": "old-meal",
        "user_id": "user-1",
        "source_type": "nutrition_task",
        "source_task_id": "task-nutrition-1",
        "linked_task_id": "task-nutrition-1",
        "food_items": [{"name": "eggs", "portion_weight": 1}],
        "macro_ratio": {
            "protein": "low", "carbs": "low", "fat": "low", "fiber": "low",
        },
        "visibility": "private",
        "team_id": None,
        "meal_time": "2026-05-05T11:00:00Z",
        "created_at": datetime(2026, 5, 5, 11, 0, 0),
        "updated_at": datetime(2026, 5, 5, 11, 0, 0),
    })

    migration = _load_migration()
    output: list[str] = []
    stats = await migration.run(fake_db, apply=False, out=output.append)
    print("DRY RUN OUTPUT:\n" + "\n".join(output))
    assert stats["dayprint_dup_groups"] == 1
    # Dry run never mutates.
    assert len(fake_db.dayprints.docs[0]["events"]) == 3

    stats = await migration.run(fake_db, apply=True, out=lambda *_: None)
    assert stats["dayprint_event_canonicalizations"] == 1
    assert stats["dayprint_events_removed"] >= 2

    raw = fake_db.dayprints.docs[0]["events"]
    assert len(raw) == 1, f"expected 1 event after migration, got: {raw}"
    keeper = raw[0]
    # Earliest by timestamp wins — that's legacy-1 (manual meal_logged).
    assert keeper["event_id"] == "legacy-1"
    assert keeper["data"]["source_key"] == "nutrition_task:user-1:task-nutrition-1"
    assert keeper["data"]["meal_id"] == "old-meal"


# ──────────────────────────────────────────────────────────────────────────
# End-to-end: legacy mess BEFORE the fix → clean state AFTER migration.
# Locks in the contract that the fix is complete only when:
#   • read-time dedupe already hides the mess from the API (resilience layer)
#   • --apply permanently cleans both meals and dayprint storage
#   • after --apply, Meals list API and Dayprint API each return 1 visible row
# ──────────────────────────────────────────────────────────────────────────


from app.services.dayprint_service import get_dayprint as _get_dayprint


@pytest.mark.asyncio
async def test_full_legacy_mess_collapses_at_api_layer_and_after_migration(fake_db):
    """Worst-realistic legacy state covering all three issue classes:
        1. duplicate meal rows (pre-unique-index)
        2. duplicate dayprint meal_logged events
        3. mixed legacy source_key formats + a stray task_completed
    The Dayprint API dedupes at read time so users never see the mess —
    AND the migration permanently collapses the underlying storage.
    """
    today = "2026-05-05"

    # Two duplicate meal rows for the same nutrition task.
    fake_db.meals.docs.append({
        "meal_id": "canonical-meal",
        "user_id": "user-1",
        "source_type": "nutrition_task",
        "source_task_id": "task-N",
        "linked_task_id": "task-N",
        "food_items": [{"name": "eggs", "portion_weight": 1}],
        "macro_ratio": {
            "protein": "moderate", "carbs": "low",
            "fat": "moderate", "fiber": "low",
        },
        "visibility": "private", "team_id": None,
        "meal_time": "2026-05-05T11:00:00Z",
        "created_at": datetime(2026, 5, 5, 11, 0, 0),
        "updated_at": datetime(2026, 5, 5, 11, 0, 0),
    })
    fake_db.meals.docs.append({
        "meal_id": "duplicate-meal",
        "user_id": "user-1",
        "source_type": "nutrition_task",
        "source_task_id": "task-N",
        "linked_task_id": "task-N",
        "food_items": [{"name": "eggs and toast", "portion_weight": 1}],
        "macro_ratio": {
            "protein": "moderate", "carbs": "high",
            "fat": "moderate", "fiber": "low",
        },
        "visibility": "private", "team_id": None,
        "meal_time": "2026-05-05T11:05:00Z",
        "created_at": datetime(2026, 5, 5, 11, 5, 0),
        "updated_at": datetime(2026, 5, 5, 11, 5, 0),
    })
    # Three dayprint events — two pointing at different meal_ids with the
    # legacy composite source_key, plus a stray task_completed from when
    # log_task_completed used to fire for nutrition tasks.
    fake_db.dayprints.docs.append({
        "user_id": "user-1",
        "date": today,
        "events": [
            {
                "event_id": "e1",
                "type": "meal_logged",
                "timestamp": "2026-05-05T11:00:30Z",
                "data": {
                    "meal_id": "canonical-meal",
                    "source_type": "nutrition_task_meal",
                    "source_task_id": "task-N",
                    "source_key": "meal_logged:nutrition_task_meal:task-N:canonical-meal",
                    "food_preview": "eggs",
                },
            },
            {
                "event_id": "e2",
                "type": "task_completed",
                "timestamp": "2026-05-05T11:00:45Z",
                "data": {
                    "task_name": "Lunch",
                    "task_type": "Nutrition",
                    "source_task_id": "task-N",
                    "source_key": "task_completed:task:task-N",
                },
            },
            {
                "event_id": "e3",
                "type": "meal_logged",
                "timestamp": "2026-05-05T11:05:30Z",
                "data": {
                    "meal_id": "duplicate-meal",
                    "source_type": "nutrition_task_meal",
                    "source_task_id": "task-N",
                    "source_key": "meal_logged:nutrition_task_meal:task-N:duplicate-meal",
                    "food_preview": "eggs and toast",
                },
            },
        ],
    })

    # ── BEFORE migration ────────────────────────────────────────────────
    # Storage still holds the mess (2 meals, 3 events) — but the Dayprint
    # API's read-time dedupe collapses to 1 visible item RIGHT NOW.
    pre_doc = await _get_dayprint("user-1", today)
    assert len(fake_db.meals.docs) == 2, "raw meals storage is still messy"
    assert len(fake_db.dayprints.docs[0]["events"]) == 3, "raw dayprint storage is still messy"
    assert len(pre_doc["events"]) == 1, \
        "Dayprint API must already hide legacy mess via read-time dedupe"
    assert pre_doc["events"][0]["type"] == "meal_logged"

    print_dayprint_state(fake_db, "BEFORE_migration")

    # ── APPLY migration ─────────────────────────────────────────────────
    migration = _load_migration()
    output: list[str] = []
    stats = await migration.run(fake_db, apply=True, out=output.append)

    # Pass-1 reports the duplicate meal group.
    assert stats["groups"] == 1
    assert stats["meals_deleted"] == 1
    # Pass-2 reports the duplicate dayprint group.
    assert stats["dayprint_dup_groups"] == 1
    assert stats["dayprint_event_canonicalizations"] == 1
    assert stats["dayprint_events_removed"] >= 2

    # ── AFTER migration ────────────────────────────────────────────────
    # Storage is now clean.
    assert len(fake_db.meals.docs) == 1
    surviving_meal = fake_db.meals.docs[0]
    assert surviving_meal["meal_id"] == "canonical-meal"
    assert surviving_meal["meal_time"] == "2026-05-05T11:00:00Z", \
        "canonical's original logged-at time must be preserved"

    raw_events = fake_db.dayprints.docs[0]["events"]
    assert len(raw_events) == 1, \
        f"exactly 1 dayprint event must survive, got: {raw_events}"
    keeper = raw_events[0]
    assert keeper["event_id"] == "e1", \
        "earliest timestamp event must be the keeper"
    assert keeper["timestamp"] == "2026-05-05T11:00:30Z", \
        "original event timestamp must be preserved"
    assert keeper["data"]["meal_id"] == "canonical-meal", \
        "surviving event must point at the canonical meal_id"
    assert keeper["data"]["source_key"] == "nutrition_task:user-1:task-N", \
        "surviving event must use the unified canonical source_key"

    # ── API surface contract ───────────────────────────────────────────
    # Both APIs must return exactly 1 visible row for this user/date.
    post_doc = await _get_dayprint("user-1", today)
    assert len(post_doc["events"]) == 1
    assert post_doc["events"][0]["data"]["meal_id"] == "canonical-meal"

    # Meals listing query — same as the GET /meals/me path.
    visible_meals = [
        m for m in fake_db.meals.docs if m.get("user_id") == "user-1"
    ]
    assert len(visible_meals) == 1
    assert visible_meals[0]["meal_id"] == "canonical-meal"

    print_dayprint_state(fake_db, "AFTER_migration")
    print("APPLY OUTPUT:\n" + "\n".join(output))


# ──────────────────────────────────────────────────────────────────────────
# Meals page (GET /meals/me) defensive dedupe — exercises the EXACT path
# the Flutter MealsHomeScreen uses, with legacy duplicate rows still in
# storage. The Meals API must return one card per canonical identity even
# before the migration runs.
# ──────────────────────────────────────────────────────────────────────────


def _seed_source_meal(db, meal_id, *, task_id, created_at, food_name="eggs",
                     meal_time=None):
    db.meals.docs.append({
        "meal_id": meal_id,
        "user_id": "user-1",
        "source_type": "nutrition_task",
        "source_task_id": task_id,
        "linked_task_id": task_id,
        "food_items": [{"name": food_name, "portion_weight": 1}],
        "macro_ratio": {
            "protein": "moderate", "carbs": "low",
            "fat": "moderate", "fiber": "low",
        },
        "visibility": "private", "team_id": None,
        "meal_time": meal_time
            or created_at.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "created_at": created_at,
        "updated_at": created_at,
    })


@pytest.mark.asyncio
async def test_meals_me_dedupes_legacy_duplicate_rows_for_same_task(
    fake_db, service,
):
    """Three legacy duplicate meal rows for the SAME nutrition task — exactly
    the state the user has in production right now. /meals/me must return
    exactly ONE card without waiting for the storage migration to run.
    """
    _seed_source_meal(
        fake_db, "canonical-meal",
        task_id="task-N",
        created_at=datetime(2026, 5, 5, 11, 0, 0),
    )
    _seed_source_meal(
        fake_db, "duplicate-meal-A",
        task_id="task-N",
        created_at=datetime(2026, 5, 5, 11, 5, 0),
        food_name="eggs and toast",
    )
    _seed_source_meal(
        fake_db, "duplicate-meal-B",
        task_id="task-N",
        created_at=datetime(2026, 5, 5, 11, 10, 0),
        food_name="eggs and toast and avocado",
    )

    response = await service.list_user_meals("user-1")

    assert response.total == 1, \
        f"Meals page must show one card per nutrition task (got {response.total})"
    assert len(response.meals) == 1
    survivor = response.meals[0]
    assert survivor.meal_id == "canonical-meal", \
        "the canonical (oldest created_at) row must win"
    assert survivor.meal_time == "2026-05-05T11:00:00Z", \
        "original logged-at time must be preserved"


@pytest.mark.asyncio
async def test_meals_me_does_not_merge_distinct_nutrition_tasks(
    fake_db, service,
):
    """Two DIFFERENT nutrition tasks must show as two separate cards even
    when their meals look similar — the canonical identity is keyed on
    (user_id, source_task_id), not on food name."""
    _seed_source_meal(
        fake_db, "task-a-meal",
        task_id="task-A",
        created_at=datetime(2026, 5, 5, 8, 0, 0),
    )
    _seed_source_meal(
        fake_db, "task-b-meal",
        task_id="task-B",
        created_at=datetime(2026, 5, 5, 12, 0, 0),
    )

    response = await service.list_user_meals("user-1")

    assert response.total == 2
    ids = {m.meal_id for m in response.meals}
    assert ids == {"task-a-meal", "task-b-meal"}


@pytest.mark.asyncio
async def test_meals_me_does_not_merge_normal_manual_meals_at_different_times(
    fake_db, service,
):
    """Two manually-logged meals (no source_task_id) at different times —
    each has its own `meal:<meal_id>` canonical identity, so both render."""
    fake_db.meals.docs.append({
        "meal_id": "manual-1",
        "user_id": "user-1",
        "food_items": [{"name": "oatmeal", "portion_weight": 1}],
        "macro_ratio": {
            "protein": "low", "carbs": "moderate",
            "fat": "low", "fiber": "moderate",
        },
        "visibility": "private", "team_id": None,
        "meal_time": "2026-05-05T08:00:00Z",
        "created_at": datetime(2026, 5, 5, 8, 0, 0),
        "updated_at": datetime(2026, 5, 5, 8, 0, 0),
    })
    fake_db.meals.docs.append({
        "meal_id": "manual-2",
        "user_id": "user-1",
        "food_items": [{"name": "oatmeal", "portion_weight": 1}],
        "macro_ratio": {
            "protein": "low", "carbs": "moderate",
            "fat": "low", "fiber": "moderate",
        },
        "visibility": "private", "team_id": None,
        "meal_time": "2026-05-05T15:00:00Z",
        "created_at": datetime(2026, 5, 5, 15, 0, 0),
        "updated_at": datetime(2026, 5, 5, 15, 0, 0),
    })

    response = await service.list_user_meals("user-1")

    assert response.total == 2, \
        "manual meals at different times must NOT be merged"
    ids = sorted(m.meal_id for m in response.meals)
    assert ids == ["manual-1", "manual-2"]


@pytest.mark.asyncio
async def test_meals_me_dedupe_logs_canonical_identity_per_returned_meal(
    fake_db, service, caplog,
):
    """Per the spec: log the canonical identity for every meal returned to
    the Meals page so production traces can prove the API only emits one
    row per identity."""
    import logging as _logging
    _seed_source_meal(
        fake_db, "canonical-meal",
        task_id="task-N",
        created_at=datetime(2026, 5, 5, 11, 0, 0),
    )
    _seed_source_meal(
        fake_db, "duplicate-meal",
        task_id="task-N",
        created_at=datetime(2026, 5, 5, 11, 5, 0),
    )

    with caplog.at_level(_logging.INFO, logger="app.services.meal_service"):
        await service.list_user_meals("user-1")

    log_text = "\n".join(r.getMessage() for r in caplog.records)
    print("LOG OUTPUT:\n" + log_text)
    assert "MealsAPI list_user_meals" in log_text
    assert "identity=nutrition_task:user-1:task-N" in log_text
    assert "meal_id=canonical-meal" in log_text


@pytest.mark.asyncio
async def test_meals_team_feed_dedupes_legacy_duplicates(fake_db, service):
    """Same defensive dedupe on the team feed path."""
    fake_db.team_members = type(fake_db.meals)()  # FakeCollection
    fake_db.team_members.docs.append({
        "team_id": "team-1",
        "user_id": "user-1",
        "status": "member",
    })
    for meal_id, created in [
        ("team-canonical", datetime(2026, 5, 5, 11, 0, 0)),
        ("team-dup-A", datetime(2026, 5, 5, 11, 5, 0)),
        ("team-dup-B", datetime(2026, 5, 5, 11, 10, 0)),
    ]:
        fake_db.meals.docs.append({
            "meal_id": meal_id,
            "user_id": "user-1",
            "source_type": "nutrition_task",
            "source_task_id": "task-N",
            "linked_task_id": "task-N",
            "food_items": [{"name": "x", "portion_weight": 1}],
            "macro_ratio": {
                "protein": "low", "carbs": "low",
                "fat": "low", "fiber": "low",
            },
            "visibility": "team",
            "team_id": "team-1",
            "meal_time": created.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "created_at": created,
            "updated_at": created,
        })

    response = await service.get_team_feed("team-1", "user-1")

    assert response.total == 1
    assert response.meals[0].meal_id == "team-canonical"


# ──────────────────────────────────────────────────────────────────────────
# Team feed (GET /teams/{id}/feed) — exercises team_service.get_team_feed,
# the path that powers TeamDayprintScreen. Two regressions to lock down:
#
#   1. A completed Nutrition task must NOT emit a parallel task_text /
#      task_with_photo item in the team feed — the bridged "meal" item
#      already represents that event. (Same root cause as the personal
#      Dayprint's task_completed suppression.)
#   2. Legacy duplicate meal rows for the same nutrition task must
#      collapse to one card via the same canonical-identity dedupe used
#      by the Meals page.
# ──────────────────────────────────────────────────────────────────────────


from app.services import team_service as team_module
from app.services.team_service import team_service


@pytest.fixture
def team_fake_db(monkeypatch):
    """FakeDb with the extra collections team_service.get_team_feed needs."""
    db = FakeDb()
    db.tasks = FakeCollection()
    db.team_members = FakeCollection()
    db.sleep_sessions = FakeCollection()
    monkeypatch.setattr(meal_module, "get_database", lambda: db)
    monkeypatch.setattr(dayprint_module, "get_database", lambda: db)
    monkeypatch.setattr(team_module, "get_database", lambda: db)
    return db


def _seed_team_member(db, team_id, user_id):
    db.team_members.docs.append({
        "team_id": team_id,
        "user_id": user_id,
        "status": "member",
        "data_sharing": {"sleep": False},
    })


def _seed_team_meal(db, meal_id, *, task_id, team_id, user_id, created_at):
    db.meals.docs.append({
        "meal_id": meal_id,
        "user_id": user_id,
        "source_type": "nutrition_task",
        "source_task_id": task_id,
        "linked_task_id": task_id,
        "food_items": [{"name": "eggs", "portion_weight": 1}],
        "macro_ratio": {
            "protein": "moderate", "carbs": "low",
            "fat": "moderate", "fiber": "low",
        },
        "visibility": "team",
        "team_id": team_id,
        "meal_time": created_at.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "created_at": created_at,
        "updated_at": created_at,
    })


@pytest.mark.asyncio
async def test_team_feed_skips_nutrition_task_completion_in_favor_of_meal_item(
    team_fake_db,
):
    """Completed Nutrition task + bridged meal: feed must show ONE meal
    card and NO task card."""
    team_id, user_id = "team-1", "user-1"
    _seed_team_member(team_fake_db, team_id, user_id)
    team_fake_db.profiles.docs.append({"user_id": user_id, "name": "Alex"})

    # Completed Nutrition task in this team.
    team_fake_db.tasks.docs.append({
        "task_id": "task-N",
        "user_id": user_id,
        "team_id": team_id,
        "task_type": "Nutrition",
        "task_name": "Lunch log",
        "completed_at": datetime(2026, 5, 5, 11, 0, 0),
        "attachments": [],
    })
    # Bridged team-shared meal.
    _seed_team_meal(
        team_fake_db, "meal-1",
        task_id="task-N", team_id=team_id, user_id=user_id,
        created_at=datetime(2026, 5, 5, 11, 0, 30),
    )

    feed = await team_service.get_team_feed(team_id, user_id)
    types = sorted(item["type"] for item in feed["items"])

    assert types == ["meal"], \
        f"Nutrition task must NOT emit a parallel task feed item. Got: {types}"
    meal_items = [i for i in feed["items"] if i["type"] == "meal"]
    assert len(meal_items) == 1
    assert meal_items[0]["meal_id"] == "meal-1"


@pytest.mark.asyncio
async def test_team_feed_dedupes_legacy_duplicate_meal_rows(team_fake_db):
    """Two legacy duplicate meal rows for the same nutrition task must
    collapse to one feed card via canonical-identity dedupe."""
    team_id, user_id = "team-1", "user-1"
    _seed_team_member(team_fake_db, team_id, user_id)
    team_fake_db.profiles.docs.append({"user_id": user_id, "name": "Alex"})

    _seed_team_meal(
        team_fake_db, "canonical-meal",
        task_id="task-N", team_id=team_id, user_id=user_id,
        created_at=datetime(2026, 5, 5, 11, 0, 0),
    )
    _seed_team_meal(
        team_fake_db, "duplicate-meal",
        task_id="task-N", team_id=team_id, user_id=user_id,
        created_at=datetime(2026, 5, 5, 11, 5, 0),
    )

    feed = await team_service.get_team_feed(team_id, user_id)
    meal_items = [i for i in feed["items"] if i["type"] == "meal"]

    assert len(meal_items) == 1, \
        f"legacy duplicate meals must collapse, got: {meal_items}"
    assert meal_items[0]["meal_id"] == "canonical-meal", \
        "the canonical (oldest) row must win"


@pytest.mark.asyncio
async def test_team_feed_still_shows_non_nutrition_completed_tasks(team_fake_db):
    """Non-Nutrition tasks (Medication, Exercise, etc.) must keep their
    task feed item — the suppression is specific to Nutrition tasks that
    have a parallel meal item."""
    team_id, user_id = "team-1", "user-1"
    _seed_team_member(team_fake_db, team_id, user_id)
    team_fake_db.profiles.docs.append({"user_id": user_id, "name": "Alex"})

    team_fake_db.tasks.docs.append({
        "task_id": "task-meds",
        "user_id": user_id,
        "team_id": team_id,
        "task_type": "Medication",
        "task_name": "Take meds",
        "completed_at": datetime(2026, 5, 5, 9, 0, 0),
        "attachments": [],
    })

    feed = await team_service.get_team_feed(team_id, user_id)
    task_items = [
        i for i in feed["items"]
        if i["type"] in ("task_text", "task_with_photo")
    ]
    assert len(task_items) == 1
    assert task_items[0]["task_type"] == "Medication"


# ──────────────────────────────────────────────────────────────────────────
# STRICT "Nutrition Task = Meal" enforcement.
#
# The previous fix layer dedupes when both a meal_logged AND a
# task_completed exist for the same nutrition task. These tests lock in
# the stricter rule: task_completed for a Nutrition task must NEVER reach
# the UI — even when it's the ONLY event present, even when it slipped
# in via a legacy code path or a stale cache. And every meal update must
# refresh the dayprint event payload in place so the dayprint never
# renders stale food_preview / image data.
# ──────────────────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_orphan_nutrition_task_completed_event_is_filtered_out_at_read_time(
    fake_db,
):
    """A solo task_completed event for a Nutrition task — no meal_logged
    in the same dayprint at all — must NOT appear in the API response.
    No "but there's nothing else for this source_key, so let it through"
    fallback.
    """
    today = "2026-05-05"
    fake_db.dayprints.docs.append({
        "user_id": "user-1",
        "date": today,
        "events": [
            {
                "event_id": "orphan-task",
                "type": "task_completed",
                "timestamp": "2026-05-05T11:00:00Z",
                "data": {
                    "task_name": "Lunch log",
                    "task_type": "Nutrition",
                    "source_task_id": "task-N",
                    "source_key": "task_completed:task:task-N",
                },
            },
            # An unrelated advisor_chat event must still pass through.
            {
                "event_id": "advisor",
                "type": "advisor_chat",
                "timestamp": "2026-05-05T12:00:00Z",
                "data": {"summary": "user said hi"},
            },
        ],
    })

    doc = await dayprint_module.get_dayprint("user-1", today)
    types = [e["type"] for e in doc["events"]]
    print_dayprint_state(fake_db, "orphan_nutrition_task_completed")
    print("RETURNED TYPES:", types)
    assert "task_completed" not in types, \
        "Nutrition task_completed must never reach the UI — filtered, not deduped"
    assert "advisor_chat" in types, \
        "non-meal events must still pass through"


@pytest.mark.asyncio
async def test_meal_logged_wins_over_task_completed_when_both_exist(fake_db):
    """Belt-and-suspenders: when a legacy doc has both events, only the
    meal_logged appears."""
    today = "2026-05-05"
    fake_db.dayprints.docs.append({
        "user_id": "user-1",
        "date": today,
        "events": [
            {
                "event_id": "legacy-task",
                "type": "task_completed",
                "timestamp": "2026-05-05T10:59:00Z",
                "data": {
                    "task_name": "Lunch log",
                    "task_type": "Nutrition",
                    "source_task_id": "task-N",
                    "source_key": "task_completed:task:task-N",
                },
            },
            {
                "event_id": "bridge-meal",
                "type": "meal_logged",
                "timestamp": "2026-05-05T11:00:00Z",
                "data": {
                    "meal_id": "m1",
                    "source_type": "nutrition_task",
                    "source_task_id": "task-N",
                    "food_preview": "eggs",
                    "source_key": "nutrition_task:user-1:task-N",
                },
            },
        ],
    })

    doc = await dayprint_module.get_dayprint("user-1", today)
    assert len(doc["events"]) == 1
    assert doc["events"][0]["type"] == "meal_logged"
    assert doc["events"][0]["event_id"] == "bridge-meal"


@pytest.mark.asyncio
async def test_update_meal_refreshes_dayprint_event_payload_in_place(
    fake_db, service,
):
    """User edits a meal via /meals/{id}. The dayprint event written when
    the meal was first logged must REFRESH its food_preview/image_url
    in place — same event_id, same timestamp, fresh payload.
    """
    today = "2026-05-05"
    fake_db.meals.docs.append({
        "meal_id": "m1",
        "user_id": "user-1",
        "source_type": "nutrition_task",
        "source_task_id": "task-N",
        "linked_task_id": "task-N",
        "food_items": [{"name": "eggs", "portion_weight": 1}],
        "macro_ratio": {
            "protein": "moderate", "carbs": "low",
            "fat": "moderate", "fiber": "low",
        },
        "visibility": "private", "team_id": None,
        "meal_time": "2026-05-05T11:00:00Z",
        "images": [],
        "created_at": datetime(2026, 5, 5, 11, 0, 0),
        "updated_at": datetime(2026, 5, 5, 11, 0, 0),
    })
    fake_db.dayprints.docs.append({
        "user_id": "user-1",
        "date": today,
        "events": [
            {
                "event_id": "evt-original",
                "type": "meal_logged",
                "timestamp": "2026-05-05T11:00:30Z",
                "data": {
                    "meal_id": "m1",
                    "food_preview": "eggs",
                    "image_url": None,
                    "visibility": "private",
                    "team_id": None,
                    "source_type": "nutrition_task",
                    "source_task_id": "task-N",
                    "source_key": "nutrition_task:user-1:task-N",
                },
            },
        ],
    })

    update = _MealUpdate(
        food_items=[
            _FoodItem(name="eggs and avocado toast", portion_weight=2),
        ],
    )
    await service.update_meal("m1", "user-1", update)

    raw = fake_db.dayprints.docs[0]["events"]
    assert len(raw) == 1, "no new event row may be inserted"
    refreshed = raw[0]
    assert refreshed["event_id"] == "evt-original", \
        "original event_id must be preserved"
    assert refreshed["timestamp"] == "2026-05-05T11:00:30Z", \
        "original logged-at timestamp must be preserved"
    # The fixture's _structure_text_to_meal echoes input back as a single
    # food name, so the refreshed preview reflects the new edit.
    assert "avocado" in refreshed["data"]["food_preview"], \
        f"food_preview must refresh, got {refreshed['data']['food_preview']!r}"
    assert refreshed["data"]["source_key"] == "nutrition_task:user-1:task-N"


@pytest.mark.asyncio
async def test_update_meal_does_not_create_dayprint_event_for_legacy_meal_without_one(
    fake_db, service,
):
    """A meal that was never logged to dayprint (e.g. legacy data, or a
    bridge that failed to emit) must not retroactively get a dayprint
    event when the user edits it. The refresh helper is "update if exists
    only" — it never INSERTs.
    """
    fake_db.meals.docs.append({
        "meal_id": "legacy-meal",
        "user_id": "user-1",
        "food_items": [{"name": "salad", "portion_weight": 1}],
        "macro_ratio": {
            "protein": "low", "carbs": "low",
            "fat": "low", "fiber": "moderate",
        },
        "visibility": "private", "team_id": None,
        "meal_time": "2026-05-05T11:00:00Z",
        "images": [],
        "created_at": datetime(2026, 5, 5, 11, 0, 0),
        "updated_at": datetime(2026, 5, 5, 11, 0, 0),
    })
    # Empty dayprints — no event for this meal exists.

    update = _MealUpdate(
        food_items=[_FoodItem(name="salad with chicken", portion_weight=1)],
    )
    await service.update_meal("legacy-meal", "user-1", update)

    # No dayprint document was created from the refresh path.
    assert len(fake_db.dayprints.docs) == 0


@pytest.mark.asyncio
async def test_strict_rule_full_lifecycle_yields_one_meal_one_dayprint_one_feed(
    team_fake_db, service,
):
    """End-to-end strict-rule check: one Nutrition task lifecycle
    (create + updateNote + uploadAttachments + completeTask + re-analyze)
    must produce EXACTLY:
        - 1 meal in `meals`
        - 1 visible dayprint item via /dayprint
        - 1 visible team feed item via /teams/{id}/feed
    AND no task_* item ever surfaces alongside the meal.
    """
    team_id, user_id = "team-1", "user-1"
    team_fake_db.team_members.docs.append({
        "team_id": team_id, "user_id": user_id, "status": "member",
        "data_sharing": {"sleep": False},
    })
    team_fake_db.profiles.docs.append({
        "user_id": user_id, "name": "Alex", "timezone": "UTC",
    })

    # Mirror the route flow.
    task_payload = lambda **kw: {  # noqa: E731
        "task_id": "task-N",
        "user_id": user_id,
        "team_id": team_id,
        "task_type": "Nutrition",
        "task_name": "Lunch log",
        "note": kw.get("note", ""),
        "attachments": kw.get("attachments", []),
        "open_datetime": "2026-05-05 11:00",
    }
    await service.create_meal_from_nutrition_task(task_payload(note="initial"))
    await service.create_meal_from_nutrition_task(task_payload(note="eggs"))
    await service.create_meal_from_nutrition_task(
        task_payload(note="eggs", attachments=[{
            "attachment_id": "att-1",
            "content_type": "image/jpeg",
            "url": "https://example.test/m.jpg",
        }]),
    )
    await service.create_meal_from_nutrition_task(
        task_payload(note="eggs and toast"),
        emit_dayprint=True,
    )
    # The completed task lives in `tasks` so the team feed test path
    # exercises the suppression rule too.
    team_fake_db.tasks.docs.append({
        "task_id": "task-N",
        "user_id": user_id,
        "team_id": team_id,
        "task_type": "Nutrition",
        "task_name": "Lunch log",
        "completed_at": datetime(2026, 5, 5, 11, 0, 0),
        "attachments": [],
    })
    # A legacy stray task_completed in the dayprint, simulating
    # pre-fix data that the route is no longer writing.
    today = dayprint_module._today_utc_str()
    dayprint_doc = team_fake_db.dayprints.docs[0]
    dayprint_doc["events"].append({
        "event_id": "stray-task-completed",
        "type": "task_completed",
        "timestamp": "2026-05-05T11:00:00Z",
        "data": {
            "task_name": "Lunch log",
            "task_type": "Nutrition",
            "source_task_id": "task-N",
            "source_key": "task_completed:task:task-N",
        },
    })

    # Now simulate a re-analyze: the meal becomes team-shared too.
    meal = team_fake_db.meals.docs[0]
    meal["visibility"] = "team"
    meal["team_id"] = team_id
    update = _MealUpdate(
        food_items=[_FoodItem(name="eggs and toast and avocado", portion_weight=1)],
    )
    final_meal = await service.update_meal(meal["meal_id"], user_id, update)

    # ── Invariants ──────────────────────────────────────────────────────
    assert len(team_fake_db.meals.docs) == 1

    dp = await dayprint_module.get_dayprint(user_id, today)
    assert len(dp["events"]) == 1, \
        f"Dayprint must show exactly 1 item, got: {dp['events']}"
    assert dp["events"][0]["type"] == "meal_logged"
    # The keeper event's payload reflects the LATEST edit, not the stale
    # initial bridge write.
    assert "avocado" in dp["events"][0]["data"]["food_preview"]

    feed = await team_service.get_team_feed(team_id, user_id)
    types = sorted(item["type"] for item in feed["items"])
    assert types == ["meal"], \
        f"Team feed: 1 meal item, no parallel task item. Got: {types}"
    assert feed["items"][0]["meal_id"] == final_meal.meal_id


# ──────────────────────────────────────────────────────────────────────────
# Historical Dayprint endpoint — `GET /dayprint/history` is what the
# DayprintTab on the advisor screen calls. Lock down legacy edge cases
# discovered after the in-app duplicates were reported.
# ──────────────────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_history_endpoint_collapses_legacy_cross_key_events_via_meal_lookup(
    fake_db,
):
    """Real-world legacy bug: a manual `POST /meals` with `linked_task_id`
    wrote a dayprint event keyed `meal:<id>` (no source_task_id), and the
    bridge later wrote a second event keyed `nutrition_task:<u>:<t>`.
    Two distinct canonical keys — dedupe alone can't merge them.

    The history endpoint must hydrate the orphan event by resolving its
    meal_id to the meal's source_task_id, then collapse via canonical key.
    """
    # Source-linked meal with linked_task_id but the dayprint has BOTH:
    #   a legacy meal:<id> event (no source_task_id)
    #   a canonical nutrition_task:<u>:<t> event from the bridge
    fake_db.meals.docs.append({
        "meal_id": "shared-meal",
        "user_id": "user-1",
        "source_type": "nutrition_task",
        "source_task_id": "task-N",
        "linked_task_id": "task-N",
        "food_items": [{"name": "eggs", "portion_weight": 1}],
        "macro_ratio": {
            "protein": "moderate", "carbs": "low",
            "fat": "moderate", "fiber": "low",
        },
        "visibility": "private", "team_id": None,
        "meal_time": "2026-04-15T11:00:00Z",
        "created_at": datetime(2026, 4, 15, 11, 0, 0),
        "updated_at": datetime(2026, 4, 15, 11, 0, 0),
    })
    fake_db.dayprints.docs.append({
        "user_id": "user-1",
        "date": "2026-04-15",
        "events": [
            {
                "event_id": "legacy-meal-key",
                "type": "meal_logged",
                "timestamp": "2026-04-15T11:00:00Z",
                "data": {
                    "meal_id": "shared-meal",
                    "source_type": "meal",  # legacy: no source_task_id
                    "source_key": "meal:shared-meal",
                },
            },
            {
                "event_id": "bridge-canonical-key",
                "type": "meal_logged",
                "timestamp": "2026-04-15T11:00:30Z",
                "data": {
                    "meal_id": "shared-meal",
                    "source_type": "nutrition_task",
                    "source_task_id": "task-N",
                    "source_key": "nutrition_task:user-1:task-N",
                },
            },
        ],
    })

    docs, _, _ = await dayprint_module.get_dayprint_history("user-1", limit=14)

    assert len(docs) == 1
    events = docs[0]["events"]
    print_dayprint_state(fake_db, "history_cross_key")
    print("HISTORY EVENTS:", json.dumps(events, default=str, indent=2))
    assert len(events) == 1, \
        f"meal-hydration must collapse cross-key duplicates. Got: {events}"


@pytest.mark.asyncio
async def test_history_endpoint_filters_orphan_nutrition_task_completed(fake_db):
    """A solo Nutrition `task_completed` event in old history (no
    meal_logged) must NOT appear via /dayprint/history."""
    fake_db.dayprints.docs.append({
        "user_id": "user-1",
        "date": "2026-04-10",
        "events": [
            {
                "event_id": "orphan",
                "type": "task_completed",
                "timestamp": "2026-04-10T11:00:00Z",
                "data": {
                    "task_name": "Lunch",
                    "task_type": "Nutrition",
                    "source_task_id": "task-old",
                },
            },
        ],
    })

    docs, _, _ = await dayprint_module.get_dayprint_history("user-1", limit=14)

    assert len(docs) == 1
    assert docs[0]["events"] == [], \
        "orphan Nutrition task_completed must be filtered from history"


@pytest.mark.asyncio
async def test_history_endpoint_dedupes_three_legacy_format_events(fake_db):
    """The original "3 dayprints" report: three events with three different
    legacy source_key formats for the same nutrition task. /dayprint/history
    must return exactly one — without depending on the migration having
    run yet.
    """
    fake_db.meals.docs.append({
        "meal_id": "old-meal-A",
        "user_id": "user-1",
        "source_type": "nutrition_task",
        "source_task_id": "task-N",
        "linked_task_id": "task-N",
        "food_items": [{"name": "eggs", "portion_weight": 1}],
        "macro_ratio": {
            "protein": "low", "carbs": "low",
            "fat": "low", "fiber": "low",
        },
        "visibility": "private", "team_id": None,
        "meal_time": "2026-04-12T11:00:00Z",
        "created_at": datetime(2026, 4, 12, 11, 0, 0),
        "updated_at": datetime(2026, 4, 12, 11, 0, 0),
    })
    fake_db.dayprints.docs.append({
        "user_id": "user-1",
        "date": "2026-04-12",
        "events": [
            {
                "event_id": "legacy-bridge-A",
                "type": "meal_logged",
                "timestamp": "2026-04-12T10:59:00Z",
                "data": {
                    "meal_id": "old-meal-A",
                    "source_type": "nutrition_task_meal",
                    "source_task_id": "task-N",
                    "source_key": "meal_logged:nutrition_task_meal:task-N:old-meal-A",
                },
            },
            {
                "event_id": "legacy-task",
                "type": "task_completed",
                "timestamp": "2026-04-12T11:00:00Z",
                "data": {
                    "task_name": "Lunch",
                    "task_type": "Nutrition",
                    "source_task_id": "task-N",
                    "source_key": "task_completed:task:task-N",
                },
            },
            {
                "event_id": "legacy-meal-keyed",
                "type": "meal_logged",
                "timestamp": "2026-04-12T11:00:01Z",
                "data": {
                    "meal_id": "old-meal-A",
                    "source_type": "meal",
                    "source_key": "meal:old-meal-A",
                },
            },
        ],
    })

    docs, _, _ = await dayprint_module.get_dayprint_history("user-1", limit=14)
    events = docs[0]["events"]
    print_dayprint_state(fake_db, "history_three_formats")
    print("HISTORY EVENTS:", json.dumps(events, default=str, indent=2))

    assert len(events) == 1
    assert events[0]["type"] == "meal_logged"


@pytest.mark.asyncio
async def test_history_does_not_mutate_underlying_dayprint_doc(fake_db):
    """Read-time hydration must operate on copies — the underlying
    dayprints document in storage stays untouched, so a future migration
    --apply still has the legacy state to work with."""
    fake_db.meals.docs.append({
        "meal_id": "m1",
        "user_id": "user-1",
        "source_type": "nutrition_task",
        "source_task_id": "task-N",
        "linked_task_id": "task-N",
        "food_items": [{"name": "eggs", "portion_weight": 1}],
        "macro_ratio": {
            "protein": "low", "carbs": "low",
            "fat": "low", "fiber": "low",
        },
        "visibility": "private", "team_id": None,
        "meal_time": "2026-04-12T11:00:00Z",
        "created_at": datetime(2026, 4, 12, 11, 0, 0),
        "updated_at": datetime(2026, 4, 12, 11, 0, 0),
    })
    raw_event = {
        "event_id": "evt",
        "type": "meal_logged",
        "timestamp": "2026-04-12T11:00:00Z",
        "data": {
            "meal_id": "m1",
            "source_type": "meal",
            "source_key": "meal:m1",
        },
    }
    fake_db.dayprints.docs.append({
        "user_id": "user-1",
        "date": "2026-04-12",
        "events": [raw_event],
    })

    # Read once — hydration mutates a COPY in memory.
    await dayprint_module.get_dayprint("user-1", "2026-04-12")

    # The raw stored event must still have its legacy shape — pass-2 of
    # the migration is responsible for rewriting it permanently, not the
    # read path.
    stored_data = fake_db.dayprints.docs[0]["events"][0]["data"]
    assert "source_task_id" not in stored_data, \
        "read-time hydration must NOT mutate stored events"
    assert stored_data["source_key"] == "meal:m1"


@pytest.mark.asyncio
async def test_create_meal_with_linked_task_id_writes_canonical_dayprint_key(
    fake_db, service, monkeypatch,
):
    """Future-proof the write path: a manual `POST /meals` with
    linked_task_id must stamp the meal AND its dayprint event with the
    canonical Nutrition-task identity, so a later bridge call is
    idempotent — no parallel `meal:<id>` event ever gets written.
    """
    # Stub out the on-disk image scan so the test doesn't need a real upload.
    monkeypatch.setattr(service, "_scan_meal_images", lambda meal_id: [])

    from app.models.meal import (
        MealCreate as _MealCreate,
        MealVisibility as _MealVisibility,
    )

    create = _MealCreate(
        meal_id="manual-with-task",
        food_items=[_FoodItem(name="eggs", portion_weight=1)],
        macro_ratio=_MacroRatio(
            protein=_MacroLevel.MODERATE,
            carbs=_MacroLevel.LOW,
            fat=_MacroLevel.MODERATE,
            fiber=_MacroLevel.LOW,
        ),
        note=None,
        visibility=_MealVisibility.PRIVATE,
        linked_task_id="task-N",
    )
    await service.create_meal("user-1", create)

    # Stored meal carries source identity, not just linked_task_id.
    stored = fake_db.meals.docs[0]
    assert stored["source_type"] == "nutrition_task"
    assert stored["source_task_id"] == "task-N"

    # Dayprint event uses the canonical key.
    today = dayprint_module._today_utc_str()
    doc = await dayprint_module.get_dayprint("user-1", today)
    assert len(doc["events"]) == 1
    event = doc["events"][0]
    assert event["data"]["source_key"] == "nutrition_task:user-1:task-N"
    assert event["data"]["source_type"] == "nutrition_task"
    assert event["data"]["source_task_id"] == "task-N"


@pytest.mark.asyncio
async def test_migration_pass_1_5_hydrates_legacy_meal_keyed_events(fake_db):
    """Permanent storage cleanup: pass-1.5 must rewrite legacy
    `meal_logged:meal:<id>` events whose meal IS source-linked, so a
    subsequent pass-2 collapses them with sibling bridge events."""
    fake_db.meals.docs.append({
        "meal_id": "linked-meal",
        "user_id": "user-1",
        "source_type": "nutrition_task",
        "source_task_id": "task-X",
        "linked_task_id": "task-X",
        "food_items": [{"name": "x", "portion_weight": 1}],
        "macro_ratio": {
            "protein": "low", "carbs": "low",
            "fat": "low", "fiber": "low",
        },
        "visibility": "private", "team_id": None,
        "meal_time": "2026-03-01T11:00:00Z",
        "created_at": datetime(2026, 3, 1, 11, 0, 0),
        "updated_at": datetime(2026, 3, 1, 11, 0, 0),
    })
    fake_db.dayprints.docs.append({
        "user_id": "user-1",
        "date": "2026-03-01",
        "events": [
            {
                "event_id": "legacy",
                "type": "meal_logged",
                "timestamp": "2026-03-01T11:00:00Z",
                "data": {
                    "meal_id": "linked-meal",
                    "source_type": "meal",
                    "source_key": "meal:linked-meal",
                },
            },
        ],
    })

    migration = _load_migration()
    await migration.run(fake_db, apply=True, out=lambda *_: None)

    rewritten = fake_db.dayprints.docs[0]["events"][0]
    assert rewritten["data"]["source_task_id"] == "task-X"
    assert rewritten["data"]["source_type"] == "nutrition_task"
    assert rewritten["data"]["source_key"] == "nutrition_task:user-1:task-X"


@pytest.mark.asyncio
async def test_history_logs_raw_event_payloads_for_production_traceability(
    fake_db, caplog,
):
    """Spec compliance: every raw event returned to the frontend must be
    logged with event_id / type / data.meal_id / data.source_key /
    data.source_type / data.source_task_id / data.task_type / timestamp,
    so production traces can prove only canonical events render."""
    import logging as _logging

    fake_db.dayprints.docs.append({
        "user_id": "user-1",
        "date": "2026-04-15",
        "events": [
            {
                "event_id": "evt-1",
                "type": "meal_logged",
                "timestamp": "2026-04-15T11:00:00Z",
                "data": {
                    "meal_id": "m1",
                    "source_type": "nutrition_task",
                    "source_task_id": "task-N",
                    "source_key": "nutrition_task:user-1:task-N",
                },
            },
        ],
    })

    with caplog.at_level(_logging.INFO, logger="app.services.dayprint_service"):
        await dayprint_module.get_dayprint_history("user-1", limit=14)

    log_text = "\n".join(r.getMessage() for r in caplog.records)
    print("LOG OUTPUT:\n" + log_text)
    for needle in (
        "DayprintAPI get_dayprint_history",
        "event_id=evt-1",
        "type=meal_logged",
        "meal_id=m1",
        "source_key=nutrition_task:user-1:task-N",
        "source_type=nutrition_task",
        "source_task_id=task-N",
        "timestamp=2026-04-15T11:00:00Z",
    ):
        assert needle in log_text, f"missing trace field: {needle!r}"


# ──────────────────────────────────────────────────────────────────────────
# Production-reported regression: "one card with picture, one without".
#
# Real-world legacy state: TWO meal rows for the same Nutrition task —
# one written by `POST /meals` with only `linked_task_id` and no images,
# one written by the bridge with `source_type=nutrition_task` and an
# image. Old code:
#   - canonical identity for the manual row was `meal:<id>` (no source_type)
#   - canonical identity for the bridge row was `nutrition_task:<u>:<t>`
#   - Meals page rendered both → "one with picture, one without"
#
# Fix invariants:
#   1. Meals API merges: surviving card has the picture and food data.
#   2. Dayprint hydration merges: surviving event has the picture and food.
#   3. Migration consolidates AND merges before deletion.
#   4. New `create_meal` calls stamp `source_type=nutrition_task` so this
#      can never recur for new data.
# ──────────────────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_meals_api_merges_picture_from_sibling_when_canonical_lacks_it(
    fake_db, service,
):
    """Two rows for the same task: oldest has no images (manual save),
    youngest has the picture (bridge). The Meals API must return ONE card,
    keyed on the oldest row's identity (preserves logged-at) but carrying
    the youngest row's picture."""
    fake_db.meals.docs.append({
        "meal_id": "manual-no-pic",
        "user_id": "user-1",
        "linked_task_id": "task-N",       # ← only signal of task-link
        "food_items": [{"name": "eggs", "portion_weight": 1}],
        "macro_ratio": {
            "protein": "low", "carbs": "low",
            "fat": "low", "fiber": "low",
        },
        "visibility": "private", "team_id": None,
        "images": [],
        "meal_time": "2026-04-15T11:00:00Z",
        "created_at": datetime(2026, 4, 15, 11, 0, 0),
        "updated_at": datetime(2026, 4, 15, 11, 0, 0),
    })
    fake_db.meals.docs.append({
        "meal_id": "bridge-with-pic",
        "user_id": "user-1",
        "source_type": "nutrition_task",
        "source_task_id": "task-N",
        "linked_task_id": "task-N",
        "food_items": [{"name": "eggs and avocado toast", "portion_weight": 1}],
        "macro_ratio": {
            "protein": "moderate", "carbs": "moderate",
            "fat": "moderate", "fiber": "moderate",
        },
        "visibility": "private", "team_id": None,
        "images": [{"url": "/api/v1/uploads/meals/bridge-with-pic/photo.jpg"}],
        "meal_time": "2026-04-15T11:05:00Z",
        "created_at": datetime(2026, 4, 15, 11, 5, 0),
        "updated_at": datetime(2026, 4, 15, 11, 5, 0),
    })

    response = await service.list_user_meals("user-1")
    assert response.total == 1
    survivor = response.meals[0]
    # Oldest row's id wins (preserves logged-at moment).
    assert survivor.meal_id == "manual-no-pic"
    # …but it carries the picture and food from the bridge row.
    assert len(survivor.images) == 1, \
        f"survivor must carry the merged picture; got {survivor.images}"
    assert survivor.images[0]["url"] == \
        "/api/v1/uploads/meals/bridge-with-pic/photo.jpg"


@pytest.mark.asyncio
async def test_dayprint_history_hydrates_picture_from_sibling_meal(fake_db):
    """Same scenario via /dayprint/history — the surviving event must carry
    the picture even when the canonical meal row itself lacks it."""
    fake_db.meals.docs.append({
        "meal_id": "manual-no-pic",
        "user_id": "user-1",
        "linked_task_id": "task-N",
        "food_items": [{"name": "eggs", "portion_weight": 1}],
        "macro_ratio": {
            "protein": "low", "carbs": "low",
            "fat": "low", "fiber": "low",
        },
        "visibility": "private", "team_id": None,
        "images": [],
        "meal_time": "2026-04-15T11:00:00Z",
        "created_at": datetime(2026, 4, 15, 11, 0, 0),
        "updated_at": datetime(2026, 4, 15, 11, 0, 0),
    })
    fake_db.meals.docs.append({
        "meal_id": "bridge-with-pic",
        "user_id": "user-1",
        "source_type": "nutrition_task",
        "source_task_id": "task-N",
        "linked_task_id": "task-N",
        "food_items": [{"name": "eggs and toast", "portion_weight": 1}],
        "macro_ratio": {
            "protein": "moderate", "carbs": "low",
            "fat": "moderate", "fiber": "low",
        },
        "visibility": "private", "team_id": None,
        "images": [{"url": "/api/v1/uploads/meals/bridge-with-pic/photo.jpg"}],
        "meal_time": "2026-04-15T11:05:00Z",
        "created_at": datetime(2026, 4, 15, 11, 5, 0),
        "updated_at": datetime(2026, 4, 15, 11, 5, 0),
    })
    fake_db.dayprints.docs.append({
        "user_id": "user-1",
        "date": "2026-04-15",
        "events": [
            {
                "event_id": "evt-no-pic",
                "type": "meal_logged",
                "timestamp": "2026-04-15T11:00:00Z",
                "data": {
                    "meal_id": "manual-no-pic",
                    "source_type": "meal",
                    "source_key": "meal:manual-no-pic",
                    "image_url": None,
                    "food_preview": "eggs",
                },
            },
            {
                "event_id": "evt-with-pic",
                "type": "meal_logged",
                "timestamp": "2026-04-15T11:05:30Z",
                "data": {
                    "meal_id": "bridge-with-pic",
                    "source_type": "nutrition_task",
                    "source_task_id": "task-N",
                    "source_key": "nutrition_task:user-1:task-N",
                    "image_url": "/api/v1/uploads/meals/bridge-with-pic/photo.jpg",
                    "food_preview": "eggs and toast",
                },
            },
        ],
    })

    docs, _, _ = await dayprint_module.get_dayprint_history("user-1", limit=14)
    events = docs[0]["events"]
    print_dayprint_state(fake_db, "with_without_picture")

    assert len(events) == 1, f"both events must collapse to one; got {len(events)}"
    survivor = events[0]
    # Earliest event_id preserved.
    assert survivor["event_id"] == "evt-no-pic"
    # ...but rewritten meal_id + image_url come from the canonical-with-merge.
    assert survivor["data"]["meal_id"] == "manual-no-pic"
    assert survivor["data"]["image_url"] == \
        "/api/v1/uploads/meals/bridge-with-pic/photo.jpg", \
        "survivor must render the picture, not None"
    assert "toast" in (survivor["data"]["food_preview"] or "")


@pytest.mark.asyncio
async def test_migration_consolidation_merges_picture_into_canonical(fake_db):
    """Permanent storage cleanup: when pass-1 deletes the bridge row, its
    image must be lifted onto the canonical row first — so the surviving
    meal in storage carries the picture."""
    fake_db.meals.docs.append({
        "meal_id": "manual-no-pic",
        "user_id": "user-1",
        "source_type": "nutrition_task",
        "source_task_id": "task-N",
        "linked_task_id": "task-N",
        "food_items": [{"name": "eggs", "portion_weight": 1}],
        "macro_ratio": {
            "protein": "low", "carbs": "low",
            "fat": "low", "fiber": "low",
        },
        "visibility": "private", "team_id": None,
        "images": [],
        "meal_time": "2026-04-15T11:00:00Z",
        "created_at": datetime(2026, 4, 15, 11, 0, 0),
        "updated_at": datetime(2026, 4, 15, 11, 0, 0),
    })
    fake_db.meals.docs.append({
        "meal_id": "bridge-with-pic",
        "user_id": "user-1",
        "source_type": "nutrition_task",
        "source_task_id": "task-N",
        "linked_task_id": "task-N",
        "food_items": [{"name": "eggs and toast", "portion_weight": 1}],
        "macro_ratio": {
            "protein": "moderate", "carbs": "low",
            "fat": "moderate", "fiber": "low",
        },
        "visibility": "private", "team_id": None,
        "images": [{"url": "/api/v1/uploads/meals/bridge-with-pic/photo.jpg"}],
        "meal_time": "2026-04-15T11:05:00Z",
        "created_at": datetime(2026, 4, 15, 11, 5, 0),
        "updated_at": datetime(2026, 4, 15, 11, 5, 0),
    })

    migration = _load_migration()
    await migration.run(fake_db, apply=True, out=lambda *_: None)

    survivors = fake_db.meals.docs
    assert len(survivors) == 1
    s = survivors[0]
    assert s["meal_id"] == "manual-no-pic", \
        "oldest row preserves the original logged time"
    assert len(s["images"]) == 1, \
        "picture must be merged onto the canonical row before delete"
    assert s["images"][0]["url"] == \
        "/api/v1/uploads/meals/bridge-with-pic/photo.jpg"


@pytest.mark.asyncio
async def test_migration_groups_legacy_rows_with_only_linked_task_id(fake_db):
    """A row with `linked_task_id` but no `source_type` must group with a
    bridge-stamped row for the same task — old grouping required source_type
    so this case slipped through."""
    fake_db.meals.docs.append({
        "meal_id": "legacy",
        "user_id": "user-1",
        "linked_task_id": "task-N",  # ← ONLY task hint
        "food_items": [{"name": "x", "portion_weight": 1}],
        "macro_ratio": {
            "protein": "low", "carbs": "low",
            "fat": "low", "fiber": "low",
        },
        "visibility": "private", "team_id": None,
        "images": [],
        "meal_time": "2026-03-01T11:00:00Z",
        "created_at": datetime(2026, 3, 1, 11, 0, 0),
        "updated_at": datetime(2026, 3, 1, 11, 0, 0),
    })
    fake_db.meals.docs.append({
        "meal_id": "canonical",
        "user_id": "user-1",
        "source_type": "nutrition_task",
        "source_task_id": "task-N",
        "linked_task_id": "task-N",
        "food_items": [{"name": "x", "portion_weight": 1}],
        "macro_ratio": {
            "protein": "low", "carbs": "low",
            "fat": "low", "fiber": "low",
        },
        "visibility": "private", "team_id": None,
        "images": [{"url": "/photo.jpg"}],
        "meal_time": "2026-03-01T11:05:00Z",
        "created_at": datetime(2026, 3, 1, 11, 5, 0),
        "updated_at": datetime(2026, 3, 1, 11, 5, 0),
    })

    migration = _load_migration()
    stats = await migration.run(fake_db, apply=False, out=lambda *_: None)

    assert stats["groups"] == 1, \
        "legacy linked_task_id-only row must group with bridge row"
    assert stats["duplicates"] == 1
