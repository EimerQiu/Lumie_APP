import asyncio
import os
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest
from pymongo.errors import DuplicateKeyError

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ["DEBUG"] = "false"

from app.services import dayprint_service as dayprint_module
from app.services import meal_service as meal_module
from app.services.meal_service import MealService


class FakeCollection:
    def __init__(self, *, unique_source: bool = False):
        self.docs = []
        self.lock = asyncio.Lock()
        self.unique_source = unique_source

    def _matches(self, doc, query):
        if "$or" in query:
            return any(self._matches(doc, part) for part in query["$or"])
        for key, expected in query.items():
            if isinstance(expected, dict) and "$ne" in expected:
                if doc.get(key) == expected["$ne"]:
                    return False
                continue
            if doc.get(key) != expected:
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

    async def insert_one(self, doc):
        async with self.lock:
            self._enforce_unique_source(doc)
            self.docs.append(dict(doc))
        return SimpleNamespace(inserted_id=doc.get("_id"))

    async def update_one(self, query, update, *args, upsert=False, **kwargs):
        async with self.lock:
            for doc in self.docs:
                if self._matches(doc, query):
                    if "$set" in update:
                        doc.update(update["$set"])
                    if "$push" in update:
                        for key, value in update["$push"].items():
                            doc.setdefault(key, []).append(value)
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

    monkeypatch.setattr(svc, "_structure_text_to_meal", fake_structure)
    monkeypatch.setattr(svc, "_resolve_user_timezone", lambda user_id: "UTC")
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


@pytest.mark.asyncio
async def test_completing_one_nutrition_task_creates_one_meal_and_dayprint(fake_db, service):
    meal_id = await service.create_meal_from_nutrition_task(
        nutrition_task(),
        emit_dayprint=True,
    )

    assert meal_id
    assert len(fake_db.meals.docs) == 1
    assert len(meal_logged_events(fake_db)) == 1


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
    assert len(meal_logged_events(fake_db)) == 1


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
    assert len(meal_logged_events(fake_db)) == 1


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
    assert len(meal_logged_events(fake_db)) == 1


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
    assert len(meal_logged_events(fake_db)) == 1
