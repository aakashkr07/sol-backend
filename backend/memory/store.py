# =============================================================================
# memory/store.py — SQLite Database Interface (Structured Memory)
# =============================================================================
#
# PURPOSE:
#   All read/write operations to the SQLite database.
#   This is the "hard facts" memory layer — things Nova should ALWAYS know.
#   Distinct from ChromaDB (which handles fuzzy episodic memories).
#
# THIS FILE HANDLES:
#   - Database initialization (creating tables from schema.sql)
#   - Creating and updating users
#   - Storing and retrieving user facts (name, job, preferences, etc.)
#   - Storing messages to conversation history
#   - Fetching recent conversation turns for the prompt window
#   - Creating conversation sessions
#
# THREADING NOTE:
#   SQLite has a per-thread connection limit. We use check_same_thread=False
#   because FastAPI runs async. For production at scale, switch to PostgreSQL.
#   For MVP with <1000 users, SQLite is perfect.
#
# USAGE:
#   from memory.store import db
#   await db.save_message(user_id, conversation_id, "user", "hello")
#   facts = await db.get_user_facts(user_id)
# =============================================================================

import sqlite3
import uuid
import json
import logging
from pathlib import Path
from datetime import datetime
from typing import Optional

from config import settings

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Database Connection Manager
# ---------------------------------------------------------------------------

