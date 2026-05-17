"""Workout service — exercises, templates, sessions, and PR tracking."""
import logging
import uuid
from datetime import datetime
from typing import Optional

from ..core.database import get_database
from ..core.datetime_utils import format_utc_datetime, format_utc_datetime_with_ms
from ..data.seed_exercises import SYSTEM_EXERCISES, ICD10_EXERCISE_FLAGS
from ..models.workout import (
    ExerciseCreate,
    ExerciseUpdate,
    TemplateCreate,
    TemplateUpdate,
    SessionCreate,
    AdvisorSessionCreate,
    SessionUpdate,
    OverloadSuggestion,
    WorkoutSource,
    SessionCreatedBy,
)

logger = logging.getLogger(__name__)


class WorkoutService:
    """CRUD + business logic for the workout system."""

    # ── Exercise Library ───────────────────────────────────────────────────────

    async def seed_system_exercises(self) -> int:
        """Upsert all system exercises.  Returns the count inserted/updated."""
        db = get_database()
        count = 0
        for ex in SYSTEM_EXERCISES:
            ex_copy = {**ex, "is_system": True, "is_active": True}
            ex_copy.setdefault("icd10_caution_codes", [])
            result = await db.exercises.update_one(
                {"exercise_id": ex["exercise_id"]},
                {"$set": ex_copy, "$setOnInsert": {"created_at": datetime.utcnow()}},
                upsert=True,
            )
            if result.upserted_id or result.modified_count:
                count += 1
        logger.info("Seeded %d system exercises", count)
        return count

    async def list_exercises(
        self,
        user_id: Optional[str] = None,
        muscle_group: Optional[str] = None,
        equipment_type: Optional[str] = None,
        movement_type: Optional[str] = None,
        search: Optional[str] = None,
        icd10_code: Optional[str] = None,
    ) -> list[dict]:
        """Return exercises matching filters.  System exercises are always
        included; custom exercises are filtered to the requesting user."""
        db = get_database()

        # Build ownership filter: system exercises + user's custom ones
        ownership_filter: list[dict] = [{"is_system": True}]
        if user_id:
            ownership_filter.append({"created_by": user_id})

        # Build field-level filters
        field_filters: dict = {"is_active": True}
        if muscle_group:
            field_filters["primary_muscles"] = muscle_group
        if equipment_type:
            field_filters["equipment_type"] = equipment_type
        if movement_type:
            field_filters["movement_type"] = movement_type

        # Combine with $and so $or (ownership) coexists with other filters
        query: dict = {
            "$and": [
                {"$or": ownership_filter},
                field_filters,
            ]
        }

        cursor = db.exercises.find(query, {"_id": 0})
        exercises = await cursor.to_list(length=500)

        # Text search (simple substring match on name)
        if search:
            search_lower = search.lower()
            exercises = [e for e in exercises if search_lower in e.get("name", "").lower()]

        # ICD-10 caution flagging
        if icd10_code:
            flagged_ids = set()
            for prefix, ex_ids in ICD10_EXERCISE_FLAGS.items():
                if icd10_code.startswith(prefix):
                    flagged_ids.update(ex_ids)
            for ex in exercises:
                ex["icd10_caution"] = ex["exercise_id"] in flagged_ids

        return exercises

    async def get_exercise(self, exercise_id: str) -> Optional[dict]:
        db = get_database()
        return await db.exercises.find_one(
            {"exercise_id": exercise_id, "is_active": True}, {"_id": 0}
        )

    async def create_exercise(self, user_id: str, data: ExerciseCreate) -> dict:
        db = get_database()
        now = datetime.utcnow()
        doc = {
            "exercise_id": f"custom_{uuid.uuid4().hex[:12]}",
            "name": data.name,
            "description": data.description,
            "primary_muscles": data.primary_muscles,
            "secondary_muscles": data.secondary_muscles,
            "equipment_type": data.equipment_type,
            "movement_type": data.movement_type,
            "form_description": data.form_description,
            "pose_type": None,
            "recommended_orientation": None,
            "is_system": False,
            "created_by": user_id,
            "icd10_caution_codes": [],
            "is_active": True,
            "created_at": now,
            "updated_at": now,
        }
        await db.exercises.insert_one(doc)
        doc.pop("_id", None)
        return doc

    async def update_exercise(
        self, user_id: str, exercise_id: str, data: ExerciseUpdate
    ) -> Optional[dict]:
        db = get_database()
        update = {k: v for k, v in data.model_dump().items() if v is not None}
        if not update:
            return await self.get_exercise(exercise_id)
        update["updated_at"] = datetime.utcnow()
        result = await db.exercises.update_one(
            {"exercise_id": exercise_id, "created_by": user_id, "is_system": False},
            {"$set": update},
        )
        if result.matched_count == 0:
            return None
        return await self.get_exercise(exercise_id)

    async def delete_exercise(self, user_id: str, exercise_id: str) -> bool:
        result = await get_database().exercises.update_one(
            {"exercise_id": exercise_id, "created_by": user_id, "is_system": False},
            {"$set": {"is_active": False, "updated_at": datetime.utcnow()}},
        )
        return result.modified_count > 0

    # ── Workout Templates ──────────────────────────────────────────────────────

    async def list_templates(self, user_id: str) -> list[dict]:
        db = get_database()
        cursor = db.workout_templates.find(
            {
                "is_active": True,
                "$or": [{"user_id": user_id}, {"is_system_default": True}],
            },
            {"_id": 0},
        )
        return await cursor.to_list(length=200)

    async def get_template(self, template_id: str) -> Optional[dict]:
        db = get_database()
        return await db.workout_templates.find_one(
            {"template_id": template_id, "is_active": True}, {"_id": 0}
        )

    async def create_template(self, user_id: str, data: TemplateCreate) -> dict:
        db = get_database()
        now = datetime.utcnow()
        doc = {
            "template_id": f"tmpl_{uuid.uuid4().hex[:12]}",
            "user_id": user_id,
            "name": data.name,
            "emoji": data.emoji,
            "split_type": data.split_type,
            "split_day_label": data.split_day_label,
            "split_group_id": data.split_group_id,
            "blocks": [b.model_dump() for b in data.blocks],
            "rest_duration_seconds": data.rest_duration_seconds,
            "is_system_default": False,
            "is_active": True,
            "created_at": now,
            "updated_at": now,
        }
        await db.workout_templates.insert_one(doc)
        doc.pop("_id", None)
        return doc

    async def update_template(
        self, user_id: str, template_id: str, data: TemplateUpdate
    ) -> Optional[dict]:
        db = get_database()
        update = {}
        for k, v in data.model_dump().items():
            if v is not None:
                if k == "blocks":
                    update[k] = [b if isinstance(b, dict) else b for b in v]
                else:
                    update[k] = v
        if not update:
            return await self.get_template(template_id)
        update["updated_at"] = datetime.utcnow()
        result = await db.workout_templates.update_one(
            {"template_id": template_id, "user_id": user_id, "is_system_default": False},
            {"$set": update},
        )
        if result.matched_count == 0:
            return None
        return await self.get_template(template_id)

    async def delete_template(self, user_id: str, template_id: str) -> bool:
        result = await get_database().workout_templates.update_one(
            {"template_id": template_id, "user_id": user_id, "is_system_default": False},
            {"$set": {"is_active": False, "updated_at": datetime.utcnow()}},
        )
        return result.modified_count > 0

    async def duplicate_template(self, user_id: str, template_id: str) -> Optional[dict]:
        original = await self.get_template(template_id)
        if not original:
            return None
        now = datetime.utcnow()
        doc = {
            **original,
            "template_id": f"tmpl_{uuid.uuid4().hex[:12]}",
            "user_id": user_id,
            "name": f"{original['name']} (Copy)",
            "is_system_default": False,
            "is_active": True,
            "created_at": now,
            "updated_at": now,
        }
        doc.pop("_id", None)
        await get_database().workout_templates.insert_one(doc)
        doc.pop("_id", None)
        return doc

    async def seed_default_template(self) -> None:
        """Create the free 'Full Body Starter' template if it doesn't exist."""
        db = get_database()
        existing = await db.workout_templates.find_one(
            {"template_id": "full_body_starter"}
        )
        if existing:
            return
        doc = {
            "template_id": "full_body_starter",
            "user_id": "system",
            "name": "Full Body Starter",
            "emoji": "⭐",
            "split_type": "full_body",
            "split_day_label": None,
            "split_group_id": None,
            "blocks": [
                {
                    "block_id": "block_main",
                    "name": "Main Workout",
                    "order": 0,
                    "exercises": [
                        {
                            "exercise_id": "bw_squat",
                            "exercise_name": "Bodyweight Squat",
                            "equipment_type": "bodyweight",
                            "pose_type": "squat",
                            "order": 0,
                            "default_sets": 3,
                            "default_reps": 10,
                            "default_weight": None,
                            "default_rest_seconds": 60,
                            "set_type": "straight",
                            "group_id": None,
                            "notes": None,
                        },
                        {
                            "exercise_id": "bw_pushup",
                            "exercise_name": "Push-Up",
                            "equipment_type": "bodyweight",
                            "pose_type": "pushup",
                            "order": 1,
                            "default_sets": 3,
                            "default_reps": 8,
                            "default_weight": None,
                            "default_rest_seconds": 60,
                            "set_type": "straight",
                            "group_id": None,
                            "notes": None,
                        },
                        {
                            "exercise_id": "bw_lunge",
                            "exercise_name": "Lunge",
                            "equipment_type": "bodyweight",
                            "pose_type": "lunge",
                            "order": 2,
                            "default_sets": 2,
                            "default_reps": 10,
                            "default_weight": None,
                            "default_rest_seconds": 60,
                            "set_type": "straight",
                            "group_id": None,
                            "notes": None,
                        },
                    ],
                }
            ],
            "rest_duration_seconds": 60,
            "is_system_default": True,
            "is_active": True,
            "created_at": datetime.utcnow(),
            "updated_at": datetime.utcnow(),
        }
        await db.workout_templates.insert_one(doc)
        logger.info("Seeded default 'Full Body Starter' template")

    # ── Workout Sessions ───────────────────────────────────────────────────────

    async def create_session(self, user_id: str, data: SessionCreate) -> dict:
        db = get_database()
        now = datetime.utcnow()

        # Compute totals
        total_sets = 0
        total_reps = 0
        total_volume = 0.0
        for ex in data.exercises:
            for s in ex.sets:
                total_sets += 1
                total_reps += s.actual_reps
                total_volume += (s.actual_weight or 0) * s.actual_reps

        session_id = f"sess_{uuid.uuid4().hex[:12]}"

        # Detect PRs
        prs = await self._detect_prs(user_id, session_id, data.exercises)

        doc = {
            "session_id": session_id,
            "user_id": user_id,
            "template_id": data.template_id,
            "template_name": data.template_name,
            "started_at": datetime.fromisoformat(data.started_at),
            "ended_at": datetime.fromisoformat(data.ended_at),
            "duration_seconds": data.duration_seconds,
            "exercises": [e.model_dump() for e in data.exercises],
            "total_sets": total_sets,
            "source": getattr(data, "source", WorkoutSource.USER_MANUAL),
            "created_by": SessionCreatedBy.USER,
            "creator_id": user_id,
            "advisor_notes": None,
            "total_reps": total_reps,
            "total_volume": total_volume,
            "prs": prs,
            "heart_rate_avg": data.heart_rate_avg,
            "heart_rate_max": data.heart_rate_max,
            "notes": data.notes,
            "created_at": now,
        }
        await db.workout_sessions.insert_one(doc)
        doc.pop("_id", None)
        return doc

    async def list_sessions(
        self, user_id: str, limit: int = 50, offset: int = 0
    ) -> list[dict]:
        db = get_database()
        cursor = (
            db.workout_sessions.find({"user_id": user_id}, {"_id": 0})
            .sort("started_at", -1)
            .skip(offset)
            .limit(limit)
        )
        return await cursor.to_list(length=limit)

    async def get_session(self, session_id: str) -> Optional[dict]:
        db = get_database()
        return await db.workout_sessions.find_one(
            {"session_id": session_id}, {"_id": 0}
        )

    async def update_session(
        self, user_id: str, session_id: str, data: SessionUpdate
    ) -> Optional[dict]:
        db = get_database()
        update: dict = {}
        if data.exercises is not None:
            update["exercises"] = [e.model_dump() for e in data.exercises]
            # Recompute totals
            total_sets = total_reps = 0
            total_volume = 0.0
            for ex in data.exercises:
                for s in ex.sets:
                    total_sets += 1
                    total_reps += s.actual_reps
                    total_volume += (s.actual_weight or 0) * s.actual_reps
            update["total_sets"] = total_sets
            update["total_reps"] = total_reps
            update["total_volume"] = total_volume
        if data.notes is not None:
            update["notes"] = data.notes
        if data.advisor_notes is not None:
            update["advisor_notes"] = data.advisor_notes
        if not update:
            return await self.get_session(session_id)
        # Allow the session owner OR the original advisor-creator to edit
        result = await db.workout_sessions.update_one(
            {
                "session_id": session_id,
                "$or": [{"user_id": user_id}, {"creator_id": user_id}],
            },
            {"$set": update},
        )
        if result.matched_count == 0:
            return None
        return await self.get_session(session_id)

    async def create_session_for_user(
        self,
        advisor_id: str,
        target_user_id: str,
        data: AdvisorSessionCreate,
    ) -> dict:
        """Advisor logs a workout on behalf of a user.

        Verifies the advisor has an active team membership with the target user
        before writing the session.
        """
        db = get_database()

        # Verify advisor is an active team member with the target user
        shared_team = await db.team_members.find_one({
            "user_id": advisor_id,
            "status": "member",
            "team_id": {
                "$in": await self._get_user_team_ids(target_user_id),
            },
        })
        if not shared_team:
            raise PermissionError("Advisor does not have access to this user")

        now = datetime.utcnow()
        total_sets = total_reps = 0
        total_volume = 0.0
        for ex in data.exercises:
            for s in ex.sets:
                total_sets += 1
                total_reps += s.actual_reps
                total_volume += (s.actual_weight or 0) * s.actual_reps

        session_id = f"sess_{uuid.uuid4().hex[:12]}"
        prs = await self._detect_prs(target_user_id, session_id, data.exercises)

        doc = {
            "session_id": session_id,
            "user_id": target_user_id,
            "template_id": data.template_id,
            "template_name": data.template_name,
            "started_at": datetime.fromisoformat(data.started_at),
            "ended_at": datetime.fromisoformat(data.ended_at),
            "duration_seconds": data.duration_seconds,
            "exercises": [e.model_dump() for e in data.exercises],
            "total_sets": total_sets,
            "total_reps": total_reps,
            "total_volume": total_volume,
            "prs": prs,
            "heart_rate_avg": None,
            "heart_rate_max": None,
            "notes": data.notes,
            "source": WorkoutSource.ADVISOR_ADDED,
            "created_by": SessionCreatedBy.ADVISOR,
            "creator_id": advisor_id,
            "advisor_notes": data.advisor_notes,
            "created_at": now,
        }
        await db.workout_sessions.insert_one(doc)
        doc.pop("_id", None)
        return doc

    async def _get_user_team_ids(self, user_id: str) -> list[str]:
        """Return all team_ids the user belongs to as an active member."""
        db = get_database()
        cursor = db.team_members.find(
            {"user_id": user_id, "status": "member"}, {"team_id": 1}
        )
        docs = await cursor.to_list(length=200)
        return [d["team_id"] for d in docs]

    # ── Personal Records ───────────────────────────────────────────────────────

    async def _detect_prs(
        self, user_id: str, session_id: str, exercises: list
    ) -> list[dict]:
        """Check each exercise's sets for new PRs, update the PR collection,
        and return a list of new PRs achieved."""
        db = get_database()
        new_prs: list[dict] = []

        for ex in exercises:
            exercise_id = ex.exercise_id if hasattr(ex, "exercise_id") else ex.get("exercise_id")
            exercise_name = ex.exercise_name if hasattr(ex, "exercise_name") else ex.get("exercise_name", "")
            sets = ex.sets if hasattr(ex, "sets") else ex.get("sets", [])

            max_weight = 0.0
            max_reps = 0
            max_volume = 0.0
            for s in sets:
                w = (s.actual_weight if hasattr(s, "actual_weight") else s.get("actual_weight")) or 0
                r = s.actual_reps if hasattr(s, "actual_reps") else s.get("actual_reps", 0)
                if w > max_weight:
                    max_weight = w
                if r > max_reps:
                    max_reps = r
                vol = w * r
                if vol > max_volume:
                    max_volume = vol

            # Check each PR type
            for pr_type, value in [
                ("max_weight", max_weight),
                ("max_reps", float(max_reps)),
                ("max_volume", max_volume),
            ]:
                if value <= 0:
                    continue
                existing = await db.personal_records.find_one(
                    {"user_id": user_id, "exercise_id": exercise_id, "pr_type": pr_type}
                )
                if existing and existing.get("value", 0) >= value:
                    continue
                # New PR!
                pr_id = f"pr_{uuid.uuid4().hex[:12]}"
                pr_doc = {
                    "pr_id": pr_id,
                    "user_id": user_id,
                    "exercise_id": exercise_id,
                    "exercise_name": exercise_name,
                    "pr_type": pr_type,
                    "value": value,
                    "previous_value": existing["value"] if existing else None,
                    "session_id": session_id,
                    "achieved_at": datetime.utcnow(),
                }
                await db.personal_records.update_one(
                    {"user_id": user_id, "exercise_id": exercise_id, "pr_type": pr_type},
                    {"$set": pr_doc},
                    upsert=True,
                )
                new_prs.append(pr_doc)

        return new_prs

    async def list_personal_records(self, user_id: str) -> list[dict]:
        db = get_database()
        cursor = db.personal_records.find({"user_id": user_id}, {"_id": 0})
        return await cursor.to_list(length=500)

    async def get_exercise_prs(self, user_id: str, exercise_id: str) -> list[dict]:
        db = get_database()
        cursor = db.personal_records.find(
            {"user_id": user_id, "exercise_id": exercise_id}, {"_id": 0}
        )
        return await cursor.to_list(length=10)

    # ── Exercise History (for overload analysis) ───────────────────────────────

    async def get_exercise_history(
        self, user_id: str, exercise_id: str, limit: int = 20
    ) -> list[dict]:
        """Return the last N session records that include a given exercise."""
        db = get_database()
        cursor = (
            db.workout_sessions.find(
                {"user_id": user_id, "exercises.exercise_id": exercise_id},
                {"_id": 0},
            )
            .sort("started_at", -1)
            .limit(limit)
        )
        sessions = await cursor.to_list(length=limit)
        # Extract just the matching exercise data from each session
        result = []
        for sess in sessions:
            for ex in sess.get("exercises", []):
                if ex.get("exercise_id") == exercise_id:
                    result.append(
                        {
                            "session_id": sess["session_id"],
                            "date": sess["started_at"].isoformat() if isinstance(sess["started_at"], datetime) else sess["started_at"],
                            "sets": ex.get("sets", []),
                        }
                    )
                    break
        return result

    # ── Progressive Overload Advice ────────────────────────────────────────────

    async def get_overload_advice(
        self, user_id: str, template_id: str
    ) -> list[dict]:
        """Generate progressive overload suggestions for a template's exercises
        based on the last 3+ sessions."""
        template = await self.get_template(template_id)
        if not template:
            return []

        suggestions: list[dict] = []
        seen_exercises: set[str] = set()

        for block in template.get("blocks", []):
            for tex in block.get("exercises", []):
                eid = tex["exercise_id"]
                if eid in seen_exercises:
                    continue
                seen_exercises.add(eid)

                history = await self.get_exercise_history(user_id, eid, limit=5)
                if len(history) < 3:
                    continue

                # Analyze the last 3 sessions
                last3 = history[:3]
                all_completed_at_target = True
                avg_weight = 0.0
                weight_count = 0

                for h in last3:
                    for s in h.get("sets", []):
                        w = s.get("actual_weight") or 0
                        r = s.get("actual_reps", 0)
                        target = s.get("target_reps", tex.get("default_reps", 10))
                        if r < target:
                            all_completed_at_target = False
                        if w > 0:
                            avg_weight += w
                            weight_count += 1

                if weight_count > 0:
                    avg_weight /= weight_count

                if all_completed_at_target and avg_weight > 0:
                    # Suggest 5-10% weight increase
                    increment = max(2.5, round(avg_weight * 0.075, 1))
                    suggestions.append(
                        OverloadSuggestion(
                            exercise_id=eid,
                            exercise_name=tex.get("exercise_name", ""),
                            suggestion_type="increase_weight",
                            current_value=round(avg_weight, 1),
                            suggested_value=round(avg_weight + increment, 1),
                            reasoning=f"You've hit your target reps for 3 consecutive sessions at {round(avg_weight, 1)} lbs/kg. Try increasing by {increment}.",
                        ).model_dump()
                    )
                elif all_completed_at_target:
                    suggestions.append(
                        OverloadSuggestion(
                            exercise_id=eid,
                            exercise_name=tex.get("exercise_name", ""),
                            suggestion_type="increase_reps",
                            current_value=float(tex.get("default_reps", 10)),
                            suggested_value=float(tex.get("default_reps", 10) + 2),
                            reasoning="You've consistently completed all target reps. Try adding 2 more reps per set.",
                        ).model_dump()
                    )

        return suggestions


workout_service = WorkoutService()
