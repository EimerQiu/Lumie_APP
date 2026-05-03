"""MongoDB database connection and utilities."""
from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorDatabase
from typing import Optional

from .config import settings


class Database:
    """MongoDB database connection manager."""

    client: Optional[AsyncIOMotorClient] = None
    db: Optional[AsyncIOMotorDatabase] = None


db = Database()


async def connect_to_mongo():
    """Connect to MongoDB."""
    db.client = AsyncIOMotorClient(settings.MONGODB_URL)
    db.db = db.client[settings.MONGODB_DB_NAME]

    # Create indexes
    await create_indexes()

    print(f"Connected to MongoDB: {settings.MONGODB_DB_NAME}")


async def close_mongo_connection():
    """Close MongoDB connection."""
    if db.client:
        db.client.close()
        print("Closed MongoDB connection")


async def create_indexes():
    """Create database indexes for performance."""
    # User collection indexes
    await db.db.users.create_index("email", unique=True)
    await db.db.users.create_index("user_id", unique=True)

    # Profile collection indexes
    await db.db.profiles.create_index("user_id", unique=True)

    # Activity collection indexes
    await db.db.activities.create_index("user_id")
    await db.db.activities.create_index([("user_id", 1), ("start_time", -1)])

    # Walk test collection indexes
    await db.db.walk_tests.create_index("user_id")
    await db.db.walk_tests.create_index([("user_id", 1), ("date", -1)])

    # Team collection indexes
    await db.db.teams.create_index("team_id", unique=True)
    await db.db.teams.create_index("created_by")
    await db.db.teams.create_index("is_deleted")

    # Team members collection indexes
    await db.db.team_members.create_index([("team_id", 1), ("user_id", 1)], unique=True)
    await db.db.team_members.create_index([("user_id", 1), ("status", 1)])
    await db.db.team_members.create_index([("team_id", 1), ("status", 1)])
    await db.db.team_members.create_index("invited_at")

    # Pending invitations collection indexes (email-based invitations)
    await db.db.pending_invitations.create_index([("team_id", 1), ("email", 1)], unique=True)
    await db.db.pending_invitations.create_index("email")
    await db.db.pending_invitations.create_index("expires_at")

    # Task collection indexes (Med-Reminder)
    await db.db.tasks.create_index("task_id", unique=True)
    await db.db.tasks.create_index([("user_id", 1), ("status", 1)])
    await db.db.tasks.create_index([("user_id", 1), ("open_datetime", 1)])
    await db.db.tasks.create_index([("team_id", 1), ("user_id", 1)])
    await db.db.tasks.create_index("created_by")

    # Task templates collection indexes
    await db.db.task_templates.create_index("id", unique=True)
    await db.db.task_templates.create_index("created_by")

    # Analysis jobs collection indexes
    await db.db.analysis_jobs.create_index("job_id", unique=True)
    await db.db.analysis_jobs.create_index([("user_id", 1), ("created_at", -1)])
    await db.db.analysis_jobs.create_index("status")

    # Advisor v2: capabilities
    await db.db.advisor_capabilities.create_index("capability_id", unique=True)

    # Advisor v2: user capabilities
    await db.db.user_advisor_capabilities.create_index(
        [("user_id", 1), ("capability_id", 1)], unique=True
    )

    # Advisor v2: skill credentials
    await db.db.advisor_skill_credentials.create_index(
        [("user_id", 1), ("skill_id", 1)], unique=True
    )

    # Advisor v2: execution jobs
    await db.db.execution_jobs.create_index("job_id", unique=True)
    await db.db.execution_jobs.create_index([("user_id", 1), ("created_at", -1)])
    await db.db.execution_jobs.create_index("status")

    # Advisor v2: audit logs
    await db.db.execution_audit_logs.create_index("log_id", unique=True)
    await db.db.execution_audit_logs.create_index([("user_id", 1), ("created_at", -1)])
    await db.db.advisor_pending_actions.create_index(
        [("user_id", 1), ("session_id", 1), ("action_type", 1), ("status", 1)]
    )
    await db.db.advisor_pending_actions.create_index("expires_at")
    await db.db.advisor_pending_actions.create_index("thread_id")

    # Advisor cross-user messaging (advisor <-> advisor)
    await db.db.advisor_cross_messages.create_index("message_id", unique=True)
    await db.db.advisor_cross_messages.create_index([("thread_id", 1), ("created_at", 1)])
    await db.db.advisor_cross_messages.create_index([("to_user_id", 1), ("status", 1)])
    await db.db.advisor_cross_messages.create_index([("from_user_id", 1), ("created_at", -1)])
    await db.db.advisor_cross_messages.create_index("expires_at")
    await db.db.advisor_cross_messages.create_index(
        "idempotency_key", unique=True, sparse=True
    )

    # Proactive advisor: audit collections
    await db.db.proactive_runs.create_index("run_id", unique=True)
    await db.db.proactive_runs.create_index([("user_id", 1), ("started_at", -1)])

    await db.db.proactive_skill_results.create_index([("run_id", 1)])
    await db.db.proactive_skill_results.create_index([("user_id", 1), ("assessed_at", -1)])

    await db.db.proactive_decisions.create_index([("run_id", 1)])
    await db.db.proactive_decisions.create_index([("user_id", 1), ("decided_at", -1)])
    await db.db.proactive_checklists.create_index("user_id", unique=True)

    # Workout: exercises collection
    await db.db.exercises.create_index("exercise_id", unique=True)
    await db.db.exercises.create_index([("is_system", 1), ("is_active", 1)])
    await db.db.exercises.create_index([("created_by", 1), ("is_active", 1)])

    # Workout: templates collection
    await db.db.workout_templates.create_index("template_id", unique=True)
    await db.db.workout_templates.create_index([("user_id", 1), ("is_active", 1)])
    await db.db.workout_templates.create_index("is_system_default")

    # Workout: sessions collection
    await db.db.workout_sessions.create_index("session_id", unique=True)
    await db.db.workout_sessions.create_index([("user_id", 1), ("started_at", -1)])
    await db.db.workout_sessions.create_index([("user_id", 1), ("template_id", 1)])

    # Workout: personal records collection
    await db.db.personal_records.create_index("pr_id", unique=True)
    await db.db.personal_records.create_index(
        [("user_id", 1), ("exercise_id", 1), ("pr_type", 1)], unique=True
    )

    # HR session collection indexes
    await db.db.hr_sessions.create_index([("user_id", 1), ("started_at", -1)])

    # HR timeseries collection indexes (bucket pattern)
    # Primary lookup: fetch all buckets for a session in order
    await db.db.hr_timeseries.create_index([("session_id", 1), ("bucket_start", 1)])
    # Secondary: user-level time-range queries (e.g. "last 7 days of HR data")
    await db.db.hr_timeseries.create_index([("user_id", 1), ("bucket_start", -1)])


def get_database() -> AsyncIOMotorDatabase:
    """Get database instance."""
    return db.db
