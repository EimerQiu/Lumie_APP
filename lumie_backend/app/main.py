"""Lumie Activity API - FastAPI application."""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .api.routes import router

app = FastAPI(
    title="Lumie Activity API",
    description="""
    Backend API for the Lumie Activity feature.

    ## Features
    - **Activity Tracking**: Track daily activity time and intensity
    - **Adaptive Goals**: Personalized activity goals based on sleep and recovery
    - **Manual Entry**: Log activities with fallback support
    - **Six-Minute Walk Test**: Functional fitness self-assessment
    - **Ring Integration**: Lumie Ring status and detected activities

    ## Target Users
    - Teens aged 13-21 with chronic health conditions
    - Users wearing a Lumie Ring

    ## Privacy & Safety
    - No calorie burn tracking
    - No MET values or performance ranking
    - All comparisons are self-referenced only
    - Teen-safe intensity categories (Low, Moderate, High)
    """,
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

# CORS configuration for Flutter app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify actual origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include API routes
app.include_router(router, prefix="/api/v1", tags=["activity"])


@app.get("/")
async def root():
    """Root endpoint with API information."""
    return {
        "name": "Lumie Activity API",
        "version": "1.0.0",
        "description": "Activity tracking for teens with chronic health conditions",
        "docs": "/docs",
        "health": "/api/v1/health",
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
