"""
Admin Task Service
Business logic for admin dashboard task operations (global task view,
admin complete, admin delete, reward calculation).
"""

from datetime import datetime
from typing import Optional, List
from fastapi import HTTPException, status

from ..core.database import get_database
from ..models.task import (
    TaskStatus, AdminTaskData, AdminTaskListResponse, RptTaskItem,
)
from ..models.team import TeamRole, MemberStatus

PAGE_SIZE = 10


class AdminTaskService:
    """Service for admin task dashboard operations"""

    async def _verify_admin_of_any_team(self, user_id: str) -> List[str]:
        """
        Verify user is admin of at least one team.
        Returns list of team_ids where user is admin.
        """
        db = get_database()
        cursor = db.team_members.find({
            "user_id": user_id,
            "role": TeamRole.ADMIN.value,
            "status": MemberStatus.MEMBER.value,
        })
        admin_memberships = await cursor.to_list(length=None)
        if not admin_memberships:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Admin dashboard requires team admin role",
            )
        return [m["team_id"] for m in admin_memberships]

    async def _get_team_member_ids(self, team_ids: List[str]) -> List[str]:
        """Get all member user_ids across the given teams"""
        db = get_database()
        cursor = db.team_members.find({
            "team_id": {"$in": team_ids},
            "status": MemberStatus.MEMBER.value,
        })
        members = await cursor.to_list(length=None)
        return list({m["user_id"] for m in members})

    async def _get_user_id_by_email(self, email: str) -> Optional[str]:
        """Look up user_id by email"""
        db = get_database()
        user = await db.users.find_one({"email": email.lower().strip()})
        return user["user_id"] if user else None

    async def _enrich_task(self, task: dict) -> AdminTaskData:
        """Convert raw task doc to AdminTaskData with enriched fields"""
        db = get_database()

        # Get username from profile
        profile = await db.profiles.find_one({"user_id": task["user_id"]})
        username = profile.get("name", "Unknown") if profile else "Unknown"

        # Get team name if team task
        family_name = None
        if task.get("team_id"):
            team = await db.teams.find_one({"team_id": task["team_id"]})
            family_name = team.get("name") if team else None

        # Get template info if from a template
        rpttask_list = []
        min_interval = 0
        if task.get("rpttask_id"):
            template = await db.task_templates.find_one({"id": task["rpttask_id"]})
            if template:
                min_interval = template.get("min_interval", 0)
                for tw in template.get("time_window_list", []):
                    # Convert HH:MM to minutes from midnight
                    open_parts = tw.get("open_time", "00:00").split(":")
                    close_parts = tw.get("close_time", "00:00").split(":")
                    rpttask_list.append(RptTaskItem(
                        id=tw.get("id", 0),
                        name=tw.get("name", ""),
                        open_time=int(open_parts[0]) * 60 + int(open_parts[1]),
                        close_time=int(close_parts[0]) * 60 + int(close_parts[1]),
                    ))

        # Compute status based on done field and close_datetime
        # done field exists → completed
        # done doesn't exist + close_datetime passed → expired
        # done doesn't exist + close_datetime not passed → pending
        now_str = datetime.utcnow().strftime("%Y-%m-%d %H:%M")

        if task.get("done"):
            task_status = TaskStatus.COMPLETED.value
        elif task["close_datetime"] < now_str:
            task_status = TaskStatus.EXPIRED.value
        else:
            task_status = TaskStatus.PENDING.value

        return AdminTaskData(
            task_id=task["task_id"],
            user_id=task["user_id"],
            username=username,
            task_type=task.get("task_type", ""),
            open_datetime=task["open_datetime"],
            close_datetime=task["close_datetime"],
            status=task_status,
            rpttask_id=task.get("rpttask_id"),
            rpttask_name=task.get("task_name", ""),
            rpttask_info=task.get("task_info"),
            rpttask_type=task.get("task_type", ""),
            rpttask_list=rpttask_list,
            small_task_id=task.get("small_task_id"),
            min_interval=min_interval,
            family_id=task.get("team_id"),
            family_name=family_name,
        )

    async def get_admin_task_list(
        self,
        admin_user_id: str,
        email: Optional[str] = None,
        time_zone: str = "UTC",
        current_time: Optional[str] = None,
        previous_offset: int = 0,
        upcoming_offset: int = 0,
    ) -> AdminTaskListResponse:
        """
        Get global task list for admin dashboard.
        Shows all tasks across teams the admin manages.
        """
        db = get_database()
        admin_team_ids = await self._verify_admin_of_any_team(admin_user_id)

        # Determine which user_ids to query
        if email:
            target_user_id = await self._get_user_id_by_email(email)
            if not target_user_id:
                return AdminTaskListResponse(previous_tasks=[], upcoming_tasks=[])
            user_ids = [target_user_id]
        else:
            # All members across admin's teams (including admin themselves)
            user_ids = await self._get_team_member_ids(admin_team_ids)
            # Also include admin's own tasks
            if admin_user_id not in user_ids:
                user_ids.append(admin_user_id)

        # Current time for splitting previous/upcoming
        now_str = current_time or datetime.utcnow().strftime("%Y-%m-%d %H:%M")

        # Previous tasks (open_datetime <= now), sorted descending (newest first), paginated
        prev_cursor = db.tasks.find({
            "user_id": {"$in": user_ids},
            "open_datetime": {"$lte": now_str},
        }).sort("open_datetime", -1).skip(previous_offset).limit(PAGE_SIZE)
        prev_tasks = await prev_cursor.to_list(length=PAGE_SIZE)

        # Upcoming tasks (open_datetime > now), sorted ascending, paginated
        up_cursor = db.tasks.find({
            "user_id": {"$in": user_ids},
            "open_datetime": {"$gt": now_str},
        }).sort("open_datetime", 1).skip(upcoming_offset).limit(PAGE_SIZE)
        up_tasks = await up_cursor.to_list(length=PAGE_SIZE)

        # Enrich all tasks
        previous = [await self._enrich_task(t) for t in prev_tasks]
        upcoming = [await self._enrich_task(t) for t in up_tasks]

        return AdminTaskListResponse(
            previous_tasks=previous,
            upcoming_tasks=upcoming,
        )

    async def admin_complete_task(
        self,
        admin_user_id: str,
        task_id: str,
        time_zone: str = "UTC",
    ) -> dict:
        """Admin marks any task as completed"""
        db = get_database()

        # Verify admin status
        await self._verify_admin_of_any_team(admin_user_id)

        task = await db.tasks.find_one({"task_id": task_id})
        if not task:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Task not found",
            )

        # Verify admin has authority: task is in one of admin's teams, or admin created it
        admin_team_ids = await self._verify_admin_of_any_team(admin_user_id)
        is_team_task = task.get("team_id") and task["team_id"] in admin_team_ids
        is_creator = task.get("created_by") == admin_user_id
        is_own_task = task["user_id"] == admin_user_id

        if not (is_team_task or is_creator or is_own_task):
            # Also check if the task's user is in one of admin's teams
            member_ids = await self._get_team_member_ids(admin_team_ids)
            if task["user_id"] not in member_ids:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="You do not have admin authority over this task's user",
                )

        # Check if already completed (done field exists)
        if task.get("done"):
            return {"message": "Task is already completed"}

        # Set done timestamp to close_datetime so task shows as "completed" not "expired"
        # Parse close_datetime and convert to UTC timestamp
        try:
            close_dt = datetime.strptime(task["close_datetime"], "%Y-%m-%d %H:%M")
        except:
            # Fallback to current time if parsing fails
            close_dt = datetime.utcnow()

        now = datetime.utcnow()
        await db.tasks.update_one(
            {"task_id": task_id},
            {"$set": {
                "done": close_dt,  # Set done to close_datetime for proper status calculation
                "updated_at": now,
            }}
        )

        return {"message": "Task completed successfully"}

    async def admin_delete_task(
        self,
        admin_user_id: str,
        task_id: str,
    ) -> dict:
        """Admin permanently deletes a task"""
        db = get_database()

        await self._verify_admin_of_any_team(admin_user_id)

        task = await db.tasks.find_one({"task_id": task_id})
        if not task:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Task not found",
            )

        # Verify authority
        admin_team_ids = await self._verify_admin_of_any_team(admin_user_id)
        is_team_task = task.get("team_id") and task["team_id"] in admin_team_ids
        is_creator = task.get("created_by") == admin_user_id
        is_own_task = task["user_id"] == admin_user_id

        if not (is_team_task or is_creator or is_own_task):
            member_ids = await self._get_team_member_ids(admin_team_ids)
            if task["user_id"] not in member_ids:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="You do not have admin authority over this task's user",
                )

        await db.tasks.delete_one({"task_id": task_id})
        return {"message": "Task deleted successfully"}

    async def get_reward_calc_tasks(
        self,
        admin_user_id: str,
        email: str,
        time_zone: str = "UTC",
        offset: int = 0,
    ) -> List[AdminTaskData]:
        """
        Get tasks for reward calculation view.
        Returns only closed/expired tasks (where close_datetime <= now) for reward/fine calculation.
        Sorted by close_datetime descending (newest closed first).
        """
        db = get_database()

        await self._verify_admin_of_any_team(admin_user_id)

        target_user_id = await self._get_user_id_by_email(email)
        if not target_user_id:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found with that email",
            )

        # Return tasks eligible for reward calculation:
        # - Completed (done field exists), OR
        # - Expired (close_datetime <= now)
        now_str = datetime.utcnow().strftime("%Y-%m-%d %H:%M")
        cursor = db.tasks.find({
            "user_id": target_user_id,
            "$or": [
                {"done": {"$exists": True}},  # Task is completed
                {"close_datetime": {"$lte": now_str}},  # Task window has closed
            ]
        }).sort("close_datetime", -1).skip(offset).limit(PAGE_SIZE)

        tasks = await cursor.to_list(length=PAGE_SIZE)
        return [await self._enrich_task(t) for t in tasks]


# Singleton instance
admin_task_service = AdminTaskService()
