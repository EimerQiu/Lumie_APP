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


def get_database() -> AsyncIOMotorDatabase:
    """Get database instance."""
    return db.db
