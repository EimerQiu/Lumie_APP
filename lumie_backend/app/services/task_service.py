"""
Task Service
Business logic for Med-Reminder task and template operations
"""

import uuid
from datetime import datetime, timedelta
from typing import Optional, List
from fastapi import HTTPException, status

from ..core.database import get_database
from ..core.subscription_helpers import get_task_limit, raise_task_limit_error
from ..models.task import (
    TaskType, TaskStatus,
    TaskCreate, TaskResponse, TaskListResponse,
    TemplateCreate, TemplateResponse, TemplateListResponse,
    TimeWindow, BatchGenerateRequest, BatchGenerateResponse,
)
from ..models.user import SubscriptionTier
from ..models.team import TeamRole, MemberStatus


class TaskService:
    """Service for handling task and template operations"""

    def _format_datetime(self, dt: datetime) -> str:
        """Format datetime to ISO string for response"""
        return dt.isoformat()

    def _task_doc_to_response(self, doc: dict) -> TaskResponse:
        """Convert a MongoDB task document to TaskResponse"""
        return TaskResponse(
            task_id=doc["task_id"],
            task_name=doc["task_name"],
            task_type=TaskType(doc["task_type"]),
            open_datetime=doc["open_datetime"],
            close_datetime=doc["close_datetime"],
            user_id=doc["user_id"],
            team_id=doc.get("team_id"),
            created_by=doc["created_by"],
            rpttask_id=doc.get("rpttask_id"),
            status=TaskStatus(doc["status"]),
            task_info=doc.get("task_info"),
            completed_at=self._format_datetime(doc["completed_at"]) if doc.get("completed_at") else None,
            created_at=self._format_datetime(doc["created_at"]),
            updated_at=self._format_datetime(doc["updated_at"]),
        )

    def _template_doc_to_response(self, doc: dict) -> TemplateResponse:
        """Convert a MongoDB template document to TemplateResponse"""
        time_window_list = [
            TimeWindow(
                id=tw["id"],
                name=tw["name"],
                open_time=tw["open_time"],
                close_time=tw["close_time"],
                is_next_day=tw.get("is_next_day", False),
            )
            for tw in doc.get("time_window_list", [])
        ]
        return TemplateResponse(
            id=doc["id"],
            template_name=doc["template_name"],
            template_type=TaskType(doc["template_type"]),
            description=doc.get("description"),
            time_windows=doc["time_windows"],
            min_interval=doc["min_interval"],
            time_window_list=time_window_list,
            created_by=doc["created_by"],
            created_at=self._format_datetime(doc["created_at"]),
            updated_at=self._format_datetime(doc["updated_at"]),
        )

    async def _get_user_subscription_tier(self, user_id: str) -> tuple:
        """
        Get user's subscription tier

        Returns:
            Tuple of (SubscriptionTier enum, tier string value)
        """
        db = get_database()
        user = await db.users.find_one({"user_id": user_id})
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found"
            )
        subscription = user.get("subscription", {})
        tier_value = subscription.get("tier", "free")
        return SubscriptionTier(tier_value), tier_value

    async def get_active_task_count(self, user_id: str) -> int:
        """
        Count number of active (non-completed) tasks for user

        Args:
            user_id: User ID to count tasks for

        Returns:
            Number of tasks where status is pending or overdue
        """
        db = get_database()
        count = await db.tasks.count_documents({
            "user_id": user_id,
            "status": {"$in": [TaskStatus.PENDING.value, TaskStatus.OVERDUE.value]}
        })
        return count

    async def _check_overdue_tasks(self, tasks: List[dict]) -> List[dict]:
        """
        Lazily mark tasks as overdue if their close_datetime has passed

        Args:
            tasks: List of task documents

        Returns:
            Updated task documents with overdue status applied
        """
        db = get_database()
        now_str = datetime.utcnow().strftime("%Y-%m-%d %H:%M")
        updated_tasks = []

        for task in tasks:
            if task["status"] == TaskStatus.PENDING.value and task["close_datetime"] < now_str:
                # Mark as overdue in DB
                await db.tasks.update_one(
                    {"task_id": task["task_id"]},
                    {"$set": {"status": TaskStatus.OVERDUE.value, "updated_at": datetime.utcnow()}}
                )
                task["status"] = TaskStatus.OVERDUE.value
            updated_tasks.append(task)

        return updated_tasks

    async def create_task(self, user_id: str, data: TaskCreate) -> TaskResponse:
        """
        Create a new task with subscription limit check

        Args:
            user_id: ID of user creating the task
            data: Task creation data

        Returns:
            TaskResponse with created task details

        Raises:
            HTTPException: If subscription limit reached or other error
        """
        db = get_database()

        # Determine the assigned user
        assigned_user_id = data.user_id if data.user_id else user_id

        # If team task, verify creator is admin of the team
        if data.team_id:
            admin_member = await db.team_members.find_one({
                "team_id": data.team_id,
                "user_id": user_id,
                "role": TeamRole.ADMIN.value,
                "status": MemberStatus.MEMBER.value
            })
            if not admin_member:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Only team admins can create team tasks"
                )

            # Verify assigned user is a member of the team
            if assigned_user_id != user_id:
                target_member = await db.team_members.find_one({
                    "team_id": data.team_id,
                    "user_id": assigned_user_id,
                    "status": MemberStatus.MEMBER.value
                })
                if not target_member:
                    raise HTTPException(
                        status_code=status.HTTP_404_NOT_FOUND,
                        detail="Assigned user is not a member of this team"
                    )

        # Check subscription limit for the assigned user
        subscription_tier, tier_value = await self._get_user_subscription_tier(assigned_user_id)
        current_count = await self.get_active_task_count(assigned_user_id)
        limit = get_task_limit(subscription_tier)

        if current_count >= limit:
            raise_task_limit_error(
                user_tier=tier_value,
                current_count=current_count,
                limit=limit,
            )

        # Validate time ordering
        if data.close_datetime <= data.open_datetime:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="End time must be after start time"
            )

        # Create task
        task_id = str(uuid.uuid4())
        now = datetime.utcnow()

        task_doc = {
            "task_id": task_id,
            "task_name": data.task_name,
            "task_type": data.task_type.value,
            "open_datetime": data.open_datetime,
            "close_datetime": data.close_datetime,
            "user_id": assigned_user_id,
            "team_id": data.team_id,
            "created_by": user_id,
            "rpttask_id": data.rpttask_id,
            "status": TaskStatus.PENDING.value,
            "task_info": data.task_info,
            "completed_at": None,
            "created_at": now,
            "updated_at": now,
        }

        await db.tasks.insert_one(task_doc)

        return self._task_doc_to_response(task_doc)

    async def get_tasks(
        self,
        user_id: str,
        status_filter: Optional[str] = None,
        date: Optional[str] = None,
    ) -> TaskListResponse:
        """
        Get tasks for user with optional filters

        Args:
            user_id: User ID
            status_filter: Filter by status (pending, completed, overdue)
            date: Filter by date (yyyy-MM-dd)

        Returns:
            TaskListResponse with matching tasks
        """
        db = get_database()

        query = {"user_id": user_id}

        if status_filter:
            query["status"] = status_filter

        if date:
            # Match tasks whose window overlaps with the given date
            query["open_datetime"] = {"$regex": f"^{date}"}

        cursor = db.tasks.find(query).sort("open_datetime", 1)
        tasks = await cursor.to_list(length=None)

        # Lazily update overdue status
        tasks = await self._check_overdue_tasks(tasks)

        # Apply status filter again after overdue check (in case filter was for a specific status)
        if status_filter:
            tasks = [t for t in tasks if t["status"] == status_filter]

        task_responses = [self._task_doc_to_response(t) for t in tasks]

        return TaskListResponse(
            tasks=task_responses,
            total=len(task_responses),
        )

    async def complete_task(self, task_id: str, user_id: str) -> TaskResponse:
        """
        Mark a task as completed

        Args:
            task_id: Task ID
            user_id: User ID (must be the assigned user)

        Returns:
            Updated TaskResponse

        Raises:
            HTTPException: If task not found or not authorized
        """
        db = get_database()

        task = await db.tasks.find_one({"task_id": task_id})
        if not task:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Task not found"
            )

        # Only the assigned user can complete
        if task["user_id"] != user_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only the assigned user can complete this task"
            )

        if task["status"] == TaskStatus.COMPLETED.value:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Task is already completed"
            )

        now = datetime.utcnow()
        await db.tasks.update_one(
            {"task_id": task_id},
            {"$set": {
                "status": TaskStatus.COMPLETED.value,
                "completed_at": now,
                "updated_at": now,
            }}
        )

        task["status"] = TaskStatus.COMPLETED.value
        task["completed_at"] = now
        task["updated_at"] = now

        return self._task_doc_to_response(task)

    async def delete_task(self, task_id: str, user_id: str) -> dict:
        """
        Delete a task

        Args:
            task_id: Task ID
            user_id: User ID (must be assignee or creator)

        Returns:
            Dict with success message

        Raises:
            HTTPException: If task not found or not authorized
        """
        db = get_database()

        task = await db.tasks.find_one({"task_id": task_id})
        if not task:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Task not found"
            )

        # Both assignee and creator can delete
        if task["user_id"] != user_id and task["created_by"] != user_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only the assigned user or task creator can delete this task"
            )

        await db.tasks.delete_one({"task_id": task_id})

        return {"message": "Task deleted successfully"}

    # ============ Template Operations ============

    async def get_templates(self, user_id: str) -> TemplateListResponse:
        """
        Get all templates for user

        Args:
            user_id: User ID

        Returns:
            TemplateListResponse with user's templates
        """
        db = get_database()

        cursor = db.task_templates.find({"created_by": user_id}).sort("created_at", -1)
        templates = await cursor.to_list(length=None)

        template_responses = [self._template_doc_to_response(t) for t in templates]

        return TemplateListResponse(
            templates=template_responses,
            total=len(template_responses),
        )

    async def create_template(self, user_id: str, data: TemplateCreate) -> TemplateResponse:
        """
        Create a new task template

        Args:
            user_id: Creator user ID
            data: Template creation data

        Returns:
            TemplateResponse with created template

        Raises:
            HTTPException: If validation fails
        """
        db = get_database()

        template_id = str(uuid.uuid4())
        now = datetime.utcnow()

        template_doc = {
            "id": template_id,
            "template_name": data.template_name,
            "template_type": data.template_type.value,
            "description": data.description,
            "time_windows": len(data.time_window_list),
            "min_interval": data.min_interval,
            "time_window_list": [tw.model_dump() for tw in data.time_window_list],
            "created_by": user_id,
            "created_at": now,
            "updated_at": now,
        }

        await db.task_templates.insert_one(template_doc)

        return self._template_doc_to_response(template_doc)

    async def get_template(self, template_id: str, user_id: str) -> TemplateResponse:
        """
        Get template detail

        Args:
            template_id: Template ID
            user_id: Requesting user ID (must be creator)

        Returns:
            TemplateResponse

        Raises:
            HTTPException: If not found or not authorized
        """
        db = get_database()

        template = await db.task_templates.find_one({"id": template_id})
        if not template:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Template not found"
            )

        if template["created_by"] != user_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You can only view your own templates"
            )

        return self._template_doc_to_response(template)

    async def delete_template(self, template_id: str, user_id: str) -> dict:
        """
        Delete a template

        Args:
            template_id: Template ID
            user_id: Requesting user ID (must be creator)

        Returns:
            Dict with success message

        Raises:
            HTTPException: If not found or not authorized
        """
        db = get_database()

        template = await db.task_templates.find_one({"id": template_id})
        if not template:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Template not found"
            )

        if template["created_by"] != user_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You can only delete your own templates"
            )

        await db.task_templates.delete_one({"id": template_id})

        return {"message": "Template deleted successfully"}

    # ============ Batch Generation ============

    def _generate_tasks_from_template(
        self,
        template: dict,
        task_name: str,
        start_date: str,
        end_date: str,
        user_id: str,
        created_by: str,
        team_id: Optional[str] = None,
        task_info: Optional[str] = None,
    ) -> List[dict]:
        """
        Generate task documents from a template for a date range

        Args:
            template: Template document
            task_name: Base name for generated tasks
            start_date: Start date (yyyy-MM-dd)
            end_date: End date (yyyy-MM-dd)
            user_id: Assigned user ID
            created_by: Creator user ID
            team_id: Optional team ID
            task_info: Optional task info

        Returns:
            List of task documents ready for insertion
        """
        from datetime import datetime as dt

        start = dt.strptime(start_date, "%Y-%m-%d")
        end = dt.strptime(end_date, "%Y-%m-%d")
        now = datetime.utcnow()

        tasks = []
        current_date = start

        while current_date <= end:
            date_str = current_date.strftime("%Y-%m-%d")

            for window in template.get("time_window_list", []):
                window_name = window["name"]
                open_time = window["open_time"]
                close_time = window["close_time"]
                is_next_day = window.get("is_next_day", False)

                open_datetime = f"{date_str} {open_time}"

                if is_next_day:
                    next_day = current_date + timedelta(days=1)
                    close_datetime = f"{next_day.strftime('%Y-%m-%d')} {close_time}"
                else:
                    close_datetime = f"{date_str} {close_time}"

                full_task_name = f"{task_name} - {window_name}"

                task_doc = {
                    "task_id": str(uuid.uuid4()),
                    "task_name": full_task_name,
                    "task_type": template["template_type"],
                    "open_datetime": open_datetime,
                    "close_datetime": close_datetime,
                    "user_id": user_id,
                    "team_id": team_id,
                    "created_by": created_by,
                    "rpttask_id": template["id"],
                    "status": TaskStatus.PENDING.value,
                    "task_info": task_info,
                    "completed_at": None,
                    "created_at": now,
                    "updated_at": now,
                }
                tasks.append(task_doc)

            current_date += timedelta(days=1)

        return tasks

    async def batch_generate(self, user_id: str, data: BatchGenerateRequest) -> BatchGenerateResponse:
        """
        Generate tasks from template for a date range

        Args:
            user_id: Creator user ID
            data: Batch generation parameters

        Returns:
            BatchGenerateResponse with created tasks

        Raises:
            HTTPException: If template not found, subscription limit, or other error
        """
        db = get_database()

        # Load template
        template = await db.task_templates.find_one({"id": data.template_id})
        if not template:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Template not found"
            )

        if template["created_by"] != user_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You can only use your own templates"
            )

        # Determine assigned user
        assigned_user_id = data.user_id if data.user_id else user_id

        # If team task, verify admin
        if data.team_id:
            admin_member = await db.team_members.find_one({
                "team_id": data.team_id,
                "user_id": user_id,
                "role": TeamRole.ADMIN.value,
                "status": MemberStatus.MEMBER.value
            })
            if not admin_member:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Only team admins can create team tasks"
                )

        # Generate task documents
        task_docs = self._generate_tasks_from_template(
            template=template,
            task_name=data.task_name,
            start_date=data.start_date,
            end_date=data.end_date,
            user_id=assigned_user_id,
            created_by=user_id,
            team_id=data.team_id,
            task_info=data.task_info,
        )

        if not task_docs:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No tasks to generate for the given date range"
            )

        # Check subscription limit
        subscription_tier, tier_value = await self._get_user_subscription_tier(assigned_user_id)
        current_count = await self.get_active_task_count(assigned_user_id)
        limit = get_task_limit(subscription_tier)
        new_total = current_count + len(task_docs)

        if new_total > limit:
            raise_task_limit_error(
                user_tier=tier_value,
                current_count=current_count,
                limit=limit,
            )

        # Bulk insert
        await db.tasks.insert_many(task_docs)

        task_responses = [self._task_doc_to_response(t) for t in task_docs]

        return BatchGenerateResponse(
            created_count=len(task_responses),
            tasks=task_responses,
        )

    async def batch_preview(self, user_id: str, data: BatchGenerateRequest) -> dict:
        """
        Preview tasks that would be generated from a template

        Args:
            user_id: User ID
            data: Batch generation parameters

        Returns:
            Dict with preview information
        """
        db = get_database()

        template = await db.task_templates.find_one({"id": data.template_id})
        if not template:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Template not found"
            )

        assigned_user_id = data.user_id if data.user_id else user_id

        task_docs = self._generate_tasks_from_template(
            template=template,
            task_name=data.task_name,
            start_date=data.start_date,
            end_date=data.end_date,
            user_id=assigned_user_id,
            created_by=user_id,
            team_id=data.team_id,
            task_info=data.task_info,
        )

        preview_tasks = [
            {
                "task_name": t["task_name"],
                "open_datetime": t["open_datetime"],
                "close_datetime": t["close_datetime"],
            }
            for t in task_docs
        ]

        return {
            "template_id": data.template_id,
            "task_count": len(preview_tasks),
            "tasks_preview": preview_tasks,
        }


# Singleton instance
task_service = TaskService()
