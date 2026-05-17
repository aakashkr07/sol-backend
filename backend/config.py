# =============================================================================
# config.py — Central Configuration for Companion AI Backend
# =============================================================================
#
# PURPOSE:
#   Single source of truth for ALL configuration values used across the backend.
#   Reads from a .env file (never hardcoded), with sensible defaults.
#   Every other file imports from here — never reads env vars directly.
#
# HOW IT WORKS:
#   - python-dotenv loads your .env file at startup
#   - pydantic Settings validates types and raises clear errors if something's missing
#   - One `settings` object is imported app-wide (singleton pattern)
#
# WHY THIS MATTERS:
#   If you ever change an API key, model name, or path — you change it in ONE place.
#   No hunting through files. No broken configs.
#
# USAGE:
#   from config import settings
#   print(settings.GROQ_API_KEY)
# =============================================================================

import os
from pathlib import Path
from dotenv import load_dotenv

# ---------------------------------------------------------------------------
# Load .env from the project root (one level above /backend)
# ---------------------------------------------------------------------------
ROOT_DIR = Path(__file__).parent.parent          # companion-ai/
BACKEND_DIR = Path(__file__).parent              # companion-ai/backend/

load_dotenv(ROOT_DIR / ".env")                   # silently ignored if .env missing


# ---------------------------------------------------------------------------
# Settings — grouped by concern
# ---------------------------------------------------------------------------

class Settings:
    """
    All runtime config in one place.
    Add new keys here, then reference them via settings.KEY_NAME.
    """

    # ── Groq / LLM ────────────────────────────────────────────────────────
    GROQ_API_KEY: str = os.getenv("GROQ_API_KEY", "")
    GROQ_BASE_URL: str = "https://api.groq.com/openai/v1"

    # Primary model: Llama 3.1 70B — best quality on Groq free tier
    # Fallback: llama3-8b-8192 if you hit rate limits (faster, cheaper)
    LLM_MODEL: str = os.getenv("LLM_MODEL", "llama-3.3-70b-versatile")
    LLM_FALLBACK_MODEL: str = "llama-3.1-8b-instant"

    # Controls response creativity. 0.7–0.85 = natural, human-feeling.
    # Too high (>0.95) = incoherent. Too low (<0.5) = robotic.
    LLM_TEMPERATURE: float = float(os.getenv("LLM_TEMPERATURE", "0.82"))

    # Max tokens the AI can generate per reply. ~300 = 2–4 sentences (texting feel).
    # Don't go over 600 for chat — walls of text break immersion.
    LLM_MAX_TOKENS: int = int(os.getenv("LLM_MAX_TOKENS", "300"))

    # ── Memory / ChromaDB ─────────────────────────────────────────────────
    # ChromaDB stores vector embeddings of every memory.
    # This path is where it persists on disk. Added to .gitignore.
    CHROMA_DB_PATH: str = str(BACKEND_DIR / "chroma_db")

    # How many memories to retrieve per message (semantic similarity search).
    # 5–8 is sweet spot: enough context, not too much noise.
    MEMORY_RETRIEVAL_COUNT: int = int(os.getenv("MEMORY_RETRIEVAL_COUNT", "6"))

    # Minimum similarity score (0–1) to include a memory in context.
    # 0.35 = fairly permissive. Raise to 0.5 if memories feel off-topic.
    MEMORY_SIMILARITY_THRESHOLD: float = float(os.getenv("MEMORY_SIMILARITY_THRESHOLD", "0.35"))

    # How many recent conversation turns to keep in the prompt window.
    # More = more context, but burns tokens fast. 10 = ~5 back-and-forths.
    RECENT_HISTORY_TURNS: int = int(os.getenv("RECENT_HISTORY_TURNS", "10"))

    # ── SQLite (structured user facts) ────────────────────────────────────
    # SQLite stores hard facts: name, age, preferences — things that should
    # ALWAYS be remembered, not retrieved by similarity.
    SQLITE_DB_PATH: str = str(BACKEND_DIR / "db" / "companion.db")

    # ── Personality ────────────────────────────────────────────────────────
    # Path to the folder containing character JSON files (nova.json, etc.)
    CHARACTERS_DIR: str = str(BACKEND_DIR / "personality" / "characters")

    # Default character loaded at startup
    DEFAULT_CHARACTER: str = os.getenv("DEFAULT_CHARACTER", "nova")

    # ── App / API ──────────────────────────────────────────────────────────
    APP_HOST: str = os.getenv("APP_HOST", "0.0.0.0")
    APP_PORT: int = int(os.getenv("APP_PORT", "8000"))
    DEBUG: bool = os.getenv("DEBUG", "true").lower() == "true"

    # Secret key for signing tokens (future auth). Generate with: openssl rand -hex 32
    SECRET_KEY: str = os.getenv("SECRET_KEY", "changeme-generate-a-real-secret-before-launch")

    # ── Memory extraction ──────────────────────────────────────────────────
    # How many conversation turns to batch before running memory extraction.
    # 1 = extract after every message (accurate but slow). 3 = good balance.
    MEMORY_EXTRACTION_EVERY_N_TURNS: int = int(os.getenv("MEMORY_EXTRACTION_EVERY_N_TURNS", "1"))

    # ── Proactive messaging (future feature) ──────────────────────────────
    # Whether Nova can initiate messages. Disabled for MVP, enable post-launch.
    PROACTIVE_MESSAGES_ENABLED: bool = os.getenv("PROACTIVE_MESSAGES_ENABLED", "false").lower() == "true"

    def validate(self):
        """
        Call at startup to catch missing critical config early.
        Better to crash with a clear error than fail silently mid-conversation.
        """
        if not self.GROQ_API_KEY:
            raise ValueError(
                "GROQ_API_KEY is missing. Add it to your .env file.\n"
                "Get one free at: https://console.groq.com"
            )
        return self


# ---------------------------------------------------------------------------
# Singleton — import this everywhere
# ---------------------------------------------------------------------------
settings = Settings()