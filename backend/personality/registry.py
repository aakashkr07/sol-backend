import hashlib
import logging
import re
from collections import Counter
from datetime import datetime
from typing import Optional

from memory.store import db
from personality.loader import Character, list_characters, load_character

logger = logging.getLogger(__name__)


def sync_companion_registry() -> None:
    for sort_order, character_id in enumerate(sorted(list_characters())):
        character = load_character(character_id)
        db.upsert_companion(
            companion_id=character.id,
            name=character.name,
            archetype=character.archetype or character.core_identity.get("vibe", ""),
            summary=character.summary or character.core_identity.get("vibe", ""),
            introduction_style=character.introduction_style or character.discovery.get("mode", ""),
            relationship_label=character.relationship_defaults.get("relationship_label", "friend"),
            match_weight=int(character.matching_profile.get("weight", 1) or 1),
            sort_order=sort_order,
            proactive_frequency=getattr(character, "proactive_frequency", "medium"),
            impulsiveness=getattr(character, "impulsiveness", 0.5),
            attachment_speed=getattr(character, "attachment_speed", 0.5),
            boredom_threshold=getattr(character, "boredom_threshold", 0.5),
            loneliness_tolerance=getattr(character, "loneliness_tolerance", 0.5),
            emotional_openness=getattr(character, "emotional_openness", 0.5),
            social_confidence=getattr(character, "social_confidence", 0.5),
            texting_consistency=getattr(character, "texting_consistency", 0.5),
            disappearance_tendency=getattr(character, "disappearance_tendency", 0.5),
            late_night_probability=getattr(character, "late_night_probability", 0.5),
            double_text_probability=getattr(character, "double_text_probability", 0.5),
            emotional_volatility=getattr(character, "emotional_volatility", 0.5),
        )


def get_active_companion_summaries() -> list[dict]:
    companions = []
    for character_id in sorted(list_characters()):
        character = load_character(character_id)
        companions.append({
            "id": character.id,
            "name": character.name,
            "archetype": character.archetype,
            "summary": character.summary or character.core_identity.get("vibe", ""),
            "introduction_style": character.introduction_style or character.discovery.get("mode", ""),
        })
    return companions


def choose_companion_for_user(user_id: str) -> Character:
    available = [load_character(character_id) for character_id in sorted(list_characters())]
    if not available:
        raise ValueError("No companion characters are available")

    chemistry = _build_user_chemistry_profile(user_id)
    ranked = _rank_characters_for_user(user_id, available, chemistry)
    return ranked[0]


def rank_companions_for_user(user_id: str) -> list[Character]:
    available = [load_character(character_id) for character_id in sorted(list_characters())]
    if not available:
        raise ValueError("No companion characters are available")

    chemistry = _build_user_chemistry_profile(user_id)
    return _rank_characters_for_user(user_id, available, chemistry)



