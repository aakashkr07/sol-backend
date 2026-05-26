-- =============================================================================
-- SOL memory system master schema
-- =============================================================================
-- This schema keeps the original MVP metadata that the app already depends on
-- while adding the layered memory tables needed for richer recall.

PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;


-- =============================================================================
-- USERS
-- =============================================================================
CREATE TABLE IF NOT EXISTS users (
    id                    TEXT PRIMARY KEY,
    display_name          TEXT,
    email                 TEXT,
    created_at            DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_seen             DATETIME DEFAULT CURRENT_TIMESTAMP,

    name                  TEXT,
    preferred_name        TEXT,
    age                   INTEGER,
    location              TEXT,
    timezone              TEXT,
    character_id          TEXT DEFAULT 'nova',
    relationship_label    TEXT DEFAULT 'friend',

    total_sessions        INTEGER DEFAULT 0,
    total_messages        INTEGER DEFAULT 0,

    emotional_baseline    REAL DEFAULT 0.5,
    baseline_sample_size  INTEGER DEFAULT 0,

    current_narrative     TEXT,
    narrative_updated_at  DATETIME
);


-- =============================================================================
-- CONVERSATIONS
-- =============================================================================
CREATE TABLE IF NOT EXISTS conversations (
    id                    TEXT PRIMARY KEY,
    user_id               TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    character_id          TEXT NOT NULL DEFAULT 'nova',
    started_at            DATETIME DEFAULT CURRENT_TIMESTAMP,
    ended_at              DATETIME,
    message_count         INTEGER DEFAULT 0,
    emotional_arc         TEXT,
    topics_discussed      TEXT,
    session_summary       TEXT,
    summary               TEXT
);


-- =============================================================================
-- MESSAGES
-- =============================================================================
CREATE TABLE IF NOT EXISTS messages (
    id                    INTEGER PRIMARY KEY AUTOINCREMENT,
    conversation_id       TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id               TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role                  TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
    content               TEXT NOT NULL,
    created_at            DATETIME DEFAULT CURRENT_TIMESTAMP,
    emotional_tone        TEXT,
    emotional_intensity   REAL DEFAULT 0.0,
    topics                TEXT,
    hour_of_day           INTEGER,
    day_of_week           INTEGER,
    memory_extracted      INTEGER DEFAULT 0
);


-- =============================================================================
-- USER FACTS
-- =============================================================================
CREATE TABLE IF NOT EXISTS user_facts (
    id                    INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id               TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    category              TEXT NOT NULL,
    fact_key              TEXT NOT NULL,
    fact_value            TEXT NOT NULL,
    confidence            REAL DEFAULT 1.0,
    source_message_id     INTEGER REFERENCES messages(id),
    source_type           TEXT DEFAULT 'extracted',
    created_at            DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at            DATETIME DEFAULT CURRENT_TIMESTAMP,
    is_outdated           INTEGER DEFAULT 0,
    superseded_by_id      INTEGER REFERENCES user_facts(id)
);


-- =============================================================================
-- ENTITIES
-- =============================================================================
CREATE TABLE IF NOT EXISTS entities (
    id                    INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id               TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name                  TEXT NOT NULL,
    type                  TEXT NOT NULL CHECK(type IN (
                              'person',
                              'place',
                              'organization',
                              'concept',
                              'event'
                          )),
    description           TEXT,
    relationship_to_user  TEXT,
    emotional_valence     REAL DEFAULT 0.0,
    first_mentioned_at    DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_mentioned_at     DATETIME DEFAULT CURRENT_TIMESTAMP,
    mention_count         INTEGER DEFAULT 1,
    UNIQUE(user_id, name)
);


-- =============================================================================
-- ENTITY RELATIONSHIPS
-- =============================================================================
CREATE TABLE IF NOT EXISTS entity_relationships (
    id                    INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id               TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    entity_a_id           INTEGER NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
    entity_b_id           INTEGER NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
    relationship_type     TEXT,
    description           TEXT,
    created_at            DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at            DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, entity_a_id, entity_b_id, relationship_type)
);


