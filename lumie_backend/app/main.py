"""Lumie API - FastAPI application."""
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pathlib import Path

from .core.config import settings
from .core.database import connect_to_mongo, close_mongo_connection
from .api.routes import router as activity_router
from .api.auth_routes import router as auth_router
from .api.profile_routes import router as profile_router
from .api.team_routes import router as team_router
from .api.rest_days_routes import router as rest_days_router
from .api.advisor_routes import router as advisor_router
from .api.task_routes import router as task_router
from .api.admin_task_routes import router as admin_task_router
from .api.analysis_routes import router as analysis_router
from .api.dayprint_routes import router as dayprint_router
from .api.checkin_routes import router as checkin_router
from .api.chat_history_routes import router as chat_history_router
from .api.sleep_routes import router as sleep_router
from .api.advisor_v2_routes import router as advisor_v2_router
from .api.proactive_routes import router as proactive_router
from .api.steps_routes import router as steps_router
from .api.hrv_routes import router as hrv_router
from .api.temperature_routes import router as temperature_router
from .api.spo2_routes import router as spo2_router
from .api.ring_command_routes import router as ring_command_router

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
    # Ensure indexes for chat history
    from .services.chat_history_service import ensure_indexes
    await ensure_indexes()
    # Seed capabilities and scan skills
    from .services.capability_service import seed_system_capabilities
    from .services.skill_registry_service import skill_registry
    await seed_system_capabilities()
    skill_registry.scan_and_index()
    logger.info("Advisor v2 system initialized (capabilities seeded, skills indexed)")
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

# Serve uploaded task media files
uploads_dir = Path(__file__).resolve().parent.parent / "uploads"
uploads_dir.mkdir(parents=True, exist_ok=True)
app.mount("/uploads", StaticFiles(directory=uploads_dir), name="uploads")
# Mirror under /api/v1/uploads for environments that proxy only /api/v1.
app.mount("/api/v1/uploads", StaticFiles(directory=uploads_dir), name="uploads_api_v1")

# Include API routes
app.include_router(auth_router, prefix="/api/v1")
app.include_router(profile_router, prefix="/api/v1")
app.include_router(activity_router, prefix="/api/v1", tags=["activity"])
app.include_router(team_router, prefix="/api/v1")
app.include_router(rest_days_router, prefix="/api/v1")
app.include_router(advisor_router, prefix="/api/v1")
app.include_router(task_router, prefix="/api/v1")
app.include_router(admin_task_router, prefix="/api/v1")
app.include_router(analysis_router, prefix="/api/v1")
app.include_router(dayprint_router, prefix="/api/v1")
app.include_router(checkin_router, prefix="/api/v1")
app.include_router(chat_history_router, prefix="/api/v1")
app.include_router(sleep_router, prefix="/api/v1")
app.include_router(advisor_v2_router, prefix="/api/v2")
app.include_router(proactive_router, prefix="/api/v1")
app.include_router(steps_router, prefix="/api/v1")
app.include_router(hrv_router, prefix="/api/v1")
app.include_router(temperature_router, prefix="/api/v1")
app.include_router(spo2_router, prefix="/api/v1")
app.include_router(ring_command_router, prefix="/api/v1")


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
            "rest-days": "/api/v1/rest-days",
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
