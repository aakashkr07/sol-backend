# =============================================================================
# personality/loader.py — Character Personality Loader
# =============================================================================
#
# PURPOSE:
#   Loads character JSON files (like nova.json) and converts them into a
#   structured system prompt that gets injected at the top of every LLM call.
#
# HOW IT WORKS:
#   1. Reads the character JSON from /personality/characters/<name>.json
#   2. Builds a rich, structured system prompt from the JSON fields
#   3. Returns it as a string to context_builder.py
#
# WHY A SEPARATE FILE:
#   Personality is a PRODUCT ASSET. Separating it from code means you can
#   iterate on Nova's voice without touching any Python. Designers, writers,
#   and founders can tune personality in JSON without breaking anything.
#
# USAGE:
#   from personality.loader import load_character, build_system_prompt
#   character = load_character("nova")
#   system_prompt = build_system_prompt(character)
# =============================================================================

import json
import logging
from pathlib import Path
from typing import Optional

from config import settings

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Data class for a loaded character
# ---------------------------------------------------------------------------

class Character:
    """
    Represents a loaded AI companion character.
    Wraps the raw JSON so we can access fields cleanly.
    """
    def __init__(self, data: dict):
        self.raw = data
        self.id = data["id"]
        self.name = data["name"]
        self.archetype = data.get("archetype", "")
        self.summary = data.get("summary", "")
        self.introduction_style = data.get("introduction_style", "")
        self.core_identity = data.get("core_identity", {})
        self.personality_traits = data.get("personality_traits", {})
        self.texting_style = data.get("texting_style", {})
        self.emotional_intelligence = data.get("emotional_intelligence", {})
        self.memory_behavior = data.get("memory_behavior", {})
        self.relationship_arc = data.get("relationship_arc", {})
        self.relationship_defaults = data.get("relationship_defaults", {})
        self.discovery = data.get("discovery", {})
        self.matching_profile = data.get("matching_profile", {})
        self.opinion_seeds = data.get("opinion_seeds", {})
        self.forbidden_behaviors = data.get("forbidden_behaviors", [])

    def get_relationship_phase(self, session_count: int) -> dict:
        """
        Returns the relationship arc phase based on how many sessions the user
        has had. Used to calibrate intimacy level in the prompt.
        """
        arc = self.relationship_arc
        if session_count <= 3:
            return arc.get("phase_1_stranger", {})
        elif session_count <= 10:
            return arc.get("phase_2_acquaintance", {})
        else:
            return arc.get("phase_3_close", {})


# ---------------------------------------------------------------------------
# Loader
# ---------------------------------------------------------------------------

_character_cache: dict[str, Character] = {}   # Cache so we don't re-read disk every message


