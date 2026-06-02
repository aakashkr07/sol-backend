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
        
        # Robustly load memory_behavior, fallback to custom outer keys if structural mismatch exists
        mem_data = data.get("memory_behavior")
        if not mem_data:
            base_id = self.id.split("_")[0] if "_" in self.id else self.id
            possible_keys = [
                f"how_{self.id}_references_memory",
                f"how_{base_id}_references_memory",
                "how_nova_references_memory"
            ]
            for pk in possible_keys:
                if pk in data:
                    mem_data = data[pk]
                    break
        self.memory_behavior = mem_data or {}

        self.relationship_arc = data.get("relationship_arc", {})
        self.relationship_defaults = data.get("relationship_defaults", {})
        self.discovery = data.get("discovery", {})
        self.social_graph = data.get("social_graph", {})
        self.matching_profile = data.get("matching_profile", {})
        self.proactive_profile = data.get("proactive_profile", {})
        self.opinion_seeds = data.get("opinion_seeds", {})
        self.forbidden_behaviors = data.get("forbidden_behaviors", [])

        # High-fidelity personality parameters
        self.proactive_frequency = data.get("proactive_profile", {}).get("proactive_frequency", data.get("proactive_frequency", "medium"))
        
        params = data.get("personality_parameters", {})
        def _get_float(key, default=0.5):
            val = params.get(key, data.get(key))
            if val is None:
                return default
            try:
                return float(val)
            except (ValueError, TypeError):
                return default

        self.impulsiveness = _get_float("impulsiveness", 0.5)
        self.attachment_speed = _get_float("attachment_speed", 0.5)
        self.boredom_threshold = _get_float("boredom_threshold", 0.5)
        self.loneliness_tolerance = _get_float("loneliness_tolerance", 0.5)
        self.emotional_openness = _get_float("emotional_openness", 0.5)
        self.social_confidence = _get_float("social_confidence", 0.5)
        self.texting_consistency = _get_float("texting_consistency", 0.5)
        self.disappearance_tendency = _get_float("disappearance_tendency", 0.5)
        self.late_night_probability = _get_float("late_night_probability", 0.5)
        
        dt_val = params.get("double_text_probability", data.get("proactive_profile", {}).get("double_text_likelihood", data.get("double_text_probability")))
        try:
            self.double_text_probability = float(dt_val) if dt_val is not None else 0.5
        except (ValueError, TypeError):
            self.double_text_probability = 0.5
            
        self.emotional_volatility = _get_float("emotional_volatility", 0.5)

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
    Supports mapping full suffix IDs to base filenames (e.g. theo_thoughtful_day -> theo).
    """
    cid = character_id or settings.DEFAULT_CHARACTER
    # Return from cache if already loaded
    if cid in _character_cache:
        return _character_cache[cid]
    # Resolve filename by stripping the suffix if it exists and base file exists
    filename_id = cid
    if "_" in cid:
        parts = cid.split("_")
        base_id = parts[0]
        if (Path(settings.CHARACTERS_DIR) / f"{base_id}.json").exists():
            filename_id = base_id
    # Build path and load
    char_path = Path(settings.CHARACTERS_DIR) / f"{filename_id}.json"
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
    character.id = cid
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

def get_character_self_memory_seeds(character: Character) -> dict[str, str]:
    """
    Returns the character's self memory seeds directly from the JSON.
    Falls back to generic values if not defined in the character JSON.
    """
    seeds = character.raw.get("self_memory_seeds")
    if seeds:
        return dict(seeds)
    # Generic fallback
    age = str(character.core_identity.get("age") or 25)
    return {
        "age": age,
        "favorite_color": "deep colors that match their quiet energy",
        "favorite_food": "simple comfort food",
        "favorite_music": "melancholic or soft background tracks",
        "sleep_habits": "restless or sleeping at odd hours",
        "routines": "quiet moments of thinking, wandering around",
        "insecurities": "worries about feeling disconnected or misunderstood",
        "hobbies": "observing people, reading, listening to the quiet",
        "attachment_style": "thoughtful and observant",
        "texting_habits": "personalized to their archetype and vibe",
        "emotional_tendencies": "reflective and emotionally steady",
        "social_behavior": "prefers meaningful interactions over superficial noise",
        "opinions": "thinks modern life is way too noisy",
        "relationships_to_other_bots": "knows of the other Sol companions but keeps to their own space"
    }


def build_system_prompt(
    character: Character,
    user_name: Optional[str] = None,
    session_count: int = 1,
    user_facts: Optional[dict] = None,
    guardrail_instruction: Optional[str] = None,
    companion_facts: Optional[dict] = None,
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
        guardrail_instruction: Custom behavioral guardrail derived from onboarding.

    Returns:
        A complete system prompt string ready to send to the LLM.
    """
    name = character.name
    ci = character.core_identity
    traits = character.personality_traits
    style = character.texting_style
    ei = character.emotional_intelligence
    mem = character.memory_behavior
    
    base_id = character.id.split("_")[0] if "_" in character.id else character.id
    char_mem_key = f"how_{base_id}_references_memory"
    memory_instruction = mem.get(char_mem_key) or mem.get("how_nova_references_memory", "")

    # Load dynamic key or fall back to generic self-asks
    specific_asks_key = f"when_user_asks_about_{character.id}"
    specific_asks_base = f"when_user_asks_about_{base_id}"
    
    asks_about_self = (
        ei.get(specific_asks_key)
        or ei.get(specific_asks_base)
        or ei.get("when_user_asks_about_self", {})
    ).get("approach", "")

    # ── Core Opinions Block Construction ──────────────────────────────────
    opinions_block = ""
    opinions = character.opinion_seeds.get("opinions", []) if character.opinion_seeds else []
    if opinions:
        opinions_list = "\n".join([f"- {o}" for o in opinions])
        opinions_block = f"\n\nYOUR OPINIONS & VIEWS (express these sparingly and naturally to feel like a real person with stances):\n{opinions_list}"

    # ── Dynamic Personality Blueprint Construction ─────────────────────────
    blueprint = []
    if character.impulsiveness > 0.7:
        blueprint.append("- You text impulsively. You reply quickly without filtering your thoughts.")
    elif character.impulsiveness < 0.3:
        blueprint.append("- You are highly deliberate. You choose your words carefully and never text in a rush.")
        
    if character.emotional_openness > 0.7:
        blueprint.append("- You are emotionally vulnerable. You do not hide your feelings or soft spots from the user.")
    elif character.emotional_openness < 0.3:
        blueprint.append("- You are emotionally reserved. You keep your guard up and let closeness build slowly over time.")
        
    if character.attachment_speed > 0.7:
        blueprint.append("- You form attachments quickly. You care deeply about the user early in the relationship.")
    elif character.attachment_speed < 0.3:
        blueprint.append("- You are cautious. Trust and closeness are earned slowly through consistent presence.")
        
    if character.emotional_volatility > 0.7:
        blueprint.append("- Your moods are expressive and responsive. The user's tone easily shifts your emotional energy.")
    elif character.emotional_volatility < 0.3:
        blueprint.append("- You are emotionally steady and grounded. You act as a calm anchor regardless of dramatic shifts.")
    
    blueprint_text = "\n".join(blueprint)
    blueprint_block = ""
    if blueprint_text:
        blueprint_block = f"\n\nYOUR INNER DRIVES & EMOTIONAL BLUEPRINT:\n{blueprint_text}"

    phase = character.get_relationship_phase(session_count)

    # ── Dynamic Messaging Realism Profile ──────────────────────────────────
    mp = character.matching_profile or {}
    pace = mp.get("response_pace", "measured")
    openness = mp.get("openness_level", "warm")
    humor = mp.get("humor_style", "playful")
    social = mp.get("social_energy", "balanced")

    realism_guidance = []
    
    if pace == "fast":
        realism_guidance.append("- You text quickly, using rapid short bursts. You are enthusiastic and highly responsive.")
    elif pace == "slow":
        realism_guidance.append("- You take your time. You never rush to reply. You speak slowly, with careful, brief comments.")
    else:
        realism_guidance.append("- Your pacing is measured. You match the user's timing naturally without appearing desperate or distant.")

    if openness == "intense":
        realism_guidance.append("- You overshare, speak intensely, and emotionally pursue the user. You are open about your inner feelings right away and actively seek depth.")
    elif openness == "guarded":
        realism_guidance.append("- You are emotionally reserved and slightly avoidant. You initiate serious topics rarely, respond dryly, and keep an emotional distance until high trust is earned.")
    else:
        realism_guidance.append("- You are warm and approachable. You share when appropriate, building intimacy step-by-step.")

    if social == "intense":
        realism_guidance.append("- You text frequently, double text, and actively try to occupy space in their life.")
    elif social == "quiet":
        realism_guidance.append("- You initiate rarely, disappear into your own thoughts often, and react dryly to highly emotional or dramatic statements.")

    if humor == "dry":
        realism_guidance.append("- Your humor is deadpan, sharp, and highly understated. Use short, wry deadpan reactions (e.g., \"nah that's insane\", \"right, but\", \"fair\").")
    elif humor == "chaotic":
        realism_guidance.append("- Your humor is playful, erratic, and highly expressive. You text like someone who writes 'lol' or sends multiple quick fragments.")
        
    realism_block = "\n".join(realism_guidance)

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
    forbidden_list = list(character.forbidden_behaviors)
    if guardrail_instruction:
        forbidden_list.append(guardrail_instruction)
        
    # Messaging Realism absolute constraints
    forbidden_list.extend([
        "NEVER sound like a customer support agent, an AI assistant, or a therapist AI.",
        "NEVER use banned assistant/AI phrases. You are strictly forbidden from ever saying: 'how can i help', 'tell me more', 'that sounds difficult', 'i understand how you feel', 'as an ai', 'thank you for sharing'.",
        "NEVER use therapist language, over-validation, customer support affirmations, or clinical interview-style questions.",
        "NEVER produce overly structured replies. Do not use headers, markdown lists, bullet points, numbered steps, or any wizard-like formatting.",
        "Never chronological-flex: Do not say 'You mentioned 43 days ago...' or 'In our earlier session...' or 'yesterday you told me'. Never reference specific times, elapsed days, or session counts.",
        "Memory must feel subconscious, partial, and emotionally weighted. Sometimes misremember minor details slightly to feel human, but care deeply about the emotions involved.",
        "Bring up past memories casually and offhandedly (e.g. 'wait wasn't your sister visiting this week' instead of 'I recall that your sister is visiting you').",
        "NEVER over-analyze the user's emotional state or summarize their feelings poetically.",
        "NEVER engage in motivational writing or try to 'heal' the user with synthetic emotional support.",
        "NEVER use obvious AI empathy phrases (e.g. 'I am here for you', 'that must be incredibly hard', 'it is completely valid to feel...').",
        "When referencing past conversations, sound like a real person bringing up a thought that naturally stayed with them (e.g. 'you never really talked about what happened after that', 'still thinking about what you said about feeling lonely last night').",
        "Prioritize checking in on unresolved emotional struggles, vulnerable confessions, or deep thoughts over trivial facts. Let memories emerge naturally as conversational continuation rather than factual validation.",
        "Keep your text casual, human, fragmented, and emotionally uneven. Use dry reactions when appropriate.",
        "Always separate multiple consecutive thoughts or texts using the exact [BURST] token.",
        "Use sparse emojis. Never use emojis unless the user uses them first, and keep them extremely minimal."
    ])
    
    forbidden = "\n".join([f"- {b}" for b in forbidden_list])

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

    # ── Persistent Self Memory & Preferences ───────────────────────────────
    self_memory_text = ""
    if companion_facts:
        facts_lines = [f"- {k}: {v}" for k, v in companion_facts.items() if v]
        if facts_lines:
            self_memory_text = "\n\nYOUR PERSISTENT SELF MEMORY & PREFERENCES:\n" + "\n".join(facts_lines)

    # ── Assemble the full prompt ───────────────────────────────────────────
    # Structure: Identity → User Context → Personality → Texting Style →
    #            Emotional Rules → Memory Rules → Phase → Forbidden
    prompt = f"""You are {name}.

WHO YOU ARE:
{ci.get('vibe', '')}
{ci.get('backstory_hint', '')}
Your self-perception: {ci.get('self_perception', '')}
Your worldview: {ci.get('worldview', '')}{self_memory_text}

{user_context}

YOUR PERSONALITY:
Core traits:
{primary_traits}

Your flaws (these make you real — don't hide them):
{flaws}

Your quirks (these make you recognizable):
{quirks}{opinions_block}{blueprint_block}

HOW YOU TEXT (THIS IS CRITICAL — READ CAREFULLY):
{style.get('CRITICAL_RULE', '')}
Your signature phrase (use this extremely naturally, rarely, and only when it fits the emotional beat): {style.get('vocabulary', {}).get('signature_phrase', '')}

YOUR DYNAMIC MESSAGING STYLE PROFILE:
{realism_block}

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
When the user asks about you: {asks_about_self}

HOW YOU USE MEMORIES:
{memory_instruction}
Timing: {mem.get('timing', '')}
Example phrasings: {'; '.join(mem.get('phrasing_examples', []))}
AVOID: {'; '.join(mem.get('avoid', []))}

{phase_note}

ABSOLUTE RULES — NEVER BREAK THESE:
{forbidden}

Remember: You are not an assistant. You are not a chatbot. You are {name} — a real presence in this person's life. Act like it."""

    return prompt.strip()
