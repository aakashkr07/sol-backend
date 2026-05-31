import json
import logging
import uuid
from typing import Optional

import httpx

from config import settings
from memory.analysis import detect_behavioral_patterns, emotion_to_valence
from memory.consolidator import maybe_consolidate_narrative
from memory.relationship_engine import refresh_after_extraction
from memory.store import db

logger = logging.getLogger(__name__)

EXTRACTION_SYSTEM_PROMPT = """You are the memory extraction engine for a deeply relational AI companion.
You are parsing casual, natural human texts and conversations (which are often messy, informal, full of slang, and emotionally rich).
Understand the user's implicit context, environment, and physical/emotional state.
Analyze the conversation and return ONLY valid JSON.

Return this shape exactly:
{
  "facts": [
    {
      "category": "identity|relationships|work|health|preferences|goals|struggles|context",
      "key": "snake_case_key",
      "value": "natural human-like fact summary",
      "confidence": 0.8
    }
  ],
  "companion_facts": [
    {
      "category": "preferences|routine|history|opinion|relation_to_other_bots|other",
      "key": "snake_case_key",
      "value": "fact value about the companion character revealed by them in their response",
      "confidence": 0.8
    }
  ],
  "entities": [
    {
      "name": "Rahul",
      "type": "person|place|organization|concept|event",
      "description": "best friend from school",
      "relationship_to_user": "best friend",
      "emotional_valence": -1.0
    }
  ],
  "relationships": [
    {
      "entity_a": "Rahul",
      "entity_b": "Mom",
      "relationship_type": "unknown_to_each_other|friends|siblings|colleagues|romantic_history|family|tension",
      "description": "Mom does not know about the tension with Rahul"
    }
  ],
  "emotions": [
    {
      "emotion": "anxious|sad|hopeful|excited|flat|playful|angry|numb|content|grief|overwhelmed|lonely|calm|proud",
      "intensity": 0.0,
      "trigger_topic": "work uncertainty",
      "trigger_entity": "Rahul"
    }
  ],
  "behavioral_patterns": [
    {
      "pattern_type": "temporal|emotional|communicative|topical|relational",
      "description": "Uses humor to soften difficult feelings",
      "confidence": 0.0
    }
  ],
  "episodic_memories": [
    {
      "title": "Rahul felt distant",
      "content": "The user said Rahul has felt distant lately and it has been quietly bothering them.",
      "emotion_tag": "sad|anxious|hopeful|grief|joy|anger|content|numb",
      "importance": 0.0
    }
  ],
  "conversation": {
    "topics_discussed": ["rahul", "distance", "friendship"],
    "emotional_arc": "started guarded and ended more vulnerable",
    "session_summary": "They opened up about feeling distance from Rahul and uncertainty about what it means."
  }
}

Rules:
- Extract only information grounded in the conversation.
- **User Facts Key-Value Redesign & Grounding**:
  * Extract user facts in a highly structured key-value fashion.
  * Instead of storing generic or robotic database strings, force the extraction of rich, multi-dimensional semantic and contextual details about the user's current situation:
    - **Environment/Location Type**: e.g., `location_type: mall`, `location: library` (implicit or explicit).
    - **Current Activity**: e.g., `activity: waiting for friend`, `current_activity: watching movie`.
    - **Social Context**: e.g., `social_state: alone`, `social_context: with family`, `social_context: with friend`.
    - **Emotional Implications/Fatigue/Sleep**: e.g., `emotional_implication: solitude/comfort`, `sleep_status: insomnia/3 days`, `sleep_deficit: 3 days`, `energy_level: exhausted`.
  * **No Robotic Strings**: Prevent writing robotic database-like statements.
  * **Clean Keys**: Keys must be clean, semantic, and written in snake_case (e.g. `location_type`, `social_context`, `current_activity`, `sleep_deficit`, `emotional_implication`).
  * **Human Values**: Values must be natural, human-like summaries representing the dimension.
  * **Examples**:
    - User says: "i'm at the mall waiting for my friend"
      -> Extract `location_type: mall`, `current_activity: waiting for friend`, `social_context: with friend`.
    - User says: "i haven't slept properly in like 3 days"
      -> Extract `sleep_deficit: 3 days`, `emotional_implication: fatigue/stress`.
- Companion facts should capture durable self-disclosed preferences, routines, opinions, or personal history revealed by the Companion (labeled as 'Companion:' in text) in their responses.
- Entities should only include important people, places, organizations, concepts, or events.
- Emotions should reflect the user, not the assistant.
- Behavioral patterns should only be included when there is a meaningful signal, not a guess.
- Episodic memories should capture emotionally or narratively meaningful moments. You MUST grade their 'importance' score strictly on a three-tier significance scale:
  * 0.1 to 0.3 (Low Significance): Purely mundane, routine, transactional, or everyday factual occurrences (e.g. eating pasta, watching a movie, doing laundry, bought groceries, weather).
  * 0.4 to 0.6 (Medium Significance): General life or narrative updates, constructive projects, or intellectual updates without deep distress (e.g. had a work meeting, planned a trip, worked on a song).
  * 0.7 to 1.0 (High Significance): Deep emotional weight, personal vulnerabilities, confessions, rejections, crying, relationship fights, or major life changes (e.g. cried alone, fought with a partner, opened up about feeling lonely, got rejected, shared a deep childhood fear).
- Max 6 facts, 6 companion_facts, 5 entities, 4 relationships, 4 emotions, 3 behavioral patterns, 4 episodic memories.
- If a section has nothing useful, return an empty array or empty object."""