class Database:
    """
    Manages the SQLite connection and all CRUD operations.
    Uses a single persistent connection (fine for SQLite).
    """

    def __init__(self):
        self._conn: Optional[sqlite3.Connection] = None

    def connect(self):
        """
        Opens the SQLite connection and initializes schema.
        Call once at startup from main.py lifespan.
        """
        # Ensure the db directory exists
        db_path = Path(settings.SQLITE_DB_PATH)
        db_path.parent.mkdir(parents=True, exist_ok=True)

        self._conn = sqlite3.connect(
            str(db_path),
            check_same_thread=False,   # FastAPI is async/multi-threaded
            isolation_level=None,      # Autocommit mode (simpler for MVP)
        )

        # Enable WAL mode: better performance for concurrent reads/writes
        self._conn.execute("PRAGMA journal_mode=WAL;")
        # Enforce foreign key constraints
        self._conn.execute("PRAGMA foreign_keys=ON;")
        # Return rows as dict-like objects
        self._conn.row_factory = sqlite3.Row

        self._init_schema()
        logger.info(f"SQLite database connected at {db_path}")

    def _init_schema(self):
        """Runs schema.sql to create tables if they don't exist."""
        schema_path = Path(__file__).parent.parent / "db" / "schema.sql"
        with open(schema_path, "r") as f:
            schema_sql = f.read()
        self._conn.executescript(schema_sql)
        logger.info("Database schema initialized")

    def close(self):
        """Close the connection gracefully at shutdown."""
        if self._conn:
            self._conn.close()
            logger.info("SQLite connection closed")

    @property
    def conn(self) -> sqlite3.Connection:
        if not self._conn:
            raise RuntimeError("Database not connected. Call db.connect() at startup.")
        return self._conn


    # ── User Operations ────────────────────────────────────────────────────

    def get_or_create_user(self, user_id: str, character_id: str = "nova") -> dict:
        """
        Retrieves a user by ID, or creates them if they don't exist.
        This is called at the start of every session.

        Returns a dict with all user fields.
        """
        row = self.conn.execute(
            "SELECT * FROM users WHERE id = ?", (user_id,)
        ).fetchone()

        if row:
            # Update last_seen timestamp
            self.conn.execute(
                "UPDATE users SET last_seen = ? WHERE id = ?",
                (datetime.utcnow().isoformat(), user_id)
            )
            return dict(row)

        # Create new user
        self.conn.execute(
            """INSERT INTO users (id, character_id, created_at, last_seen)
               VALUES (?, ?, ?, ?)""",
            (user_id, character_id, datetime.utcnow().isoformat(), datetime.utcnow().isoformat())
        )
        logger.info(f"New user created: {user_id}")
        return {"id": user_id, "character_id": character_id, "name": None,
                "total_sessions": 0, "total_messages": 0}

    def update_user_name(self, user_id: str, name: str, preferred_name: str = None):
        """Stores the user's name after it's learned (onboarding or extraction)."""
        self.conn.execute(
            """UPDATE users SET name = ?, preferred_name = ?
               WHERE id = ?""",
            (name, preferred_name or name, user_id)
        )

    def get_user(self, user_id: str) -> Optional[dict]:
        """Returns full user row or None."""
        row = self.conn.execute(
            "SELECT * FROM users WHERE id = ?", (user_id,)
        ).fetchone()
        return dict(row) if row else None

    def increment_user_stats(self, user_id: str, messages: int = 1, sessions: int = 0):
        """Bumps message and session counters. Called after each message."""
        self.conn.execute(
            """UPDATE users
               SET total_messages = total_messages + ?,
                   total_sessions = total_sessions + ?
               WHERE id = ?""",
            (messages, sessions, user_id)
        )


    # ── User Facts Operations ──────────────────────────────────────────────

    def save_user_fact(
        self,
        user_id: str,
        category: str,
        key: str,
        value: str,
        confidence: float = 1.0,
        source: str = "extracted"
    ):
        """
        Inserts or updates a user fact.
        Uses UPSERT (INSERT OR REPLACE) on the unique(user_id, key) constraint.

        Example:
            db.save_user_fact("u123", "personal", "job", "product designer")
        """
        now = datetime.utcnow().isoformat()
        self.conn.execute(
            """INSERT INTO user_facts (user_id, category, key, value, confidence, source, created_at, updated_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)
               ON CONFLICT(user_id, key) DO UPDATE SET
                   value = excluded.value,
                   confidence = excluded.confidence,
                   updated_at = excluded.updated_at""",
            (user_id, category, key, value, confidence, source, now, now)
        )
        logger.debug(f"Saved fact for {user_id}: {key} = {value}")

    def get_user_facts(self, user_id: str) -> dict:
        """
        Returns all user facts as a flat key→value dict.
        This is injected into every prompt via context_builder.py.

        Returns:
            e.g. {"job": "designer", "favorite_music": "lo-fi", "sister_name": "Priya"}
        """
        rows = self.conn.execute(
            "SELECT key, value FROM user_facts WHERE user_id = ? ORDER BY updated_at DESC",
            (user_id,)
        ).fetchall()
        return {row["key"]: row["value"] for row in rows}

    def get_user_facts_by_category(self, user_id: str, category: str) -> dict:
        """Returns facts filtered by category (e.g. 'relationships', 'struggles')."""
        rows = self.conn.execute(
            "SELECT key, value FROM user_facts WHERE user_id = ? AND category = ?",
            (user_id, category)
        ).fetchall()
        return {row["key"]: row["value"] for row in rows}


    # ── Conversation / Session Operations ─────────────────────────────────

    def create_conversation(self, user_id: str, character_id: str = "nova") -> str:
        """
        Creates a new conversation session. Returns the conversation ID.
        Call this at the start of each new session (app open, new chat, etc.)
        """
        conv_id = str(uuid.uuid4())
        self.conn.execute(
            """INSERT INTO conversations (id, user_id, character_id, started_at)
               VALUES (?, ?, ?, ?)""",
            (conv_id, user_id, character_id, datetime.utcnow().isoformat())
        )
        self.increment_user_stats(user_id, sessions=1)
        return conv_id

    def get_current_conversation(self, user_id: str) -> Optional[str]:
        """
        Returns the most recent open conversation ID for the user.
        "Open" = no ended_at timestamp.
        """
        row = self.conn.execute(
            """SELECT id FROM conversations
               WHERE user_id = ? AND ended_at IS NULL
               ORDER BY started_at DESC LIMIT 1""",
            (user_id,)
        ).fetchone()
        return row["id"] if row else None

    def close_conversation(self, conversation_id: str):
        """Mark a conversation as ended (called when user leaves the app)."""
        self.conn.execute(
            "UPDATE conversations SET ended_at = ? WHERE id = ?",
            (datetime.utcnow().isoformat(), conversation_id)
        )

    def save_conversation_summary(self, conversation_id: str, summary: str):
        """Stores the AI-generated summary of a completed conversation."""
        self.conn.execute(
            "UPDATE conversations SET summary = ? WHERE id = ?",
            (summary, conversation_id)
        )


    # ── Message Operations ─────────────────────────────────────────────────

    def save_message(
        self,
        conversation_id: str,
        user_id: str,
        role: str,         # 'user' or 'assistant'
        content: str,
    ) -> int:
        """
        Persists a single message to the database.
        Returns the new message's row ID (used for memory extraction tracking).
        """
        cursor = self.conn.execute(
            """INSERT INTO messages (conversation_id, user_id, role, content, created_at)
               VALUES (?, ?, ?, ?, ?)""",
            (conversation_id, user_id, role, content, datetime.utcnow().isoformat())
        )
        # Update message count on the conversation
        self.conn.execute(
            "UPDATE conversations SET message_count = message_count + 1 WHERE id = ?",
            (conversation_id,)
        )
        self.increment_user_stats(user_id, messages=1)
        return cursor.lastrowid

    def get_recent_messages(self, user_id: str, limit: int = None) -> list[dict]:
        """
        Returns the most recent N messages for a user, ordered oldest→newest.
        This is the "short-term memory" injected into every prompt.

        The limit defaults to settings.RECENT_HISTORY_TURNS.
        """
        n = limit or settings.RECENT_HISTORY_TURNS
        rows = self.conn.execute(
            """SELECT role, content, created_at FROM messages
               WHERE user_id = ?
               ORDER BY created_at DESC
               LIMIT ?""",
            (user_id, n)
        ).fetchall()

        # Reverse so oldest→newest (correct LLM message order)
        return [dict(r) for r in reversed(rows)]

    def get_unextracted_messages(self, user_id: str) -> list[dict]:
        """
        Returns messages that haven't had memory extraction run on them yet.
        Used by memory/extractor.py to know what to process.
        """
        rows = self.conn.execute(
            """SELECT id, role, content FROM messages
               WHERE user_id = ? AND memory_extracted = 0
               ORDER BY created_at ASC""",
            (user_id,)
        ).fetchall()
        return [dict(r) for r in rows]

    def mark_messages_extracted(self, message_ids: list[int]):
        """Mark a list of messages as having had memory extraction run."""
        if not message_ids:
            return
        placeholders = ",".join("?" * len(message_ids))
        self.conn.execute(
            f"UPDATE messages SET memory_extracted = 1 WHERE id IN ({placeholders})",
            message_ids
        )


    # ── Memory Index Operations ────────────────────────────────────────────

    def log_memory(
        self,
        memory_id: str,
        user_id: str,
        content: str,
        emotion_tag: Optional[str] = None,
        importance: float = 0.5,
        conversation_id: Optional[str] = None,
        source_message_ids: Optional[list] = None,
    ):
        """
        Records a memory in the SQLite index.
        The actual vector embedding lives in ChromaDB.
        This is the structured metadata for that memory.
        """
        self.conn.execute(
            """INSERT OR IGNORE INTO memories
               (id, user_id, content, emotion_tag, importance, conversation_id,
                source_message_ids, created_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                memory_id, user_id, content, emotion_tag, importance,
                conversation_id,
                json.dumps(source_message_ids or []),
                datetime.utcnow().isoformat()
            )
        )

    def get_total_sessions(self, user_id: str) -> int:
        """Returns how many sessions this user has had (for relationship phase)."""
        row = self.conn.execute(
            "SELECT total_sessions FROM users WHERE id = ?", (user_id,)
        ).fetchone()
        return row["total_sessions"] if row else 1


# ---------------------------------------------------------------------------
# Singleton — import this everywhere
# ---------------------------------------------------------------------------
db = Database()