def resolve_or_assign_primary_pair(
    user_id: str,
    requested_companion_id: Optional[str] = None,
    make_primary: bool = True,
) -> dict:
    if requested_companion_id:
        character = load_character(requested_companion_id)
        # Check if this pair already exists before creating anything
        existing_pair = db.get_pair(user_id, requested_companion_id)
        if existing_pair:
            if make_primary:
                db.set_primary_pair(existing_pair["id"])
            return db.get_pair_by_id(existing_pair["id"]) or existing_pair
    else:
        primary_pair = db.get_primary_pair(user_id)
        if primary_pair:
            return primary_pair
        existing_pairs = db.list_pairs_for_user(user_id)
        if existing_pairs:
            db.set_primary_pair(existing_pairs[0]["id"])
            return db.get_pair_by_id(existing_pairs[0]["id"]) or existing_pairs[0]
        character = choose_companion_for_user(user_id)

    # Ensure the companion is registered in the database to satisfy the foreign key constraint
    if not db.get_companion(character.id):
        db.upsert_companion(
            companion_id=character.id,
            name=character.name,
            archetype=character.archetype or character.core_identity.get("vibe", ""),
            summary=character.summary or character.core_identity.get("vibe", ""),
            introduction_style=character.introduction_style or character.discovery.get("mode", ""),
            relationship_label=character.relationship_defaults.get("relationship_label", "friend"),
            match_weight=int(character.matching_profile.get("weight", 1) or 1),
            sort_order=999,  # Default sort order for dynamically registered variants
            proactive_frequency=getattr(character, "proactive_frequency", "medium"),
            impulsiveness=getattr(character, "impulsiveness", 0.5),
            attachment_speed=getattr(character, "attachment_speed", 0.5),
            boredom_threshold=getattr(character, "boredom_threshold", 0.5),
            loneliness_tolerance=getattr(character, "loneliness_tolerance", 0.5),
            emotional_openness=getattr(character, "emotional_openness", 0.5),
            social_confidence=getattr(character, "social_confidence", 0.5),
            texting_consistency=getattr(character, "texting_consistency", 0.5),
            disappearance_tendency=getattr(character, "disappearance_tendency", 0.5),
            late_night_probability=getattr(character, "late_night_probability", 0.5),
            double_text_probability=getattr(character, "double_text_probability", 0.5),
            emotional_volatility=getattr(character, "emotional_volatility", 0.5),
        )
        logger.info("Dynamically registered companion variant in DB: %s", character.id)

    pair = db.get_or_create_relationship_pair(
        user_id=user_id,
        companion_id=character.id,
        assignment_source="explicit" if requested_companion_id else "matcher",
        assignment_reason=(
            f"user explicitly opened {character.name}"
            if requested_companion_id
            else _build_assignment_reason(user_id, character)
        ),
    )

    if requested_companion_id and make_primary:
        db.set_primary_pair(pair["id"])
        return db.get_pair_by_id(pair["id"]) or pair

    if not db.get_primary_pair(user_id):
        db.set_primary_pair(pair["id"])
        pair = db.get_pair_by_id(pair["id"]) or pair

    return pair


def build_opening_line(character: Character, session_count: int = 1) -> str:
    discovery = character.discovery or {}
    if session_count <= 1:
        custom_openers = discovery.get("first_session_openers") or discovery.get("openers") or []
        
        # Curated casual, accidental, observational first-session openers
        default_openers = [
            "u awake",
            "okay wait i think i opened your profile by accident earlier",
            "why is everyone awake rn",
            "random but hi",
            "you awake too?",
        ]
        
        # Filter out formal AI introductions from character json
        formal_words = ["assistant", "ai", "virtual", "chat", "help you", "hello, i am", "how can i help"]
        casual_custom = [
            o for o in custom_openers 
            if not any(w in o.lower() for w in formal_words)
        ]
        
        # Merge default low-pressure/accidental openers with casual custom ones
        openers = default_openers + casual_custom
    else:
        openers = discovery.get("returning_openers") or discovery.get("openers") or []

    if openers:
        digest = hashlib.sha256(f"{character.id}:{session_count}".encode("utf-8")).hexdigest()
        index = int(digest[:8], 16) % len(openers)
        return str(openers[index]).strip()

    return "hey"


def build_pair_payload(pair: dict) -> dict:
    companion = load_character(pair["companion_id"])
    return {
        "pair_id": pair["id"],
        "companion_id": companion.id,
        "companion_name": companion.name,
        "companion_summary": companion.summary or companion.core_identity.get("vibe", ""),
        "relationship_label": pair.get("relationship_label") or companion.relationship_defaults.get("relationship_label", "friend"),
        "is_primary": bool(pair.get("is_primary")),
        "assignment_status": pair.get("assignment_status"),
        "current_stage": pair.get("current_stage"),
        "proactive_enabled": bool(pair.get("proactive_enabled", 1)),
        "proactive_cadence": pair.get("proactive_cadence") or "balanced",
        "proactive_emotional_callbacks_enabled": bool(
            pair.get("proactive_emotional_callbacks_enabled", 1)
        ),
        "total_sessions": int(pair.get("total_sessions") or 0),
        "total_messages": int(pair.get("total_messages") or 0),
    }