async def extract_and_save(user_id: str, pair_id: str, companion_id: str, conversation_id: str) -> None:
    try:
        pending_messages = db.get_unextracted_messages(user_id, pair_id=pair_id, conversation_id=conversation_id)
        if not pending_messages:
            return

        preferences = db.get_or_create_user_preferences(user_id)
        if not int(preferences.get("allow_memory_storage") or 0):
            db.mark_messages_extracted([int(message["id"]) for message in pending_messages])
            return

        message_ids = [int(message["id"]) for message in pending_messages]
        conversation_text = _format_messages_for_extraction(pending_messages)
        extracted = await _run_extraction_llm(conversation_text)
        if not extracted:
            logger.warning("Extraction returned nothing for user %s", user_id)
            return

        latest_user_message_id = _latest_user_message_id(pending_messages)
        conversation_meta = extracted.get("conversation") or {}
        topics = _normalize_topics(conversation_meta.get("topics_discussed") or [])
        primary_emotion = (extracted.get("emotions") or [{}])[0]

        with db.transaction():
            if latest_user_message_id:
                db.annotate_message(
                    latest_user_message_id,
                    emotional_tone=primary_emotion.get("emotion"),
                    emotional_intensity=_safe_float(primary_emotion.get("intensity")),
                    topics=topics,
                )

            _save_facts(user_id, pair_id, companion_id, extracted.get("facts") or [], latest_user_message_id)
            _save_companion_facts(user_id, pair_id, companion_id, extracted.get("companion_facts") or [], latest_user_message_id)
            entity_name_to_id = _save_entities(user_id, pair_id, companion_id, extracted.get("entities") or [])
            _save_relationships(user_id, pair_id, companion_id, entity_name_to_id, extracted.get("relationships") or [])
            _save_emotions(user_id, pair_id, companion_id, latest_user_message_id, extracted.get("emotions") or [])
            _save_behavioral_patterns(user_id, pair_id, companion_id, extracted.get("behavioral_patterns") or [])
            db.save_conversation_insights(
                conversation_id=conversation_id,
                emotional_arc=conversation_meta.get("emotional_arc"),
                topics_discussed=topics,
                session_summary=conversation_meta.get("session_summary"),
            )

        memories = extracted.get("episodic_memories") or extracted.get("memories") or []
        if memories:
            await _save_memories_to_chroma(
                user_id=user_id,
                pair_id=pair_id,
                companion_id=companion_id,
                conversation_id=conversation_id,
                memories=memories,
                source_message_ids=message_ids,
            )

        with db.transaction():
            detect_behavioral_patterns(user_id, pair_id, companion_id)
            refresh_after_extraction(pair_id, conversation_id=conversation_id)
            await maybe_consolidate_narrative(user_id, pair_id, companion_id)
            db.mark_messages_extracted(message_ids)

        logger.info(
            "Extraction complete for %s: %s facts, %s entities, %s emotions, %s memories",
            user_id,
            len(extracted.get("facts") or []),
            len(extracted.get("entities") or []),
            len(extracted.get("emotions") or []),
            len(memories),
        )

    except Exception as exc:
        logger.error("Memory extraction failed for user %s: %s", user_id, exc, exc_info=True)


