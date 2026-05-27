# Sol Master Project Source Of Truth

This document is the canonical high-level map of the `sol_mvp` repository as it exists today.

It is intended to answer:

- what Sol is
- how the system is structured
- what technologies are used
- how the frontend and backend connect
- how auth, chat, memory, onboarding, inbox, and proactive systems work
- what the database stores
- where the characters live
- what every authored project file is for
- which directories are source, generated output, or local runtime state

It is not a replacement for reading the code, but it should make the codebase navigable enough that future work starts from shared understanding instead of rediscovery.

## 1. Project Identity

Sol is a relationship-first AI messaging product. The current repo already implements:

- Firebase sign-in
- FastAPI backend orchestration
- pair-scoped relationship identity
- long-term memory extraction and retrieval
- multiple character personalities
- inbox-first messaging UX
- proactive message surfacing
- privacy/presence settings
- relationship progression state

The current architecture is designed around one core product principle:

> the trust boundary is not the user alone, and not the companion alone, but the user-companion pair

That is the reason `pair_id` is central across messages, facts, emotional events, patterns, memories, narratives, and proactive behavior.

## 2. Top-Level Repository Layout

Root directories:

- `backend/`
  - FastAPI API, auth verification, memory systems, database, personality system, proactive logic, deployment config
- `frontend/companion_app/`
  - Flutter client for login, onboarding, inbox, chat, profile/privacy, and notification hooks

Root files:

- `.env`
  - local root environment file; currently used by backend config loader if present
- `.gitignore`
  - excludes secrets, Python caches, local DB files, Chroma data, Flutter build output, IDE files
- `README.md`
  - concise repo-level overview and setup notes
- `MASTER_PROJECT_SOURCE_OF_TRUTH.md`
  - this file

## 3. Current System Architecture

At a high level, the system is:

1. Flutter app authenticates user with Google via Firebase Auth.
2. Flutter gets a Firebase ID token from the signed-in user.
3. Flutter calls FastAPI with `Authorization: Bearer <firebase_token>`.
4. FastAPI verifies the token using Firebase Admin SDK.
5. Backend resolves or creates the correct `relationship_pair` for the user and companion.
6. Backend loads contextual memory and relationship state.
7. Backend builds a system prompt from the character asset plus memory layers.
8. Backend calls Groq for response generation.
9. Backend splits the raw reply into burst segments for text-message realism.
10. Backend stores user and assistant messages in SQLite.
11. Background extraction writes facts, entities, emotions, patterns, and episodic memories.
12. Chroma stores semantic episodic memories for later retrieval.
13. Inbox and proactive systems surface continuity back into the client.

## 4. Core Concepts And Identifiers

The important ids are:

- `user_id`
  - Firebase UID; account identity
- `companion_id`
  - one personality identity such as `nova` or `atlas`
- `pair_id`
  - canonical relationship identity; currently formed as `user_id::companion_id`
- `conversation_id`
  - one chat session inside a pair
- `message.id`
  - one row in the messages table
- `memory_index.chroma_id`
  - pointer to the Chroma memory object

Important product distinction:

- A `user` is an account.
- A `companion` is a personality asset.
- A `relationship_pair` is the emotional relationship object.
- A `conversation` is one session thread within that pair.

## 5. Technology Stack

### Backend

- Python
- FastAPI
- Uvicorn
- Pydantic
- Firebase Admin SDK
- SQLite
- ChromaDB
- Groq API via `httpx`
- dotenv for config loading

### Frontend

- Flutter
- Dart
- Firebase Core
- Firebase Auth
- Firebase Messaging
- Google Sign-In
- Shared Preferences
- `http`
- Google Fonts

### Deployment / Infra Shape

- Railway for backend hosting
- Firebase for auth and mobile notification integration
- SQLite + Chroma persisted via mounted disk/volume in production

## 6. Runtime Boundary Map

### What is durable user data

- SQLite database at `backend/db/companion.db` locally, or `/data/db/companion.db` in Railway when configured
- Chroma vector store at `backend/chroma_db/` locally, or `/data/chroma_db` in Railway when configured

### What is generated or disposable

- Python virtualenv folders: `backend/.venv/`, `backend/venv/`
- Flutter build output: `frontend/companion_app/build/`
- Flutter tooling cache: `frontend/companion_app/.dart_tool/`
- IDE metadata: `.idea/`, `*.iml`
- SQLite WAL/shm files

These are not product logic and should not be treated as source of truth.

## 7. User Experience Flow

### Auth flow

1. App launches.
2. Firebase initializes.
3. `_AuthGate` listens to `FirebaseAuth.instance.authStateChanges()`.
4. If signed out, app shows `LoginScreen`.
5. If signed in, local onboarding completion is checked per user id.
6. If onboarding is incomplete, app shows `OnboardingScreen`.
7. If onboarding is complete, app shows `InboxScreen`.

### First-run onboarding flow

1. App loads roster from backend.
2. Backend resolves or creates a primary pair.
3. Frontend presents the matched companion as a message encounter rather than a setup wizard.
4. User taps the CTA to open messages.
5. Backend starts the first session and returns opening bursts.
6. Frontend marks onboarding complete locally and stashes the session for immediate chat handoff.

### Inbox flow

1. App calls `/api/companions/me`.
2. Backend returns:
   - available companions
   - existing pairs
   - primary pair
   - inbox entries
3. Inbox groups entries into:
   - `Waiting On You`
   - `New Around You`
   - `Quiet Threads`
4. Tapping an entry opens its thread by starting or resuming a session.

### Chat flow

1. Chat screen loads the bootstrapped or resumed session.
2. Existing history is rendered if available.
3. Opening bursts are played as staggered text messages when starting fresh.
4. User sends a message.
5. Backend returns burst payloads.
6. Typing indicators and delayed burst playback simulate texting realism.
7. Client periodically pulls pending proactive events and injects them into the thread.