def build_inbox_entries(user_id: str) -> list[dict]:
    pairs = db.list_pairs_for_user(user_id)
    pending_counts = db.get_pending_proactive_counts(user_id)
    entries = [
        _build_pair_inbox_entry(pair, pending_counts.get(pair["id"], 0))
        for pair in pairs
    ]

    surfaced_companions = {pair["companion_id"] for pair in pairs}
    discovery_limit = _discovery_limit_for_user(pairs)
    for character in _ordered_discovery_candidates(user_id):
        if character.id in surfaced_companions:
            continue
        if discovery_limit <= 0:
            break
        entries.append(_build_discovery_inbox_entry(user_id, character, pairs))
        discovery_limit -= 1

    return sorted(entries, key=_inbox_sort_key, reverse=True)


def _build_pair_inbox_entry(pair: dict, unread_count: int) -> dict:
    companion = load_character(pair["companion_id"])
    latest_message = db.get_latest_message_for_pair(pair["id"])
    latest_role = latest_message.get("role") if latest_message else None
    
    # If a pair has no message history (inactive threads)
    if not latest_message:
        waiting_on_user = False
        unread_count = 0
        
        # Stable dynamic social presence
        presence_options = ["active 12m ago", "online tonight", "quiet for now"]
        digest = hashlib.sha256(pair["id"].encode("utf-8")).hexdigest()
        presence_idx = int(digest[:8], 16) % len(presence_options)
        social_presence = presence_options[presence_idx]
        
        preview_text = companion.summary or build_opening_line(companion, session_count=1)
        preview_at = (
            pair.get("last_interaction_at")
            or pair.get("last_session_started_at")
            or pair.get("updated_at")
            or pair.get("created_at")
        )
        
        # Check social graph connections for active companion references
        arrival_hint = ""
        status_text = _status_text_for_pair(pair)
        
        # Find active companions (other pairs with messages or primary status)
        user_pairs = db.list_pairs_for_user(pair["user_id"])
        active_companion_ids = {
            p["companion_id"] for p in user_pairs
            if p["id"] != pair["id"] and (p.get("is_primary") or int(p.get("total_messages") or 0) > 0)
        }
        
        related_ids = [item.get("character_id") for item in companion.social_graph.get("connections", [])]
        connected_active_id = next((cid for cid in related_ids if cid in active_companion_ids), None)
        if connected_active_id:
            active_name = load_character(connected_active_id).name
            arrival_hint = f"{active_name} mentioned you"
            status_text = f"{active_name} mentioned you"
    else:
        waiting_on_user = bool(unread_count) or latest_role == "assistant"
        preview_text = (
            latest_message["content"].strip()
            if (latest_message.get("content") or "").strip()
            else companion.summary or build_opening_line(companion, session_count=1)
        )
        preview_at = (
            latest_message.get("created_at")
            if latest_message
            else pair.get("last_interaction_at")
            or pair.get("last_session_started_at")
            or pair.get("updated_at")
            or pair.get("created_at")
        )
        social_presence = _social_presence_for_pair(pair, latest_role, unread_count)
        arrival_hint = ""
        status_text = _status_text_for_pair(pair)

    conversation_id = db.get_current_conversation(pair["user_id"], pair_id=pair["id"])

    return {
        "entry_kind": "thread",
        "pair_id": pair["id"],
        "companion_id": companion.id,
        "companion_name": companion.name,
        "companion_summary": companion.summary or companion.core_identity.get("vibe", ""),
        "preview_text": preview_text,
        "preview_at": preview_at,
        "status_text": status_text,
        "status_priority": 2 if unread_count else 1,
        "current_conversation_id": conversation_id,
        "is_primary": bool(pair.get("is_primary")),
        "is_discovered": True,
        "unread_count": unread_count,
        "latest_role": latest_role,
        "waiting_on_user": waiting_on_user,
        "social_presence": social_presence,
        "arrival_hint": arrival_hint,
        "relationship_stage": pair.get("current_stage") or "new",
        "total_sessions": int(pair.get("total_sessions") or 0),
    }


