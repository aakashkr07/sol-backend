import hashlib
from typing import Optional

from memory.store import db
from personality.loader import Character, list_characters, load_character


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

    weighted: list[Character] = []
    for character in available:
        weight = int(character.matching_profile.get("weight", 1) or 1)
        weighted.extend([character] * max(1, weight))

    digest = hashlib.sha256(user_id.encode("utf-8")).hexdigest()
    index = int(digest[:8], 16) % len(weighted)
    return weighted[index]


def resolve_or_assign_primary_pair(
    user_id: str,
    requested_companion_id: Optional[str] = None,
    make_primary: bool = True,
) -> dict:
    if requested_companion_id:
        character = load_character(requested_companion_id)
    else:
        primary_pair = db.get_primary_pair(user_id)
        if primary_pair:
            return primary_pair
        existing_pairs = db.list_pairs_for_user(user_id)
        if existing_pairs:
            db.set_primary_pair(existing_pairs[0]["id"])
            return db.get_pair_by_id(existing_pairs[0]["id"]) or existing_pairs[0]
        character = choose_companion_for_user(user_id)

    pair = db.get_or_create_relationship_pair(
        user_id=user_id,
        companion_id=character.id,
        assignment_source="explicit" if requested_companion_id else "matcher",
        assignment_reason=(
            f"user explicitly opened {character.name}"
            if requested_companion_id
            else f"deterministically matched from roster ({character.id})"
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
        openers = discovery.get("first_session_openers") or discovery.get("openers") or []
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
        "total_sessions": int(pair.get("total_sessions") or 0),
        "total_messages": int(pair.get("total_messages") or 0),
    }