### Profile / presence flow

The profile screen is now a product-facing privacy/presence screen rather than a mechanics inspector.

It controls:

- continuity storage toggle
- proactive messages toggle
- push registration allowance
- sensitive emotional check-ins
- quiet hours
- thread-specific proactive cadence
- thread reset
- account deletion

## 8. Backend Request And Data Flow

### `/api/session/start`

Purpose:

- open a new thread or resume an existing active conversation inside a pair

Main steps:

1. authenticate user
2. resolve or assign pair
3. create/find user
4. resume existing conversation if `resume_existing=true`
5. otherwise create a conversation and generate opening message
6. store opening assistant bursts
7. return session payload

### `/api/chat`

Purpose:

- handle one user message and return one assistant reply as burst segments

Main steps:

1. authenticate user
2. resolve pair
3. validate conversation ownership
4. save user message plus pacing metadata
5. update relationship state
6. build context from facts, narrative, patterns, entities, emotions, and episodic memories
7. call Groq
8. split reply into bursts
9. save assistant bursts
10. enqueue background extraction if due
11. return structured chat response

### `/api/companions/me`

Purpose:

- provide inbox-first data model for the frontend

Returns:

- `available_companions`
- `pairs`
- `primary_pair`
- `inbox_entries`
- `user_name`

### `/api/me/profile`

Purpose:

- provide account, presence, pair summary, and memory count for the profile screen

Important note:

- This endpoint used to expose more relationship internals.
- It has been trimmed back so the product surface does not overexpose the engine.

### `/api/me/proactive/pending`

Purpose:

- pull pending proactive events and mark them delivered

### `/api/ops/*`

Purpose:

- internal/admin observability for users, pairs, events, and proactive runs

## 9. Memory System

The memory system has multiple layers, each with a distinct job.

### Layer 1: Structured durable facts

Table:

- `user_facts`

Examples:

- preferred name
- work situation
- recurring preferences

Use:

- hard memory that should not rely on semantic vector retrieval

### Layer 2: Entities and relationship graph

Tables:

- `entities`
- `entity_relationships`

Examples:

- mother
- Rahul
- office
- relationship between friend and family

Use:

- social grounding and better context construction

### Layer 3: Emotional history

Table:

- `emotional_events`

Use:

- emotional continuity
- callbacks
- emotional direction inference

### Layer 4: Behavioral patterns

Table:

- `behavioral_patterns`

Use:

- detect recurring ways the user communicates or emotionally responds

### Layer 5: Narrative summaries

Table:

- `narrative_summaries`

Use:

- internal rolling life-phase summary
- compact continuity over time

### Layer 6: Episodic semantic memories

Stores:

- Chroma vector memories
- mirrored metadata in SQLite `memory_index`

Use:

- semantic retrieval of emotionally important episodes

## 10. Relationship Simulation System

Relationship progression is stored in `relationship_pairs`.

Tracked scores:

- closeness
- trust
- openness
- comfort
- rhythm
- topic familiarity

Stage progression:

- `new`
- `warming`
- `settled`
- `close`
- `bonded`

State changes happen from:

- session starts
- user message behavior
- assistant replies
- memory extraction refresh

This means the relationship state is not a static label. It is continuously nudged by interaction behavior.

## 11. Matching System

The system no longer uses simple static assignment alone.

It now infers a hidden user chemistry profile from message behavior:

- active hours
- response pace
- message length style
- openness level
- humor style
- rhythm
- social energy

That profile is matched against `matching_profile` values inside character JSON assets.

The assignment still remains deterministic enough to be stable, but it is now behavior-shaped rather than purely id-hash-based.

## 12. Personality System

All personality assets live in:

- `backend/personality/characters/`

Each character file contains:

- identity
- archetype
- summary
- texting style
- emotional intelligence rules
- memory behavior
- relationship arc
- discovery openers
- social graph connections
- matching profile
- proactive profile
- forbidden behaviors

### Current character roster

- `atlas`
  - dry intellectual night owl
- `elio`
  - character asset in roster
- `june`
  - character asset in roster
- `kaia`
  - character asset in roster
- `mira`
  - warm overtalker with emotional instinct
- `nira`
  - character asset in roster
- `nova`
  - warm observant late-night confidant
- `orion`
  - character asset in roster
- `remy`
  - character asset in roster
- `sabine`
  - character asset in roster
- `theo`
  - character asset in roster
- `vale`
  - character asset in roster

Important implementation note:

- Nova, Atlas, and Mira currently have explicit `proactive_profile` tuning in addition to their matching profile.
- Other characters still get differentiated proactive defaults through code based on their asset fields.

## 13. Proactive Messaging System

There are two layers:

### Pair-level switches

Stored in `relationship_pairs`:

- `proactive_enabled`
- `proactive_cadence`
- `proactive_emotional_callbacks_enabled`
- `proactive_last_sent_at`
- `proactive_last_reason`
- `proactive_cooldown_until`

### User-level switches

Stored in `user_preferences`:

- `allow_proactive_messages`
- `allow_push_notifications`
- `allow_sensitive_proactive`
- quiet hours

### Strategy layer

Defined in code by `ProactiveStyle`:

- minimum inactivity threshold
- cooldown bias
- opening device
- contextual motive
- silence instruction
- emotional callback instruction
- gentle presence instruction
- notification mode
- double-text likelihood
- callback trust floor
- presence trust floor
- early-stage presence allowance

This is what makes outreach behavior different by personality rather than only by cadence setting.

## 14. Database Structure

Primary schema file:

- [backend/db/schema.sql](/C:/Users/aakash09/Desktop/sol_mvp/backend/db/schema.sql)

### Tables

#### `users`

Stores account-level identity and aggregates.

Columns:

- `id`
- `display_name`
- `email`
- `created_at`
- `last_seen`
- `name`
- `preferred_name`
- `age`
- `location`
- `timezone`
- `character_id`
- `relationship_label`
- `total_sessions`
- `total_messages`

