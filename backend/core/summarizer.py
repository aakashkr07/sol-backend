import logging
from typing import Optional

from config import settings
from core.llm import generate_reply
from memory.analysis import emotional_direction_from_events, infer_themes
from memory.store import db

logger = logging.getLogger(__name__)

MIN_SIGNALS_FOR_SYNTHESIS = 4
MAX_FACTS = 8
MAX_EPISODES = 8
MAX_PATTERNS = 5
MAX_CONVERSATIONS = 4
MAX_CONFLICTS = 4

NARRATIVE_SYSTEM_PROMPT = """You write compact internal memory summaries for a deeply relational AI companion.
Return plain text only.

Goals:
- Capture the user's current life phase and emotional arc.
- Preserve continuity across time, not just recap one chat.
- Notice contradictions, recurring themes, and what still feels unresolved.
- Sound observant, emotionally intelligent, and human.

Rules:
- Write 5-7 sentences.
- Do not address the user directly.
- Do not mention AI, prompts, or retrieval.
- Do not invent specifics that are not in the notes.
- Treat contradictions as shifts or uncertainty, not mistakes."""


async def run_pair_memory_maintenance(
    user_id: str,
    pair_id: str,
    companion_id: str,
    conversation_id: Optional[str] = None,
) -> Optional[dict]:
    relationship_state = db.get_relationship_state_snapshot(pair_id)
    current_narrative = db.get_current_narrative(user_id, pair_id=pair_id) or {}
    last_updated = current_narrative.get("created_at")

    fact_rows = db.get_user_fact_rows(user_id, pair_id=pair_id, limit=MAX_FACTS)
    conflicts = db.get_fact_conflicts(pair_id, limit=MAX_CONFLICTS)
    recent_conflicts = [
        item
        for item in conflicts
        if _is_newer_than(item.get("current_updated_at"), last_updated)
        or _is_newer_than(item.get("previous_updated_at"), last_updated)
    ]
    recent_emotions = db.get_recent_emotions_since(user_id, last_updated, pair_id=pair_id, limit=10)
    recent_memories = db.get_recent_memory_rows(user_id, pair_id=pair_id, limit=MAX_EPISODES, since=last_updated)
    patterns = db.get_active_patterns(user_id, pair_id=pair_id, limit=MAX_PATTERNS)
    conversation_summaries = db.get_recent_conversation_summaries(pair_id, limit=MAX_CONVERSATIONS)

    new_signal_count = (
        len(recent_emotions)
        + len(recent_memories)
        + len([item for item in conversation_summaries if _is_newer_than(item.get("started_at"), last_updated)])
    )
    if new_signal_count < MIN_SIGNALS_FOR_SYNTHESIS and not recent_conflicts:
        db.apply_memory_decay(pair_id)
        return None

    summary = await _generate_narrative(
        relationship_state=relationship_state,
        facts=fact_rows,
        conflicts=recent_conflicts or conflicts[:2],
        emotions=recent_emotions,
        memories=recent_memories,
        patterns=patterns,
        conversations=conversation_summaries,
        previous_summary=current_narrative.get("summary"),
    )
    if not summary:
        db.apply_memory_decay(pair_id)
        return None

    timestamps = [
        value
        for value in [*[item.get("created_at") for item in recent_emotions], *[item.get("created_at") for item in recent_memories]]
        if value
    ]
    if conversation_summaries:
        timestamps.extend(item.get("started_at") for item in conversation_summaries if item.get("started_at"))
        timestamps.extend(item.get("ended_at") for item in conversation_summaries if item.get("ended_at"))

    period_start = min(timestamps) if timestamps else last_updated
    period_end = max(timestamps) if timestamps else None
    themes = infer_themes(recent_memories or fact_rows, recent_emotions)
    direction = emotional_direction_from_events(recent_emotions)

    db.save_narrative_summary(
        user_id=user_id,
        pair_id=pair_id,
        companion_id=companion_id,
        period_start=period_start,
        period_end=period_end,
        summary=summary,
        themes=themes,
        emotional_direction=direction,
    )
    decayed = db.apply_memory_decay(pair_id)

    return {
        "summary": summary,
        "themes": themes,
        "emotional_direction": direction,
        "decayed_memories": decayed,
        "relationship_state": relationship_state,
    }


async def _generate_narrative(
    relationship_state: Optional[dict],
    facts: list[dict],
    conflicts: list[dict],
    emotions: list[dict],
    memories: list[dict],
    patterns: list[dict],
    conversations: list[dict],
    previous_summary: Optional[str] = None,
) -> Optional[str]:
    prompt = _build_narrative_prompt(
        relationship_state=relationship_state,
        facts=facts,
        conflicts=conflicts,
        emotions=emotions,
        memories=memories,
        patterns=patterns,
        conversations=conversations,
        previous_summary=previous_summary,
    )

    try:
        return await generate_reply(
            messages=[{"role": "user", "content": prompt}],
            system_prompt=NARRATIVE_SYSTEM_PROMPT,
            temperature=0.25,
            max_tokens=260,
            model=settings.LLM_FALLBACK_MODEL,
        )
    except Exception as exc:
        logger.warning("Narrative synthesis failed, using heuristic fallback: %s", exc)
        return _heuristic_narrative(
            relationship_state=relationship_state,
            facts=facts,
            conflicts=conflicts,
            emotions=emotions,
            memories=memories,
            patterns=patterns,
            conversations=conversations,
            previous_summary=previous_summary,
        )