-- =============================================================================
-- EMOTIONAL EVENTS
-- =============================================================================
CREATE TABLE IF NOT EXISTS emotional_events (
    id                    INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id               TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    message_id            INTEGER REFERENCES messages(id),
    emotion               TEXT NOT NULL,
    intensity             REAL NOT NULL DEFAULT 0.5,
    trigger_topic         TEXT,
    trigger_entity        TEXT,
    valence               REAL DEFAULT 0.0,
    created_at            DATETIME DEFAULT CURRENT_TIMESTAMP,
    hour_of_day           INTEGER,
    day_of_week           INTEGER
);


-- =============================================================================
-- BEHAVIORAL PATTERNS
-- =============================================================================
CREATE TABLE IF NOT EXISTS behavioral_patterns (
    id                    INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id               TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    pattern_type          TEXT NOT NULL,
    description           TEXT NOT NULL,
    evidence_count        INTEGER DEFAULT 1,
    confidence            REAL DEFAULT 0.5,
    first_detected_at     DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_seen_at          DATETIME DEFAULT CURRENT_TIMESTAMP,
    is_active             INTEGER DEFAULT 1,
    source                TEXT DEFAULT 'detector',
    UNIQUE(user_id, pattern_type, description)
);


-- =============================================================================
-- NARRATIVE SUMMARIES
-- =============================================================================
CREATE TABLE IF NOT EXISTS narrative_summaries (
    id                    INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id               TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    period_start          DATETIME,
    period_end            DATETIME,
    summary               TEXT NOT NULL,
    themes                TEXT,
    emotional_direction   TEXT,
    created_at            DATETIME DEFAULT CURRENT_TIMESTAMP
);


-- =============================================================================
-- MEMORY INDEX
-- =============================================================================
CREATE TABLE IF NOT EXISTS memory_index (
    id                    INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id               TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    chroma_id             TEXT NOT NULL,
    title                 TEXT,
    content               TEXT,
    emotion_tag           TEXT,
    strength              REAL DEFAULT 1.0,
    emotional_weight      REAL DEFAULT 0.5,
    created_at            DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_retrieved_at     DATETIME,
    retrieval_count       INTEGER DEFAULT 0,
    source_message_ids    TEXT,
    conversation_id       TEXT REFERENCES conversations(id),
    archived              INTEGER DEFAULT 0,
    UNIQUE(user_id, chroma_id)
);


-- =============================================================================
-- INDEXES
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_messages_user_created
    ON messages(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_messages_conv
    ON messages(conversation_id, created_at ASC);

CREATE INDEX IF NOT EXISTS idx_messages_user_unextracted
    ON messages(user_id, memory_extracted, created_at ASC);

CREATE INDEX IF NOT EXISTS idx_facts_user_key
    ON user_facts(user_id, fact_key, is_outdated);

CREATE INDEX IF NOT EXISTS idx_facts_category
    ON user_facts(user_id, category, is_outdated);

CREATE UNIQUE INDEX IF NOT EXISTS idx_user_facts_active_unique
    ON user_facts(user_id, fact_key)
    WHERE is_outdated = 0;

CREATE INDEX IF NOT EXISTS idx_entities_user_name
    ON entities(user_id, name);

CREATE INDEX IF NOT EXISTS idx_entities_mention_count
    ON entities(user_id, mention_count DESC, last_mentioned_at DESC);

CREATE INDEX IF NOT EXISTS idx_relationships_user_entities
    ON entity_relationships(user_id, entity_a_id, entity_b_id);

CREATE INDEX IF NOT EXISTS idx_emotional_user_created
    ON emotional_events(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_emotional_user_dayofweek
    ON emotional_events(user_id, day_of_week, hour_of_day);

CREATE INDEX IF NOT EXISTS idx_patterns_user_active
    ON behavioral_patterns(user_id, is_active, confidence DESC);

CREATE INDEX IF NOT EXISTS idx_narrative_user_created
    ON narrative_summaries(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_memory_index_user
    ON memory_index(user_id, archived, strength DESC, created_at DESC);
