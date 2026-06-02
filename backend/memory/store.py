import json
import logging
import sqlite3
import threading
import uuid
from contextlib import contextmanager
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Optional

from config import settings

logger = logging.getLogger(__name__)


def _utcnow_iso() -> str:
    return datetime.utcnow().isoformat(timespec="milliseconds")


def _day_of_week(dt: datetime) -> int:
    return dt.weekday()


def make_pair_id(user_id: str, companion_id: str) -> str:
    return f"{user_id}::{companion_id}"


PAIR_REBUILD_TABLES = {
    "entities": {
        "expected": ["unique(pair_id, name)"],
        "legacy": ["unique(user_id, name)"],
    },
    "entity_relationships": {
        "expected": ["unique(pair_id, entity_a_id, entity_b_id, relationship_type)"],
        "legacy": ["unique(user_id, entity_a_id, entity_b_id, relationship_type)"],
    },
    "behavioral_patterns": {
        "expected": ["unique(pair_id, pattern_type, description)"],
        "legacy": ["unique(user_id, pattern_type, description)"],
    },
    "memory_index": {
        "expected": ["unique(pair_id, chroma_id)"],
        "legacy": ["unique(user_id, chroma_id)"],
    },
}


class Database:
    def __init__(self):
        self._conn: Optional[sqlite3.Connection] = None
        self._local = threading.local()
        self._transaction_lock = threading.RLock()

    @contextmanager
    def transaction(self, mode: str = "IMMEDIATE"):
        """Thread-safe re-entrant SQLite transaction context manager."""
        if mode not in ("IMMEDIATE", "DEFERRED", "EXCLUSIVE"):
            raise ValueError(f"Invalid transaction mode: {mode}")

        if not hasattr(self._local, "depth"):
            self._local.depth = 0

        is_outermost = False
        lock_acquired = False
        if self._local.depth == 0:
            self._transaction_lock.acquire()
            lock_acquired = True
            try:
                self.conn.execute(f"BEGIN {mode}")
                is_outermost = True
            except Exception:
                self._transaction_lock.release()
                raise

        self._local.depth += 1
        try:
            yield
            self._local.depth -= 1
            if is_outermost:
                self.conn.execute("COMMIT")
                if lock_acquired:
                    self._transaction_lock.release()
                    lock_acquired = False
        except Exception as e:
            if is_outermost:
                self._local.depth = 0
                try:
                    self.conn.execute("ROLLBACK")
                except sqlite3.OperationalError as rollback_err:
                    logger.warning("Rollback failed or transaction wasn't active: %s", rollback_err)
                finally:
                    if lock_acquired:
                        self._transaction_lock.release()
                        lock_acquired = False
            else:
                self._local.depth -= 1
            raise e

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

    def ping(self) -> None:
        self.conn.execute("SELECT 1").fetchone()

    @property
    def conn(self) -> sqlite3.Connection:
        if not self._conn:
            raise RuntimeError("Database not connected. Call db.connect() first.")
        return self._conn

    def _init_schema(self):
        self._prepare_legacy_tables_for_schema()

        schema_path = Path(__file__).parent.parent / "db" / "schema.sql"
        with open(schema_path, "r", encoding="utf-8") as handle:
            schema_sql = handle.read()

        schema_body, index_sql = self._split_schema_sections(schema_sql)

        # Important ordering:
        # 1. create canonical tables
        # 2. add missing columns onto legacy tables
        # 3. migrate/backfill data
        # 4. create indexes that depend on pair-scoped columns
        #
        # Older local databases may not have `pair_id` yet. If we execute the
        # index section first, SQLite fails before the migration code can run.
        self.conn.executescript(schema_body)

        self._ensure_columns()
        self._sync_companion_rows()
        self._ensure_pair_rows_from_existing_data()
        self._migrate_legacy_data()
        self._migrate_pair_scoped_data()
        self._dedupe_active_facts()
        self._drop_legacy_indexes()
        if index_sql.strip():
            self.conn.executescript(index_sql)
        logger.info("Database schema initialized")

    def _split_schema_sections(self, schema_sql: str) -> tuple[str, str]:
        marker = "-- =============================================================================\n-- INDEXES"
        if marker not in schema_sql:
            return schema_sql, ""
        body, tail = schema_sql.split(marker, 1)
        return body, f"{marker}{tail}"

    def _prepare_legacy_tables_for_schema(self):
        if self._table_exists("user_facts"):
            columns = self._get_table_columns("user_facts")
            if "fact_key" not in columns and "key" in columns:
                self._rename_table_for_rebuild("user_facts", "user_facts_legacy")

        for table_name, rules in PAIR_REBUILD_TABLES.items():
            if not self._table_exists(table_name):
                continue
            if self._table_needs_pair_rebuild(table_name, rules["expected"], rules["legacy"]):
                self._rename_table_for_rebuild(table_name, self._legacy_pair_table_name(table_name))

    def _migrate_legacy_data(self):
        if self._table_exists("user_facts_legacy"):
            rows = self.conn.execute(
                """
                SELECT user_id, category, key, value, confidence, source, created_at, updated_at
                FROM user_facts_legacy
                """
            ).fetchall()

            for row in rows:
                companion_id = self._legacy_companion_for_user(row["user_id"])
                pair_id = make_pair_id(row["user_id"], companion_id)
                existing = self.conn.execute(
                    """
                    SELECT id, fact_value
                    FROM user_facts
                    WHERE pair_id = ? AND fact_key = ? AND is_outdated = 0
                    LIMIT 1
                    """,
                    (pair_id, row["key"]),
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
                        (user_id, pair_id, companion_id, category, fact_key, fact_value,
                         confidence, source_type, created_at, updated_at, is_outdated)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
                    """,
                    (
                        row["user_id"],
                        pair_id,
                        companion_id,
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
                companion_id = self._legacy_companion_for_user(row["user_id"])
                pair_id = make_pair_id(row["user_id"], companion_id)
                self.conn.execute(
                    """
                    INSERT INTO memory_index
                        (user_id, pair_id, companion_id, chroma_id, title, content, emotion_tag, strength,
                         emotional_weight, created_at, source_message_ids, conversation_id, archived)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(pair_id, chroma_id) DO NOTHING
                    """,
                    (
                        row["user_id"],
                        pair_id,
                        companion_id,
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

        entity_id_map = self._migrate_legacy_entities()
        self._migrate_legacy_entity_relationships(entity_id_map)
        self._migrate_legacy_behavioral_patterns()
        self._migrate_legacy_memory_index()
        self._refresh_pair_memory_counts()
        self._cleanup_migrated_legacy_tables()

    def _migrate_pair_scoped_data(self):
        self._backfill_conversation_pairs()
        self._backfill_message_pairs()
        for table_name in (
            "user_facts",
            "entities",
            "entity_relationships",
            "emotional_events",
            "behavioral_patterns",
            "narrative_summaries",
            "memory_index",
        ):
            self._backfill_pair_columns_for_table(table_name)

    def _drop_legacy_indexes(self):
        self.conn.execute("DROP INDEX IF EXISTS idx_user_facts_active_unique")

    def _legacy_pair_table_name(self, table_name: str) -> str:
        return f"{table_name}_pair_legacy"

    def _rename_table_for_rebuild(self, table_name: str, legacy_name: str):
        if self._table_exists(legacy_name):
            return
        self.conn.execute(f"ALTER TABLE {table_name} RENAME TO {legacy_name}")
        logger.info("Renamed legacy %s table to %s for canonical rebuild", table_name, legacy_name)

    def _get_table_sql(self, table_name: str) -> str:
        row = self.conn.execute(
            "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
            (table_name,),
        ).fetchone()
        return (row["sql"] or "") if row else ""

    def _table_needs_pair_rebuild(
        self,
        table_name: str,
        expected_fragments: list[str],
        legacy_fragments: list[str],
    ) -> bool:
        sql = self._get_table_sql(table_name).lower()
        if not sql:
            return False
        return any(fragment not in sql for fragment in expected_fragments) or any(
            fragment in sql for fragment in legacy_fragments
        )

    def _legacy_companion_for_user(self, user_id: str) -> str:
        user = self.get_user(user_id) or {}
        return user.get("character_id") or settings.DEFAULT_CHARACTER

    def _sync_companion_rows(self):
        if not self._table_exists("companions"):
            return

        rows = []
        if self._table_exists("users") and "character_id" in self._get_table_columns("users"):
            rows.extend(self.conn.execute("SELECT DISTINCT character_id FROM users").fetchall())
        if self._table_exists("conversations") and "character_id" in self._get_table_columns("conversations"):
            rows.extend(self.conn.execute("SELECT DISTINCT character_id FROM conversations").fetchall())

        seen: set[str] = set()
        for row in rows:
            companion_id = row["character_id"]
            if not companion_id or companion_id in seen:
                continue
            seen.add(companion_id)
            self.conn.execute(
                """
                INSERT INTO companions (id, name, status, created_at, updated_at)
                VALUES (?, ?, 'active', ?, ?)
                ON CONFLICT(id) DO NOTHING
                """,
                (companion_id, companion_id.title(), _utcnow_iso(), _utcnow_iso()),
            )

    def _ensure_pair_rows_from_existing_data(self):
        if not self._table_exists("relationship_pairs"):
            return

        user_rows = self.conn.execute(
            "SELECT id, character_id, relationship_label FROM users"
        ).fetchall()
        for row in user_rows:
            companion_id = row["character_id"] or settings.DEFAULT_CHARACTER
            pair_id = make_pair_id(row["id"], companion_id)
            self.conn.execute(
                """
                INSERT INTO relationship_pairs
                    (id, user_id, companion_id, relationship_label, assignment_status,
                     assignment_source, assignment_reason, is_primary, created_at, updated_at)
                VALUES (?, ?, ?, ?, 'active', 'legacy_migration',
                        'backfilled from pre-pair user data', 1, ?, ?)
                ON CONFLICT(id) DO NOTHING
                """,
                (
                    pair_id,
                    row["id"],
                    companion_id,
                    row["relationship_label"] or "friend",
                    _utcnow_iso(),
                    _utcnow_iso(),
                ),
            )

        if not self._table_exists("conversations"):
            return

        conversation_rows = self.conn.execute(
            """
            SELECT DISTINCT user_id, COALESCE(companion_id, character_id, ?) AS companion_id
            FROM conversations
            """,
            (settings.DEFAULT_CHARACTER,),
        ).fetchall()
        for row in conversation_rows:
            pair_id = make_pair_id(row["user_id"], row["companion_id"])
            self.conn.execute(
                """
                INSERT INTO relationship_pairs
                    (id, user_id, companion_id, relationship_label, assignment_status,
                     assignment_source, assignment_reason, is_primary, created_at, updated_at)
                VALUES (?, ?, ?, 'friend', 'active', 'legacy_migration',
                        'backfilled from pre-pair conversation data', 0, ?, ?)
                ON CONFLICT(id) DO NOTHING
                """,
                (
                    pair_id,
                    row["user_id"],
                    row["companion_id"],
                    _utcnow_iso(),
                    _utcnow_iso(),
                ),
            )

    def _migrate_legacy_entities(self) -> dict[int, int]:
        legacy_table = self._legacy_pair_table_name("entities")
        if not self._table_exists(legacy_table):
            return {}

        entity_id_map: dict[int, int] = {}
        rows = self.conn.execute(f"SELECT * FROM {legacy_table} ORDER BY id ASC").fetchall()
        for row in rows:
            payload = dict(row)
            companion_id = payload.get("companion_id") or self._legacy_companion_for_user(payload["user_id"])
            pair_id = payload.get("pair_id") or make_pair_id(payload["user_id"], companion_id)
            entity_id = self.upsert_entity(
                user_id=payload["user_id"],
                pair_id=pair_id,
                companion_id=companion_id,
                name=payload["name"],
                entity_type=payload["type"],
                description=payload.get("description"),
                relationship_to_user=payload.get("relationship_to_user"),
                emotional_valence=float(payload.get("emotional_valence") or 0.0),
            )
            self.conn.execute(
                """
                UPDATE entities
                SET first_mentioned_at = COALESCE(?, first_mentioned_at),
                    last_mentioned_at = COALESCE(?, last_mentioned_at),
                    mention_count = MAX(mention_count, ?)
                WHERE id = ?
                """,
                (
                    payload.get("first_mentioned_at"),
                    payload.get("last_mentioned_at"),
                    int(payload.get("mention_count") or 1),
                    entity_id,
                ),
            )
            entity_id_map[int(payload["id"])] = entity_id
        return entity_id_map

    def _migrate_legacy_entity_relationships(self, entity_id_map: dict[int, int]):
        legacy_table = self._legacy_pair_table_name("entity_relationships")
        if not self._table_exists(legacy_table):
            return

        rows = self.conn.execute(f"SELECT * FROM {legacy_table} ORDER BY id ASC").fetchall()
        for row in rows:
            payload = dict(row)
            entity_a_id = entity_id_map.get(int(payload["entity_a_id"]))
            entity_b_id = entity_id_map.get(int(payload["entity_b_id"]))
            if not entity_a_id or not entity_b_id:
                continue
            companion_id = payload.get("companion_id") or self._legacy_companion_for_user(payload["user_id"])
            pair_id = payload.get("pair_id") or make_pair_id(payload["user_id"], companion_id)
            self.save_entity_relationship(
                user_id=payload["user_id"],
                pair_id=pair_id,
                companion_id=companion_id,
                entity_a_id=entity_a_id,
                entity_b_id=entity_b_id,
                relationship_type=payload.get("relationship_type"),
                description=payload.get("description"),
            )

    def _migrate_legacy_behavioral_patterns(self):
        legacy_table = self._legacy_pair_table_name("behavioral_patterns")
        if not self._table_exists(legacy_table):
            return

        rows = self.conn.execute(f"SELECT * FROM {legacy_table} ORDER BY id ASC").fetchall()
        for row in rows:
            payload = dict(row)
            companion_id = payload.get("companion_id") or self._legacy_companion_for_user(payload["user_id"])
            pair_id = payload.get("pair_id") or make_pair_id(payload["user_id"], companion_id)
            self.upsert_behavioral_pattern(
                user_id=payload["user_id"],
                pair_id=pair_id,
                companion_id=companion_id,
                pattern_type=payload["pattern_type"],
                description=payload["description"],
                evidence_count=int(payload.get("evidence_count") or 1),
                confidence=float(payload.get("confidence") or 0.5),
                source=payload.get("source") or "legacy_migration",
                is_active=bool(payload.get("is_active", 1)),
            )

    def _migrate_legacy_memory_index(self):
        legacy_table = self._legacy_pair_table_name("memory_index")
        if not self._table_exists(legacy_table):
            return

        rows = self.conn.execute(f"SELECT * FROM {legacy_table} ORDER BY id ASC").fetchall()
        for row in rows:
            payload = dict(row)
            companion_id = payload.get("companion_id") or self._legacy_companion_for_user(payload["user_id"])
            pair_id = payload.get("pair_id") or make_pair_id(payload["user_id"], companion_id)
            self.conn.execute(
                """
                INSERT INTO memory_index
                    (user_id, pair_id, companion_id, chroma_id, title, content, emotion_tag,
                     strength, emotional_weight, created_at, last_retrieved_at, retrieval_count,
                     source_message_ids, conversation_id, archived)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(pair_id, chroma_id) DO UPDATE SET
                    title = COALESCE(excluded.title, memory_index.title),
                    content = COALESCE(excluded.content, memory_index.content),
                    emotion_tag = COALESCE(excluded.emotion_tag, memory_index.emotion_tag),
                    strength = MAX(memory_index.strength, excluded.strength),
                    emotional_weight = MAX(memory_index.emotional_weight, excluded.emotional_weight),
                    last_retrieved_at = COALESCE(excluded.last_retrieved_at, memory_index.last_retrieved_at),
                    retrieval_count = MAX(memory_index.retrieval_count, excluded.retrieval_count),
                    source_message_ids = COALESCE(excluded.source_message_ids, memory_index.source_message_ids),
                    conversation_id = COALESCE(excluded.conversation_id, memory_index.conversation_id),
                    archived = MIN(memory_index.archived, excluded.archived)
                """,
                (
                    payload["user_id"],
                    pair_id,
                    companion_id,
                    payload["chroma_id"],
                    payload.get("title"),
                    payload.get("content"),
                    payload.get("emotion_tag"),
                    float(payload.get("strength") or 1.0),
                    float(payload.get("emotional_weight") or 0.5),
                    payload.get("created_at") or _utcnow_iso(),
                    payload.get("last_retrieved_at"),
                    int(payload.get("retrieval_count") or 0),
                    payload.get("source_message_ids"),
                    payload.get("conversation_id"),
                    int(payload.get("archived") or 0),
                ),
            )

    def _refresh_pair_memory_counts(self):
        if not self._table_exists("relationship_pairs") or not self._table_exists("memory_index"):
            return
        self.conn.execute(
            """
            UPDATE relationship_pairs
            SET memory_count = COALESCE(
                (
                    SELECT COUNT(*)
                    FROM memory_index
                    WHERE memory_index.pair_id = relationship_pairs.id
                      AND memory_index.archived = 0
                ),
                0
            )
            """
        )

    def _cleanup_migrated_legacy_tables(self):
        legacy_tables = ["user_facts_legacy", *[self._legacy_pair_table_name(name) for name in PAIR_REBUILD_TABLES]]
        for table_name in legacy_tables:
            if self._table_exists(table_name):
                self.conn.execute(f"DROP TABLE IF EXISTS {table_name}")
                logger.info("Dropped migrated legacy table %s", table_name)

    def _dedupe_active_facts(self):
        if not self._table_exists("user_facts"):
            return

        duplicate_groups = self.conn.execute(
            """
            SELECT pair_id, fact_key, COUNT(*) AS duplicate_count
            FROM user_facts
            WHERE is_outdated = 0
              AND pair_id IS NOT NULL
              AND TRIM(COALESCE(fact_key, '')) != ''
            GROUP BY pair_id, fact_key
            HAVING COUNT(*) > 1
            """
        ).fetchall()

        deduped = 0
        for group in duplicate_groups:
            rows = self.conn.execute(
                """
                SELECT *
                FROM user_facts
                WHERE pair_id = ? AND fact_key = ? AND is_outdated = 0
                ORDER BY
                    COALESCE(updated_at, created_at) DESC,
                    confidence DESC,
                    id DESC
                """,
                (group["pair_id"], group["fact_key"]),
            ).fetchall()
            if len(rows) <= 1:
                continue

            keeper = rows[0]
            for stale in rows[1:]:
                self.conn.execute(
                    """
                    UPDATE user_facts
                    SET is_outdated = 1,
                        superseded_by_id = ?,
                        updated_at = ?
                    WHERE id = ?
                    """,
                    (keeper["id"], _utcnow_iso(), stale["id"]),
                )
                deduped += 1

        if deduped:
            logger.info("Deduplicated %s legacy active user facts before creating canonical indexes", deduped)

    def _backfill_conversation_pairs(self):
        if not self._table_exists("conversations"):
            return

        rows = self.conn.execute(
            "SELECT id, user_id, pair_id, companion_id, character_id FROM conversations"
        ).fetchall()
        for row in rows:
            companion_id = row["companion_id"] or row["character_id"] or self._legacy_companion_for_user(row["user_id"])
            pair_id = row["pair_id"] or make_pair_id(row["user_id"], companion_id)
            self.conn.execute(
                """
                UPDATE conversations
                SET pair_id = COALESCE(pair_id, ?),
                    companion_id = COALESCE(companion_id, ?),
                    character_id = COALESCE(character_id, ?)
                WHERE id = ?
                """,
                (pair_id, companion_id, companion_id, row["id"]),
            )

    def _backfill_message_pairs(self):
        if not self._table_exists("messages"):
            return

        rows = self.conn.execute(
            """
            SELECT m.id, m.user_id, m.pair_id, m.companion_id, m.conversation_id,
                   c.pair_id AS conv_pair_id, c.companion_id AS conv_companion_id, c.character_id
            FROM messages m
            LEFT JOIN conversations c ON c.id = m.conversation_id
            """
        ).fetchall()
        for row in rows:
            companion_id = (
                row["companion_id"]
                or row["conv_companion_id"]
                or row["character_id"]
                or self._legacy_companion_for_user(row["user_id"])
            )
            pair_id = row["pair_id"] or row["conv_pair_id"] or make_pair_id(row["user_id"], companion_id)
            self.conn.execute(
                """
                UPDATE messages
                SET pair_id = COALESCE(pair_id, ?),
                    companion_id = COALESCE(companion_id, ?)
                WHERE id = ?
                """,
                (pair_id, companion_id, row["id"]),
            )

    def _backfill_pair_columns_for_table(self, table_name: str):
        if not self._table_exists(table_name):
            return

        columns = self._get_table_columns(table_name)
        if "pair_id" not in columns or "companion_id" not in columns:
            return

        rows = self.conn.execute(f"SELECT rowid AS _rowid_, * FROM {table_name}").fetchall()
        for row in rows:
            companion_id = row["companion_id"] or self._legacy_companion_for_user(row["user_id"])
            pair_id = row["pair_id"] or make_pair_id(row["user_id"], companion_id)
            self.conn.execute(
                f"""
                UPDATE {table_name}
                SET pair_id = COALESCE(pair_id, ?),
                    companion_id = COALESCE(companion_id, ?)
                WHERE rowid = ?
                """,
                (pair_id, companion_id, row["_rowid_"]),
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
                "onboarding_signals TEXT",
                "onboarding_completed INTEGER DEFAULT 0",
            ],
            "companions": [
                "status TEXT DEFAULT 'active'",
                "archetype TEXT",
                "summary TEXT",
                "introduction_style TEXT",
                "relationship_label TEXT DEFAULT 'friend'",
                "match_weight INTEGER DEFAULT 1",
                "sort_order INTEGER DEFAULT 0",
                "proactive_frequency TEXT DEFAULT 'medium'",
                "impulsiveness REAL DEFAULT 0.5",
                "attachment_speed REAL DEFAULT 0.5",
                "boredom_threshold REAL DEFAULT 0.5",
                "loneliness_tolerance REAL DEFAULT 0.5",
                "emotional_openness REAL DEFAULT 0.5",
                "social_confidence REAL DEFAULT 0.5",
                "texting_consistency REAL DEFAULT 0.5",
                "disappearance_tendency REAL DEFAULT 0.5",
                "late_night_probability REAL DEFAULT 0.5",
                "double_text_probability REAL DEFAULT 0.5",
                "emotional_volatility REAL DEFAULT 0.5",
                "created_at DATETIME DEFAULT CURRENT_TIMESTAMP",
                "updated_at DATETIME DEFAULT CURRENT_TIMESTAMP",
            ],
            "relationship_pairs": [
                "relationship_label TEXT DEFAULT 'friend'",
                "assignment_status TEXT DEFAULT 'assigned'",
                "assignment_source TEXT DEFAULT 'matcher'",
                "assignment_reason TEXT",
                "is_primary INTEGER DEFAULT 0",
                "introduced_at DATETIME",
                "first_session_at DATETIME",
                "last_session_started_at DATETIME",
                "last_interaction_at DATETIME",
                "last_user_message_at DATETIME",
                "last_companion_message_at DATETIME",
                "closeness_score REAL DEFAULT 0.18",
                "trust_score REAL DEFAULT 0.18",
                "openness_score REAL DEFAULT 0.12",
                "comfort_score REAL DEFAULT 0.14",
                "rhythm_score REAL DEFAULT 0.10",
                "topic_familiarity_score REAL DEFAULT 0.05",
                "total_sessions INTEGER DEFAULT 0",
                "total_messages INTEGER DEFAULT 0",
                "memory_count INTEGER DEFAULT 0",
                "current_stage TEXT DEFAULT 'new'",
                "proactive_enabled INTEGER DEFAULT 1",
                "proactive_cadence TEXT DEFAULT 'balanced'",
                "proactive_emotional_callbacks_enabled INTEGER DEFAULT 1",
                "proactive_last_sent_at DATETIME",
                "proactive_last_reason TEXT",
                "proactive_cooldown_until DATETIME",
                "created_at DATETIME DEFAULT CURRENT_TIMESTAMP",
                "updated_at DATETIME DEFAULT CURRENT_TIMESTAMP",
            ],
            "conversations": [
                "pair_id TEXT",
                "companion_id TEXT",
                "character_id TEXT DEFAULT 'nova'",
                "last_message_at DATETIME",
                "session_number INTEGER DEFAULT 1",
                "session_status TEXT DEFAULT 'active'",
                "emotional_arc TEXT",
                "topics_discussed TEXT",
                "session_summary TEXT",
                "summary TEXT",
            ],
            "messages": [
                "pair_id TEXT",
                "companion_id TEXT",
                "emotional_tone TEXT",
                "emotional_intensity REAL DEFAULT 0.0",
                "topics TEXT",
                "hour_of_day INTEGER",
                "day_of_week INTEGER",
                "client_sent_at DATETIME",
                "draft_duration_ms INTEGER",
                "reply_latency_ms INTEGER",
                "text_length INTEGER",
                "memory_extracted INTEGER DEFAULT 0",
                "parent_message_id INTEGER",
            ],
            "user_facts": [
                "pair_id TEXT",
                "companion_id TEXT",
                "source_message_id INTEGER",
                "source_type TEXT DEFAULT 'extracted'",
                "is_outdated INTEGER DEFAULT 0",
                "superseded_by_id INTEGER",
            ],
            "companion_facts": [
                "pair_id TEXT",
                "companion_id TEXT",
                "source_message_id INTEGER",
                "source_type TEXT DEFAULT 'extracted'",
                "is_outdated INTEGER DEFAULT 0",
                "superseded_by_id INTEGER",
            ],
            "entities": [
                "pair_id TEXT",
                "companion_id TEXT",
            ],
            "entity_relationships": [
                "pair_id TEXT",
                "companion_id TEXT",
            ],
            "behavioral_patterns": [
                "pair_id TEXT",
                "companion_id TEXT",
                "source TEXT DEFAULT 'detector'",
            ],
            "emotional_events": [
                "pair_id TEXT",
                "companion_id TEXT",
                "valence REAL DEFAULT 0.0",
            ],
            "narrative_summaries": [
                "pair_id TEXT",
                "companion_id TEXT",
            ],
            "memory_index": [
                "pair_id TEXT",
                "companion_id TEXT",
                "title TEXT",
                "content TEXT",
                "emotion_tag TEXT",
                "source_message_ids TEXT",
                "conversation_id TEXT",
                "archived INTEGER DEFAULT 0",
            ],
            "companion_life_events": [
                "pair_id TEXT",
                "companion_id TEXT",
                "event_description TEXT",
                "event_type TEXT",
                "occurred_at DATETIME DEFAULT CURRENT_TIMESTAMP",
                "is_resolved INTEGER DEFAULT 0",
                "context_injected INTEGER DEFAULT 0",
            ],
            "queued_notifications": [
                "id TEXT",
                "user_id TEXT",
                "pair_id TEXT",
                "companion_id TEXT",
                "sender_name TEXT",
                "message_preview TEXT",
                "timestamp DATETIME",
                "status TEXT",
                "retry_count INTEGER",
                "last_attempt_at DATETIME",
                "delivered_at DATETIME",
                "payload_json TEXT",
            ],
        }

        # Check and create queued_notifications table & indexes dynamically if missing
        if not self._table_exists("queued_notifications"):
            try:
                self.conn.execute("""
                    CREATE TABLE queued_notifications (
                        id                    TEXT PRIMARY KEY,
                        user_id               TEXT REFERENCES users(id) ON DELETE CASCADE,
                        pair_id               TEXT REFERENCES relationship_pairs(id) ON DELETE CASCADE,
                        companion_id          TEXT REFERENCES companions(id) ON DELETE CASCADE,
                        sender_name           TEXT,
                        message_preview       TEXT,
                        timestamp             DATETIME DEFAULT CURRENT_TIMESTAMP,
                        status                TEXT DEFAULT 'pending',
                        retry_count           INTEGER DEFAULT 0,
                        last_attempt_at       DATETIME,
                        delivered_at          DATETIME,
                        payload_json          TEXT
                    )
                """)
                logger.info("Created table queued_notifications dynamically")

            except Exception as e:
                logger.error("Failed to dynamically create queued_notifications table: %s", e)

        if self._table_exists("queued_notifications"):
            try:
                self.conn.execute("""
                    CREATE INDEX IF NOT EXISTS idx_queued_notifications_user_status
                    ON queued_notifications(user_id, status)
                """)
                self.conn.execute("""
                    CREATE INDEX IF NOT EXISTS idx_queued_notifications_timestamp
                    ON queued_notifications(timestamp DESC)
                """)
                logger.info("Ensured indexes for queued_notifications")
            except Exception as e:
                logger.error("Failed to dynamically create queued_notifications indexes: %s", e)

        for table, columns in required_columns.items():
            if not self._table_exists(table):
                continue
            existing = self._get_table_columns(table)
            for definition in columns:
                name = definition.split()[0]
                if name not in existing:
                    self.conn.execute(f"ALTER TABLE {table} ADD COLUMN {definition}")
                    logger.info("Added column %s.%s", table, name)

        # Backfill cadence migration to fix existing databases
        try:
            self.conn.execute(
                "UPDATE relationship_pairs SET proactive_cadence = 'gentle' WHERE proactive_cadence = 'light';"
            )
            logger.info("Migrated legacy 'light' proactive_cadence values to 'gentle'")
        except Exception as e:
            logger.error("Failed to migrate legacy proactive_cadence values: %s", e)

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

    def get_or_create_user(
        self,
        user_id: str,
        character_id: str = "nova",
        display_name: Optional[str] = None,
        email: Optional[str] = None,
    ) -> dict:
        row = self.conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()

        if row:
            self.conn.execute(
                """
                UPDATE users
                SET last_seen = ?,
                    character_id = COALESCE(character_id, ?),
                    display_name = COALESCE(?, display_name),
                    email = COALESCE(?, email)
                WHERE id = ?
                """,
                (_utcnow_iso(), character_id, display_name, email, user_id),
            )
            return dict(
                self.conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
            )

        now = _utcnow_iso()
        self.conn.execute(
            """
            INSERT INTO users
                (id, created_at, last_seen, character_id, total_sessions, total_messages,
                 display_name, email)
            VALUES (?, ?, ?, ?, 0, 0, ?, ?)
            """,
            (user_id, now, now, character_id, display_name, email),
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

    def save_onboarding_signals(
        self,
        user_id: str,
        preferred_name: str,
        signals: dict,
        onboarding_completed: int = 1,
    ):
        signals_json = json.dumps(signals)
        display_name = preferred_name
        self.conn.execute(
            """
            UPDATE users
            SET preferred_name = ?,
                name = COALESCE(name, ?),
                display_name = COALESCE(display_name, ?),
                onboarding_signals = ?,
                onboarding_completed = ?
            WHERE id = ?
            """,
            (preferred_name, preferred_name, display_name, signals_json, onboarding_completed, user_id),
        )

    def get_user(self, user_id: str) -> Optional[dict]:
        return self._row_to_dict(
            self.conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
        )

    def list_users(self, limit: int = 50) -> list[dict]:
        rows = self.conn.execute(
            """
            SELECT *
            FROM users
            ORDER BY last_seen DESC, created_at DESC
            LIMIT ?
            """,
            (limit,),
        ).fetchall()
        return [dict(row) for row in rows]

    def get_or_create_user_preferences(self, user_id: str) -> dict:
        now = _utcnow_iso()
        self.conn.execute(
            """
            INSERT INTO user_preferences
                (user_id, quiet_hours_start, quiet_hours_end, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(user_id) DO NOTHING
            """,
            (
                user_id,
                settings.PROACTIVE_DEFAULT_QUIET_HOURS_START,
                settings.PROACTIVE_DEFAULT_QUIET_HOURS_END,
                now,
                now,
            ),
        )
        row = self.conn.execute(
            "SELECT * FROM user_preferences WHERE user_id = ?",
            (user_id,),
        ).fetchone()
        return dict(row)

    def update_user_preferences(self, user_id: str, **updates) -> dict:
        self.get_or_create_user_preferences(user_id)
        allowed = {
            "allow_memory_storage",
            "show_memory_overview",
            "allow_proactive_messages",
            "allow_push_notifications",
            "quiet_hours_start",
            "quiet_hours_end",
            "allow_sensitive_proactive",
        }
        assignments = []
        values: list[Any] = []
        for key, value in updates.items():
            if key not in allowed or value is None:
                continue
            assignments.append(f"{key} = ?")
            values.append(value)

        if assignments:
            values.extend([_utcnow_iso(), user_id])
            self.conn.execute(
                f"""
                UPDATE user_preferences
                SET {", ".join(assignments)},
                    updated_at = ?
                WHERE user_id = ?
                """,
                values,
            )
        return self.get_or_create_user_preferences(user_id)

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

    def register_device_token(self, user_id: str, platform: str, push_token: str) -> dict:
        device_id = str(uuid.uuid5(uuid.NAMESPACE_URL, f"{user_id}:{platform}:{push_token}"))
        now = _utcnow_iso()
        self.conn.execute(
            """
            INSERT INTO device_registrations
                (id, user_id, platform, push_token, is_enabled, last_seen_at, created_at, updated_at)
            VALUES (?, ?, ?, ?, 1, ?, ?, ?)
            ON CONFLICT(user_id, push_token) DO UPDATE SET
                platform = excluded.platform,
                is_enabled = 1,
                last_seen_at = excluded.last_seen_at,
                updated_at = excluded.updated_at
            """,
            (device_id, user_id, platform, push_token, now, now, now),
        )
        row = self.conn.execute(
            """
            SELECT *
            FROM device_registrations
            WHERE user_id = ? AND push_token = ?
            LIMIT 1
            """,
            (user_id, push_token),
        ).fetchone()
        return dict(row)

    def list_device_tokens(self, user_id: str, enabled_only: bool = True) -> list[dict]:
        query = """
            SELECT *
            FROM device_registrations
            WHERE user_id = ?
        """
        params: list[Any] = [user_id]
        if enabled_only:
            query += " AND is_enabled = 1"
        query += " ORDER BY updated_at DESC"
        rows = self.conn.execute(query, params).fetchall()
        return [dict(row) for row in rows]

    def list_user_ids(self) -> list[str]:
        rows = self.conn.execute("SELECT id FROM users").fetchall()
        return [row["id"] for row in rows]

    # ------------------------------------------------------------------
    # Companion registry + relationship pairs
    # ------------------------------------------------------------------

    def upsert_companion(
        self,
        companion_id: str,
        name: str,
        archetype: Optional[str] = None,
        summary: Optional[str] = None,
        introduction_style: Optional[str] = None,
        relationship_label: str = "friend",
        match_weight: int = 1,
        sort_order: int = 0,
        proactive_frequency: str = "medium",
        impulsiveness: float = 0.5,
        attachment_speed: float = 0.5,
        boredom_threshold: float = 0.5,
        loneliness_tolerance: float = 0.5,
        emotional_openness: float = 0.5,
        social_confidence: float = 0.5,
        texting_consistency: float = 0.5,
        disappearance_tendency: float = 0.5,
        late_night_probability: float = 0.5,
        double_text_probability: float = 0.5,
        emotional_volatility: float = 0.5,
    ):
        now = _utcnow_iso()
        self.conn.execute(
            """
            INSERT INTO companions
                (id, name, status, archetype, summary, introduction_style, relationship_label,
                 match_weight, sort_order, proactive_frequency, impulsiveness, attachment_speed,
                 boredom_threshold, loneliness_tolerance, emotional_openness, social_confidence,
                 texting_consistency, disappearance_tendency, late_night_probability,
                 double_text_probability, emotional_volatility, created_at, updated_at)
            VALUES (?, ?, 'active', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                status = 'active',
                archetype = COALESCE(excluded.archetype, companions.archetype),
                summary = COALESCE(excluded.summary, companions.summary),
                introduction_style = COALESCE(excluded.introduction_style, companions.introduction_style),
                relationship_label = COALESCE(excluded.relationship_label, companions.relationship_label),
                match_weight = excluded.match_weight,
                sort_order = excluded.sort_order,
                proactive_frequency = excluded.proactive_frequency,
                impulsiveness = excluded.impulsiveness,
                attachment_speed = excluded.attachment_speed,
                boredom_threshold = excluded.boredom_threshold,
                loneliness_tolerance = excluded.loneliness_tolerance,
                emotional_openness = excluded.emotional_openness,
                social_confidence = excluded.social_confidence,
                texting_consistency = excluded.texting_consistency,
                disappearance_tendency = excluded.disappearance_tendency,
                late_night_probability = excluded.late_night_probability,
                double_text_probability = excluded.double_text_probability,
                emotional_volatility = excluded.emotional_volatility,
                updated_at = excluded.updated_at
            """,
            (
                companion_id,
                name,
                archetype,
                summary,
                introduction_style,
                relationship_label,
                max(1, int(match_weight)),
                sort_order,
                proactive_frequency,
                impulsiveness,
                attachment_speed,
                boredom_threshold,
                loneliness_tolerance,
                emotional_openness,
                social_confidence,
                texting_consistency,
                disappearance_tendency,
                late_night_probability,
                double_text_probability,
                emotional_volatility,
                now,
                now,
            ),
        )

    def get_companion(self, companion_id: str) -> Optional[dict]:
        return self._row_to_dict(
            self.conn.execute("SELECT * FROM companions WHERE id = ?", (companion_id,)).fetchone()
        )

    def list_companions(self) -> list[dict]:
        rows = self.conn.execute(
            "SELECT * FROM companions WHERE status = 'active' ORDER BY sort_order ASC, name ASC"
        ).fetchall()
        return [dict(row) for row in rows]

    def get_pair_by_id(self, pair_id: str) -> Optional[dict]:
        return self._row_to_dict(
            self.conn.execute("SELECT * FROM relationship_pairs WHERE id = ?", (pair_id,)).fetchone()
        )

    def get_pair(self, user_id: str, companion_id: str) -> Optional[dict]:
        return self._row_to_dict(
            self.conn.execute(
                """
                SELECT *
                FROM relationship_pairs
                WHERE user_id = ? AND companion_id = ?
                LIMIT 1
                """,
                (user_id, companion_id),
            ).fetchone()
        )

    def get_primary_pair(self, user_id: str) -> Optional[dict]:
        row = self.conn.execute(
            """
            SELECT *
            FROM relationship_pairs
            WHERE user_id = ? AND is_primary = 1
            ORDER BY updated_at DESC
            LIMIT 1
            """,
            (user_id,),
        ).fetchone()
        if row:
            return self._row_to_dict(row)
    # Fallback: return most recent pair but do NOT silently treat it as primary
        return self._row_to_dict(
            self.conn.execute(
                """
                SELECT *
                FROM relationship_pairs
                WHERE user_id = ?
                ORDER BY updated_at DESC
                LIMIT 1
                """,
                (user_id,),
            ).fetchone()
        )

    def list_pairs_for_user(self, user_id: str) -> list[dict]:
        rows = self.conn.execute(
            """
            SELECT *
            FROM relationship_pairs
            WHERE user_id = ?
            ORDER BY is_primary DESC, updated_at DESC
            """,
            (user_id,),
        ).fetchall()
        return [dict(row) for row in rows]

    def update_pair_proactive_settings(
        self,
        pair_id: str,
        *,
        proactive_enabled: Optional[bool] = None,
        proactive_cadence: Optional[str] = None,
        proactive_emotional_callbacks_enabled: Optional[bool] = None,
    ) -> Optional[dict]:
        assignments = []
        values: list[Any] = []
        if proactive_enabled is not None:
            assignments.append("proactive_enabled = ?")
            values.append(1 if proactive_enabled else 0)
        if proactive_cadence is not None:
            assignments.append("proactive_cadence = ?")
            values.append(proactive_cadence)
        if proactive_emotional_callbacks_enabled is not None:
            assignments.append("proactive_emotional_callbacks_enabled = ?")
            values.append(1 if proactive_emotional_callbacks_enabled else 0)

        if not assignments:
            return self.get_pair_by_id(pair_id)

        values.extend([_utcnow_iso(), pair_id])
        self.conn.execute(
            f"""
            UPDATE relationship_pairs
            SET {", ".join(assignments)},
                updated_at = ?
            WHERE id = ?
            """,
            values,
        )
        return self.get_pair_by_id(pair_id)

    def set_primary_pair(self, pair_id: str):
        pair = self.get_pair_by_id(pair_id)
        if not pair:
            return
        self.conn.execute(
            "UPDATE relationship_pairs SET is_primary = 0 WHERE user_id = ?",
            (pair["user_id"],),
        )
        self.conn.execute(
            "UPDATE relationship_pairs SET is_primary = 1, updated_at = ? WHERE id = ?",
            (_utcnow_iso(), pair_id),
        )
        self.conn.execute(
            "UPDATE users SET character_id = ?, relationship_label = COALESCE(relationship_label, ?) WHERE id = ?",
            (pair["companion_id"], pair.get("relationship_label") or "friend", pair["user_id"]),
        )

    def get_or_create_relationship_pair(
        self,
        user_id: str,
        companion_id: str,
        relationship_label: str = "friend",
        assignment_source: str = "matcher",
        assignment_reason: Optional[str] = None,
    ) -> dict:
        with self.transaction():
            pair = self.get_pair(user_id, companion_id)
            if pair:
                self.conn.execute(
                    """
                    UPDATE relationship_pairs
                    SET updated_at = ?,
                        relationship_label = COALESCE(?, relationship_label),
                        assignment_source = COALESCE(?, assignment_source),
                        assignment_reason = COALESCE(?, assignment_reason)
                    WHERE id = ?
                    """,
                    (_utcnow_iso(), relationship_label, assignment_source, assignment_reason, pair["id"]),
                )
                return dict(
                    self.conn.execute("SELECT * FROM relationship_pairs WHERE id = ?", (pair["id"],)).fetchone()
                )

            pair_id = make_pair_id(user_id, companion_id)
            now = _utcnow_iso()
            self.conn.execute(
                """
                INSERT INTO relationship_pairs
                    (id, user_id, companion_id, relationship_label, assignment_status,
                     assignment_source, assignment_reason, is_primary, created_at, updated_at)
                VALUES (?, ?, ?, ?, 'assigned', ?, ?, 0, ?, ?)
                """,
                (
                    pair_id,
                    user_id,
                    companion_id,
                    relationship_label,
                    assignment_source,
                    assignment_reason,
                    now,
                    now,
                ),
            )
            return dict(self.conn.execute("SELECT * FROM relationship_pairs WHERE id = ?", (pair_id,)).fetchone())

    def increment_pair_stats(self, pair_id: str, messages: int = 1, sessions: int = 0):
        self.conn.execute(
            """
            UPDATE relationship_pairs
            SET total_messages = total_messages + ?,
                total_sessions = total_sessions + ?,
                updated_at = ?,
                last_interaction_at = CASE
                    WHEN ? > 0 THEN ?
                    ELSE last_interaction_at
                END
            WHERE id = ?
            """,
            (messages, sessions, _utcnow_iso(), messages, _utcnow_iso(), pair_id),
        )

    def touch_pair_message(self, pair_id: str, role: str):
        now = _utcnow_iso()
        if role == "user":
            self.conn.execute(
                """
                UPDATE relationship_pairs
                SET last_user_message_at = ?, last_interaction_at = ?, updated_at = ?
                WHERE id = ?
                """,
                (now, now, now, pair_id),
            )
        else:
            self.conn.execute(
                """
                UPDATE relationship_pairs
                SET last_companion_message_at = ?, last_interaction_at = ?, updated_at = ?,
                    assignment_status = CASE
                        WHEN assignment_status IN ('assigned', 'introduced') THEN 'active'
                        ELSE assignment_status
                    END
                WHERE id = ?
                """,
                (now, now, now, pair_id),
            )

    # ------------------------------------------------------------------
    # Facts
    # ------------------------------------------------------------------

    def save_user_fact(
        self,
        user_id: str,
        pair_id: str,
        companion_id: str,
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
            WHERE pair_id = ? AND fact_key = ? AND is_outdated = 0
            ORDER BY updated_at DESC
            LIMIT 1
            """,
            (pair_id, key),
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
                (user_id, pair_id, companion_id, category, fact_key, fact_value, confidence,
                 source_message_id, source_type, created_at, updated_at, is_outdated)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
            """,
            (
                user_id,
                pair_id,
                companion_id,
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

    def get_user_facts(self, user_id: str, pair_id: Optional[str] = None) -> dict[str, str]:
        if not pair_id:
            primary = self.get_primary_pair(user_id)
            pair_id = primary["id"] if primary else None
        
        if pair_id:
            rows = self.conn.execute(
                """
                SELECT fact_key, fact_value
                FROM user_facts
                WHERE pair_id = ? AND is_outdated = 0
                ORDER BY updated_at DESC
                """,
                (pair_id,),
            ).fetchall()
            return {row["fact_key"]: row["fact_value"] for row in rows}
        return {}

    def get_user_fact_rows(self, user_id: str, pair_id: Optional[str] = None, limit: int = 12) -> list[dict]:
        if not pair_id:
            primary = self.get_primary_pair(user_id)
            pair_id = primary["id"] if primary else None

        if pair_id:
            rows = self.conn.execute(
                """
                SELECT *
                FROM user_facts
                WHERE pair_id = ? AND is_outdated = 0
                ORDER BY confidence DESC, updated_at DESC
                LIMIT ?
                """,
                (pair_id, limit),
            ).fetchall()
            return [dict(row) for row in rows]
        return []

    def update_user_fact_value(
        self,
        *,
        user_id: str,
        pair_id: str,
        fact_id: int,
        value: str,
    ) -> Optional[dict]:
        now = _utcnow_iso()
        row = self.conn.execute(
            """
            SELECT *
            FROM user_facts
            WHERE id = ? AND user_id = ? AND pair_id = ? AND is_outdated = 0
            LIMIT 1
            """,
            (fact_id, user_id, pair_id),
        ).fetchone()
        if not row:
            return None

        self.conn.execute(
            """
            UPDATE user_facts
            SET fact_value = ?,
                confidence = MAX(confidence, 0.96),
                source_type = 'user_corrected',
                updated_at = ?
            WHERE id = ?
            """,
            (value.strip(), now, fact_id),
        )
        updated = self.conn.execute(
            "SELECT * FROM user_facts WHERE id = ?",
            (fact_id,),
        ).fetchone()
        return dict(updated) if updated else None

    def get_fact_conflicts(self, pair_id: str, limit: int = 8) -> list[dict]:
        rows = self.conn.execute(
            """
            SELECT prior.fact_key,
                   active.fact_value AS current_value,
                   active.updated_at AS current_updated_at,
                   prior.fact_value AS previous_value,
                   prior.updated_at AS previous_updated_at,
                   active.confidence AS current_confidence,
                   prior.confidence AS previous_confidence
            FROM user_facts prior
            JOIN user_facts active
              ON active.id = prior.superseded_by_id
            WHERE prior.pair_id = ?
              AND prior.is_outdated = 1
              AND active.pair_id = ?
              AND active.is_outdated = 0
            ORDER BY active.updated_at DESC
            LIMIT ?
            """,
            (pair_id, pair_id, limit),
        ).fetchall()
        return [dict(row) for row in rows]

    def get_user_facts_by_category(
        self,
        user_id: str,
        category: str,
        pair_id: Optional[str] = None,
    ) -> dict[str, str]:
        if not pair_id:
            primary = self.get_primary_pair(user_id)
            pair_id = primary["id"] if primary else None

        if pair_id:
            rows = self.conn.execute(
                """
                SELECT fact_key, fact_value
                FROM user_facts
                WHERE pair_id = ? AND category = ? AND is_outdated = 0
                ORDER BY updated_at DESC
                """,
                (pair_id, category),
            ).fetchall()
            return {row["fact_key"]: row["fact_value"] for row in rows}
        return {}

    def save_companion_fact(
        self,
        user_id: str,
        pair_id: str,
        companion_id: str,
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
            SELECT * FROM companion_facts
            WHERE pair_id = ? AND fact_key = ? AND is_outdated = 0
            ORDER BY updated_at DESC
            LIMIT 1
            """,
            (pair_id, key),
        ).fetchone()

        if current:
            if current["fact_value"] == value:
                self.conn.execute(
                    """
                    UPDATE companion_facts
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
                "UPDATE companion_facts SET is_outdated = 1, updated_at = ? WHERE id = ?",
                (now, current["id"]),
            )

        cursor = self.conn.execute(
            """
            INSERT INTO companion_facts
                (user_id, pair_id, companion_id, category, fact_key, fact_value, confidence,
                 source_message_id, source_type, created_at, updated_at, is_outdated)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
            """,
            (
                user_id,
                pair_id,
                companion_id,
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
                "UPDATE companion_facts SET superseded_by_id = ? WHERE id = ?",
                (new_id, current["id"]),
            )

        return new_id

    def get_companion_facts(self, user_id: str, pair_id: Optional[str] = None) -> dict[str, str]:
        if pair_id:
            rows = self.conn.execute(
                """
                SELECT fact_key, fact_value
                FROM companion_facts
                WHERE pair_id = ? AND is_outdated = 0
                ORDER BY updated_at DESC
                """,
                (pair_id,),
            ).fetchall()
        else:
            rows = self.conn.execute(
                """
                SELECT fact_key, fact_value
                FROM companion_facts
                WHERE user_id = ? AND is_outdated = 0
                ORDER BY updated_at DESC
                """,
                (user_id,),
            ).fetchall()
        return {row["fact_key"]: row["fact_value"] for row in rows}

    # ------------------------------------------------------------------
    # Conversations
    # ------------------------------------------------------------------

    def create_conversation(self, user_id: str, pair_id: str, companion_id: str) -> str:
        with self.transaction():
            conv_id = str(uuid.uuid4())
            pair = self.get_pair_by_id(pair_id) or {}
            session_number = int(pair.get("total_sessions") or 0) + 1
            now = _utcnow_iso()
            self.conn.execute(
                """
                INSERT INTO conversations
                    (id, user_id, pair_id, companion_id, character_id, started_at,
                     last_message_at, session_number, session_status, message_count)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'active', 0)
                """,
                (conv_id, user_id, pair_id, companion_id, companion_id, now, now, session_number),
            )
            self.increment_user_stats(user_id, messages=0, sessions=1)
            self.increment_pair_stats(pair_id, messages=0, sessions=1)
            self.conn.execute(
                """
                UPDATE relationship_pairs
                SET first_session_at = COALESCE(first_session_at, ?),
                    last_session_started_at = ?,
                    assignment_status = CASE
                        WHEN assignment_status = 'assigned' THEN 'introduced'
                        ELSE assignment_status
                    END,
                    updated_at = ?
                WHERE id = ?
                """,
                (now, now, now, pair_id),
            )
            return conv_id

    def get_current_conversation(self, user_id: str, pair_id: Optional[str] = None) -> Optional[str]:
        if pair_id:
        # First look for an active (not ended) conversation
            row = self.conn.execute(
                """
                SELECT id
                FROM conversations
                WHERE user_id = ? AND pair_id = ? AND ended_at IS NULL
                ORDER BY started_at DESC
                LIMIT 1
                """,
                (user_id, pair_id),
            ).fetchone()
            if row:
                return row["id"]
            # Fallback: return most recent conversation even if closed,
            # so session/start can resume history rather than starting fresh
            row = self.conn.execute(
                """
                SELECT id
                FROM conversations
                WHERE user_id = ? AND pair_id = ?
                ORDER BY started_at DESC
                LIMIT 1
                """,
                (user_id, pair_id),
            ).fetchone()
            return row["id"] if row else None
        else:
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
            if row:
                return row["id"]
            row = self.conn.execute(
                """
                SELECT id
                FROM conversations
                WHERE user_id = ?
                ORDER BY started_at DESC
                LIMIT 1
                """,
                (user_id,),
            ).fetchone()
            return row["id"] if row else None

    def get_conversation(self, conversation_id: str) -> Optional[dict]:
        return self._row_to_dict(
            self.conn.execute("SELECT * FROM conversations WHERE id = ?", (conversation_id,)).fetchone()
        )

    def close_conversation(self, conversation_id: str):
        self.conn.execute(
            "UPDATE conversations SET ended_at = ?, session_status = 'closed' WHERE id = ?",
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

    def get_recent_conversation_summaries(
        self,
        pair_id: str,
        limit: int = 5,
    ) -> list[dict]:
        rows = self.conn.execute(
            """
            SELECT id, started_at, ended_at, emotional_arc, topics_discussed, session_summary
            FROM conversations
            WHERE pair_id = ?
              AND session_summary IS NOT NULL
              AND TRIM(session_summary) <> ''
            ORDER BY started_at DESC
            LIMIT ?
            """,
            (pair_id, limit),
        ).fetchall()
        summaries = []
        for row in rows:
            payload = dict(row)
            payload["topics_discussed"] = self._deserialize_topics(payload.get("topics_discussed"))
            summaries.append(payload)
        return summaries

    # ------------------------------------------------------------------
    # Messages
    # ------------------------------------------------------------------

    def save_message(
        self,
        conversation_id: str,
        user_id: str,
        pair_id: str,
        companion_id: str,
        role: str,
        content: str,
        emotional_tone: Optional[str] = None,
        emotional_intensity: float = 0.0,
        topics: Optional[list[str]] = None,
        client_sent_at: Optional[str] = None,
        draft_duration_ms: Optional[int] = None,
        reply_latency_ms: Optional[int] = None,
        parent_message_id: Optional[int] = None,
    ) -> int:
        with self.transaction():
            now = datetime.utcnow()
            text_length = len((content or "").strip())
            cursor = self.conn.execute(
                """
                INSERT INTO messages
                    (conversation_id, user_id, pair_id, companion_id, role, content, created_at,
                     emotional_tone, emotional_intensity, topics, hour_of_day, day_of_week,
                     client_sent_at, draft_duration_ms, reply_latency_ms, text_length, parent_message_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    conversation_id,
                    user_id,
                    pair_id,
                    companion_id,
                    role,
                    content,
                    now.isoformat(timespec="milliseconds"),
                    emotional_tone,
                    emotional_intensity,
                    json.dumps(topics or []),
                    now.hour,
                    _day_of_week(now),
                    client_sent_at,
                    draft_duration_ms,
                    reply_latency_ms,
                    text_length,
                    parent_message_id,
                ),
            )
            self.conn.execute(
                """
                UPDATE conversations
                SET message_count = message_count + 1,
                    last_message_at = ?
                WHERE id = ?
                """,
                (now.isoformat(timespec="milliseconds"), conversation_id),
            )
            self.increment_user_stats(user_id, messages=1)
            self.increment_pair_stats(pair_id, messages=1, sessions=0)
            self.touch_pair_message(pair_id, role)
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
        pair_id: Optional[str] = None,
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
                ORDER BY created_at DESC, id DESC
                LIMIT ?
                """,
                (conversation_id, n),
            ).fetchall()
        elif pair_id:
            rows = self.conn.execute(
                """
                SELECT *
                FROM messages
                WHERE pair_id = ?
                ORDER BY created_at DESC, id DESC
                LIMIT ?
                """,
                (pair_id, n),
            ).fetchall()
        else:
            rows = self.conn.execute(
                """
                SELECT *
                FROM messages
                WHERE user_id = ?
                ORDER BY created_at DESC, id DESC
                LIMIT ?
                """,
                (user_id, n),
            ).fetchall()

        return [self._normalize_message_row(row) for row in reversed(rows)]

    def get_message(self, message_id: int) -> Optional[dict]:
        row = self.conn.execute(
            "SELECT * FROM messages WHERE id = ? LIMIT 1",
            (message_id,),
        ).fetchone()
        return self._normalize_message_row(row) if row else None

    def get_latest_message_for_pair(self, pair_id: str) -> Optional[dict]:
        row = self.conn.execute(
            """
            SELECT *
            FROM messages
            WHERE pair_id = ?
            ORDER BY created_at DESC, id DESC
            LIMIT 1
            """,
            (pair_id,),
        ).fetchone()
        if not row:
            return None
        return self._normalize_message_row(row)

    def get_unextracted_messages(
        self,
        user_id: str,
        pair_id: Optional[str] = None,
        conversation_id: Optional[str] = None,
        limit: int = 20,
    ) -> list[dict]:
        if conversation_id:
            rows = self.conn.execute(
                """
                SELECT *
                FROM messages
                WHERE user_id = ? AND conversation_id = ? AND memory_extracted = 0
                ORDER BY created_at ASC, id ASC
                LIMIT ?
                """,
                (user_id, conversation_id, limit),
            ).fetchall()
        elif pair_id:
            rows = self.conn.execute(
                """
                SELECT *
                FROM messages
                WHERE pair_id = ? AND memory_extracted = 0
                ORDER BY created_at ASC, id ASC
                LIMIT ?
                """,
                (pair_id, limit),
            ).fetchall()
        else:
            rows = self.conn.execute(
                """
                SELECT *
                FROM messages
                WHERE user_id = ? AND memory_extracted = 0
                ORDER BY created_at ASC, id ASC
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
        pair_id: str,
        companion_id: str,
        name: str,
        entity_type: str,
        description: Optional[str] = None,
        relationship_to_user: Optional[str] = None,
        emotional_valence: Optional[float] = None,
    ) -> int:
        now = _utcnow_iso()
        existing = self.conn.execute(
            "SELECT * FROM entities WHERE pair_id = ? AND LOWER(name) = LOWER(?)",
            (pair_id, name),
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
                (user_id, pair_id, companion_id, name, type, description, relationship_to_user,
                 emotional_valence, first_mentioned_at, last_mentioned_at, mention_count)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
            """,
            (
                user_id,
                pair_id,
                companion_id,
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

    def get_entities_for_context(self, user_id: str, pair_id: Optional[str], query_text: str, limit: int = 6) -> list[dict]:
        rows = self.conn.execute(
            """
            SELECT *
            FROM entities
            WHERE pair_id = ?
            ORDER BY mention_count DESC, last_mentioned_at DESC
            LIMIT 25
            """,
            (pair_id or make_pair_id(user_id, settings.DEFAULT_CHARACTER),),
        ).fetchall()
        entities = [dict(row) for row in rows]
        lowered_query = query_text.lower()
        mentioned = [entity for entity in entities if entity["name"].lower() in lowered_query]
        remaining = [entity for entity in entities if entity["name"].lower() not in lowered_query]
        return (mentioned + remaining)[:limit]

    def save_entity_relationship(
        self,
        user_id: str,
        pair_id: str,
        companion_id: str,
        entity_a_id: int,
        entity_b_id: int,
        relationship_type: Optional[str],
        description: Optional[str],
    ):
        now = _utcnow_iso()
        self.conn.execute(
            """
            INSERT INTO entity_relationships
                (user_id, pair_id, companion_id, entity_a_id, entity_b_id, relationship_type, description, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(pair_id, entity_a_id, entity_b_id, relationship_type) DO UPDATE SET
                description = COALESCE(excluded.description, entity_relationships.description),
                updated_at = excluded.updated_at
            """,
            (user_id, pair_id, companion_id, entity_a_id, entity_b_id, relationship_type, description, now, now),
        )

    def get_relationships_for_entities(self, user_id: str, pair_id: str, entity_ids: list[int], limit: int = 6) -> list[dict]:
        if not entity_ids:
            return []
        placeholders = ",".join("?" for _ in entity_ids)
        params: list[Any] = [pair_id, *entity_ids, *entity_ids, limit]
        rows = self.conn.execute(
            f"""
            SELECT rel.*, a.name AS entity_a_name, b.name AS entity_b_name
            FROM entity_relationships rel
            JOIN entities a ON a.id = rel.entity_a_id
            JOIN entities b ON b.id = rel.entity_b_id
            WHERE rel.pair_id = ?
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
        pair_id: str,
        companion_id: str,
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
                (user_id, pair_id, companion_id, message_id, emotion, intensity, trigger_topic,
                 trigger_entity, valence, created_at, hour_of_day, day_of_week)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                user_id,
                pair_id,
                companion_id,
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
        return int(cursor.lastrowid)

    def get_recent_emotional_events(self, user_id: str, pair_id: Optional[str] = None, limit: int = 8) -> list[dict]:
        if pair_id:
            rows = self.conn.execute(
                """
                SELECT *
                FROM emotional_events
                WHERE pair_id = ?
                ORDER BY created_at DESC
                LIMIT ?
                """,
                (pair_id, limit),
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

    def get_emotional_summary(self, user_id: str, pair_id: Optional[str] = None, limit: int = 10) -> dict:
        events = self.get_recent_emotional_events(user_id, pair_id=pair_id, limit=limit)
        if not events:
            return {
                "baseline": None,
                "sample_size": 0,
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
            "baseline": round(sum(normalized) / len(normalized), 3),
            "sample_size": len(events),
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
        pair_id: str,
        companion_id: str,
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
            WHERE pair_id = ? AND pattern_type = ? AND description = ?
            LIMIT 1
            """,
            (pair_id, pattern_type, description),
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
                (user_id, pair_id, companion_id, pattern_type, description, evidence_count, confidence,
                 first_detected_at, last_seen_at, is_active, source)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                user_id,
                pair_id,
                companion_id,
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

    def get_active_patterns(self, user_id: str, pair_id: Optional[str] = None, limit: int = 5) -> list[dict]:
        if pair_id:
            rows = self.conn.execute(
                """
                SELECT *
                FROM behavioral_patterns
                WHERE pair_id = ? AND is_active = 1
                ORDER BY confidence DESC, evidence_count DESC, last_seen_at DESC
                LIMIT ?
                """,
                (pair_id, limit),
            ).fetchall()
        else:
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
        pair_id: str,
        companion_id: str,
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
                (user_id, pair_id, companion_id, period_start, period_end, summary, themes, emotional_direction, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                user_id,
                pair_id,
                companion_id,
                period_start,
                period_end,
                summary,
                json.dumps(themes or []),
                emotional_direction,
                created_at,
            ),
        )
        return int(cursor.lastrowid)

    def get_current_narrative(self, user_id: str, pair_id: Optional[str] = None) -> Optional[dict]:
        if not pair_id:
            primary = self.get_primary_pair(user_id)
            pair_id = primary["id"] if primary else None

        if pair_id:
            row = self.conn.execute(
                """
                SELECT *
                FROM narrative_summaries
                WHERE pair_id = ?
                ORDER BY created_at DESC
                LIMIT 1
                """,
                (pair_id,),
            ).fetchone()
            if not row:
                return None
            payload = dict(row)
            payload["themes"] = self._deserialize_topics(payload.get("themes"))
            return payload
        return None

    # ------------------------------------------------------------------
    # Episodic memory bookkeeping
    # ------------------------------------------------------------------

    def log_memory(
        self,
        chroma_id: str,
        user_id: str,
        pair_id: str,
        companion_id: str,
        content: str,
        title: Optional[str] = None,
        emotion_tag: Optional[str] = None,
        emotional_weight: float = 0.5,
        strength: float = 1.0,
        conversation_id: Optional[str] = None,
        source_message_ids: Optional[list[int]] = None,
    ):
        existing = self.conn.execute(
            "SELECT 1 FROM memory_index WHERE pair_id = ? AND chroma_id = ? LIMIT 1",
            (pair_id, chroma_id),
        ).fetchone()
        self.conn.execute(
            """
            INSERT INTO memory_index
                (user_id, pair_id, companion_id, chroma_id, title, content, emotion_tag, strength, emotional_weight,
                 created_at, source_message_ids, conversation_id, archived)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
            ON CONFLICT(pair_id, chroma_id) DO UPDATE SET
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
                pair_id,
                companion_id,
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
        if not existing:
            self.conn.execute(
                """
                UPDATE relationship_pairs
                SET memory_count = memory_count + 1,
                    updated_at = ?
                WHERE id = ?
                """,
                (_utcnow_iso(), pair_id),
            )

    def get_memory_metadata_map(self, pair_id: str, chroma_ids: list[str]) -> dict[str, dict]:
        if not chroma_ids:
            return {}
        placeholders = ",".join("?" for _ in chroma_ids)
        rows = self.conn.execute(
            f"""
            SELECT *
            FROM memory_index
            WHERE pair_id = ? AND chroma_id IN ({placeholders})
            """,
            [pair_id, *chroma_ids],
        ).fetchall()
        return {row["chroma_id"]: dict(row) for row in rows}

    def list_pair_memories(self, pair_id: str, limit: int = 40) -> list[dict]:
        rows = self.conn.execute(
            """
            SELECT *
            FROM memory_index
            WHERE pair_id = ?
            ORDER BY archived ASC, emotional_weight DESC, created_at DESC
            LIMIT ?
            """,
            (pair_id, limit),
        ).fetchall()
        payload = []
        for row in rows:
            item = dict(row)
            item["source_message_ids"] = self._deserialize_topics(item.get("source_message_ids"))
            payload.append(item)
        return payload

    def delete_memory_record(self, pair_id: str, chroma_id: str) -> bool:
        cursor = self.conn.execute(
            """
            DELETE FROM memory_index
            WHERE pair_id = ? AND chroma_id = ?
            """,
            (pair_id, chroma_id),
        )
        self._refresh_pair_memory_counts()
        return int(cursor.rowcount or 0) > 0

    def update_memory_record(
        self,
        *,
        pair_id: str,
        chroma_id: str,
        title: Optional[str] = None,
        content: Optional[str] = None,
    ) -> Optional[dict]:
        row = self.conn.execute(
            """
            SELECT *
            FROM memory_index
            WHERE pair_id = ? AND chroma_id = ?
            LIMIT 1
            """,
            (pair_id, chroma_id),
        ).fetchone()
        if not row:
            return None

        self.conn.execute(
            """
            UPDATE memory_index
            SET title = COALESCE(?, title),
                content = COALESCE(?, content),
                strength = MIN(strength + 0.08, 2.5)
            WHERE pair_id = ? AND chroma_id = ?
            """,
            (
                title.strip() if title is not None else None,
                content.strip() if content is not None else None,
                pair_id,
                chroma_id,
            ),
        )
        updated = self.conn.execute(
            "SELECT * FROM memory_index WHERE pair_id = ? AND chroma_id = ?",
            (pair_id, chroma_id),
        ).fetchone()
        return dict(updated) if updated else None

    def reinforce_memories(self, pair_id: str, chroma_ids: list[str]):
        if not chroma_ids:
            return
        placeholders = ",".join("?" for _ in chroma_ids)
        self.conn.execute(
            f"""
            UPDATE memory_index
            SET retrieval_count = retrieval_count + 1,
                last_retrieved_at = ?,
                strength = MIN(strength + 0.08, 2.5)
            WHERE pair_id = ? AND chroma_id IN ({placeholders})
            """,
            [_utcnow_iso(), pair_id, *chroma_ids],
        )

    def apply_memory_decay(self, pair_id: str) -> int:
        now = datetime.utcnow().isoformat(timespec="milliseconds")
        cursor = self.conn.execute(
            """
            UPDATE memory_index
            SET strength = MAX(
                    0.18,
                    strength - CASE
                        WHEN retrieval_count >= 6 THEN 0.01
                        WHEN retrieval_count >= 3 THEN 0.025
                        WHEN last_retrieved_at IS NOT NULL THEN 0.045
                        ELSE 0.065
                    END
                ),
                archived = CASE
                    WHEN archived = 1 THEN 1
                    WHEN strength <= 0.24 AND retrieval_count = 0 THEN 1
                    ELSE 0
                END,
                last_retrieved_at = COALESCE(last_retrieved_at, ?)
            WHERE pair_id = ?
              AND archived = 0
              AND julianday('now') - julianday(created_at) >= 3
            """,
            (now, pair_id),
        )
        self._refresh_pair_memory_counts()
        return int(cursor.rowcount or 0)

    def get_relationship_state_snapshot(self, pair_id: str) -> Optional[dict]:
        pair = self.get_pair_by_id(pair_id)
        if not pair:
            return None
        return {
            "closeness": round(float(pair.get("closeness_score") or 0.0), 3),
            "trust": round(float(pair.get("trust_score") or 0.0), 3),
            "openness": round(float(pair.get("openness_score") or 0.0), 3),
            "comfort": round(float(pair.get("comfort_score") or 0.0), 3),
            "rhythm": round(float(pair.get("rhythm_score") or 0.0), 3),
            "topic_familiarity": round(float(pair.get("topic_familiarity_score") or 0.0), 3),
            "stage": pair.get("current_stage") or "new",
            "sessions": int(pair.get("total_sessions") or 0),
            "messages": int(pair.get("total_messages") or 0),
        }

    def save_companion_life_event(
        self,
        event_id: str,
        pair_id: str,
        companion_id: str,
        event_description: str,
        event_type: str,
        is_resolved: int = 0,
        context_injected: int = 0,
    ) -> None:
        self.conn.execute(
            """
            INSERT INTO companion_life_events (id, pair_id, companion_id, event_description, event_type, is_resolved, context_injected)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (event_id, pair_id, companion_id, event_description, event_type, is_resolved, context_injected),
        )

    def get_latest_unresolved_life_event(self, pair_id: str) -> Optional[dict]:
        row = self.conn.execute(
            """
            SELECT * FROM companion_life_events
            WHERE pair_id = ? AND is_resolved = 0
            ORDER BY occurred_at DESC LIMIT 1
            """,
            (pair_id,),
        ).fetchone()
        return self._row_to_dict(row)

    def mark_life_event_injected(self, event_id: str) -> None:
        self.conn.execute(
            "UPDATE companion_life_events SET context_injected = 1 WHERE id = ?",
            (event_id,),
        )

    def mark_life_event_resolved(self, event_id: str) -> None:
        self.conn.execute(
            "UPDATE companion_life_events SET is_resolved = 1, context_injected = 1 WHERE id = ?",
            (event_id,),
        )

    def reset_pair_memory(self, pair_id: str) -> dict[str, int]:
        with self.transaction():
            counts = {}
            for table_name in (
                "user_facts",
                "companion_facts",
                "entities",
                "entity_relationships",
                "emotional_events",
                "behavioral_patterns",
                "narrative_summaries",
                "memory_index",
                "proactive_events",
                "companion_life_events",
            ):
                cursor = self.conn.execute(
                    f"DELETE FROM {table_name} WHERE pair_id = ?",
                    (pair_id,),
                )
                counts[table_name] = int(cursor.rowcount or 0)

            self.conn.execute(
                """
                UPDATE relationship_pairs
                SET closeness_score = 0.18,
                    trust_score = 0.18,
                    openness_score = 0.12,
                    comfort_score = 0.14,
                    rhythm_score = 0.10,
                    topic_familiarity_score = 0.05,
                    memory_count = 0,
                    current_stage = 'new',
                    proactive_last_sent_at = NULL,
                    proactive_last_reason = NULL,
                    proactive_cooldown_until = NULL,
                    updated_at = ?
                WHERE id = ?
                """,
                (_utcnow_iso(), pair_id),
            )
            return counts

    def delete_user_account(self, user_id: str) -> dict[str, int]:
        with self.transaction():
            rows = self.conn.execute(
                "SELECT id FROM relationship_pairs WHERE user_id = ?",
                (user_id,),
            ).fetchall()
            pair_ids = [row["id"] for row in rows]
            for pair_id in pair_ids:
                self.reset_pair_memory(pair_id)

            counts = {}
            for table_name in ("device_registrations", "user_preferences", "system_events"):
                cursor = self.conn.execute(
                    f"DELETE FROM {table_name} WHERE user_id = ?",
                    (user_id,),
                )
                counts[table_name] = int(cursor.rowcount or 0)

            cursor = self.conn.execute("DELETE FROM users WHERE id = ?", (user_id,))
            counts["users"] = int(cursor.rowcount or 0)
            return counts

    def log_proactive_event(
        self,
        *,
        event_id: str,
        user_id: str,
        pair_id: str,
        companion_id: str,
        conversation_id: Optional[str],
        reason: Optional[str],
        message_text: str,
        payload_json: str,
        notification_status: str = "not_attempted",
        status: str = "pending",
        scheduled_for: Optional[str] = None,
    ) -> None:
        scheduled_at = scheduled_for or _utcnow_iso()
        self.conn.execute(
            """
            INSERT INTO proactive_events
                (id, user_id, pair_id, companion_id, conversation_id, reason, status,
                 message_text, payload_json, notification_status, scheduled_for, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                event_id,
                user_id,
                pair_id,
                companion_id,
                conversation_id,
                reason,
                status,
                message_text,
                payload_json,
                notification_status,
                scheduled_at,
                _utcnow_iso(),
            ),
        )

    def list_pending_proactive_events(
        self,
        user_id: str,
        pair_id: Optional[str] = None,
        *,
        due_only: bool = True,
    ) -> list[dict]:
        due_clause = "AND datetime(COALESCE(scheduled_for, created_at)) <= datetime(?)" if due_only else ""
        now = _utcnow_iso()
        if pair_id:
            rows = self.conn.execute(
                f"""
                SELECT *
                FROM proactive_events
                WHERE user_id = ? AND pair_id = ? AND status = 'pending'
                {due_clause}
                ORDER BY scheduled_for ASC, created_at ASC
                """,
                (user_id, pair_id, now) if due_only else (user_id, pair_id),
            ).fetchall()
        else:
            rows = self.conn.execute(
                f"""
                SELECT *
                FROM proactive_events
                WHERE user_id = ? AND status = 'pending'
                {due_clause}
                ORDER BY scheduled_for ASC, created_at ASC
                """,
                (user_id, now) if due_only else (user_id,),
            ).fetchall()
        return [dict(row) for row in rows]

    def has_pending_proactive_event(self, user_id: str, pair_id: str) -> bool:
        row = self.conn.execute(
            """
            SELECT 1
            FROM proactive_events
            WHERE user_id = ? AND pair_id = ? AND status = 'pending'
            LIMIT 1
            """,
            (user_id, pair_id),
        ).fetchone()
        return row is not None

    def get_pending_proactive_counts(self, user_id: str) -> dict[str, int]:
        rows = self.conn.execute(
            """
            SELECT pair_id, COUNT(*) AS pending_count
            FROM proactive_events
            WHERE user_id = ?
              AND status = 'pending'
              AND datetime(COALESCE(scheduled_for, created_at)) <= datetime(?)
            GROUP BY pair_id
            """,
            (user_id, _utcnow_iso()),
        ).fetchall()
        return {
            str(row["pair_id"]): int(row["pending_count"] or 0)
            for row in rows
            if row["pair_id"]
        }

    def mark_proactive_events_delivered(self, event_ids: list[str]) -> None:
        if not event_ids:
            return
        placeholders = ",".join("?" for _ in event_ids)
        self.conn.execute(
            f"""
            UPDATE proactive_events
            SET status = 'delivered',
                delivered_at = COALESCE(delivered_at, ?)
            WHERE id IN ({placeholders})
            """,
            [_utcnow_iso(), *event_ids],
        )

    def mark_proactive_notification_status(
        self,
        event_id: str,
        notification_status: str,
    ) -> Optional[dict]:
        self.conn.execute(
            """
            UPDATE proactive_events
            SET notification_status = ?
            WHERE id = ?
            """,
            (notification_status, event_id),
        )
        row = self.conn.execute(
            "SELECT * FROM proactive_events WHERE id = ?",
            (event_id,),
        ).fetchone()
        return dict(row) if row else None

    def touch_pair_proactive(
        self,
        pair_id: str,
        reason: Optional[str],
        cooldown_until: Optional[str] = None,
    ) -> None:
        sent_at = _utcnow_iso()
        self.conn.execute(
            """
            UPDATE relationship_pairs
            SET proactive_last_sent_at = ?,
                proactive_last_reason = ?,
                proactive_cooldown_until = ?,
                updated_at = ?
            WHERE id = ?
            """,
            (sent_at, reason, cooldown_until or sent_at, _utcnow_iso(), pair_id),
        )

    def log_system_event(
        self,
        kind: str,
        severity: str = "info",
        *,
        user_id: Optional[str] = None,
        pair_id: Optional[str] = None,
        conversation_id: Optional[str] = None,
        payload: Optional[dict] = None,
    ) -> int:
        cursor = self.conn.execute(
            """
            INSERT INTO system_events
                (kind, severity, user_id, pair_id, conversation_id, payload_json, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                kind,
                severity,
                user_id,
                pair_id,
                conversation_id,
                json.dumps(payload or {}),
                _utcnow_iso(),
            ),
        )
        return int(cursor.lastrowid)

    def list_system_events(
        self,
        limit: int = 100,
        kind: Optional[str] = None,
        severity: Optional[str] = None,
    ) -> list[dict]:
        query = """
            SELECT *
            FROM system_events
            WHERE 1 = 1
        """
        params: list[Any] = []
        if kind:
            query += " AND kind = ?"
            params.append(kind)
        if severity:
            query += " AND severity = ?"
            params.append(severity)
        query += " ORDER BY created_at DESC LIMIT ?"
        params.append(limit)
        rows = self.conn.execute(query, params).fetchall()
        payload = []
        for row in rows:
            item = dict(row)
            try:
                item["payload"] = json.loads(item.get("payload_json") or "{}")
            except json.JSONDecodeError:
                item["payload"] = {}
            payload.append(item)
        return payload

    def get_recent_memory_rows(
        self,
        user_id: str,
        pair_id: Optional[str] = None,
        limit: int = 8,
        since: Optional[str] = None,
    ) -> list[dict]:
        if pair_id and since:
            rows = self.conn.execute(
                """
                SELECT *
                FROM memory_index
                WHERE pair_id = ? AND archived = 0 AND created_at >= ?
                ORDER BY created_at DESC, emotional_weight DESC
                LIMIT ?
                """,
                (pair_id, since, limit),
            ).fetchall()
        elif pair_id:
            rows = self.conn.execute(
                """
                SELECT *
                FROM memory_index
                WHERE pair_id = ? AND archived = 0
                ORDER BY created_at DESC, emotional_weight DESC
                LIMIT ?
                """,
                (pair_id, limit),
            ).fetchall()
        elif since:
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

    def get_recent_emotions_since(
        self,
        user_id: str,
        since: Optional[str],
        pair_id: Optional[str] = None,
        limit: int = 10,
    ) -> list[dict]:
        if pair_id and since:
            rows = self.conn.execute(
                """
                SELECT *
                FROM emotional_events
                WHERE pair_id = ? AND created_at >= ?
                ORDER BY created_at DESC
                LIMIT ?
                """,
                (pair_id, since, limit),
            ).fetchall()
        elif pair_id:
            rows = self.conn.execute(
                """
                SELECT *
                FROM emotional_events
                WHERE pair_id = ?
                ORDER BY created_at DESC
                LIMIT ?
                """,
                (pair_id, limit),
            ).fetchall()
        elif since:
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

    # ------------------------------------------------------------------
    # Notification queue operations
    # ------------------------------------------------------------------

    def queue_notification(
        self,
        user_id: str,
        pair_id: str,
        companion_id: str,
        sender_name: str,
        message_preview: str,
        payload_dict: dict,
    ) -> dict:
        notification_id = str(uuid.uuid4())
        now = _utcnow_iso()
        payload_json = json.dumps(payload_dict or {})
        self.conn.execute(
            """
            INSERT INTO queued_notifications (
                id, user_id, pair_id, companion_id, sender_name, message_preview,
                timestamp, status, retry_count, payload_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', 0, ?)
            """,
            (
                notification_id,
                user_id,
                pair_id,
                companion_id,
                sender_name,
                message_preview,
                now,
                payload_json,
            ),
        )
        logger.info("Queued notification: %s", notification_id)
        row = self.conn.execute(
            "SELECT * FROM queued_notifications WHERE id = ?",
            (notification_id,),
        ).fetchone()
        return dict(row)

    def get_notification(self, notification_id: str) -> Optional[dict]:
        row = self.conn.execute(
            "SELECT * FROM queued_notifications WHERE id = ?",
            (notification_id,),
        ).fetchone()
        return dict(row) if row else None

    def get_recent_queued_notification_for_pair(
        self,
        pair_id: str,
        *,
        exclude_id: Optional[str] = None,
        within_seconds: int = 15,
    ) -> Optional[dict]:
        since = (datetime.utcnow() - timedelta(seconds=within_seconds)).isoformat(timespec="milliseconds")
        params: list[Any] = [pair_id, since]
        query = """
            SELECT *
            FROM queued_notifications
            WHERE pair_id = ?
              AND datetime(timestamp) >= datetime(?)
              AND status IN ('pending', 'sent', 'failed')
        """
        if exclude_id:
            query += " AND id != ?"
            params.append(exclude_id)
        query += " ORDER BY timestamp DESC LIMIT 1"
        row = self.conn.execute(query, params).fetchone()
        return dict(row) if row else None

    def update_queued_notification_payload(
        self,
        notification_id: str,
        *,
        message_preview: str,
        payload_dict: dict,
    ) -> Optional[dict]:
        self.conn.execute(
            """
            UPDATE queued_notifications
            SET message_preview = ?,
                payload_json = ?
            WHERE id = ?
            """,
            (message_preview, json.dumps(payload_dict or {}), notification_id),
        )
        return self.get_notification(notification_id)

    def get_pending_notifications(self, limit: int = 20) -> list[dict]:
        rows = self.conn.execute(
            """
            SELECT *
            FROM queued_notifications
            WHERE status IN ('pending', 'failed') AND retry_count < 3
            ORDER BY timestamp ASC
            LIMIT ?
            """,
            (limit,),
        ).fetchall()
        return [dict(row) for row in rows]

    def mark_notification_status(
        self,
        notification_id: str,
        status: str,
        error_message: Optional[str] = None,
    ) -> Optional[dict]:
        now = _utcnow_iso()
        if status == "delivered":
            self.conn.execute(
                """
                UPDATE queued_notifications
                SET status = ?,
                    retry_count = retry_count + 1,
                    last_attempt_at = ?,
                    delivered_at = ?
                WHERE id = ?
                """,
                (status, now, now, notification_id),
            )
        else:
            self.conn.execute(
                """
                UPDATE queued_notifications
                SET status = ?,
                    retry_count = retry_count + 1,
                    last_attempt_at = ?
                WHERE id = ?
                """,
                (status, now, notification_id),
            )
        logger.info(
            "Notification %s status updated to %s (error_message=%s)",
            notification_id,
            status,
            error_message,
        )
        row = self.conn.execute(
            "SELECT * FROM queued_notifications WHERE id = ?",
            (notification_id,),
        ).fetchone()
        return dict(row) if row else None

    def confirm_notification_delivery(self, notification_id: str) -> Optional[dict]:
        now = _utcnow_iso()
        self.conn.execute(
            """
            UPDATE queued_notifications
            SET status = 'delivered',
                delivered_at = ?
            WHERE id = ?
            """,
            (now, notification_id),
        )
        logger.info("Notification %s delivery confirmed", notification_id)
        row = self.conn.execute(
            "SELECT * FROM queued_notifications WHERE id = ?",
            (notification_id,),
        ).fetchone()
        return dict(row) if row else None


db = Database()