def _build_discovery_inbox_entry(user_id: str, character: Character, pairs: list[dict]) -> dict:
    related_ids = [item.get("character_id") for item in character.social_graph.get("connections", [])]
    active_pairs = [
        pair for pair in pairs
        if pair.get("is_primary") or int(pair.get("total_messages") or 0) > 0 or int(pair.get("total_sessions") or 0) > 0
    ]
    known_pair = next((pair for pair in active_pairs if pair["companion_id"] in related_ids), None)
    arrival_hint = _arrival_hint_for_character(character, known_pair)
    preview_text = _arrival_preview_for_character(character, known_pair)
    sort_anchor = known_pair.get("updated_at") if known_pair else None

    return {
        "entry_kind": "arrival",
        "pair_id": "",
        "companion_id": character.id,
        "companion_name": character.name,
        "companion_summary": character.summary or character.core_identity.get("vibe", ""),
        "preview_text": preview_text,
        "preview_at": sort_anchor or _stable_discovery_timestamp(user_id, character.id),
        "status_text": arrival_hint,
        "status_priority": 3,
        "current_conversation_id": None,
        "is_primary": False,
        "is_discovered": False,
        "unread_count": 1,
        "latest_role": "assistant",
        "waiting_on_user": True,
        "social_presence": "new around you",
        "arrival_hint": arrival_hint,
        "relationship_stage": "arrival",
        "total_sessions": 0,
    }


def _discovery_limit_for_user(pairs: list[dict]) -> int:
    if not pairs:
        return 0
    total_sessions = sum(int(pair.get("total_sessions") or 0) for pair in pairs)
    if total_sessions >= 7:
        return 4
    if total_sessions >= 3:
        return 3
    if total_sessions >= 1:
        return 2
    return 1


def _ordered_discovery_candidates(user_id: str) -> list[Character]:
    characters = [load_character(character_id) for character_id in sorted(list_characters())]
    chemistry = _build_user_chemistry_profile(user_id)
    return _rank_characters_for_user(user_id, characters, chemistry)


def _arrival_hint_for_character(character: Character, known_pair: Optional[dict]) -> str:
    if known_pair:
        known_name = load_character(known_pair["companion_id"]).name
        for connection in character.social_graph.get("connections", []):
            if connection.get("character_id") == known_pair["companion_id"]:
                return connection.get("arrival_hint") or f"{known_name} mentioned you"
        return f"{known_name} mentioned you"
    return character.discovery.get("mode") or "new here"


def _arrival_preview_for_character(character: Character, known_pair: Optional[dict]) -> str:
    if known_pair:
        for connection in character.social_graph.get("connections", []):
            if connection.get("character_id") == known_pair["companion_id"]:
                intro_lines = connection.get("intro_lines") or []
                if intro_lines:
                    return str(intro_lines[0]).strip()
    openers = character.discovery.get("first_session_openers") or []
    if openers:
        return str(openers[0]).strip()
    return build_opening_line(character, session_count=1)


def _stable_discovery_timestamp(user_id: str, companion_id: str) -> str:
    digest = hashlib.sha256(f"arrival:{user_id}:{companion_id}".encode("utf-8")).hexdigest()
    return f"arrival-{digest[:12]}"


def _status_text_for_pair(pair: dict) -> str:
    stage = (pair.get("current_stage") or "new").lower()
    if stage == "new":
        return "new thread"
    if stage == "warming":
        return "familiar now"
    if stage == "settled":
        return "settled rhythm"
    if stage == "close":
        return "close"
    if stage == "bonded":
        return "always around"
    return "active"


