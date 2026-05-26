import logging
from typing import Optional

from config import settings
from memory.retriever import format_memories_for_prompt, retrieve_relevant_memories
from memory.store import db
from personality.loader import build_system_prompt, load_character

logger = logging.getLogger(__name__)

FACT_LIMIT = 12
ENTITY_LIMIT = 6
PATTERN_LIMIT = 5
EMOTION_LIMIT = 6
RELATIONSHIP_LIMIT = 6


async def build_context(
    user_id: str,
    current_message: str,
    conversation_id: Optional[str] = None,
    character_id: Optional[str] = None,
) -> tuple[str, list[dict]]:
    user = db.get_user(user_id)
    if not user:
        user = db.get_or_create_user(user_id)

    cid = character_id or user.get("character_id") or settings.DEFAULT_CHARACTER
    session_count = db.get_total_sessions(user_id)
    active_facts = db.get_user_facts(user_id)
    fact_rows = db.get_user_fact_rows(user_id, limit=FACT_LIMIT)
    user_name = user.get("preferred_name") or user.get("name")

    character = load_character(cid)
    base_system_prompt = build_system_prompt(
        character=character,
        user_name=user_name,
        session_count=session_count,
        user_facts=active_facts,
    )

    history_messages = db.get_recent_messages(
        user_id=user_id,
        limit=settings.RECENT_HISTORY_TURNS,
        conversation_id=conversation_id,
    )
    memory_query = _build_memory_query(current_message, history_messages)
    episodic_memories = retrieve_relevant_memories(
        user_id=user_id,
        query_text=memory_query,
        n_results=settings.MEMORY_RETRIEVAL_COUNT,
    )

    entities = db.get_entities_for_context(user_id, memory_query, limit=ENTITY_LIMIT)
    relationships = db.get_relationships_for_entities(
        user_id=user_id,
        entity_ids=[int(entity["id"]) for entity in entities],
        limit=RELATIONSHIP_LIMIT,
    )
    emotional_summary = db.get_emotional_summary(user_id, limit=EMOTION_LIMIT)
    recent_emotions = db.get_recent_emotional_events(user_id, limit=EMOTION_LIMIT)
    active_patterns = db.get_active_patterns(user_id, limit=PATTERN_LIMIT)
    current_narrative = db.get_current_narrative(user_id)

    layered_memory_block = _build_layered_memory_block(
        fact_rows=fact_rows,
        entities=entities,
        relationships=relationships,
        emotional_summary=emotional_summary,
        recent_emotions=recent_emotions,
        active_patterns=active_patterns,
        current_narrative=current_narrative,
        episodic_memories=episodic_memories,
    )

    final_system_prompt = _assemble_system_prompt(
        base_prompt=base_system_prompt,
        layered_memory_block=layered_memory_block,
        session_count=session_count,
    )

    messages = _format_history_as_messages(history_messages)

    if settings.DEBUG:
        logger.debug(
            "Context built for %s: %s facts, %s entities, %s patterns, %s retrieved episodes",
            user_id,
            len(fact_rows),
            len(entities),
            len(active_patterns),
            len(episodic_memories),
        )

    return final_system_prompt, messages


def _assemble_system_prompt(
    base_prompt: str,
    layered_memory_block: str,
    session_count: int,
) -> str:
    sections = [base_prompt]

    if layered_memory_block:
        sections.append(
            "\n---\nMEMORY SYSTEM CONTEXT:\n"
            "Use this layered context naturally. Reference it only when it genuinely helps."
            " Do not dump it back to the user. Treat patterns as soft signals, not hard truths.\n\n"
            f"{layered_memory_block}\n---"
        )

    if session_count == 1:
        sections.append(
            "\nThis is the first conversation. Be warm, curious, and attentive while you learn who they are."
        )
    elif session_count <= 3:
        sections.append(
            f"\nThis is conversation #{session_count}. You can gently build on earlier moments when it feels natural."
        )
    else:
        sections.append(
            "\nYou know this person across time. Pay attention to continuity, shifts in tone, and what seems unresolved."
        )

    return "\n".join(sections)


