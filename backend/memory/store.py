import json
import logging
import sqlite3
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any, Optional

from config import settings

logger = logging.getLogger(__name__)


def _utcnow_iso() -> str:
    return datetime.utcnow().isoformat(timespec="seconds")


def _day_of_week(dt: datetime) -> int:
    return dt.weekday()


class Database:
    def __init__(self):
        self._conn: Optional[sqlite3.Connection] = None

    def connect(self):
        db_path = Path(settings.SQLITE_DB_PATH)
        db_path.parent.mkdir(parents=True, exist_ok=True)

        self._conn = sqlite3.connect(
            str(db_path),
            check_same_thread=False,
            isolation_level=None,
        )
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA journal_mode=WAL;")
        self._conn.execute("PRAGMA foreign_keys=ON;")

        self._init_schema()
        logger.info("SQLite database connected at %s", db_path)

    def close(self):
        if self._conn:
            self._conn.close()
            logger.info("SQLite connection closed")

    @property
    def conn(self) -> sqlite3.Connection:
        if not self._conn:
            raise RuntimeError("Database not connected. Call db.connect() first.")
        return self._conn

    def _init_schema(self):
        self._prepare_legacy_tables_for_schema()

        schema_path = Path(__file__).parent.parent / "db" / "schema.sql"
        with open(schema_path, "r", encoding="utf-8") as handle:
            self.conn.executescript(handle.read())

        self._ensure_columns()
        self._migrate_legacy_data()
        logger.info("Database schema initialized")

    def _prepare_legacy_tables_for_schema(self):
        if self._table_exists("user_facts"):
            columns = self._get_table_columns("user_facts")
            if "fact_key" not in columns and "key" in columns:
                if not self._table_exists("user_facts_legacy"):
                    self.conn.execute("ALTER TABLE user_facts RENAME TO user_facts_legacy")
                    logger.info("Renamed legacy user_facts table for migration")

    def _migrate_legacy_data(self):
        if self._table_exists("user_facts_legacy"):
            rows = self.conn.execute(
                """
                SELECT user_id, category, key, value, confidence, source, created_at, updated_at
                FROM user_facts_legacy
                """
            ).fetchall()

            for row in rows:
                existing = self.conn.execute(
                    """
                    SELECT id, fact_value
                    FROM user_facts
                    WHERE user_id = ? AND fact_key = ? AND is_outdated = 0
                    LIMIT 1
                    """,
                    (row["user_id"], row["key"]),
                ).fetchone()

                if existing and existing["fact_value"] == row["value"]:
                    self.conn.execute(
                        """
                        UPDATE user_facts
                        SET confidence = CASE
                                WHEN ? > confidence THEN ?
                                ELSE confidence
                            END,
                            updated_at = ?
                        WHERE id = ?
                        """,
                        (
                            float(row["confidence"] or 0.8),
                            float(row["confidence"] or 0.8),
                            row["updated_at"] or _utcnow_iso(),
                            existing["id"],
                        ),
                    )
                    continue

                if existing:
                    self.conn.execute(
                        "UPDATE user_facts SET is_outdated = 1, updated_at = ? WHERE id = ?",
                        (row["updated_at"] or _utcnow_iso(), existing["id"]),
                    )

                self.conn.execute(
                    """
                    INSERT INTO user_facts
                        (user_id, category, fact_key, fact_value, confidence, source_type, created_at, updated_at, is_outdated)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)
                    """,
                    (
                        row["user_id"],
                        row["category"],
                        row["key"],
                        row["value"],
                        float(row["confidence"] or 0.8),
                        row["source"] or "legacy_migration",
                        row["created_at"] or _utcnow_iso(),
                        row["updated_at"] or _utcnow_iso(),
                    ),
                )

        if self._table_exists("memories"):
            rows = self.conn.execute(
                """
                SELECT id, user_id, content, emotion_tag, importance, source_message_ids,
                       conversation_id, created_at, archived
                FROM memories
                """
            ).fetchall()

            for row in rows:
                self.conn.execute(
                    """
                    INSERT INTO memory_index
                        (user_id, chroma_id, title, content, emotion_tag, strength,
                         emotional_weight, created_at, source_message_ids, conversation_id, archived)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(user_id, chroma_id) DO NOTHING
                    """,
                    (
                        row["user_id"],
                        row["id"],
                        self._build_memory_title(row["content"]),
                        row["content"],
                        row["emotion_tag"],
                        float(row["importance"] or 0.5),
                        float(row["importance"] or 0.5),
                        row["created_at"] or _utcnow_iso(),
                        row["source_message_ids"] or "[]",
                        row["conversation_id"],
                        int(row["archived"] or 0),
                    ),
                )

    def _ensure_columns(self):
        required_columns = {
            "users": [
                "display_name TEXT",
                "email TEXT",
                "name TEXT",
                "preferred_name TEXT",
                "age INTEGER",
                "location TEXT",
                "timezone TEXT",
                "character_id TEXT DEFAULT 'nova'",
                "relationship_label TEXT DEFAULT 'friend'",
                "total_sessions INTEGER DEFAULT 0",
                "emotional_baseline REAL DEFAULT 0.5",
                "baseline_sample_size INTEGER DEFAULT 0",
                "current_narrative TEXT",
                "narrative_updated_at DATETIME",
            ],
            "conversations": [
                "character_id TEXT DEFAULT 'nova'",
                "emotional_arc TEXT",
                "topics_discussed TEXT",
                "session_summary TEXT",
                "summary TEXT",
            ],
            "messages": [
                "emotional_tone TEXT",
                "emotional_intensity REAL DEFAULT 0.0",
                "topics TEXT",
                "hour_of_day INTEGER",
                "day_of_week INTEGER",
                "memory_extracted INTEGER DEFAULT 0",
            ],
            "user_facts": [
                "source_message_id INTEGER",
                "source_type TEXT DEFAULT 'extracted'",
                "is_outdated INTEGER DEFAULT 0",
                "superseded_by_id INTEGER",
            ],
            "behavioral_patterns": [
                "source TEXT DEFAULT 'detector'",
            ],
            "emotional_events": [
                "valence REAL DEFAULT 0.0",
            ],
            "memory_index": [
                "title TEXT",
                "content TEXT",
                "emotion_tag TEXT",
                "source_message_ids TEXT",
                "conversation_id TEXT",
                "archived INTEGER DEFAULT 0",
            ],
        }

        for table, columns in required_columns.items():
            if not self._table_exists(table):
                continue
            existing = self._get_table_columns(table)
            for definition in columns:
                name = definition.split()[0]
                if name not in existing:
                    self.conn.execute(f"ALTER TABLE {table} ADD COLUMN {definition}")
                    logger.info("Added column %s.%s", table, name)

    def _table_exists(self, table_name: str) -> bool:
        row = self.conn.execute(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
            (table_name,),
        ).fetchone()
        return row is not None

    def _get_table_columns(self, table_name: str) -> set[str]:
        rows = self.conn.execute(f"PRAGMA table_info({table_name})").fetchall()
        return {row["name"] for row in rows}

    def _row_to_dict(self, row: Optional[sqlite3.Row]) -> Optional[dict]:
        return dict(row) if row else None

    def _deserialize_topics(self, value: Optional[str]) -> list[str]:
        if not value:
            return []
        try:
            parsed = json.loads(value)
            return parsed if isinstance(parsed, list) else []
        except json.JSONDecodeError:
            return []

    def _normalize_message_row(self, row: sqlite3.Row) -> dict:
        payload = dict(row)
        payload["topics"] = self._deserialize_topics(payload.get("topics"))
        return payload

    def _build_memory_title(self, content: Optional[str]) -> str:
        text = (content or "").strip()
        if not text:
            return "Untitled moment"
        return text[:80]

    # ------------------------------------------------------------------
    # User operations
    # ------------------------------------------------------------------

    def get_or_create_user(self, user_id: str, character_id: str = "nova") -> dict:
        row = self.conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()

        if row:
            self.conn.execute(
                "UPDATE users SET last_seen = ?, character_id = COALESCE(character_id, ?) WHERE id = ?",
                (_utcnow_iso(), character_id, user_id),
            )
            return dict(
                self.conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
            )

        now = _utcnow_iso()
        self.conn.execute(
            """
            INSERT INTO users
                (id, created_at, last_seen, character_id, total_sessions, total_messages,
                 emotional_baseline, baseline_sample_size)
            VALUES (?, ?, ?, ?, 0, 0, 0.5, 0)
            """,
            (user_id, now, now, character_id),
        )
        logger.info("New user created: %s", user_id)
        return dict(self.conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone())

    def update_user_name(self, user_id: str, name: str, preferred_name: str | None = None):
        display_name = preferred_name or name
        self.conn.execute(
            """
            UPDATE users
            SET name = ?, preferred_name = COALESCE(?, preferred_name, ?), display_name = COALESCE(display_name, ?)
            WHERE id = ?
            """,
            (name, preferred_name, name, display_name, user_id),
        )

    def get_user(self, user_id: str) -> Optional[dict]:
        return self._row_to_dict(
            self.conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
        )

    def increment_user_stats(self, user_id: str, messages: int = 1, sessions: int = 0):
        self.conn.execute(
            """
            UPDATE users
            SET total_messages = total_messages + ?,
                total_sessions = total_sessions + ?
            WHERE id = ?
            """,
            (messages, sessions, user_id),
        )

    def get_total_sessions(self, user_id: str) -> int:
        row = self.conn.execute(
            "SELECT total_sessions FROM users WHERE id = ?",
            (user_id,),
        ).fetchone()
        return int(row["total_sessions"]) if row else 0

    # ------------------------------------------------------------------
    # Facts
    # ------------------------------------------------------------------

    def save_user_fact(
        self,
        user_id: str,
        category: str,
        key: str,
        value: str,
        confidence: float = 1.0,
        source_message_id: Optional[int] = None,
        source_type: str = "extracted",
    ) -> int:
        now = _utcnow_iso()
        current = self.conn.execute(
            """
            SELECT * FROM user_facts
            WHERE user_id = ? AND fact_key = ? AND is_outdated = 0
            ORDER BY updated_at DESC
            LIMIT 1
            """,
            (user_id, key),
        ).fetchone()

        if current:
            if current["fact_value"] == value:
                self.conn.execute(
                    """
                    UPDATE user_facts
                    SET category = ?,
                        confidence = CASE
                            WHEN ? > confidence THEN ?
                            ELSE confidence
                        END,
                        source_message_id = COALESCE(?, source_message_id),
                        source_type = ?,
                        updated_at = ?
                    WHERE id = ?
                    """,
                    (
                        category,
                        confidence,
                        confidence,
                        source_message_id,
                        source_type,
                        now,
                        current["id"],
                    ),
                )
                return int(current["id"])

            self.conn.execute(
                "UPDATE user_facts SET is_outdated = 1, updated_at = ? WHERE id = ?",
                (now, current["id"]),
            )

        cursor = self.conn.execute(
            """
            INSERT INTO user_facts
                (user_id, category, fact_key, fact_value, confidence, source_message_id,
                 source_type, created_at, updated_at, is_outdated)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
            """,
            (
                user_id,
                category,
                key,
                value,
                confidence,
                source_message_id,
                source_type,
                now,
                now,
            ),
        )
        new_id = int(cursor.lastrowid)

        if current:
            self.conn.execute(
                "UPDATE user_facts SET superseded_by_id = ? WHERE id = ?",
                (new_id, current["id"]),
            )

        return new_id

    def get_user_facts(self, user_id: str) -> dict[str, str]:
        rows = self.conn.execute(
            """
            SELECT fact_key, fact_value
            FROM user_facts
            WHERE user_id = ? AND is_outdated = 0
            ORDER BY updated_at DESC
            """,
            (user_id,),
        ).fetchall()
        return {row["fact_key"]: row["fact_value"] for row in rows}

    def get_user_fact_rows(self, user_id: str, limit: int = 12) -> list[dict]:
        rows = self.conn.execute(
            """
            SELECT *
            FROM user_facts
            WHERE user_id = ? AND is_outdated = 0
            ORDER BY confidence DESC, updated_at DESC
            LIMIT ?
            """,
            (user_id, limit),
        ).fetchall()
        return [dict(row) for row in rows]

    def get_user_facts_by_category(self, user_id: str, category: str) -> dict[str, str]:
        rows = self.conn.execute(
            """
            SELECT fact_key, fact_value
            FROM user_facts
            WHERE user_id = ? AND category = ? AND is_outdated = 0
            ORDER BY updated_at DESC
            """,
            (user_id, category),
        ).fetchall()
        return {row["fact_key"]: row["fact_value"] for row in rows}

    # ------------------------------------------------------------------
    # Conversations
    # ------------------------------------------------------------------

    def create_conversation(self, user_id: str, character_id: str = "nova") -> str:
        conv_id = str(uuid.uuid4())
        self.conn.execute(
            """
            INSERT INTO conversations (id, user_id, character_id, started_at, message_count)
            VALUES (?, ?, ?, ?, 0)
            """,
            (conv_id, user_id, character_id, _utcnow_iso()),
        )
        self.increment_user_stats(user_id, messages=0, sessions=1)
        return conv_id

    def get_current_conversation(self, user_id: str) -> Optional[str]:
        row = self.conn.execute(
            """
            SELECT id
            FROM conversations
            WHERE user_id = ? AND ended_at IS NULL
            ORDER BY started_at DESC
            LIMIT 1
            """,
            (user_id,),
        ).fetchone()
        return row["id"] if row else None

    def close_conversation(self, conversation_id: str):
        self.conn.execute(
            "UPDATE conversations SET ended_at = ? WHERE id = ?",
            (_utcnow_iso(), conversation_id),
        )

    def save_conversation_summary(self, conversation_id: str, summary: str):
        self.conn.execute(
            "UPDATE conversations SET session_summary = ?, summary = ? WHERE id = ?",
            (summary, summary, conversation_id),
        )

    def save_conversation_insights(
        self,
        conversation_id: str,
        emotional_arc: Optional[str] = None,
        topics_discussed: Optional[list[str]] = None,
        session_summary: Optional[str] = None,
    ):
        self.conn.execute(
            """
            UPDATE conversations
            SET emotional_arc = COALESCE(?, emotional_arc),
                topics_discussed = COALESCE(?, topics_discussed),
                session_summary = COALESCE(?, session_summary),
                summary = COALESCE(?, summary)
            WHERE id = ?
            """,
            (
                emotional_arc,
                json.dumps(topics_discussed or []) if topics_discussed else None,
                session_summary,
                session_summary,
                conversation_id,
            ),
        )

    # ------------------------------------------------------------------
    # Messages
    # ------------------------------------------------------------------

    def save_message(
        self,
        conversation_id: str,
        user_id: str,
        role: str,
        content: str,
        emotional_tone: Optional[str] = None,
        emotional_intensity: float = 0.0,
        topics: Optional[list[str]] = None,
    ) -> int:
        now = datetime.utcnow()
        cursor = self.conn.execute(
            """
            INSERT INTO messages
                (conversation_id, user_id, role, content, created_at, emotional_tone,
                 emotional_intensity, topics, hour_of_day, day_of_week)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                conversation_id,
                user_id,
                role,
                content,
                now.isoformat(timespec="seconds"),
                emotional_tone,
                emotional_intensity,
                json.dumps(topics or []),
                now.hour,
                _day_of_week(now),
            ),
        )
        self.conn.execute(
            "UPDATE conversations SET message_count = message_count + 1 WHERE id = ?",
            (conversation_id,),
        )
        self.increment_user_stats(user_id, messages=1)
        return int(cursor.lastrowid)

    def annotate_message(
        self,
        message_id: int,
        emotional_tone: Optional[str] = None,
        emotional_intensity: Optional[float] = None,
        topics: Optional[list[str]] = None,
    ):
        self.conn.execute(
            """
            UPDATE messages
            SET emotional_tone = COALESCE(?, emotional_tone),
                emotional_intensity = COALESCE(?, emotional_intensity),
                topics = COALESCE(?, topics)
            WHERE id = ?
            """,
            (
                emotional_tone,
                emotional_intensity,
                json.dumps(topics) if topics is not None else None,
                message_id,
            ),
        )

    def get_recent_messages(
        self,
        user_id: str,
        limit: Optional[int] = None,
        conversation_id: Optional[str] = None,
    ) -> list[dict]:
        n = limit or settings.RECENT_HISTORY_TURNS
        if conversation_id:
            rows = self.conn.execute(
                """
                SELECT *
                FROM messages
                WHERE conversation_id = ?
                ORDER BY created_at DESC
                LIMIT ?
                """,
                (conversation_id, n),
            ).fetchall()
        else:
            rows = self.conn.execute(
                """
                SELECT *
                FROM messages
                WHERE user_id = ?
                ORDER BY created_at DESC
                LIMIT ?
                """,
                (user_id, n),
            ).fetchall()

        return [self._normalize_message_row(row) for row in reversed(rows)]

    def get_unextracted_messages(
        self,
        user_id: str,
        conversation_id: Optional[str] = None,
        limit: int = 20,
    ) -> list[dict]:
        if conversation_id:
            rows = self.conn.execute(
                """
                SELECT *
                FROM messages
                WHERE user_id = ? AND conversation_id = ? AND memory_extracted = 0
                ORDER BY created_at ASC
                LIMIT ?
                """,
                (user_id, conversation_id, limit),
            ).fetchall()
        else:
            rows = self.conn.execute(
                """
                SELECT *
                FROM messages
                WHERE user_id = ? AND memory_extracted = 0
                ORDER BY created_at ASC
                LIMIT ?
                """,
                (user_id, limit),
            ).fetchall()
        return [self._normalize_message_row(row) for row in rows]

    def mark_messages_extracted(self, message_ids: list[int]):
        if not message_ids:
            return
        placeholders = ",".join("?" for _ in message_ids)
        self.conn.execute(
            f"UPDATE messages SET memory_extracted = 1 WHERE id IN ({placeholders})",
            message_ids,
        )

    # ------------------------------------------------------------------
    # Entities and relationships
    # ------------------------------------------------------------------

    def upsert_entity(
        self,
        user_id: str,
        name: str,
        entity_type: str,
        description: Optional[str] = None,
        relationship_to_user: Optional[str] = None,
        emotional_valence: Optional[float] = None,
    ) -> int:
        now = _utcnow_iso()
        existing = self.conn.execute(
            "SELECT * FROM entities WHERE user_id = ? AND LOWER(name) = LOWER(?)",
            (user_id, name),
        ).fetchone()

        if existing:
            new_valence = existing["emotional_valence"]
            if emotional_valence is not None:
                new_valence = round((float(existing["emotional_valence"] or 0.0) + emotional_valence) / 2, 3)

            self.conn.execute(
                """
                UPDATE entities
                SET type = COALESCE(?, type),
                    description = COALESCE(?, description),
                    relationship_to_user = COALESCE(?, relationship_to_user),
                    emotional_valence = ?,
                    last_mentioned_at = ?,
                    mention_count = mention_count + 1
                WHERE id = ?
                """,
                (
                    entity_type,
                    description,
                    relationship_to_user,
                    new_valence,
                    now,
                    existing["id"],
                ),
            )
            return int(existing["id"])

        cursor = self.conn.execute(
            """
            INSERT INTO entities
                (user_id, name, type, description, relationship_to_user,
                 emotional_valence, first_mentioned_at, last_mentioned_at, mention_count)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)
            """,
            (
                user_id,
                name,
                entity_type,
                description,
                relationship_to_user,
                emotional_valence or 0.0,
                now,
                now,
            ),
        )
        return int(cursor.lastrowid)

    def get_entities_for_context(self, user_id: str, query_text: str, limit: int = 6) -> list[dict]:
        rows = self.conn.execute(
            """
            SELECT *
            FROM entities
            WHERE user_id = ?
            ORDER BY mention_count DESC, last_mentioned_at DESC
            LIMIT 25
            """,
            (user_id,),
        ).fetchall()
        entities = [dict(row) for row in rows]
        lowered_query = query_text.lower()
        mentioned = [entity for entity in entities if entity["name"].lower() in lowered_query]
        remaining = [entity for entity in entities if entity["name"].lower() not in lowered_query]
        return (mentioned + remaining)[:limit]

    def save_entity_relationship(
        self,
        user_id: str,
        entity_a_id: int,
        entity_b_id: int,
        relationship_type: Optional[str],
        description: Optional[str],
    ):
        now = _utcnow_iso()
        self.conn.execute(
            """
            INSERT INTO entity_relationships
                (user_id, entity_a_id, entity_b_id, relationship_type, description, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(user_id, entity_a_id, entity_b_id, relationship_type) DO UPDATE SET
                description = COALESCE(excluded.description, entity_relationships.description),
                updated_at = excluded.updated_at
            """,
            (user_id, entity_a_id, entity_b_id, relationship_type, description, now, now),
        )

    def get_relationships_for_entities(self, user_id: str, entity_ids: list[int], limit: int = 6) -> list[dict]:
        if not entity_ids:
            return []
        placeholders = ",".join("?" for _ in entity_ids)
        params: list[Any] = [user_id, *entity_ids, *entity_ids, limit]
        rows = self.conn.execute(
            f"""
            SELECT rel.*, a.name AS entity_a_name, b.name AS entity_b_name
            FROM entity_relationships rel
            JOIN entities a ON a.id = rel.entity_a_id
            JOIN entities b ON b.id = rel.entity_b_id
            WHERE rel.user_id = ?
              AND (rel.entity_a_id IN ({placeholders}) OR rel.entity_b_id IN ({placeholders}))
            ORDER BY rel.updated_at DESC
            LIMIT ?
            """,
            params,
        ).fetchall()
        return [dict(row) for row in rows]

    # ------------------------------------------------------------------
    # Emotional timeline
    # ------------------------------------------------------------------

    def log_emotional_event(
        self,
        user_id: str,
        message_id: Optional[int],
        emotion: str,
        intensity: float,
        trigger_topic: Optional[str] = None,
        trigger_entity: Optional[str] = None,
        valence: float = 0.0,
    ) -> int:
        now = datetime.utcnow()
        cursor = self.conn.execute(
            """
            INSERT INTO emotional_events
                (user_id, message_id, emotion, intensity, trigger_topic, trigger_entity,
                 valence, created_at, hour_of_day, day_of_week)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                user_id,
                message_id,
                emotion,
                intensity,
                trigger_topic,
                trigger_entity,
                valence,
                now.isoformat(timespec="seconds"),
                now.hour,
                _day_of_week(now),
            ),
        )

        user = self.get_user(user_id) or {}
        sample_size = int(user.get("baseline_sample_size") or 0)
        current_baseline = float(user.get("emotional_baseline") or 0.5)
        normalized_valence = max(0.0, min(1.0, (valence + 1.0) / 2.0))
        next_sample_size = sample_size + 1
        next_baseline = ((current_baseline * sample_size) + normalized_valence) / next_sample_size

        self.conn.execute(
            """
            UPDATE users
            SET emotional_baseline = ?, baseline_sample_size = ?
            WHERE id = ?
            """,
            (round(next_baseline, 4), next_sample_size, user_id),
        )
        return int(cursor.lastrowid)

    def get_recent_emotional_events(self, user_id: str, limit: int = 8) -> list[dict]:
        rows = self.conn.execute(
            """
            SELECT *
            FROM emotional_events
            WHERE user_id = ?
            ORDER BY created_at DESC
            LIMIT ?
            """,
            (user_id, limit),
        ).fetchall()
        return [dict(row) for row in rows]

    def get_emotional_summary(self, user_id: str, limit: int = 10) -> dict:
        user = self.get_user(user_id) or {}
        events = self.get_recent_emotional_events(user_id, limit=limit)
        if not events:
            return {
                "baseline": float(user.get("emotional_baseline") or 0.5),
                "sample_size": int(user.get("baseline_sample_size") or 0),
                "recent_average": None,
                "direction": None,
                "dominant_emotions": [],
            }

        normalized = [max(0.0, min(1.0, (float(event.get("valence", 0.0)) + 1.0) / 2.0)) for event in events]
        recent_average = round(sum(normalized) / len(normalized), 3)
        direction = self._infer_emotional_direction(events)

        counts: dict[str, int] = {}
        for event in events:
            counts[event["emotion"]] = counts.get(event["emotion"], 0) + 1
        dominant = [emotion for emotion, _ in sorted(counts.items(), key=lambda item: item[1], reverse=True)[:3]]

        return {
            "baseline": float(user.get("emotional_baseline") or 0.5),
            "sample_size": int(user.get("baseline_sample_size") or 0),
            "recent_average": recent_average,
            "direction": direction,
            "dominant_emotions": dominant,
        }

    def _infer_emotional_direction(self, events: list[dict]) -> str:
        values = [float(event.get("valence", 0.0)) for event in reversed(events)]
        if len(values) < 4:
            return "stable"

        midpoint = len(values) // 2
        first_half = sum(values[:midpoint]) / max(1, len(values[:midpoint]))
        second_half = sum(values[midpoint:]) / max(1, len(values[midpoint:]))
        swing = max(values) - min(values)

        if swing >= 0.9:
            return "volatile"
        if second_half - first_half > 0.18:
            return "improving"
        if second_half - first_half < -0.18:
            return "declining"
        return "stable"

    # ------------------------------------------------------------------
    # Patterns
    # ------------------------------------------------------------------

    def upsert_behavioral_pattern(
        self,
        user_id: str,
        pattern_type: str,
        description: str,
        evidence_count: int = 1,
        confidence: float = 0.5,
        source: str = "detector",
        is_active: bool = True,
    ) -> int:
        now = _utcnow_iso()
        existing = self.conn.execute(
            """
            SELECT *
            FROM behavioral_patterns
            WHERE user_id = ? AND pattern_type = ? AND description = ?
            LIMIT 1
            """,
            (user_id, pattern_type, description),
        ).fetchone()

        if existing:
            self.conn.execute(
                """
                UPDATE behavioral_patterns
                SET evidence_count = MAX(evidence_count, ?),
                    confidence = CASE
                        WHEN ? > confidence THEN ?
                        ELSE confidence
                    END,
                    last_seen_at = ?,
                    is_active = ?,
                    source = ?
                WHERE id = ?
                """,
                (
                    evidence_count,
                    confidence,
                    confidence,
                    now,
                    1 if is_active else 0,
                    source,
                    existing["id"],
                ),
            )
            return int(existing["id"])

        cursor = self.conn.execute(
            """
            INSERT INTO behavioral_patterns
                (user_id, pattern_type, description, evidence_count, confidence,
                 first_detected_at, last_seen_at, is_active, source)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                user_id,
                pattern_type,
                description,
                evidence_count,
                confidence,
                now,
                now,
                1 if is_active else 0,
                source,
            ),
        )
        return int(cursor.lastrowid)

    def get_active_patterns(self, user_id: str, limit: int = 5) -> list[dict]:
        rows = self.conn.execute(
            """
            SELECT *
            FROM behavioral_patterns
            WHERE user_id = ? AND is_active = 1
            ORDER BY confidence DESC, evidence_count DESC, last_seen_at DESC
            LIMIT ?
            """,
            (user_id, limit),
        ).fetchall()
        return [dict(row) for row in rows]

    # ------------------------------------------------------------------
    # Narrative
    # ------------------------------------------------------------------

    def save_narrative_summary(
        self,
        user_id: str,
        period_start: Optional[str],
        period_end: Optional[str],
        summary: str,
        themes: Optional[list[str]] = None,
        emotional_direction: Optional[str] = None,
    ) -> int:
        created_at = _utcnow_iso()
        cursor = self.conn.execute(
            """
            INSERT INTO narrative_summaries
                (user_id, period_start, period_end, summary, themes, emotional_direction, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                user_id,
                period_start,
                period_end,
                summary,
                json.dumps(themes or []),
                emotional_direction,
                created_at,
            ),
        )
        self.conn.execute(
            """
            UPDATE users
            SET current_narrative = ?, narrative_updated_at = ?
            WHERE id = ?
            """,
            (summary, created_at, user_id),
        )
        return int(cursor.lastrowid)

    def get_current_narrative(self, user_id: str) -> Optional[dict]:
        user = self.get_user(user_id)
        if user and user.get("current_narrative"):
            return {
                "summary": user["current_narrative"],
                "created_at": user.get("narrative_updated_at"),
            }

        row = self.conn.execute(
            """
            SELECT *
            FROM narrative_summaries
            WHERE user_id = ?
            ORDER BY created_at DESC
            LIMIT 1
            """,
            (user_id,),
        ).fetchone()
        if not row:
            return None
        payload = dict(row)
        payload["themes"] = self._deserialize_topics(payload.get("themes"))
        return payload

    # ------------------------------------------------------------------
    # Episodic memory bookkeeping
    # ------------------------------------------------------------------

    def log_memory(
        self,
        chroma_id: str,
        user_id: str,
        content: str,
        title: Optional[str] = None,
        emotion_tag: Optional[str] = None,
        emotional_weight: float = 0.5,
        strength: float = 1.0,
        conversation_id: Optional[str] = None,
        source_message_ids: Optional[list[int]] = None,
    ):
        self.conn.execute(
            """
            INSERT INTO memory_index
                (user_id, chroma_id, title, content, emotion_tag, strength, emotional_weight,
                 created_at, source_message_ids, conversation_id, archived)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
            ON CONFLICT(user_id, chroma_id) DO UPDATE SET
                title = COALESCE(excluded.title, memory_index.title),
                content = COALESCE(excluded.content, memory_index.content),
                emotion_tag = COALESCE(excluded.emotion_tag, memory_index.emotion_tag),
                emotional_weight = excluded.emotional_weight,
                strength = excluded.strength,
                source_message_ids = COALESCE(excluded.source_message_ids, memory_index.source_message_ids),
                conversation_id = COALESCE(excluded.conversation_id, memory_index.conversation_id)
            """,
            (
                user_id,
                chroma_id,
                title or self._build_memory_title(content),
                content,
                emotion_tag,
                strength,
                emotional_weight,
                _utcnow_iso(),
                json.dumps(source_message_ids or []),
                conversation_id,
            ),
        )

    def get_memory_metadata_map(self, user_id: str, chroma_ids: list[str]) -> dict[str, dict]:
        if not chroma_ids:
            return {}
        placeholders = ",".join("?" for _ in chroma_ids)
        rows = self.conn.execute(
            f"""
            SELECT *
            FROM memory_index
            WHERE user_id = ? AND chroma_id IN ({placeholders})
            """,
            [user_id, *chroma_ids],
        ).fetchall()
        return {row["chroma_id"]: dict(row) for row in rows}

    def reinforce_memories(self, user_id: str, chroma_ids: list[str]):
        if not chroma_ids:
            return
        placeholders = ",".join("?" for _ in chroma_ids)
        self.conn.execute(
            f"""
            UPDATE memory_index
            SET retrieval_count = retrieval_count + 1,
                last_retrieved_at = ?,
                strength = MIN(strength + 0.08, 2.5)
            WHERE user_id = ? AND chroma_id IN ({placeholders})
            """,
            [_utcnow_iso(), user_id, *chroma_ids],
        )

    def get_recent_memory_rows(
        self,
        user_id: str,
        limit: int = 8,
        since: Optional[str] = None,
    ) -> list[dict]:
        if since:
            rows = self.conn.execute(
                """
                SELECT *
                FROM memory_index
                WHERE user_id = ? AND archived = 0 AND created_at >= ?
                ORDER BY created_at DESC, emotional_weight DESC
                LIMIT ?
                """,
                (user_id, since, limit),
            ).fetchall()
        else:
            rows = self.conn.execute(
                """
                SELECT *
                FROM memory_index
                WHERE user_id = ? AND archived = 0
                ORDER BY created_at DESC, emotional_weight DESC
                LIMIT ?
                """,
                (user_id, limit),
            ).fetchall()
        return [dict(row) for row in rows]

    def get_recent_emotions_since(self, user_id: str, since: Optional[str], limit: int = 10) -> list[dict]:
        if since:
            rows = self.conn.execute(
                """
                SELECT *
                FROM emotional_events
                WHERE user_id = ? AND created_at >= ?
                ORDER BY created_at DESC
                LIMIT ?
                """,
                (user_id, since, limit),
            ).fetchall()
        else:
            rows = self.conn.execute(
                """
                SELECT *
                FROM emotional_events
                WHERE user_id = ?
                ORDER BY created_at DESC
                LIMIT ?
                """,
                (user_id, limit),
            ).fetchall()
        return [dict(row) for row in rows]


db = Database()