def _social_presence_for_pair(pair: dict, latest_role: Optional[str], unread_count: int) -> str:
    if unread_count > 0:
        return "waiting on you"
    if latest_role == "assistant":
        return "left something behind"
    if pair.get("proactive_last_reason") == "emotional_callback":
        return "still thinking about earlier"
    if stage := (pair.get("current_stage") or "").lower():
        if stage in {"close", "bonded"}:
            return "feels lived in"
    return "quiet for now"


def _inbox_sort_key(entry: dict) -> tuple[int, str]:
    return (
        int(entry.get("status_priority") or 0),
        str(entry.get("preview_at") or ""),
    )


def _rank_characters_for_user(
    user_id: str,
    characters: list[Character],
    chemistry: Optional[dict] = None,
) -> list[Character]:
    profile = chemistry or _build_user_chemistry_profile(user_id)
    return sorted(
        characters,
        key=lambda character: (
            _compatibility_score(profile, character),
            int(character.matching_profile.get("weight", 1) or 1),
            _stable_tiebreaker(user_id, character.id),
        ),
        reverse=True,
    )


def _compatibility_score(profile: dict, character: Character) -> float:
    spec = character.matching_profile or {}
    score = 0.0
    score += 0.18 * _categorical_match(
        profile.get("active_window"),
        spec.get("active_window"),
        order=["morning", "day", "evening", "late_night"],
    )
    score += 0.14 * _categorical_match(
        profile.get("response_pace"),
        spec.get("response_pace"),
        order=["fast", "measured", "slow"],
    )
    score += 0.14 * _categorical_match(
        profile.get("message_length_style"),
        spec.get("message_length_style"),
        order=["short", "medium", "long"],
    )
    score += 0.15 * _categorical_match(
        profile.get("openness_level"),
        spec.get("openness_level"),
        order=["guarded", "warm", "intense"],
    )
    score += 0.13 * _categorical_match(
        profile.get("humor_style"),
        spec.get("humor_style"),
        order=["dry", "intellectual", "playful", "chaotic", "soft"],
    )
    score += 0.12 * _categorical_match(
        profile.get("rhythm"),
        spec.get("rhythm"),
        order=["slow", "steady", "burst"],
    )
    score += 0.10 * _categorical_match(
        profile.get("social_energy"),
        spec.get("social_energy"),
        order=["quiet", "balanced", "warm", "intense"],
    )
    score += min(0.04, max(0.0, (float(profile.get("confidence") or 0.0) * 0.04)))
    score += min(0.05, max(0.0, (int(spec.get("weight", 1) or 1) - 1) * 0.01))
    return round(score, 4)


