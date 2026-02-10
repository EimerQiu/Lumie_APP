"""Lumie API - FastAPI application."""
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pathlib import Path

from .core.config import settings
from .core.database import connect_to_mongo, close_mongo_connection
from .api.routes import router as activity_router
from .api.auth_routes import router as auth_router
from .api.profile_routes import router as profile_router
from .api.team_routes import router as team_router

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan events."""
    # Startup
    logger.info("Starting Lumie API...")
    await connect_to_mongo()
    logger.info("Connected to MongoDB")
    yield
    # Shutdown
    logger.info("Shutting down Lumie API...")
    await close_mongo_connection()
    logger.info("Disconnected from MongoDB")


app = FastAPI(
    title="Lumie API",
    description="""
    Backend API for the Lumie App - Activity tracking for teens with chronic health conditions.

    ## Authentication
    - **Sign Up**: Create a new account with email/password
    - **Log In**: Authenticate and get JWT token
    - **Account Type**: Select teen or parent account type

    ## User Profile
    - **Teen Profile**: Name, age, height, weight, optional ICD-10 code
    - **Parent Profile**: Name, optional physical attributes
    - **ICD-10 Lookup**: Search medical condition codes

    ## Activity Features
    - **Activity Tracking**: Track daily activity time and intensity
    - **Adaptive Goals**: Personalized activity goals based on sleep and recovery
    - **Manual Entry**: Log activities with fallback support
    - **Six-Minute Walk Test**: Functional fitness self-assessment
    - **Ring Integration**: Lumie Ring status and detected activities

    ## Target Users
    - Teens aged 13-21 with chronic health conditions
    - Parents of teens using Lumie

    ## Privacy & Safety (Teen-First Design)
    - No calorie burn tracking
    - No MET values or performance ranking
    - All comparisons are self-referenced only
    - Teen-safe intensity categories (Low, Moderate, High)
    - ICD-10 codes never displayed publicly
    - No social comparison or leaderboards
    """,
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
    lifespan=lifespan,
)

# CORS configuration for Flutter app
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include API routes
app.include_router(auth_router, prefix="/api/v1")
app.include_router(profile_router, prefix="/api/v1")
app.include_router(activity_router, prefix="/api/v1", tags=["activity"])
app.include_router(team_router, prefix="/api/v1")


@app.get("/")
async def root():
    """Root endpoint with API information."""
    return {
        "name": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "description": "Activity tracking for teens with chronic health conditions",
        "docs": "/docs",
        "endpoints": {
            "auth": "/api/v1/auth",
            "profile": "/api/v1/profile",
            "activity": "/api/v1/activity",
            "teams": "/api/v1/teams",
            "health": "/api/v1/health",
        }
    }


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {
        "status": "healthy",
        "service": settings.APP_NAME,
        "version": settings.APP_VERSION,
    }


@app.get("/invite/{token}")
async def invitation_page(token: str):
    """Serve the web invitation page."""
    static_dir = Path(__file__).parent / "static"
    invite_html = static_dir / "invite.html"

    if not invite_html.exists():
        return {"error": "Invitation page not found"}

    return FileResponse(invite_html)


@app.get("/verify")
async def verification_page():
    """Serve the email verification page."""
    static_dir = Path(__file__).parent / "static"
    verify_html = static_dir / "verify.html"

    if not verify_html.exists():
        return {"error": "Verification page not found"}

    return FileResponse(verify_html)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
