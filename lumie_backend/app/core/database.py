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


def get_database() -> AsyncIOMotorDatabase:
    """Get database instance."""
    return db.db
