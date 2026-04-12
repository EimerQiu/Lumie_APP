"""Application configuration settings."""
import os
from typing import Optional
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    # App
    APP_NAME: str = "Lumie API"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = False

    # MongoDB
    MONGODB_URL: str = os.getenv("MONGODB_URL", "mongodb://localhost:27017")
    MONGODB_DB_NAME: str = os.getenv("MONGODB_DB_NAME", "lumie_db")

    # JWT Authentication
    SECRET_KEY: str = os.getenv("SECRET_KEY", "lumie-super-secret-key-change-in-production-2024")
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 7  # 7 days

    # LLM provider
    PALEBLUEDOT_API_KEY: str = os.getenv("PALEBLUEDOT_API_KEY", "")
    PALEBLUEDOT_API_BASE_URL: str = os.getenv("PALEBLUEDOT_API_BASE_URL", "https://open.palebluedot.ai/v1")
    PALEBLUEDOT_MODEL: str = os.getenv("PALEBLUEDOT_MODEL", "openai/gpt-5.4")
    # Backward-compatible fallback while environments are migrated.
    ANTHROPIC_API_KEY: str = os.getenv("ANTHROPIC_API_KEY", "")
    OPENAI_API_KEY: str = os.getenv("OPENAI_API_KEY", "")
    OPENAI_API_BASE_URL: str = os.getenv("OPENAI_API_BASE_URL", "https://api.openai.com/v1")
    OPENAI_VISION_MODEL: str = os.getenv("OPENAI_VISION_MODEL", "gpt-4.1-mini")

    # Sandbox (AI data analysis)
    SANDBOX_MONGO_URI: str = os.getenv("SANDBOX_MONGO_URI", "")

    # CORS
    CORS_ORIGINS: list[str] = ["*"]

    class Config:
        env_file = ".env"
        case_sensitive = True
        extra = "ignore"


settings = Settings()
