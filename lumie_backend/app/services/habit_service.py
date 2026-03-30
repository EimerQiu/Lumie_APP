"""Habit Tracker service — daily entry persistence."""
import logging
from datetime import datetime
from typing import Optional

from ..core.database import get_database
from ..models.habit import HabitEntryUpsert, HabitEntryResponse

logger = logging.getLogger(__name__)


class HabitService:
    async def upsert_entry(
        self, user_id: str, entry: HabitEntryUpsert
    ) -> HabitEntryResponse:
        """Create or fully overwrite today's habit entry for the user.

        Only supplied (non-None) fields replace existing values; fields
        that are None in the payload are left unchanged in the database
        so that editing one card doesn't wipe others already logged.
        """
        db = get_database()
        now = datetime.utcnow()

        # Build the $set payload from only the fields that were provided
        update_fields: dict = {"updated_at": now}
        for field in ("mood", "energy", "hunger", "workload", "fatigue", "condition_metric"):
            value = getattr(entry, field)
            if value is not None:
                update_fields[field] = value

        await db.habit_entries.update_one(
            {"user_id": user_id, "date": entry.date},
            {
                "$set": update_fields,
                "$setOnInsert": {"user_id": user_id, "date": entry.date},
            },
            upsert=True,
        )

        doc = await db.habit_entries.find_one({"user_id": user_id, "date": entry.date})
        return self._doc_to_response(doc)

    async def get_entry(self, user_id: str, date: str) -> Optional[HabitEntryResponse]:
        """Return the habit entry for a specific YYYY-MM-DD date, or None."""
        db = get_database()
        doc = await db.habit_entries.find_one({"user_id": user_id, "date": date})
        return self._doc_to_response(doc) if doc else None

    async def get_today_context(self, user_id: str, date: str) -> dict:
        """Return a structured dict suitable for injecting into Advisor context."""
        entry = await self.get_entry(user_id, date)
        if entry is None:
            return {}
        return {
            k: v
            for k, v in {
                "mood": entry.mood,
                "energy": entry.energy,
                "hunger": entry.hunger,
                "workload": entry.workload,
                "fatigue": entry.fatigue,
                "condition_metric": entry.condition_metric,
            }.items()
            if v is not None
        }

    def _doc_to_response(self, doc: dict) -> HabitEntryResponse:
        return HabitEntryResponse(
            user_id=doc["user_id"],
            date=doc["date"],
            mood=doc.get("mood"),
            energy=doc.get("energy"),
            hunger=doc.get("hunger"),
            workload=doc.get("workload"),
            fatigue=doc.get("fatigue"),
            condition_metric=doc.get("condition_metric"),
            updated_at=doc.get("updated_at", datetime.utcnow()),
        )


habit_service = HabitService()
