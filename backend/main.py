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
import time
import uuid
from contextlib import asynccontextmanager

from fastapi import FastAPI, Query, Request
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

    # 7. Start the Proactive Dispatch Worker loop in the background
    worker_task = None
    if settings.PROACTIVE_MESSAGES_ENABLED:
        import asyncio
        from core.proactive_engine import maybe_generate_for_user

        async def run_worker_loop():
            logger.info("Starting Sol Proactive Dispatch Worker...")
            while True:
                try:
                    # Get list of all registered users in the database
                    users = db.conn.execute("SELECT id FROM users").fetchall()
                    for user in users:
                        user_id = user["id"]
                        # Scan pairs, evaluate quiet hours/inactivity, and generate proactive messages
                        events = await maybe_generate_for_user(user_id, limit=1)
                        if events:
                            logger.info("Successfully generated and dispatched %d proactive notification events for user %s", len(events), user_id)
                    # Poll every 10 minutes (600 seconds)
                    await asyncio.sleep(600)
                except asyncio.CancelledError:
                    logger.info("Proactive worker loop cancelled")
                    break
                except Exception as exc:
                    logger.error("Error in proactive worker loop: %s", exc, exc_info=True)
                    await asyncio.sleep(60)

        worker_task = asyncio.create_task(run_worker_loop())
        logger.info("Proactive dispatch background worker task successfully spawned")

    logger.info("=" * 60)
    logger.info(f"Server ready at http://{settings.APP_HOST}:{settings.APP_PORT}")
    logger.info("=" * 60)

    yield   # Application runs here

    # ── SHUTDOWN ───────────────────────────────────────────────────────────
    logger.info("Shutting down gracefully...")
    
    if worker_task:
        logger.info("Cancelling proactive dispatch background worker...")
        worker_task.cancel()
        try:
            await worker_task
        except asyncio.CancelledError:
            pass
        logger.info("Proactive dispatch background worker stopped")

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
app.state.metrics = {
    "requests_total": 0,
    "requests_failed": 0,
    "last_request_id": None,
}


# ---------------------------------------------------------------------------
# CORS Middleware
# ---------------------------------------------------------------------------
# Required so the Flutter web version (and local development) can call the API.
# For production: replace "*" with your actual domain(s).

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------------------------------------------------------------------------
# Mount Routers
# ---------------------------------------------------------------------------

from api.chat import router as chat_router
from api.ops import router as ops_router
from api.profile import router as profile_router
from api.proactive import router as proactive_router
from api.onboarding import router as onboarding_router

app.include_router(chat_router, prefix="/api", tags=["chat"])
app.include_router(onboarding_router, prefix="/api", tags=["onboarding"])
app.include_router(profile_router, prefix="/api", tags=["profile"])
app.include_router(proactive_router, prefix="/api", tags=["proactive"])
app.include_router(ops_router, prefix="/api", tags=["ops"])


@app.middleware("http")
async def request_metrics_middleware(request: Request, call_next):
    request_id = request.headers.get("x-request-id") or str(uuid.uuid4())
    started = time.perf_counter()
    app.state.metrics["requests_total"] += 1
    app.state.metrics["last_request_id"] = request_id

    try:
        response = await call_next(request)
    except Exception:
        app.state.metrics["requests_failed"] += 1
        raise

    duration_ms = round((time.perf_counter() - started) * 1000, 2)
    if response.status_code >= 500:
        app.state.metrics["requests_failed"] += 1
    response.headers["x-request-id"] = request_id
    response.headers["x-response-time-ms"] = str(duration_ms)
    logger.info("%s %s -> %s in %sms", request.method, request.url.path, response.status_code, duration_ms)
    return response


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
async def health_check(deep: bool = Query(default=False)):
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

    # Check LLM configuration. Railway should not depend on an external Groq
    # round-trip just to consider the service alive.
    health["subsystems"]["groq"] = "configured" if settings.GROQ_API_KEY else "missing_api_key"
    health["model"] = settings.LLM_MODEL

    if deep:
        try:
            from core.llm import check_llm_health
            llm_health = await check_llm_health()
            health["subsystems"]["groq_deep"] = llm_health["status"]
            health["deep_model"] = llm_health.get("model")
            if llm_health["status"] != "ok":
                health["status"] = "degraded"
        except Exception as e:
            health["subsystems"]["groq_deep"] = f"error: {e}"
            health["status"] = "degraded"

    return health


@app.get("/metrics", tags=["health"])
async def metrics_snapshot():
    return {
        "requests": app.state.metrics,
        "debug": settings.DEBUG,
        "allowed_origins": settings.CORS_ALLOWED_ORIGINS,
    }


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