def _build_layered_memory_block(
    fact_rows: list[dict],
    entities: list[dict],
    relationships: list[dict],
    emotional_summary: dict,
    recent_emotions: list[dict],
    active_patterns: list[dict],
    current_narrative: Optional[dict],
    episodic_memories: list[dict],
) -> str:
    sections = []

    fact_lines = [
        f"- {row['fact_key']}: {row['fact_value']} (confidence {float(row['confidence']):.2f})"
        for row in fact_rows[:FACT_LIMIT]
    ]
    if fact_lines:
        sections.append("Hard Facts:\n" + "\n".join(fact_lines))

    entity_lines = []
    for entity in entities[:ENTITY_LIMIT]:
        detail = entity["name"]
        if entity.get("relationship_to_user"):
            detail += f" - {entity['relationship_to_user']}"
        if entity.get("description"):
            detail += f" ({entity['description']})"
        entity_lines.append(f"- {detail}")
    if entity_lines:
        sections.append("Important Entities:\n" + "\n".join(entity_lines))

    relationship_lines = []
    for relationship in relationships[:RELATIONSHIP_LIMIT]:
        description = relationship.get("description") or relationship.get("relationship_type") or "connected"
        relationship_lines.append(
            f"- {relationship['entity_a_name']} <-> {relationship['entity_b_name']}: {description}"
        )
    if relationship_lines:
        sections.append("Relationship Map:\n" + "\n".join(relationship_lines))

    emotion_lines = []
    baseline = emotional_summary.get("baseline")
    recent_average = emotional_summary.get("recent_average")
    if baseline is not None:
        emotion_lines.append(f"- Emotional baseline: {baseline:.2f} on a 0.0-1.0 scale")
    if recent_average is not None:
        emotion_lines.append(f"- Recent average mood: {recent_average:.2f}")
    if emotional_summary.get("direction"):
        emotion_lines.append(f"- Recent direction: {emotional_summary['direction']}")
    if emotional_summary.get("dominant_emotions"):
        emotion_lines.append(
            f"- Dominant recent emotions: {', '.join(emotional_summary['dominant_emotions'])}"
        )
    for event in recent_emotions[:4]:
        line = f"- {event['emotion']} at intensity {float(event.get('intensity', 0.0)):.2f}"
        if event.get("trigger_entity"):
            line += f" around {event['trigger_entity']}"
        elif event.get("trigger_topic"):
            line += f" around {event['trigger_topic']}"
        emotion_lines.append(line)
    if emotion_lines:
        sections.append("Emotional Timeline:\n" + "\n".join(emotion_lines))

    pattern_lines = [
        f"- {pattern['description']} (confidence {float(pattern['confidence']):.2f})"
        for pattern in active_patterns[:PATTERN_LIMIT]
    ]
    if pattern_lines:
        sections.append("Behavioral Patterns:\n" + "\n".join(pattern_lines))

    if current_narrative and current_narrative.get("summary"):
        sections.append("Current Life Narrative:\n" + current_narrative["summary"])

    episode_block = format_memories_for_prompt(episodic_memories)
    if episode_block:
        sections.append("Relevant Episodes:\n" + episode_block)

    return "\n\n".join(sections)


def _build_memory_query(current_message: str, recent_messages: list[dict]) -> str:
    parts = []
    for message in recent_messages[-3:]:
        if message.get("role") == "user":
            parts.append(message["content"])
    parts.append(current_message)
    return " ".join(parts)[:600]


def _format_history_as_messages(history: list[dict]) -> list[dict]:
    messages = []
    for message in history:
        role = message.get("role", "user")
        content = (message.get("content") or "").strip()
        if content and role in {"user", "assistant"}:
            messages.append({"role": role, "content": content})
    return messages


def get_or_create_conversation(user_id: str, character_id: str = "nova") -> str:
    conversation_id = db.get_current_conversation(user_id)
    if not conversation_id:
        conversation_id = db.create_conversation(user_id, character_id)
        logger.info("New conversation created for %s: %s", user_id, conversation_id)
    return conversation_id
