import re
from datetime import datetime
from typing import Optional

from memory.store import db

DISCLOSURE_PATTERNS = [
    r"\bi feel\b",
    r"\bi felt\b",
    r"\bi'm\b",
    r"\bi am\b",
    r"\bi've been\b",
    r"\bi have been\b",
    r"\bi need\b",
    r"\bi want\b",
    r"\bi miss\b",
    r"\bi'm scared\b",
    r"\bi am scared\b",
]

EMOTION_PATTERNS = [
    r"\bsad\b",
    r"\banxious\b",
    r"\boverwhelmed\b",
    r"\blonely\b",
    r"\bangry\b",
    r"\bexcited\b",
    r"\bhopeful\b",
    r"\bproud\b",
    r"\bgrief\b",
]

QUESTION_PATTERNS = [
    r"\bhow did\b",
    r"\bwhat happened\b",
    r"\bare you\b",
    r"\bwhat do you think\b",
]


def on_session_started(pair_id: str) -> Optional[dict]:
    pair = db.get_pair_by_id(pair_id)
    if not pair:
        return None

    session_count = int(pair.get("total_sessions") or 0)
    last_started = _parse_ts(
        pair.get("last_interaction_at")
        or pair.get("last_user_message_at")
        or pair.get("last_companion_message_at")
    )
    now = datetime.utcnow()
    gap_days = ((now - last_started).total_seconds() / 86400.0) if last_started else None

    rhythm_delta = 0.0
    comfort_delta = 0.0
    closeness_delta = 0.0
    if session_count <= 1:
        rhythm_delta += 0.03
        comfort_delta += 0.02
    else:
        if gap_days is not None:
            if gap_days <= 2:
                rhythm_delta += 0.04
                comfort_delta += 0.02
            elif gap_days <= 7:
                rhythm_delta += 0.02
            elif gap_days > 21:
                rhythm_delta -= 0.03

        closeness_delta += min(0.03, 0.004 * min(session_count, 7))

    return _apply_pair_deltas(
        pair_id=pair_id,
        closeness_delta=closeness_delta,
        comfort_delta=comfort_delta,
        rhythm_delta=rhythm_delta,
        stage=_infer_stage(pair, closeness_shift=closeness_delta),
    )


def on_message_saved(
    pair_id: str,
    role: str,
    content: str,
    topics: Optional[list[str]] = None,
) -> Optional[dict]:
    pair = db.get_pair_by_id(pair_id)
    if not pair or not content.strip():
        return pair

    text = content.strip()
    if role == "user":
        deltas = _user_message_deltas(pair, text, topics or [])
    else:
        deltas = _assistant_message_deltas(pair, text)

    return _apply_pair_deltas(
        pair_id=pair_id,
        closeness_delta=deltas["closeness"],
        trust_delta=deltas["trust"],
        openness_delta=deltas["openness"],
        comfort_delta=deltas["comfort"],
        rhythm_delta=deltas["rhythm"],
        topic_familiarity_delta=deltas["topic_familiarity"],
        stage=_infer_stage(pair, closeness_shift=deltas["closeness"], trust_shift=deltas["trust"]),
    )


def refresh_after_extraction(pair_id: str, conversation_id: Optional[str] = None) -> Optional[dict]:
    pair = db.get_pair_by_id(pair_id)
    if not pair:
        return None

    active_patterns = db.get_active_patterns(pair["user_id"], pair_id=pair_id, limit=6)
    emotions = db.get_recent_emotional_events(pair["user_id"], pair_id=pair_id, limit=8)
    entities = db.get_entities_for_context(pair["user_id"], pair_id, "", limit=10)
    recent_messages = db.get_recent_messages(
        user_id=pair["user_id"],
        pair_id=pair_id,
        conversation_id=conversation_id,
        limit=10,
    )

    topic_overlap = _topic_overlap_score(recent_messages)
    topic_delta = 0.02 if topic_overlap >= 0.5 else 0.01 if topic_overlap >= 0.25 else 0.0
    openness_delta = 0.015 if _recent_vulnerability(emotions, active_patterns) else 0.0
    trust_delta = 0.015 if any("recurring" in (p.get("description") or "").lower() for p in active_patterns) else 0.0
    closeness_delta = 0.01 if len(entities) >= 3 else 0.0

    return _apply_pair_deltas(
        pair_id=pair_id,
        closeness_delta=closeness_delta,
        trust_delta=trust_delta,
        openness_delta=openness_delta,
        topic_familiarity_delta=topic_delta,
        stage=_infer_stage(pair, closeness_shift=closeness_delta, trust_shift=trust_delta),
    )