async def _run_extraction_llm(conversation_text: str) -> Optional[dict]:
    if not settings.GROQ_API_KEY:
        logger.error("No GROQ_API_KEY; cannot run extraction")
        return None

    payload = {
        "model": settings.LLM_FALLBACK_MODEL,
        "temperature": 0.1,
        "max_tokens": 1400,
        "messages": [
            {"role": "system", "content": EXTRACTION_SYSTEM_PROMPT},
            {"role": "user", "content": f"Extract memory signals from this conversation:\n\n{conversation_text}"},
        ],
    }

    try:
        async with httpx.AsyncClient(timeout=20.0) as client:
            response = await client.post(
                f"{settings.GROQ_BASE_URL}/chat/completions",
                headers={
                    "Authorization": f"Bearer {settings.GROQ_API_KEY}",
                    "Content-Type": "application/json",
                },
                json=payload,
            )
            response.raise_for_status()
            data = response.json()
            raw_text = data["choices"][0]["message"]["content"].strip()

            if raw_text.startswith("```"):
                raw_text = raw_text.strip("`")
                if raw_text.startswith("json"):
                    raw_text = raw_text[4:]

            return json.loads(raw_text.strip())

    except json.JSONDecodeError as exc:
        logger.error("Extraction LLM returned invalid JSON: %s", exc)
        return None
    except Exception as exc:
        logger.error("Extraction LLM call failed: %s", exc)
        return None


def _save_facts(user_id: str, pair_id: str, companion_id: str, facts: list[dict], source_message_id: Optional[int]):
    for fact in facts:
        if not _is_valid_fact(fact):
            continue

        db.save_user_fact(
            user_id=user_id,
            pair_id=pair_id,
            companion_id=companion_id,
            category=fact.get("category", "identity"),
            key=fact["key"],
            value=str(fact["value"]).strip(),
            confidence=_safe_float(fact.get("confidence"), default=0.8),
            source_message_id=source_message_id,
            source_type="extractor",
        )

        if fact["key"] in {"name", "preferred_name", "first_name"}:
            db.update_user_name(user_id, str(fact["value"]).strip())


def _save_companion_facts(user_id: str, pair_id: str, companion_id: str, companion_facts: list[dict], source_message_id: Optional[int]):
    for fact in companion_facts:
        if not _is_valid_fact(fact):
            continue

        db.save_companion_fact(
            user_id=user_id,
            pair_id=pair_id,
            companion_id=companion_id,
            category=fact.get("category", "preferences"),
            key=fact["key"],
            value=str(fact["value"]).strip(),
            confidence=_safe_float(fact.get("confidence"), default=0.8),
            source_message_id=source_message_id,
            source_type="extractor",
        )


def _save_entities(user_id: str, pair_id: str, companion_id: str, entities: list[dict]) -> dict[str, int]:
    entity_name_to_id: dict[str, int] = {}

    for entity in entities:
        name = (entity.get("name") or "").strip()
        entity_type = (entity.get("type") or "").strip()
        if not name or entity_type not in {"person", "place", "organization", "concept", "event"}:
            continue

        entity_id = db.upsert_entity(
            user_id=user_id,
            pair_id=pair_id,
            companion_id=companion_id,
            name=name,
            entity_type=entity_type,
            description=(entity.get("description") or "").strip() or None,
            relationship_to_user=(entity.get("relationship_to_user") or "").strip() or None,
            emotional_valence=_clamp(_safe_float(entity.get("emotional_valence")), -1.0, 1.0),
        )
        entity_name_to_id[name.lower()] = entity_id

    return entity_name_to_id


def _save_relationships(
    user_id: str,
    pair_id: str,
    companion_id: str,
    entity_name_to_id: dict[str, int],
    relationships: list[dict],
):
    for relationship in relationships:
        entity_a_name = (relationship.get("entity_a") or "").strip()
        entity_b_name = (relationship.get("entity_b") or "").strip()
        if not entity_a_name or not entity_b_name:
            continue

        entity_a_id = entity_name_to_id.get(entity_a_name.lower())
        entity_b_id = entity_name_to_id.get(entity_b_name.lower())
        if not entity_a_id or not entity_b_id or entity_a_id == entity_b_id:
            continue

        db.save_entity_relationship(
            user_id=user_id,
            pair_id=pair_id,
            companion_id=companion_id,
            entity_a_id=entity_a_id,
            entity_b_id=entity_b_id,
            relationship_type=(relationship.get("relationship_type") or "").strip() or None,
            description=(relationship.get("description") or "").strip() or None,
        )