def _build_narrative_prompt(
    relationship_state: Optional[dict],
    facts: list[dict],
    conflicts: list[dict],
    emotions: list[dict],
    memories: list[dict],
    patterns: list[dict],
    conversations: list[dict],
    previous_summary: Optional[str],
) -> str:
    sections = []

    if relationship_state:
        sections.append(
            "Relationship state:\n"
            f"- stage: {relationship_state.get('stage')}\n"
            f"- closeness: {relationship_state.get('closeness')}\n"
            f"- trust: {relationship_state.get('trust')}\n"
            f"- openness: {relationship_state.get('openness')}\n"
            f"- comfort: {relationship_state.get('comfort')}\n"
            f"- rhythm: {relationship_state.get('rhythm')}\n"
            f"- topic familiarity: {relationship_state.get('topic_familiarity')}"
        )

    if previous_summary:
        sections.append(f"Previous narrative summary:\n- {previous_summary}")

    if facts:
        fact_lines = [
            f"- {fact['fact_key']}: {fact['fact_value']} (confidence {float(fact.get('confidence') or 0.0):.2f})"
            for fact in facts[:MAX_FACTS]
        ]
        sections.append("Stable facts:\n" + "\n".join(fact_lines))

    if conflicts:
        conflict_lines = [
            "- "
            + f"{item['fact_key']} shifted from {item['previous_value']} to {item['current_value']}"
            for item in conflicts[:MAX_CONFLICTS]
        ]
        sections.append("Known shifts or contradictions:\n" + "\n".join(conflict_lines))

    if emotions:
        emotion_lines = []
        for event in emotions[:10]:
            line = f"- {event.get('emotion')} at intensity {float(event.get('intensity') or 0.0):.2f}"
            if event.get("trigger_entity"):
                line += f" around {event['trigger_entity']}"
            elif event.get("trigger_topic"):
                line += f" around {event['trigger_topic']}"
            emotion_lines.append(line)
        sections.append("Recent emotions:\n" + "\n".join(emotion_lines))

    if memories:
        memory_lines = [
            f"- {memory.get('title') or 'Episode'}: {memory.get('content') or ''}"
            for memory in memories[:MAX_EPISODES]
        ]
        sections.append("Recent episodes:\n" + "\n".join(memory_lines))

    if patterns:
        pattern_lines = [
            f"- {pattern.get('description')} (confidence {float(pattern.get('confidence') or 0.0):.2f})"
            for pattern in patterns[:MAX_PATTERNS]
        ]
        sections.append("Recurring patterns:\n" + "\n".join(pattern_lines))

    if conversations:
        convo_lines = []
        for item in conversations[:MAX_CONVERSATIONS]:
            topics = ", ".join(item.get("topics_discussed") or [])
            summary = item.get("session_summary") or ""
            arc = item.get("emotional_arc") or ""
            line = f"- {summary}"
            if topics:
                line += f" | topics: {topics}"
            if arc:
                line += f" | arc: {arc}"
            convo_lines.append(line)
        sections.append("Recent conversation summaries:\n" + "\n".join(convo_lines))

    sections.append("Write the updated internal life narrative.")
    return "\n\n".join(section for section in sections if section.strip())


def _heuristic_narrative(
    relationship_state: Optional[dict],
    facts: list[dict],
    conflicts: list[dict],
    emotions: list[dict],
    memories: list[dict],
    patterns: list[dict],
    conversations: list[dict],
    previous_summary: Optional[str] = None,
) -> str:
    themes = infer_themes(memories or facts, emotions)
    direction = emotional_direction_from_events(emotions)
    dominant_emotion = emotions[0]["emotion"] if emotions else "mixed"
    memory_text = (memories[0].get("title") or memories[0].get("content")) if memories else None
    pattern_text = patterns[0]["description"] if patterns else None
    session_text = conversations[0].get("session_summary") if conversations else None
    stage = relationship_state.get("stage") if relationship_state else "new"

    lines = [
        f"Lately their life has felt mostly {dominant_emotion}, with a {direction} emotional direction overall."
    ]
    if themes:
        lines.append(f"The main threads around them right now seem to be {', '.join(themes[:3])}.")
    if memory_text:
        lines.append(f"A recent moment still carrying weight is {memory_text}.")
    elif session_text:
        lines.append(f"A recent conversation centered on {session_text[0].lower() + session_text[1:]}.")
    if pattern_text:
        lines.append(f"A recurring pattern is that {pattern_text[0].lower() + pattern_text[1:]}")
    if conflicts:
        conflict = conflicts[0]
        lines.append(
            f"One detail that seems to have shifted is {conflict['fact_key'].replace('_', ' ')} moving from "
            f"{conflict['previous_value']} to {conflict['current_value']}."
        )
    elif facts:
        fact = facts[0]
        lines.append(f"A stable background detail is {fact['fact_key'].replace('_', ' ')}: {fact['fact_value']}.")
    if previous_summary and stage in {"close", "bonded"}:
        lines.append("The broader picture feels continuous rather than isolated, with familiar themes resurfacing.")

    return " ".join(lines[:6])


def _is_newer_than(value: Optional[str], threshold: Optional[str]) -> bool:
    if not value:
        return False
    if not threshold:
        return True
    return value > threshold