def _user_message_deltas(pair: dict, text: str, topics: list[str]) -> dict[str, float]:
    lowered = text.lower()
    length = len(text)
    word_count = len(text.split())
    disclosure_hits = _pattern_hits(lowered, DISCLOSURE_PATTERNS)
    emotion_hits = _pattern_hits(lowered, EMOTION_PATTERNS)
    question_hits = _pattern_hits(lowered, QUESTION_PATTERNS)

    openness = 0.006 + min(0.045, disclosure_hits * 0.012 + emotion_hits * 0.008)
    if length > 180:
        openness += 0.02
    elif length > 90:
        openness += 0.01

    trust = 0.004 + min(0.03, disclosure_hits * 0.01 + emotion_hits * 0.006)
    closeness = 0.004 + min(0.03, openness * 0.55 + (0.012 if word_count > 22 else 0.0))
    comfort = 0.004 + min(0.02, 0.008 if question_hits else 0.0)
    rhythm = 0.003 + (0.008 if length < 80 else 0.014 if length < 240 else 0.01)
    topic_familiarity = 0.005 + min(0.02, len(topics) * 0.004)

    if any(token in lowered for token in ["idk", "i don't know", "whatever", "fine", "nvm"]):
        comfort -= 0.008
        trust -= 0.005

    return {
        "closeness": closeness,
        "trust": trust,
        "openness": openness,
        "comfort": comfort,
        "rhythm": rhythm,
        "topic_familiarity": topic_familiarity,
    }


def _assistant_message_deltas(pair: dict, text: str) -> dict[str, float]:
    lowered = text.lower()
    question_hits = _pattern_hits(lowered, QUESTION_PATTERNS)
    warmth_bonus = 0.01 if any(token in lowered for token in ["hey", "wait", "okay", "right", "honestly"]) else 0.0
    follow_up_bonus = 0.012 if question_hits else 0.0

    return {
        "closeness": 0.004 + warmth_bonus,
        "trust": 0.003 + (0.007 if question_hits else 0.0),
        "openness": 0.0,
        "comfort": 0.006 + warmth_bonus,
        "rhythm": 0.006 + follow_up_bonus,
        "topic_familiarity": 0.003,
    }


def _apply_pair_deltas(
    pair_id: str,
    closeness_delta: float = 0.0,
    trust_delta: float = 0.0,
    openness_delta: float = 0.0,
    comfort_delta: float = 0.0,
    rhythm_delta: float = 0.0,
    topic_familiarity_delta: float = 0.0,
    stage: Optional[str] = None,
) -> Optional[dict]:
    db.conn.execute(
        """
        UPDATE relationship_pairs
        SET closeness_score = MIN(MAX(closeness_score + ?, 0.0), 1.0),
            trust_score = MIN(MAX(trust_score + ?, 0.0), 1.0),
            openness_score = MIN(MAX(openness_score + ?, 0.0), 1.0),
            comfort_score = MIN(MAX(comfort_score + ?, 0.0), 1.0),
            rhythm_score = MIN(MAX(rhythm_score + ?, 0.0), 1.0),
            topic_familiarity_score = MIN(MAX(topic_familiarity_score + ?, 0.0), 1.0),
            current_stage = COALESCE(?, current_stage),
            updated_at = ?
        WHERE id = ?
        """,
        (
            closeness_delta,
            trust_delta,
            openness_delta,
            comfort_delta,
            rhythm_delta,
            topic_familiarity_delta,
            stage,
            datetime.utcnow().isoformat(timespec="milliseconds"),
            pair_id,
        ),
    )
    return db.get_pair_by_id(pair_id)


def _infer_stage(
    pair: dict,
    closeness_shift: float = 0.0,
    trust_shift: float = 0.0,
) -> str:
    closeness = float(pair.get("closeness_score") or 0.0) + closeness_shift
    trust = float(pair.get("trust_score") or 0.0) + trust_shift
    sessions = int(pair.get("total_sessions") or 0)

    if sessions <= 1 and closeness < 0.24:
        return "new"
    if closeness < 0.34 or trust < 0.3:
        return "warming"
    if closeness < 0.56 or trust < 0.5:
        return "settled"
    if closeness < 0.76:
        return "close"
    return "bonded"


def _topic_overlap_score(messages: list[dict]) -> float:
    topic_sets = []
    for message in messages:
        topics = [str(topic).strip().lower() for topic in message.get("topics") or [] if str(topic).strip()]
        if topics:
            topic_sets.append(set(topics))
    if len(topic_sets) < 2:
        return 0.0

    overlap_count = 0
    comparisons = 0
    for i in range(1, len(topic_sets)):
        comparisons += 1
        if topic_sets[i - 1].intersection(topic_sets[i]):
            overlap_count += 1
    return overlap_count / max(1, comparisons)


def _recent_vulnerability(emotions: list[dict], patterns: list[dict]) -> bool:
    strong_emotion = any(
        float(event.get("intensity") or 0.0) >= 0.65 and float(event.get("valence") or 0.0) <= -0.25
        for event in emotions
    )
    expressive_pattern = any(
        "open up" in (pattern.get("description") or "").lower()
        or "vulnerab" in (pattern.get("description") or "").lower()
        for pattern in patterns
    )
    return strong_emotion or expressive_pattern


def _pattern_hits(text: str, patterns: list[str]) -> int:
    return sum(1 for pattern in patterns if re.search(pattern, text))


def _parse_ts(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value)
    except ValueError:
        return None