def _save_emotions(user_id: str, pair_id: str, companion_id: str, message_id: Optional[int], emotions: list[dict]):
    for item in emotions:
        emotion = (item.get("emotion") or "").strip()
        if not emotion:
            continue
        intensity = _clamp(_safe_float(item.get("intensity"), default=0.5), 0.0, 1.0)
        db.log_emotional_event(
            user_id=user_id,
            pair_id=pair_id,
            companion_id=companion_id,
            message_id=message_id,
            emotion=emotion,
            intensity=intensity,
            trigger_topic=(item.get("trigger_topic") or "").strip() or None,
            trigger_entity=(item.get("trigger_entity") or "").strip() or None,
            valence=emotion_to_valence(emotion),
        )


def _save_behavioral_patterns(user_id: str, pair_id: str, companion_id: str, patterns: list[dict]):
    for pattern in patterns:
        description = (pattern.get("description") or "").strip()
        pattern_type = (pattern.get("pattern_type") or "").strip()
        if not description or pattern_type not in {"temporal", "emotional", "communicative", "topical", "relational"}:
            continue

        db.upsert_behavioral_pattern(
            user_id=user_id,
            pair_id=pair_id,
            companion_id=companion_id,
            pattern_type=pattern_type,
            description=description,
            evidence_count=1,
            confidence=_clamp(_safe_float(pattern.get("confidence"), default=0.55), 0.0, 1.0),
            source="extractor",
        )


async def _save_memories_to_chroma(
    user_id: str,
    pair_id: str,
    companion_id: str,
    conversation_id: str,
    memories: list[dict],
    source_message_ids: list[int],
) -> None:
    try:
        from memory.retriever import get_chroma_collection

        collection = get_chroma_collection(pair_id=pair_id, user_id=user_id)

        for memory in memories:
            content = (memory.get("content") or "").strip()
            if len(content) < 12:
                continue

            chroma_id = str(uuid.uuid4())
            title = (memory.get("title") or "").strip() or content[:80]
            emotion_tag = (memory.get("emotion_tag") or "").strip() or None
            importance = _clamp(_safe_float(memory.get("importance"), default=0.5), 0.0, 1.0)

            collection.add(
                ids=[chroma_id],
                documents=[content],
                metadatas=[{
                    "user_id": user_id,
                    "pair_id": pair_id,
                    "companion_id": companion_id,
                    "conversation_id": conversation_id,
                    "title": title,
                    "emotion_tag": emotion_tag or "",
                    "emotional_weight": importance,
                }],
            )

            db.log_memory(
                chroma_id=chroma_id,
                user_id=user_id,
                pair_id=pair_id,
                companion_id=companion_id,
                content=content,
                title=title,
                emotion_tag=emotion_tag,
                emotional_weight=importance,
                strength=max(0.9, importance),
                conversation_id=conversation_id,
                source_message_ids=source_message_ids,
            )

    except Exception as exc:
        logger.error("Failed to save memories to ChromaDB: %s", exc, exc_info=True)


def _format_messages_for_extraction(messages: list[dict]) -> str:
    lines = []
    for message in messages:
        role = "User" if message["role"] == "user" else "Companion"
        lines.append(f"{role}: {message['content']}")
    return "\n".join(lines)


def _latest_user_message_id(messages: list[dict]) -> Optional[int]:
    for message in reversed(messages):
        if message.get("role") == "user":
            return int(message["id"])
    return None


def _normalize_topics(topics: list) -> list[str]:
    normalized = []
    for topic in topics:
        value = str(topic).strip()
        if value and value not in normalized:
            normalized.append(value)
    return normalized[:8]


def _is_valid_fact(fact: dict) -> bool:
    value = str(fact.get("value", "")).strip()
    key = str(fact.get("key", "")).strip()
    return bool(key and value and len(key) < 80 and len(value) < 500)


def _safe_float(value, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _clamp(value: float, lower: float, upper: float) -> float:
    return max(lower, min(value, upper))
