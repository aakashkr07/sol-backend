# Sol Canonical Data Model

The backend now treats each relationship as a first-class pair.

## Core ids

- `user_id`: verified Firebase UID
- `companion_id`: the assigned or explicitly selected companion
- `pair_id`: `user_id::companion_id`
- `conversation_id`: one session within a pair

## Canonical entities

- `users`
  - account-level identity only
  - stores display metadata and aggregate totals
- `companions`
  - roster metadata mirrored from personality JSON assets
  - one row per companion identity
- `relationship_pairs`
  - the canonical emotional relationship object
  - stores assignment metadata, pair-level counters, and the first relationship-state fields
  - exactly one `is_primary` pair is active per user at a time
- `conversations`
  - one session within a pair
  - scoped by `pair_id`
- `messages`
  - one utterance within a conversation
  - always scoped by `pair_id`

## Pair-scoped memory

Every memory-bearing table includes `pair_id` and `companion_id`:

- `user_facts`
- `entities`
- `entity_relationships`
- `emotional_events`
- `behavioral_patterns`
- `narrative_summaries`
- `memory_index`

Chroma collections are also pair-scoped using a hashed collection name derived from `pair_id`.

## Why this matters

This prevents memory bleed between:

- different users talking to the same companion
- the same user talking to different companions

The pair is now the trust boundary for recall, extraction, and narrative continuity.

## Companion assignment lifecycle

- first contact
  - if the user has no pair yet, the backend deterministically matches one companion from the active roster
- explicit selection
  - if the user starts a session with a specific `companion_id`, that pair becomes the user's primary pair
- ongoing sessions
  - new conversations are always opened inside one pair, never across companions