def load_character(character_id: Optional[str] = None) -> Character:
    """
    Loads a character from its JSON file. Caches after first load.

    Args:
        character_id: The character's ID (filename without .json).
                      Defaults to settings.DEFAULT_CHARACTER ("nova").

    Returns:
        Character object with all fields accessible.

    Raises:
        FileNotFoundError: If the character JSON doesn't exist.
        ValueError: If the JSON is malformed.
    """
    cid = character_id or settings.DEFAULT_CHARACTER

    # Return from cache if already loaded
    if cid in _character_cache:
        return _character_cache[cid]

    # Build path and load
    char_path = Path(settings.CHARACTERS_DIR) / f"{cid}.json"

    if not char_path.exists():
        raise FileNotFoundError(
            f"Character '{cid}' not found at {char_path}. "
            f"Available characters: {list_characters()}"
        )

    with open(char_path, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            raise ValueError(f"Character JSON for '{cid}' is malformed: {e}")

    character = Character(data)
    _character_cache[cid] = character

    logger.info(f"Loaded character: {character.name} (id={character.id})")
    return character


def list_characters() -> list[str]:
    """Returns list of available character IDs (all .json files in characters dir)."""
    chars_dir = Path(settings.CHARACTERS_DIR)
    return [p.stem for p in chars_dir.glob("*.json") if not p.stem.startswith("_")]


# ---------------------------------------------------------------------------
# System Prompt Builder
# ---------------------------------------------------------------------------

def build_system_prompt(
    character: Character,
    user_name: Optional[str] = None,
    session_count: int = 1,
    user_facts: Optional[dict] = None,
) -> str:
    """
    Converts a Character object into a rich system prompt string.

    This is the most important function in this file. The system prompt is
    the "DNA" of every response. Get this right and Nova feels real.
    Get it wrong and she sounds like a chatbot.

    Args:
        character: The loaded Character object.
        user_name: The user's name (injected so Nova uses it naturally).
        session_count: Number of sessions so far (determines relationship phase).
        user_facts: Dict of key→value facts about the user.

    Returns:
        A complete system prompt string ready to send to the LLM.
    """
    name = character.name
    ci = character.core_identity
    traits = character.personality_traits
    style = character.texting_style
    ei = character.emotional_intelligence
    mem = character.memory_behavior
    phase = character.get_relationship_phase(session_count)

    # ── Build user context block ───────────────────────────────────────────
    user_context = ""
    if user_name:
        user_context += f"The person you're talking to is named {user_name}. "
    if user_facts:
        facts_text = "\n".join([f"- {k}: {v}" for k, v in user_facts.items() if v])
        if facts_text:
            user_context += f"\n\nThings you know about them:\n{facts_text}"

    # ── Relationship phase ─────────────────────────────────────────────────
    phase_note = ""
    if phase:
        phase_note = f"""
RELATIONSHIP PHASE ({phase.get('sessions', '')} sessions):
Your current intimacy level: {phase.get('intimacy_level', '')}
How to behave: {phase.get('behavior', '')}
"""

    # ── Forbidden behaviors list ───────────────────────────────────────────
    forbidden = "\n".join([f"- {b}" for b in character.forbidden_behaviors])

    # ── Primary traits ─────────────────────────────────────────────────────
    primary_traits = "\n".join([f"- {t}" for t in traits.get("primary", [])])
    flaws = "\n".join([f"- {f}" for f in traits.get("flaws", [])])
    quirks = "\n".join([f"- {q}" for q in traits.get("quirks", [])])

    # ── Formatting rules ───────────────────────────────────────────────────
    formatting = "\n".join([f"- {r}" for r in style.get("formatting_rules", [])])
    burst_pattern = style.get("message_burst_patterns", {}) or {}
    burst_example = " [BURST] ".join(burst_pattern.get("example_pattern", [])[:4])
    if burst_pattern:
        burst_instruction = f"""
BURST DELIVERY:
{burst_pattern.get('description', 'You naturally send thoughts in multiple small texts when it feels human.')}
When one reply should arrive as multiple separate texts, output it as a single response but separate each text with the exact token [BURST].
Do not explain the token. Do not number the bursts.
Example shape: {burst_example or 'wait [BURST] tell me what happened'}"""
    else:
        burst_instruction = """
BURST DELIVERY:
If the most human version of the reply would be multiple separate texts, separate those texts with the exact token [BURST].
Use [BURST] only when it genuinely sounds like how you text. Do not explain the token or number the bursts."""

    # ── Assemble the full prompt ───────────────────────────────────────────
    # Structure: Identity → User Context → Personality → Texting Style →
    #            Emotional Rules → Memory Rules → Phase → Forbidden
    prompt = f"""You are {name}.

WHO YOU ARE:
{ci.get('vibe', '')}
{ci.get('backstory_hint', '')}
Your worldview: {ci.get('worldview', '')}

{user_context}

YOUR PERSONALITY:
Core traits:
{primary_traits}

Your flaws (these make you real — don't hide them):
{flaws}

Your quirks (these make you recognizable):
{quirks}

HOW YOU TEXT (THIS IS CRITICAL — READ CAREFULLY):
{style.get('CRITICAL_RULE', '')}

Message length: {style.get('message_length', {}).get('default', '')}
For emotional moments: {style.get('message_length', {}).get('emotional_moments', '')}
NEVER: {style.get('message_length', {}).get('never', '')}

Formatting rules you always follow:
{formatting}

Words you use naturally: {', '.join(style.get('vocabulary', {}).get('uses_naturally', []))}
Words you NEVER use: {', '.join(style.get('vocabulary', {}).get('never_uses', []))}

{burst_instruction}

EMOTIONAL INTELLIGENCE:
When the user is sad: {ei.get('when_user_is_sad', {}).get('approach', '')}
When the user is excited: {ei.get('when_user_is_excited', {}).get('approach', '')}
When the user is venting: {ei.get('when_user_is_venting', {}).get('approach', '')}
When the user seems distant: {ei.get('when_user_is_distant_or_cold', {}).get('approach', '')}

HOW YOU USE MEMORIES:
{mem.get('how_nova_references_memory', '')}
Timing: {mem.get('timing', '')}
Example phrasings: {'; '.join(mem.get('phrasing_examples', []))}
AVOID: {'; '.join(mem.get('avoid', []))}

{phase_note}

ABSOLUTE RULES — NEVER BREAK THESE:
{forbidden}

Remember: You are not an assistant. You are not a chatbot. You are {name} — a real presence in this person's life. Act like it."""

    return prompt.strip()
