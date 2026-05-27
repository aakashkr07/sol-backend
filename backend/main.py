# =============================================================================
# main.py — FastAPI Application Entry Point
# =============================================================================
#
# PURPOSE:
#   The root of the backend application.
#   Handles: startup/shutdown, CORS configuration, route mounting, health checks.
#
# HOW TO RUN:
#   From the /backend directory:
#     uvicorn main:app --reload --host 0.0.0.0 --port 8000
#
#   Or via the helper script (root level):
#     python -m uvicorn main:app --reload
#
# STARTUP SEQUENCE:
#   1. Validate config (crash early if GROQ_API_KEY missing)
#   2. Connect SQLite database + initialize schema
#   3. Initialize ChromaDB client
#   4. Mount API routes
#   → Server ready to accept requests
#
# CORS:
#   Currently open (allow all origins) for development.
#   Before launch: restrict to your production domain.
#
# LIFESPAN:
#   FastAPI 0.95+ uses lifespan context managers instead of @app.on_event.
#   The lifespan function runs startup code before yield, shutdown code after.
# =============================================================================

import logging
import sys
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from auth.firebase import initialize_firebase_auth
from config import settings

# ---------------------------------------------------------------------------
# Logging configuration
# ---------------------------------------------------------------------------
# Set up before anything else so all module-level loggers work from the start.

logging.basicConfig(
    level=logging.DEBUG if settings.DEBUG else logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
    datefmt="%H:%M:%S",
    handlers=[
        logging.StreamHandler(sys.stdout),   # Console output
        # Add FileHandler here if you want log files:
        # logging.FileHandler("companion.log"),
    ]
)

logger = logging.getLogger("main")


# ---------------------------------------------------------------------------
# Application lifespan (startup + shutdown)
# ---------------------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Everything in the 'before yield' block runs at startup.
    Everything in the 'after yield' block runs at shutdown.

    Using lifespan instead of @app.on_event because:
    - It's the modern FastAPI pattern (0.95+)
    - It's cleaner and handles async properly
    - It runs exactly once, not per-request
    """

    # ── STARTUP ────────────────────────────────────────────────────────────
    logger.info("=" * 60)
    logger.info("Sol backend starting up")
    logger.info("=" * 60)

    # 1. Validate critical configuration
    try:
        settings.validate()
        logger.info(f"Config valid. Model: {settings.LLM_MODEL}")
    except ValueError as e:
        logger.critical(f"Config validation failed: {e}")
        sys.exit(1)

    # 2. Initialize SQLite database
    from memory.store import db
    try:
        db.connect()
        logger.info("SQLite database ready")
    except Exception as e:
        logger.critical(f"Database initialization failed: {e}")
        sys.exit(1)

    # 3. Initialize ChromaDB (creates client, doesn't load all data)
    from memory.retriever import get_chroma_client
    try:
        get_chroma_client()
        logger.info(f"ChromaDB ready at {settings.CHROMA_DB_PATH}")
    except Exception as e:
        # ChromaDB failure is non-fatal at startup — app can run without memories
        # (though memory features won't work until it's fixed)
        logger.error(f"ChromaDB initialization failed: {e}. Memory features disabled.")

    # 4. Load default character (validates the JSON is parseable)
    from personality.loader import load_character
    from personality.registry import sync_companion_registry
    try:
        char = load_character(settings.DEFAULT_CHARACTER)
        logger.info(f"Default character loaded: {char.name}")
    except Exception as e:
        logger.critical(f"Failed to load default character: {e}")
        sys.exit(1)

    # 5. Initialize Firebase token verification
    try:
        initialize_firebase_auth()
        logger.info("Firebase auth verification ready")
    except Exception as e:
        logger.critical(f"Failed to initialize Firebase auth: {e}")
        sys.exit(1)

    # 6. Sync companion registry from personality assets
    try:
        sync_companion_registry()
        logger.info("Companion registry synced")
    except Exception as e:
        logger.critical(f"Failed to sync companion registry: {e}")
        sys.exit(1)

    logger.info("=" * 60)
    logger.info(f"Server ready at http://{settings.APP_HOST}:{settings.APP_PORT}")
    logger.info("=" * 60)

    yield   # Application runs here

    # ── SHUTDOWN ───────────────────────────────────────────────────────────
    logger.info("Shutting down gracefully...")
    db.close()
    logger.info("Database connections closed. Goodbye.")


# ---------------------------------------------------------------------------
# FastAPI Application
# ---------------------------------------------------------------------------

app = FastAPI(
    title="Sol API",
    description="Backend for Sol's companion relationship system.",
    version="0.1.0",
    docs_url="/docs" if settings.DEBUG else None,    # Hide Swagger in production
    redoc_url="/redoc" if settings.DEBUG else None,
    lifespan=lifespan,
)


# ---------------------------------------------------------------------------
# CORS Middleware
# ---------------------------------------------------------------------------
# Required so the Flutter web version (and local development) can call the API.
# For production: replace "*" with your actual domain(s).

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],           # TODO: Restrict before launch
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------------------------------------------------------------------------
# Mount Routers
# ---------------------------------------------------------------------------

from api.chat import router as chat_router

app.include_router(chat_router, prefix="/api", tags=["chat"])


# ---------------------------------------------------------------------------
# Health Check Endpoints
# ---------------------------------------------------------------------------

@app.get("/", tags=["health"])
async def root():
    """Root endpoint — quick check that the server is alive."""
    return {
        "status": "alive",
        "app": "Sol",
        "version": "0.1.0",
        "character": settings.DEFAULT_CHARACTER,
    }


@app.get("/health", tags=["health"])
async def health_check():
    """
    Detailed health check — used by monitoring, Flutter app on startup.
    Returns status of each subsystem.
    """
    from memory.store import db as database
    from memory.retriever import get_memory_count

    health = {
        "status": "ok",
        "subsystems": {}
    }

    # Check SQLite
    try:
        database.conn.execute("SELECT 1").fetchone()
        health["subsystems"]["sqlite"] = "ok"
    except Exception as e:
        health["subsystems"]["sqlite"] = f"error: {e}"
        health["status"] = "degraded"

    # Check ChromaDB
    try:
        from memory.retriever import get_chroma_client
        get_chroma_client()
        health["subsystems"]["chromadb"] = "ok"
    except Exception as e:
        health["subsystems"]["chromadb"] = f"error: {e}"
        health["status"] = "degraded"

    # Check Groq (quick ping)
    try:
        from core.llm import check_llm_health
        llm_health = await check_llm_health()
        health["subsystems"]["groq"] = llm_health["status"]
        health["model"] = llm_health.get("model")
    except Exception as e:
        health["subsystems"]["groq"] = f"error: {e}"
        health["status"] = "degraded"

    return health


# ---------------------------------------------------------------------------
# Run directly (for development without uvicorn CLI)
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host=settings.APP_HOST,
        port=settings.APP_PORT,
        reload=settings.DEBUG,
        log_level="debug" if settings.DEBUG else "info",
    )
