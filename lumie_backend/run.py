#!/usr/bin/env python3
"""Run the Lumie Activity API server (LOCAL DEVELOPMENT ONLY).

⚠️  THIS IS FOR LOCAL DEVELOPMENT
This script runs the API with auto-reload on localhost:8000.

FOR PRODUCTION DEPLOYMENT:
- Do NOT use this script on the production server
- The production API is managed by systemctl (lumie-api service)
- See lumie_backend/deploy.sh for deployment steps
- The API runs via systemd service file (managed by systemctl)
- Production URL: https://yumo.org/api/v1/
"""
import uvicorn

if __name__ == "__main__":
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="info",
    )