def _build_user_chemistry_profile(user_id: str) -> dict:
    import json
    messages = db.get_recent_messages(user_id=user_id, limit=120)
    user_messages = [message for message in messages if message.get("role") == "user"]
    user = db.get_user(user_id) or {}

    if not user_messages:
        fallback_hour = datetime.utcnow().hour
        profile = {
            "active_window": _classify_active_window([fallback_hour]),
            "response_pace": "measured",
            "message_length_style": "medium",
            "openness_level": "warm",
            "humor_style": "playful",
            "rhythm": "steady",
            "social_energy": "balanced",
            "confidence": 0.12,
            "signal_labels": ["early activity signals"],
            "timezone": user.get("timezone"),
        }
    else:
        lengths = [int(message.get("text_length") or len((message.get("content") or "").strip())) for message in user_messages]
        drafts = [int(message.get("draft_duration_ms") or 0) for message in user_messages if message.get("draft_duration_ms") is not None]
        latencies = [int(message.get("reply_latency_ms") or 0) for message in user_messages if message.get("reply_latency_ms") is not None]
        hours = [
            int(message.get("hour_of_day"))
            for message in user_messages
            if message.get("hour_of_day") is not None
        ]
        texts = [(message.get("content") or "").lower() for message in user_messages]

        average_length = sum(lengths) / max(1, len(lengths))
        average_draft = (sum(drafts) / len(drafts)) if drafts else None
        average_latency = (sum(latencies) / len(latencies)) if latencies else None
        burst_ratio = _burst_ratio(user_messages)
        openness_score = _openness_score(texts, average_length)
        humor_style = _infer_humor_style(texts)
        social_energy = _infer_social_energy(texts, average_length, burst_ratio, openness_score)

        signal_labels = [
            f"{_classify_active_window(hours)} active hours",
            f"{_classify_message_length(average_length)} messages",
            f"{_infer_rhythm(average_draft, burst_ratio)} rhythm",
        ]

        profile = {
            "active_window": _classify_active_window(hours),
            "response_pace": _classify_response_pace(average_draft, average_latency),
            "message_length_style": _classify_message_length(average_length),
            "openness_level": _classify_openness(openness_score),
            "humor_style": humor_style,
            "rhythm": _infer_rhythm(average_draft, burst_ratio),
            "social_energy": social_energy,
            "confidence": min(1.0, 0.18 + (len(user_messages) * 0.03)),
            "signal_labels": signal_labels,
            "timezone": user.get("timezone"),
        }

    # Seeding chemistry using onboarding signals if message history is thin (< 30 messages)
    if len(user_messages) < 30:
        onboarding_signals = user.get("onboarding_signals")
        signals = {}
        if onboarding_signals:
            try:
                if isinstance(onboarding_signals, str):
                    signals = json.loads(onboarding_signals)
                elif isinstance(onboarding_signals, dict):
                    signals = onboarding_signals
            except Exception:
                pass
        
        if signals:
            connection_style = signals.get("connection_style")
            if connection_style == "takes_their_time":
                profile["response_pace"] = "slow"
                profile["humor_style"] = "soft"
                profile["social_energy"] = "quiet"
            elif connection_style == "easy_to_talk_to":
                profile["openness_level"] = "warm"
                profile["humor_style"] = "playful"
                profile["social_energy"] = "balanced"
            elif connection_style == "says_whats_on_mind":
                profile["openness_level"] = "intense"
                profile["humor_style"] = "dry"
            elif connection_style == "makes_things_fun":
                profile["humor_style"] = "chaotic"
                profile["social_energy"] = "intense"
            elif connection_style == "meaningful_conversations":
                profile["openness_level"] = "intense"
                profile["humor_style"] = "intellectual"
                profile["message_length_style"] = "long"

            depth_preference = signals.get("depth_preference")
            if depth_preference == "let_it_happen":
                profile["openness_level"] = profile.get("openness_level") or "warm"
                profile["rhythm"] = "slow"
            elif depth_preference == "little_honesty":
                profile["openness_level"] = profile.get("openness_level") or "warm"
                profile["humor_style"] = "dry"
            elif depth_preference == "dont_mind_personal":
                profile["openness_level"] = "intense"
                profile["message_length_style"] = "long"
            elif depth_preference == "skip_small_talk":
                profile["openness_level"] = "intense"
                profile["humor_style"] = "intellectual"
                profile["rhythm"] = "burst"

            profile["confidence"] = min(1.0, profile.get("confidence", 0.0) + 0.15)
            profile["signal_labels"].append("seeded onboarding chemistry")

    return profile


def _build_assignment_reason(user_id: str, character: Character) -> str:
    profile = _build_user_chemistry_profile(user_id)
    labels = ", ".join(profile.get("signal_labels") or ["early chemistry signals"])
    return f"matched from {labels} ({character.id})"


def _categorical_match(value: Optional[str], target: Optional[str], order: Optional[list[str]] = None) -> float:
    if not value or not target:
        return 0.42
    if value == target:
        return 1.0
    if order and value in order and target in order:
        distance = abs(order.index(value) - order.index(target))
        if distance == 1:
            return 0.72
        if distance == 2:
            return 0.38
        return 0.12
    return 0.2


