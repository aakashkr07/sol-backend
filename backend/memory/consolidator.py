import logging
from typing import Optional

from config import settings
from core.llm import generate_reply
from memory.analysis import emotional_direction_from_events, infer_themes
from memory.store import db

logger = logging.getLogger(__name__)

MIN_NEW_ITEMS_FOR_SUMMARY = 4
EMOTION_WINDOW = 10
MEMORY_WINDOW = 8

NARRATIVE_SYSTEM_PROMPT = """You write short internal narrative summaries for an AI companion.
Write a compact, emotionally intelligent summary of what this user has been going through lately.

Rules:
- Write 4-6 sentences max.
- Focus on patterns, emotional arc, important people, and current pressure points.
- Sound observant and caring, not clinical or robotic.
- Do not address the user directly.
- Do not invent specifics that are not present in the notes.
- Return plain text only."""


async def maybe_consolidate_narrative(user_id: str) -> Optional[str]:
    user = db.get_user(user_id) or {}
    last_updated = user.get("narrative_updated_at")

    recent_emotions = db.get_recent_emotions_since(user_id, last_updated, limit=EMOTION_WINDOW)
    recent_memories = db.get_recent_memory_rows(user_id, limit=MEMORY_WINDOW, since=last_updated)

    if len(recent_emotions) + len(recent_memories) < MIN_NEW_ITEMS_FOR_SUMMARY:
        return None

    facts = db.get_user_fact_rows(user_id, limit=8)
    patterns = db.get_active_patterns(user_id, limit=4)
    summary = await _generate_narrative(user_id, facts, recent_emotions, recent_memories, patterns)
    if not summary:
        return None

    timestamps = [item.get("created_at") for item in recent_emotions + recent_memories if item.get("created_at")]
    period_start = min(timestamps) if timestamps else None
    period_end = max(timestamps) if timestamps else None
    themes = infer_themes(recent_memories, recent_emotions)
    direction = emotional_direction_from_events(recent_emotions)

    db.save_narrative_summary(
        user_id=user_id,
        period_start=period_start,
        period_end=period_end,
        summary=summary,
        themes=themes,
        emotional_direction=direction,
    )
    return summary


async def _generate_narrative(
    user_id: str,
    facts: list[dict],
    emotions: list[dict],
    memories: list[dict],
    patterns: list[dict],
) -> Optional[str]:
    prompt = _build_narrative_prompt(user_id, facts, emotions, memories, patterns)

    try:
        return await generate_reply(
            messages=[{"role": "user", "content": prompt}],
            system_prompt=NARRATIVE_SYSTEM_PROMPT,
            temperature=0.25,
            max_tokens=220,
            model=settings.LLM_FALLBACK_MODEL,
        )
    except Exception as exc:
        logger.warning("Narrative synthesis failed, using heuristic fallback: %s", exc)
        return _heuristic_narrative(facts, emotions, memories, patterns)


def _build_narrative_prompt(
    user_id: str,
    facts: list[dict],
    emotions: list[dict],
    memories: list[dict],
    patterns: list[dict],
) -> str:
    fact_lines = [
        f"- {fact['fact_key']}: {fact['fact_value']}"
        for fact in facts[:6]
    ]
    emotion_lines = [
        f"- {event['emotion']} (intensity {float(event.get('intensity', 0.0)):.2f})"
        + (f" about {event['trigger_entity']}" if event.get("trigger_entity") else "")
        + (f" around {event['trigger_topic']}" if event.get("trigger_topic") else "")
        for event in emotions[:8]
    ]
    memory_lines = [
        f"- {memory.get('title') or memory.get('content', '')}"
        for memory in memories[:6]
    ]
    pattern_lines = [
        f"- {pattern['description']}"
        for pattern in patterns[:4]
    ]

    return "\n".join([
        f"User id: {user_id}",
        "",
        "Relevant facts:",
        *fact_lines,
        "",
        "Recent emotions:",
        *emotion_lines,
        "",
        "Recent episodes:",
        *memory_lines,
        "",
        "Active patterns:",
        *pattern_lines,
        "",
        "Write the narrative summary.",
    ])


def _heuristic_narrative(
    facts: list[dict],
    emotions: list[dict],
    memories: list[dict],
    patterns: list[dict],
) -> str:
    themes = infer_themes(memories, emotions)
    direction = emotional_direction_from_events(emotions)
    dominant_emotion = emotions[0]["emotion"] if emotions else "mixed"
    pattern_text = patterns[0]["description"] if patterns else None
    memory_text = memories[0].get("title") or memories[0].get("content") if memories else None

    lines = [
        f"Lately, the user's inner world has felt mostly {dominant_emotion} with a {direction} overall arc."
    ]
    if themes:
        lines.append(f"The main themes around them right now are {', '.join(themes[:3])}.")
    if memory_text:
        lines.append(f"A notable recent episode is {memory_text}.")
    if pattern_text:
        lines.append(f"A recurring pattern showing up is that {pattern_text[0].lower() + pattern_text[1:]}")
    if facts:
        highlighted = facts[0]
        lines.append(
            f"An important stable detail in the background is {highlighted['fact_key'].replace('_', ' ')}: {highlighted['fact_value']}."
        )

    return " ".join(lines[:5])