#### `companions`

Stores companion registry metadata mirrored from personality assets.

Columns:

- `id`
- `name`
- `status`
- `archetype`
- `summary`
- `introduction_style`
- `relationship_label`
- `match_weight`
- `sort_order`
- `created_at`
- `updated_at`

#### `relationship_pairs`

The most important table. One row per user-companion relationship.

Columns:

- `id`
- `user_id`
- `companion_id`
- `relationship_label`
- `assignment_status`
- `assignment_source`
- `assignment_reason`
- `is_primary`
- `introduced_at`
- `first_session_at`
- `last_session_started_at`
- `last_interaction_at`
- `last_user_message_at`
- `last_companion_message_at`
- `closeness_score`
- `trust_score`
- `openness_score`
- `comfort_score`
- `rhythm_score`
- `topic_familiarity_score`
- `total_sessions`
- `total_messages`
- `memory_count`
- `current_stage`
- `proactive_enabled`
- `proactive_cadence`
- `proactive_emotional_callbacks_enabled`
- `proactive_last_sent_at`
- `proactive_last_reason`
- `proactive_cooldown_until`
- `created_at`
- `updated_at`

#### `user_preferences`

Account-level privacy and presence toggles.

Columns:

- `user_id`
- `allow_memory_storage`
- `show_memory_overview`
- `allow_proactive_messages`
- `allow_push_notifications`
- `quiet_hours_start`
- `quiet_hours_end`
- `allow_sensitive_proactive`
- `created_at`
- `updated_at`

#### `device_registrations`

Push token registry per user and platform.

Columns:

- `id`
- `user_id`
- `platform`
- `push_token`
- `is_enabled`
- `last_seen_at`
- `created_at`
- `updated_at`

#### `proactive_events`

Queued/generated proactive messages.

Columns:

- `id`
- `user_id`
- `pair_id`
- `companion_id`
- `conversation_id`
- `reason`
- `status`
- `message_text`
- `payload_json`
- `notification_status`
- `scheduled_for`
- `delivered_at`
- `created_at`

#### `system_events`

Operational logs and backend diagnostics.

Columns:

- `id`
- `kind`
- `severity`
- `user_id`
- `pair_id`
- `conversation_id`
- `payload_json`
- `created_at`

#### `conversations`

Session container inside a pair.

Columns:

- `id`
- `user_id`
- `pair_id`
- `companion_id`
- `character_id`
- `started_at`
- `ended_at`
- `last_message_at`
- `session_number`
- `session_status`
- `message_count`
- `emotional_arc`
- `topics_discussed`
- `session_summary`
- `summary`

#### `messages`

One utterance in a conversation.

Columns:

- `id`
- `conversation_id`
- `user_id`
- `pair_id`
- `companion_id`
- `role`
- `content`
- `created_at`
- `emotional_tone`
- `emotional_intensity`
- `topics`
- `hour_of_day`
- `day_of_week`
- `client_sent_at`
- `draft_duration_ms`
- `reply_latency_ms`
- `text_length`
- `memory_extracted`

#### `user_facts`

Durable factual memory rows.

Columns:

- `id`
- `user_id`
- `pair_id`
- `companion_id`
- `category`
- `fact_key`
- `fact_value`
- `confidence`
- `source_message_id`
- `source_type`
- `created_at`
- `updated_at`
- `is_outdated`
- `superseded_by_id`

#### `entities`

Important people/places/concepts/events mentioned by the user.

Columns:

- `id`
- `user_id`
- `pair_id`
- `companion_id`
- `name`
- `type`
- `description`
- `relationship_to_user`
- `emotional_valence`
- `first_mentioned_at`
- `last_mentioned_at`
- `mention_count`

#### `entity_relationships`

Links between entities.

Columns:

- `id`
- `user_id`
- `pair_id`
- `companion_id`
- `entity_a_id`
- `entity_b_id`
- `relationship_type`
- `description`
- `created_at`
- `updated_at`

#### `emotional_events`

Stored emotional markers inferred from conversation.

Columns:

- `id`
- `user_id`
- `pair_id`
- `companion_id`
- `message_id`
- `emotion`
- `intensity`
- `trigger_topic`
- `trigger_entity`
- `valence`
- `created_at`
- `hour_of_day`
- `day_of_week`

#### `behavioral_patterns`

Persistent detected behavior patterns.

Columns:

- `id`
- `user_id`
- `pair_id`
- `companion_id`
- `pattern_type`
- `description`
- `evidence_count`
- `confidence`
- `first_detected_at`
- `last_seen_at`
- `is_active`
- `source`

#### `narrative_summaries`

Rolling internal narrative summaries.

Columns:

- `id`
- `user_id`
- `pair_id`
- `companion_id`
- `period_start`
- `period_end`
- `summary`
- `themes`
- `emotional_direction`
- `created_at`

#### `memory_index`

SQLite mirror metadata for Chroma memories.

Columns:

- `id`
- `user_id`
- `pair_id`
- `companion_id`
- `chroma_id`
- `title`
- `content`
- `emotion_tag`
- `strength`
- `emotional_weight`
- `created_at`
- `last_retrieved_at`
- `retrieval_count`
- `source_message_ids`
- `conversation_id`
- `archived`

### Indexes

The schema defines indexes for:

- primary pair lookup
- companion lookup
- proactive scheduling
- conversation retrieval by pair and status
- message retrieval by pair and conversation
- unextracted message scanning
- fact uniqueness and category lookup
- entity lookup
- emotion lookup
- pattern lookup
- narrative lookup
- memory lookup
- device registration lookup
- proactive event lookup
- system event lookup

## 15. Deployment And Environment Model

Backend config comes from:

- repo root `.env`
- `backend/.env`

`backend/.env` overrides root `.env` if both exist.

Important env vars:

- `GROQ_API_KEY`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_SERVICE_ACCOUNT_PATH`
- `PUBLIC_BASE_URL`
- `CORS_ALLOWED_ORIGINS`
- `ADMIN_DEBUG_TOKEN`
- `SQLITE_DB_PATH`
- `CHROMA_DB_PATH`
- `PROACTIVE_MESSAGES_ENABLED`
- `PROACTIVE_MAX_PER_RUN`
- `PROACTIVE_DEFAULT_QUIET_HOURS_START`
- `PROACTIVE_DEFAULT_QUIET_HOURS_END`
- `PROACTIVE_INACTIVITY_HOURS_MIN`
- `PROACTIVE_INACTIVITY_HOURS_MAX`

Production expectation:

- Railway service rooted at `/backend`
- volume mounted at `/data`
- SQLite stored at `/data/db/companion.db`
- Chroma stored at `/data/chroma_db`
- Firebase Admin credential mounted into container

## 16. File Inventory Rules For This Section

The next sections describe project files.

To keep the inventory useful, files are divided into:

- authored source and config
- generated platform scaffolding
- local runtime state / caches / vendored environments

Generated and runtime directories are still documented, but not line-by-line down into third-party dependency internals because those are not authored project logic.

## 17. Root File Inventory

### `README.md`

Repo-level overview.

What it does:

- explains Sol at a high level
- gives local backend/frontend setup
- lists test commands
- points to Railway deploy docs
- notes repo hygiene expectations

### `.gitignore`

Defines what should not be committed.

Key exclusions:

- local env files
- Firebase service-account secrets
- Python cache and test output
- local SQLite data
- local Chroma data
- local Python virtualenvs
- Flutter tool/build output
- IDE metadata

### `.env`

Local root environment file.

Current role:

- backend config loader reads it first if present
- should be treated as local secret material, not documentation

## 18. Backend File Inventory

### `backend/.env.example`

Template for required backend environment variables.

Purpose:

- shows expected runtime keys
- documents local/dev defaults
- especially useful for Railway variable setup

### `backend/config.py`

Central backend configuration module.

Responsibilities:

- load env from root and `backend/.env`
- define all runtime settings
- provide defaults
- validate critical configuration

Key settings grouped here:

- Groq model and token settings
- Chroma path
- SQLite path
- Firebase settings
- app host/port/debug/CORS
- proactive behavior knobs

### `backend/main.py`

FastAPI entrypoint.

Responsibilities:

- configure logging
- define app lifespan startup/shutdown
- validate config
- connect SQLite
- initialize Chroma
- load default character
- initialize Firebase Admin auth
- sync companion registry from personality assets
- register routers
- apply CORS middleware
- expose `/`, `/health`, and `/metrics`
- track simple request metrics

### `backend/requirements.txt`

Python dependency manifest.

Key libraries:

- `fastapi`
- `uvicorn`
- `httpx`
- `python-dotenv`
- `firebase-admin`
- `chromadb`
- `pydantic`
- `anyio`
- `numpy`

### `backend/Procfile`

Simple process definition for platforms expecting Procfile semantics.

Current command:

- `uvicorn main:app --host 0.0.0.0 --port $PORT`

### `backend/railway.json`

Railway deployment config.

Defines:

- start command
- healthcheck path
- healthcheck timeout
- restart policy

### `backend/RAILWAY_SETUP.md`

Deployment runbook for Railway.

Covers:

- service root
- required env vars
- health check behavior
- persistent volume requirement
- Firebase Admin credential mounting
- push/proactive notes
- hygiene checklist

### `backend/DATA_MODEL.md`

Short canonical note explaining pair-centric data modeling.

Best used as:

- a conceptual companion to `schema.sql`

### `backend/inspect_db.py`

Local debugging helper script.

Purpose:

- inspect the local SQLite DB schema directly
- not part of runtime server behavior

### `backend/db/schema.sql`

Canonical relational schema definition for Sol.

Purpose:

- initialize the database
- document tables and indexes
- provide default structure before `store.py` incremental column self-healing

### `backend/api/__init__.py`

Package marker for backend API module.

### `backend/api/chat.py`

Primary chat and session API.

Responsibilities:

- request/response models
- request-auth consistency checks
- pair resolution
- `/api/chat`
- `/api/session/start`
- `/api/user/{user_id}/profile`
- `/api/companions/me`
- burst payload conversion

This file is the main backend entrypoint for active user conversation.

### `backend/api/profile.py`

Profile and control surface API.

Responsibilities:

- fetch current user profile summary
- fetch pair memories
- update user preferences
- update pair proactive preferences
- register device push token
- delete a pair memory
- reset a pair
- delete account

### `backend/api/proactive.py`

Very small API surface for pending proactive events.

Responsibilities:

- expose `/api/me/proactive/pending`

### `backend/api/ops.py`

Operational/admin debug API.

Responsibilities:

- access control for ops endpoints
- summary stats
- debug users
- debug one pair
- fetch system events
- manually trigger proactive generation

### `backend/auth/__init__.py`

Package marker for auth module.

### `backend/auth/firebase.py`

Firebase Admin integration and auth verification.

Responsibilities:

- initialize Firebase Admin SDK
- support service-account file or application-default credentials
- verify Firebase ID tokens
- expose `AuthenticatedIdentity`
- provide FastAPI dependency for bearer auth

### `backend/core/__init__.py`

Package marker for core backend logic.

### `backend/core/llm.py`

Groq abstraction layer.

Responsibilities:

- send chat completion requests to Groq
- fallback from primary to fallback model on rate limit
- clean returned model text
- expose health check helper
- define `LLMError` and `RateLimitError`

### `backend/core/context_builder.py`

Conversation context assembler.

Responsibilities:

- load user and pair
- load active facts if memory storage is allowed
- load recent messages
- build semantic memory query
- retrieve episodic memories from Chroma
- gather entities, relationships, emotional summary, patterns, narrative, and relationship state
- format all of that into layered internal context
- compose final system prompt

This is one of the most important orchestration files in the backend.

### `backend/core/burst_engine.py`

Text-message realism layer.

Responsibilities:

- normalize model output
- split raw text into message bursts
- support explicit `[BURST]` token from system prompt
- heuristically split sentences or clauses when needed
- compute:
  - pre-burst delays
  - typing durations
  - pause intensity
  - follow-up detection

### `backend/core/proactive_engine.py`

Personality-aware outreach engine.

Responsibilities:

- decide whether a proactive message should be sent
- rank pairs for outreach
- honor quiet hours, cooldowns, pending events, and cadence
- compute style-specific thresholds and instructions
- generate proactive event text via context + LLM
- save proactive messages into the conversation
- queue event payloads
- send push notifications when enabled

This file is the core of Sol’s “they reached out first” behavior.

### `backend/core/summarizer.py`

Narrative summarization layer.

Responsibilities:

- decide when enough new signals exist to synthesize a new narrative summary
- build narrative-generation prompt
- call LLM for compact internal life narrative
- fallback to heuristic summary if LLM generation fails
- save summary, themes, and emotional direction
- apply memory decay

### `backend/memory/__init__.py`

Package marker for memory module.

### `backend/memory/store.py`

SQLite storage layer and data access backbone.

This is the single largest and most structurally important backend file.

Responsibilities:

- connect/close SQLite
- initialize schema
- self-heal schema with `_ensure_columns()`
- provide CRUD and helper methods for almost every table
- create users, pairs, conversations, messages
- manage user preferences and pair preferences
- manage device registrations
- manage proactive events
- manage facts, entities, relationships, emotions, patterns, narratives, and memory index
- expose context-builder retrieval helpers
- expose ops/debug retrieval helpers
- manage account deletion and pair reset

Practical meaning:

- if the backend has a “source of truth” code file for relational state, this is it

### `backend/memory/retriever.py`

Chroma memory access layer.

Responsibilities:

- initialize/get Chroma client
- derive collection names from `pair_id`
- migrate legacy user-scoped collection naming if needed
- retrieve relevant episodic memories by semantic similarity
- count, delete, or clear memories
- format episodic memories for prompt injection

### `backend/memory/extractor.py`

Conversation-to-memory extraction pipeline.

Responsibilities:

- gather unextracted messages
- call a dedicated LLM extraction prompt
- parse JSON extraction result
- annotate latest message with emotion/topics
- save facts, entities, relationships, emotions, patterns
- save conversation insights
- save episodic memories into Chroma and memory index
- refresh relationship state after extraction
- trigger narrative consolidation

### `backend/memory/relationship_engine.py`

Relationship scoring engine.

Responsibilities:

- update relationship state on session start
- update relationship state on each saved message
- refresh state after extraction
- infer current stage
- detect vulnerability and topic continuity
- apply pair score deltas safely inside score bounds

### `backend/memory/analysis.py`

Heuristic analysis helpers.

Responsibilities:

- emotion-to-valence mapping
- behavioral pattern detection
- theme inference
- emotional direction inference
- late-night openness detection
- recurring emotional day detection
- recurring trigger detection
- volatility detection

### `backend/memory/consolidator.py`

Thin wrapper around narrative maintenance.

Responsibilities:

- trigger summarizer when appropriate after extraction

### `backend/personality/__init__.py`

Package marker for personality system.

### `backend/personality/loader.py`

Character asset loader and system-prompt builder.

Responsibilities:

- load JSON personality files
- cache loaded character objects
- expose `Character`
- map relationship phases from session count
- build deeply structured system prompt from asset fields

### `backend/personality/registry.py`

Companion registry and pairing logic.

Responsibilities:

- sync personality assets into `companions` table
- expose roster summaries
- choose companion for user by chemistry matching
- resolve/assign primary pair
- build natural opening line
- build pair payloads
- build inbox entries
- build discovery entries and social arrival hints

This file is where the social-layer roster logic lives.

### `backend/personality/characters/atlas.json`

Character asset for Atlas.

Role:

- dry, guarded, intellectual personality
- includes discovery openers, social links, matching profile, proactive profile

### `backend/personality/characters/elio.json`

Character asset for Elio.

Role:

- full personality asset participating in matching/discovery/prompting

### `backend/personality/characters/june.json`

Character asset for June.

Role:

- full personality asset participating in matching/discovery/prompting

### `backend/personality/characters/kaia.json`

Character asset for Kaia.

Role:

- full personality asset participating in matching/discovery/prompting

### `backend/personality/characters/mira.json`

Character asset for Mira.

Role:

- expressive, warm, fast-energy personality
- explicit proactive profile included

### `backend/personality/characters/nira.json`

Character asset for Nira.

Role:

- full personality asset participating in matching/discovery/prompting

### `backend/personality/characters/nova.json`

Character asset for Nova.

Role:

- flagship warm/confidant personality
- most representative original personality asset
- explicit proactive profile included

### `backend/personality/characters/orion.json`

Character asset for Orion.

Role:

- full personality asset participating in matching/discovery/prompting

### `backend/personality/characters/remy.json`

Character asset for Remy.

Role:

- full personality asset participating in matching/discovery/prompting

### `backend/personality/characters/sabine.json`

Character asset for Sabine.

Role:

- full personality asset participating in matching/discovery/prompting

### `backend/personality/characters/theo.json`

Character asset for Theo.

Role:

- full personality asset participating in matching/discovery/prompting

### `backend/personality/characters/vale.json`

Character asset for Vale.

Role:

- full personality asset participating in matching/discovery/prompting

### `backend/tests/test_proactive_engine.py`

Backend unit tests for proactive decision logic.

Purpose:

- validate proactive send decision rules and guardrails

### `backend/chroma_db/`

Runtime vector store data.

What it is:

- local persisted Chroma memory store
- not authored source

### `backend/db/companion.db`, `companion.db-shm`, `companion.db-wal`

Runtime SQLite database and WAL files.

What they are:

- local persisted relational data
- not authored source

### `backend/.venv/` and `backend/venv/`

Local Python virtual environments.

What they are:

- local dependency installs
- not source code

## 19. Frontend File Inventory

### `frontend/companion_app/pubspec.yaml`

Flutter package manifest.

Defines:

- app name/version
- Dart SDK range
- dependencies
- dev dependencies
- asset paths
- custom font family mapping
- launcher icon generation settings

### `frontend/companion_app/pubspec.lock`

Resolved dependency lockfile.

Purpose:

- records exact Flutter/Dart package versions installed locally

### `frontend/companion_app/README.md`

Small frontend-specific readme.

Purpose:

- brief app scope
- local run command
- useful checks

### `frontend/companion_app/analysis_options.yaml`

Dart/Flutter analyzer and lint config.

Purpose:

- lint behavior and project analysis rules

### `frontend/companion_app/firebase.json`

Firebase-related project config for client tooling.

### `frontend/companion_app/lib/main.dart`

Flutter app entrypoint.

Responsibilities:

- initialize Firebase
- lock orientation
- configure system UI
- create app theme
- route through auth gate
- send users to login, onboarding, or inbox

### `frontend/companion_app/lib/firebase_options.dart`

Generated FlutterFire config.

Purpose:

- per-platform Firebase app configuration constants

### `frontend/companion_app/lib/services/auth_service.dart`

Client auth abstraction.

Responsibilities:

- Google sign-in
- Firebase sign-in
- expose current user data
- provide Firebase ID token
- sign out
- map Firebase errors to user-friendly messages

### `frontend/companion_app/lib/services/api_service.dart`

HTTP client and response models for the app.

Responsibilities:

- define endpoint URLs
- hold all API DTO models
- send chat/session/profile/inbox/proactive requests
- update preferences
- reset/delete account data
- register device tokens
- parse API failures into `ChatException`

This is the frontend’s main networking contract layer.

### `frontend/companion_app/lib/services/onboarding_service.dart`

Local onboarding-completion persistence.

Responsibilities:

- store per-user onboarding completion in `SharedPreferences`

### `frontend/companion_app/lib/services/session_bootstrap_service.dart`

In-memory session handoff helper.

Responsibilities:

- stash a freshly-created session during onboarding or inbox navigation
- allow chat screen to consume it during initialization

### `frontend/companion_app/lib/services/notification_hooks_service.dart`

Push token registration helper.

Responsibilities:

- request notification permission
- fetch current FCM token
- register token with backend
- re-register on token refresh

### `frontend/companion_app/lib/models/message_model.dart`

Local UI message model.

Defines:

- `MessageRole`
- `MessageStatus`
- `Message`

Responsibilities:

- represent message bubbles in chat UI
- represent local message status and timestamp formatting
- convert history rows into UI messages

### `frontend/companion_app/lib/widgets/message_bubble.dart`

Reusable chat bubble widget.

Responsibilities:

- animate message entrance
- render user vs companion bubble styles
- group adjacent messages visually
- show avatar, timestamp, and user send/read state

### `frontend/companion_app/lib/widgets/typing_indicator.dart`

Typing animation widget.

Responsibilities:

- represent companion typing state
- vary dots, spacing, and tempo based on pause intensity and follow-up behavior

### `frontend/companion_app/lib/painters/fragment_painter.dart`

Custom painter and particle definitions for the login screen background.

Responsibilities:

- draw floating text fragments and motes
- create the atmospheric visual identity of the sign-in screen

### `frontend/companion_app/lib/screens/login_screen.dart`

Animated login screen.

Responsibilities:

- visual entrance sequence
- rotating taglines
- atmospheric background fragments
- Google sign-in button
- privacy copy
- login error handling

### `frontend/companion_app/lib/screens/onboarding_screen.dart`

First-run encounter screen.

Responsibilities:

- load matched companion from roster
- stage introductory encounter copy
- present matched companion card
- open first session
- hand session to app gate callback

### `frontend/companion_app/lib/screens/inbox_screen.dart`

Inbox-first home screen.

Responsibilities:

- load roster and inbox entries
- render ambient social activity
- group threads by state
- open thread taps into chat
- open presence/profile settings
- sign out

### `frontend/companion_app/lib/screens/chat_screen.dart`

Primary conversation screen.

Responsibilities:

- initialize from bootstrapped session, resumed session, or fresh start
- render history
- play opening and reply bursts with timing
- send messages with pacing metadata
- show typing indicators
- pull proactive events on resume
- open profile screen
- sign out

### `frontend/companion_app/lib/screens/profile_screen.dart`

Presence and privacy screen.

Responsibilities:

- load account and pair presence data
- switch viewed thread in settings context
- update user-level privacy preferences
- update pair-level proactive preferences
- configure quiet hours
- reset thread
- delete account

Important note:

- this screen intentionally no longer exposes live relationship-state internals or full visible memory mechanics in the main product surface

### `frontend/companion_app/test/api_service_test.dart`

Tests for frontend API parsing and request model behavior.

### `frontend/companion_app/test/widget_test.dart`

Default/basic widget test scaffold.

### `frontend/companion_app/assets/images/sol_logo.png`

Primary Sol logo used in splash, chat avatar treatment, and UI accents.

### `frontend/companion_app/assets/images/google_logo.png`

Google logo for sign-in button.

### `frontend/companion_app/assets/icon/app_icon.png`

Base image for generated launcher icons.

### `frontend/companion_app/assets/fonts/CormorantGaramond-Light.ttf`

Custom display font used for brand-forward typography.

### `frontend/companion_app/assets/fonts/CormorantGaramond-Regular.ttf`

Regular weight of the same font family.

## 20. Frontend Platform And Scaffold File Inventory

These files are important to shipping the Flutter app, but most are platform scaffolding rather than product logic.

### Android

#### `frontend/companion_app/android/build.gradle.kts`

Top-level Android Gradle config.

#### `frontend/companion_app/android/settings.gradle.kts`

Android module inclusion and plugin management.

#### `frontend/companion_app/android/gradle.properties`

Gradle property configuration.

#### `frontend/companion_app/android/gradle/wrapper/gradle-wrapper.properties`

Pins Gradle wrapper version/location.

#### `frontend/companion_app/android/gradlew`

Unix Gradle wrapper launcher.

#### `frontend/companion_app/android/gradlew.bat`

Windows Gradle wrapper launcher.

#### `frontend/companion_app/android/local.properties`

Local machine Flutter/SDK path config. Local-only.

#### `frontend/companion_app/android/app/build.gradle.kts`

Android app module build config.

#### `frontend/companion_app/android/app/google-services.json`

Android Firebase app config.

#### `frontend/companion_app/android/app/src/main/AndroidManifest.xml`

Primary Android app manifest.

#### `frontend/companion_app/android/app/src/debug/AndroidManifest.xml`

Debug manifest overlay.

#### `frontend/companion_app/android/app/src/profile/AndroidManifest.xml`

Profile-build manifest overlay.

#### `frontend/companion_app/android/app/src/main/kotlin/com/solmvp/companion_app/MainActivity.kt`

Android entry activity for Flutter app.

#### `frontend/companion_app/android/app/src/main/res/values/styles.xml`

Android app styles.

#### `frontend/companion_app/android/app/src/main/res/values-night/styles.xml`

Night-mode style overrides.

#### `frontend/companion_app/android/app/src/main/res/drawable/launch_background.xml`

Legacy splash/launch drawable.

#### `frontend/companion_app/android/app/src/main/res/drawable-v21/launch_background.xml`

API-21+ launch drawable variant.

#### `frontend/companion_app/android/app/src/main/res/mipmap-mdpi/ic_launcher.png`

Android launcher icon.

#### `frontend/companion_app/android/app/src/main/res/mipmap-hdpi/ic_launcher.png`

Android launcher icon.

#### `frontend/companion_app/android/app/src/main/res/mipmap-xhdpi/ic_launcher.png`

Android launcher icon.

#### `frontend/companion_app/android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png`

Android launcher icon.

#### `frontend/companion_app/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png`

Android launcher icon.

### iOS

#### `frontend/companion_app/ios/Flutter/Debug.xcconfig`

iOS debug Flutter config.

#### `frontend/companion_app/ios/Flutter/Release.xcconfig`

iOS release Flutter config.

#### `frontend/companion_app/ios/Flutter/AppFrameworkInfo.plist`

Flutter framework metadata for iOS.

#### `frontend/companion_app/ios/Runner/AppDelegate.swift`

iOS native app delegate.

#### `frontend/companion_app/ios/Runner/Info.plist`

iOS app metadata and capabilities.

#### `frontend/companion_app/ios/Runner/Runner-Bridging-Header.h`

Swift/Objective-C bridging header.

#### `frontend/companion_app/ios/Runner/Base.lproj/Main.storyboard`

Main iOS storyboard.

#### `frontend/companion_app/ios/Runner/Base.lproj/LaunchScreen.storyboard`

iOS launch screen.

#### `frontend/companion_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/*`

iOS app icon assets in multiple sizes plus `Contents.json`.

#### `frontend/companion_app/ios/Runner/Assets.xcassets/LaunchImage.imageset/*`

Legacy launch image assets and metadata.

#### `frontend/companion_app/ios/Runner.xcodeproj/project.pbxproj`

Primary iOS project definition.

#### `frontend/companion_app/ios/Runner.xcodeproj/project.xcworkspace/*`

Xcode workspace metadata.

#### `frontend/companion_app/ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme`

Shared Xcode scheme.

#### `frontend/companion_app/ios/Runner.xcworkspace/*`

Workspace metadata.

#### `frontend/companion_app/ios/RunnerTests/RunnerTests.swift`

iOS test scaffold.

### macOS

#### `frontend/companion_app/macos/Flutter/GeneratedPluginRegistrant.swift`

Generated plugin registration for macOS.

#### `frontend/companion_app/macos/Flutter/Flutter-Debug.xcconfig`

macOS Flutter debug config.

#### `frontend/companion_app/macos/Flutter/Flutter-Release.xcconfig`

macOS Flutter release config.

#### `frontend/companion_app/macos/Runner/AppDelegate.swift`

macOS app delegate.

#### `frontend/companion_app/macos/Runner/MainFlutterWindow.swift`

macOS main Flutter window host.

#### `frontend/companion_app/macos/Runner/Info.plist`

macOS app metadata.

#### `frontend/companion_app/macos/Runner/DebugProfile.entitlements`

macOS entitlements for debug/profile.

#### `frontend/companion_app/macos/Runner/Release.entitlements`

macOS release entitlements.

#### `frontend/companion_app/macos/Runner/Base.lproj/MainMenu.xib`

macOS main menu UI.

#### `frontend/companion_app/macos/Runner/Assets.xcassets/AppIcon.appiconset/*`

macOS app icon assets and metadata.

#### `frontend/companion_app/macos/Runner/Configs/AppInfo.xcconfig`

App metadata config.

#### `frontend/companion_app/macos/Runner/Configs/Debug.xcconfig`

Debug build config.

#### `frontend/companion_app/macos/Runner/Configs/Release.xcconfig`

Release build config.

#### `frontend/companion_app/macos/Runner/Configs/Warnings.xcconfig`

Warning/lint settings.

#### `frontend/companion_app/macos/Runner.xcodeproj/project.pbxproj`

macOS Xcode project definition.

#### `frontend/companion_app/macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme`

Shared macOS scheme.

#### `frontend/companion_app/macos/Runner.xcworkspace/*`

macOS Xcode workspace metadata.

#### `frontend/companion_app/macos/RunnerTests/RunnerTests.swift`

macOS test scaffold.

### Linux

#### `frontend/companion_app/linux/CMakeLists.txt`

Top-level Linux build config.

#### `frontend/companion_app/linux/flutter/CMakeLists.txt`

Flutter Linux integration build rules.

#### `frontend/companion_app/linux/flutter/generated_plugin_registrant.cc`

Generated Linux plugin registration.

#### `frontend/companion_app/linux/flutter/generated_plugin_registrant.h`

Generated Linux plugin registration header.

#### `frontend/companion_app/linux/flutter/generated_plugins.cmake`

Generated plugin CMake includes.

#### `frontend/companion_app/linux/runner/CMakeLists.txt`

Linux runner build config.

#### `frontend/companion_app/linux/runner/main.cc`

Linux desktop entrypoint.

#### `frontend/companion_app/linux/runner/my_application.cc`

Linux application host implementation.

#### `frontend/companion_app/linux/runner/my_application.h`

Linux application host header.

### Windows

#### `frontend/companion_app/windows/CMakeLists.txt`

Top-level Windows build config.

#### `frontend/companion_app/windows/flutter/CMakeLists.txt`

Flutter Windows integration config.

#### `frontend/companion_app/windows/flutter/generated_plugin_registrant.cc`

Generated Windows plugin registration.

#### `frontend/companion_app/windows/flutter/generated_plugin_registrant.h`

Generated Windows plugin registration header.

#### `frontend/companion_app/windows/flutter/generated_plugins.cmake`

Generated plugin build wiring.

#### `frontend/companion_app/windows/runner/CMakeLists.txt`

Windows runner build config.

#### `frontend/companion_app/windows/runner/main.cpp`

Windows desktop entrypoint.

#### `frontend/companion_app/windows/runner/flutter_window.cpp`

Flutter window host implementation.

#### `frontend/companion_app/windows/runner/flutter_window.h`

Flutter window host header.

#### `frontend/companion_app/windows/runner/win32_window.cpp`

Base Win32 host window implementation.

#### `frontend/companion_app/windows/runner/win32_window.h`

Base Win32 host window header.

#### `frontend/companion_app/windows/runner/utils.cpp`

Windows helper utilities.

#### `frontend/companion_app/windows/runner/utils.h`

Windows helper utility header.

#### `frontend/companion_app/windows/runner/Runner.rc`

Windows resource manifest.

#### `frontend/companion_app/windows/runner/resource.h`

Windows resource ids.

#### `frontend/companion_app/windows/runner/runner.exe.manifest`

Windows executable manifest.

#### `frontend/companion_app/windows/runner/resources/app_icon.ico`

Windows app icon.

### Web

#### `frontend/companion_app/web/index.html`

Flutter web host page.

#### `frontend/companion_app/web/manifest.json`

Web app manifest.

#### `frontend/companion_app/web/favicon.png`

Web favicon.

#### `frontend/companion_app/web/icons/Icon-192.png`

Web app icon.

#### `frontend/companion_app/web/icons/Icon-512.png`

Web app icon.

#### `frontend/companion_app/web/icons/Icon-maskable-192.png`

Maskable PWA icon.

#### `frontend/companion_app/web/icons/Icon-maskable-512.png`

Maskable PWA icon.

## 21. Local/Generated Frontend Directories

### `frontend/companion_app/.dart_tool/`

Generated Flutter/Dart tool state.

### `frontend/companion_app/build/`

Generated app build output.

### `frontend/companion_app/.idea/`

IDE metadata.

These are not source-of-truth code.

## 22. Current Known Design Decisions

1. Pair isolation is foundational and intentional.
2. SQLite remains the structured system of record.
3. Chroma is used for episodic semantic memory, not everything.
4. Personality lives primarily in JSON assets, not code constants.
5. Flutter client is inbox-first, not assistant-first.
6. Hidden chemistry matching is preferred over visible configuration.
7. Relationship mechanics are increasingly hidden from end-user UI.
8. Proactive messaging is shaped by both global preferences and per-personality behavior.

## 23. Current Risks / Important Caveats

1. The repo contains runtime data and local env files in the workspace.
   - They are ignored by `.gitignore`, but should not be treated as canonical source.
2. The backend depends on Firebase Admin credential setup in deployed environments.
3. Persistent memory in production depends on mounted durable storage.
4. Not every recent code path was fully runtime-verified from the assistant environment.
5. Some frontend API models still contain fields that are no longer surfaced in UI, because the app evolved faster than the DTO cleanup.

## 24. Recommended Forward Working Practice

When extending Sol from here:

1. Start with this document.
2. Then read these files first:
   - `backend/main.py`
   - `backend/api/chat.py`
   - `backend/memory/store.py`
   - `backend/core/context_builder.py`
   - `backend/personality/registry.py`
   - `frontend/companion_app/lib/main.dart`
   - `frontend/companion_app/lib/services/api_service.dart`
   - `frontend/companion_app/lib/screens/inbox_screen.dart`
   - `frontend/companion_app/lib/screens/chat_screen.dart`
3. Treat `pair_id` as sacred.
4. Treat personality JSONs as product assets, not just data files.
5. Keep runtime/generated folders out of architectural reasoning unless debugging deploy/runtime issues.

## 25. Short “If You Forget Everything Else” Summary

Sol is a Flutter + FastAPI relationship product where:

- Firebase proves identity
- FastAPI orchestrates chat
- SQLite stores structured continuity
- Chroma stores semantic episodic memory
- personality JSONs define character behavior
- the user-companion pair is the memory boundary
- the inbox is the social home
- chat is burst-based for realism
- proactive behavior is controlled by both settings and per-personality strategy

That is the current system in one sentence.