def _classify_active_window(hours: list[int]) -> str:
    if not hours:
        return "evening"
    average_hour = sum(hours) / len(hours)
    if 5 <= average_hour < 11:
        return "morning"
    if 11 <= average_hour < 17:
        return "day"
    if 17 <= average_hour < 22:
        return "evening"
    return "late_night"


def _classify_response_pace(average_draft: Optional[float], average_latency: Optional[float]) -> str:
    if average_draft is not None:
        if average_draft < 18000:
            return "fast"
        if average_draft > 90000:
            return "slow"
    if average_latency is not None:
        if average_latency < 300000:
            return "fast"
        if average_latency > 5400000:
            return "slow"
    return "measured"


def _classify_message_length(average_length: float) -> str:
    if average_length < 52:
        return "short"
    if average_length > 170:
        return "long"
    return "medium"


def _openness_score(texts: list[str], average_length: float) -> float:
    disclosure_patterns = [
        r"\bi feel\b",
        r"\bi felt\b",
        r"\bi've\b",
        r"\bi have\b",
        r"\bi'm\b",
        r"\bi am\b",
        r"\bi miss\b",
        r"\bi need\b",
        r"\bi want\b",
        r"\bi think\b",
    ]
    hits = 0
    for text in texts:
        hits += sum(1 for pattern in disclosure_patterns if re.search(pattern, text))
    return (hits / max(1, len(texts))) + (0.6 if average_length > 150 else 0.25 if average_length > 90 else 0.0)


def _classify_openness(score: float) -> str:
    if score < 0.6:
        return "guarded"
    if score > 1.2:
        return "intense"
    return "warm"


def _infer_humor_style(texts: list[str]) -> str:
    buckets = Counter()
    for text in texts:
        if any(token in text for token in ["lol", "lmao", "haha", "😭", "omg", "no because"]):
            buckets["chaotic"] += 1
        if any(token in text for token in ["honestly", "interesting", "actually", "theory", "weirdly"]):
            buckets["intellectual"] += 1
        if any(token in text for token in ["sure", "right", "bleak", "obviously", "unfortunate"]):
            buckets["dry"] += 1
        if any(token in text for token in ["wait", "cute", "aw", "okay", "hi"]):
            buckets["playful"] += 1
        if any(token in text for token in ["hmm", "...", "idk", "maybe"]):
            buckets["soft"] += 1
    return buckets.most_common(1)[0][0] if buckets else "playful"


def _infer_rhythm(average_draft: Optional[float], burst_ratio: float) -> str:
    if burst_ratio >= 0.35:
        return "burst"
    if average_draft is not None and average_draft > 95000:
        return "slow"
    return "steady"


def _infer_social_energy(
    texts: list[str],
    average_length: float,
    burst_ratio: float,
    openness_score: float,
) -> str:
    expressive_hits = sum(
        1
        for text in texts
        if any(token in text for token in ["!!", "😭", "lol", "omg", "literally", "wait"])
    )
    if expressive_hits >= max(2, len(texts) // 3) or burst_ratio > 0.4:
        return "intense"
    if openness_score > 1.0 or average_length > 120:
        return "warm"
    if average_length < 55 and expressive_hits == 0:
        return "quiet"
    return "balanced"


def _burst_ratio(user_messages: list[dict]) -> float:
    if len(user_messages) < 2:
        return 0.0
    burst_links = 0
    comparisons = 0
    previous_time: Optional[datetime] = None
    for message in user_messages:
        created_at = message.get("created_at")
        try:
            current_time = datetime.fromisoformat(created_at) if created_at else None
        except ValueError:
            current_time = None
        if previous_time and current_time:
            comparisons += 1
            if (current_time - previous_time).total_seconds() <= 240:
                burst_links += 1
        previous_time = current_time
    return burst_links / max(1, comparisons)


def _stable_tiebreaker(user_id: str, character_id: str) -> float:
    digest = hashlib.sha256(f"{user_id}:{character_id}".encode("utf-8")).hexdigest()
    return int(digest[:8], 16) / 0xFFFFFFFF
