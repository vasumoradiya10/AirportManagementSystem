"""
Airport Management System - FastAPI Application Entrypoint.
Serves REST API endpoints and mounts the Frontend web interface.
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from datetime import datetime
from pathlib import Path
from . import db, config
from .routes import flights, gates, bookings, baggage, analytics

app = FastAPI(
    title="Airport Management System (AMS) API",
    description="Full-featured Airport & Aviation Management REST API powered by PostgreSQL & Advanced SQL",
    version="1.0.0"
)

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Register API Routers
app.include_router(flights.router)
app.include_router(gates.router)
app.include_router(bookings.router)
app.include_router(baggage.router)
app.include_router(analytics.router)


@app.get("/api/health", tags=["Health"])
def health_check():
    """System health check and database connectivity diagnostics."""
    is_db_up = db.check_connection()
    return {
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "database": {
            "engine": "PostgreSQL",
            "host": config.DB_HOST,
            "port": config.DB_PORT,
            "database_name": config.DB_NAME,
            "connected": is_db_up,
            "mode": "Live PostgreSQL" if is_db_up else "Operational Demo Mode (Credentials pending)"
        }
    }


# Mount Frontend Static Assets
frontend_path = Path(config.FRONTEND_DIR)
if frontend_path.exists():
    app.mount("/static", StaticFiles(directory=str(frontend_path)), name="static")

    @app.get("/", tags=["Frontend"])
    def serve_frontend_root():
        index_file = frontend_path / "index.html"
        if index_file.exists():
            return FileResponse(str(index_file))
        return {"message": "AMS API is running. Place index.html inside frontend/"}
