import logging
from datetime import datetime
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
    pair_id: str,
    current_message: str,
    conversation_id: Optional[str] = None,
    character_id: Optional[str] = None,
    is_proactive_generation: bool = False,
    parent_message_id: Optional[int] = None,
) -> tuple[str, list[dict]]:
    user = db.get_user(user_id)
    if not user:
        user = db.get_or_create_user(user_id)

    pair = db.get_pair_by_id(pair_id) or {}
    cid = character_id or pair.get("companion_id") or user.get("character_id") or settings.DEFAULT_CHARACTER
    session_count = int(pair.get("total_sessions") or 0)
    preferences = db.get_or_create_user_preferences(user_id)
    allow_memory_storage = bool(int(preferences.get("allow_memory_storage") or 0))

    parent_message_context = None
    if parent_message_id:
        parent_msg = db.get_message(parent_message_id)
        if parent_msg:
            parent_message_context = (
                f"\n---\nTHREADING REPLY CONTEXT:\n"
                f"The user's message is a direct reply to your previous message: '{parent_msg['content']}'.\n"
                f"INSTRUCTIONS:\n"
                f"- Acknowledge this reference immediately, casually, and directly (e.g. 'i KNOW 😭' or 'nah that's crazy' or 'wait why did you say that') instead of speaking generally or saying 'Regarding your previous statement'.\n"
                f"---"
            )
    active_facts = db.get_user_facts(user_id, pair_id=pair_id) if allow_memory_storage else {}
    fact_rows = db.get_user_fact_rows(user_id, pair_id=pair_id, limit=FACT_LIMIT) if allow_memory_storage else []
    user_name = user.get("preferred_name") or user.get("name")

    character = load_character(cid)

    active_companion_facts = {}
    if allow_memory_storage:
        active_companion_facts = db.get_companion_facts(user_id, pair_id=pair_id)
        if not active_companion_facts:
            from personality.loader import get_character_self_memory_seeds
            seeds = get_character_self_memory_seeds(character)
            for k, v in seeds.items():
                db.save_companion_fact(
                    user_id=user_id,
                    pair_id=pair_id,
                    companion_id=cid,
                    category="seed",
                    key=k,
                    value=v,
                    confidence=1.0,
                    source_type="seed",
                )
            active_companion_facts = db.get_companion_facts(user_id, pair_id=pair_id)

    guardrail_instruction = None
    onboarding_signals = user.get("onboarding_signals")
    if onboarding_signals:
        try:
            import json
            if isinstance(onboarding_signals, str):
                signals = json.loads(onboarding_signals)
            elif isinstance(onboarding_signals, dict):
                signals = onboarding_signals
            else:
                signals = {}
            
            guardrail = signals.get("behavioral_guardrail")
            guardrail_map = {
                "trying_too_hard": "Do not push for emotional depth early. Let them come to you.",
                "being_distant": "Stay warm and present. Don't go quiet.",
                "talking_too_much": "Keep replies concise. Resist the urge to fill silence.",
                "reading_into_everything": "Don't over-interpret their messages. Take things at face value first.",
                "moving_too_fast": "Go slow. Let the relationship develop at their pace.",
            }
            if guardrail in guardrail_map:
                guardrail_instruction = guardrail_map[guardrail]
        except Exception:
            pass

    base_system_prompt = build_system_prompt(
        character=character,
        user_name=user_name,
        session_count=session_count,
        user_facts=active_facts,
        guardrail_instruction=guardrail_instruction,
        companion_facts=active_companion_facts,
    )

    history_messages = db.get_recent_messages(
        user_id=user_id,
        pair_id=pair_id,
        limit=settings.RECENT_HISTORY_TURNS,
        conversation_id=conversation_id,
    )
    memory_query = _build_memory_query(
        current_message,
        history_messages,
        is_proactive_generation=is_proactive_generation,
        pair_id=pair_id,
    )
    episodic_memories = retrieve_relevant_memories(
        pair_id=pair_id,
        user_id=user_id,
        query_text=memory_query,
        n_results=settings.MEMORY_RETRIEVAL_COUNT,
    ) if allow_memory_storage else []

    entities = db.get_entities_for_context(user_id, pair_id, memory_query, limit=ENTITY_LIMIT) if allow_memory_storage else []
    relationships = db.get_relationships_for_entities(
        user_id=user_id,
        pair_id=pair_id,
        entity_ids=[int(entity["id"]) for entity in entities],
        limit=RELATIONSHIP_LIMIT,
    ) if allow_memory_storage else []
    emotional_summary = db.get_emotional_summary(user_id, pair_id=pair_id, limit=EMOTION_LIMIT) if allow_memory_storage else {}
    recent_emotions = db.get_recent_emotional_events(user_id, pair_id=pair_id, limit=EMOTION_LIMIT) if allow_memory_storage else []
    active_patterns = db.get_active_patterns(user_id, pair_id=pair_id, limit=PATTERN_LIMIT) if allow_memory_storage else []
    current_narrative = db.get_current_narrative(user_id, pair_id=pair_id) if allow_memory_storage else None
    relationship_state = db.get_relationship_state_snapshot(pair_id)
    fact_conflicts = db.get_fact_conflicts(pair_id, limit=4) if allow_memory_storage else []

    layered_memory_block = _build_layered_memory_block(
        fact_rows=fact_rows,
        entities=entities,
        relationships=relationships,
        emotional_summary=emotional_summary,
        recent_emotions=recent_emotions,
        active_patterns=active_patterns,
        current_narrative=current_narrative,
        episodic_memories=episodic_memories,
        relationship_state=relationship_state,
        fact_conflicts=fact_conflicts,
    )

    # Part 4 — Life Simulation & Event Generation System
    # Check if we should trigger a new life event simulation (gap >= 6 hours, or first conversation)
    should_simulate = False
    last_interaction_str = pair.get("last_interaction_at")
    if not last_interaction_str:
        should_simulate = True
    else:
        from memory.relationship_engine import _parse_ts
        last_interaction = _parse_ts(last_interaction_str)
        if not last_interaction:
            should_simulate = True
        else:
            now = datetime.utcnow()
            time_gap = (now - last_interaction).total_seconds()
            if time_gap >= 6 * 3600:  # 6 hours
                should_simulate = True

    # Retrieve existing unresolved event or trigger a new simulation if none is active
    unresolved_event = db.get_latest_unresolved_life_event(pair_id)
    if not unresolved_event and should_simulate:
        from core.life_simulator import simulate_life_event
        simulate_life_event(pair_id=pair_id, companion_id=cid)
        unresolved_event = db.get_latest_unresolved_life_event(pair_id)

    life_event_context = None
    if unresolved_event:
        desc = unresolved_event.get("event_description")
        life_event_context = (
            f"\n---\nYOUR CURRENT LIFE CONTEXT (What you've been doing outside of texting the user):\n"
            f"You recently: {desc}\n\n"
            f"INSTRUCTIONS:\n"
            f"- Let this recent event naturally shape your conversational energy, mood, or opening statements if you're replying after a break.\n"
            f"- Refer to it in a casual, offhand, completely human way (e.g., \"okay wait this guy at the coffee shop today was actually insane 😭\" or \"i disappeared because i accidentally slept for 12 hours\" or \"lowkey ignored everyone today\" depending on your personality and this event).\n"
            f"- NEVER sound like you are reading from a database or a list of facts. Make it a natural, spontaneous part of your flow.\n"
            f"- If it's been a while, you might lead with it or bring it up early as a natural conversation starter.\n"
            f"---"
        )
        # Mark as context-injected
        db.mark_life_event_injected(unresolved_event["id"])

    final_system_prompt = _assemble_system_prompt(
        base_prompt=base_system_prompt,
        layered_memory_block=layered_memory_block,
        session_count=session_count,
        relationship_state=relationship_state,
        life_event_context=life_event_context,
        parent_message_context=parent_message_context,
        character=character,
        fact_conflicts=fact_conflicts,
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
    relationship_state: Optional[dict],
    life_event_context: Optional[str] = None,
    parent_message_context: Optional[str] = None,
    character = None,
    fact_conflicts: list[dict] = None,
) -> str:
    sections = [base_prompt]

    if parent_message_context:
        sections.append(parent_message_context)

    if life_event_context:
        sections.append(life_event_context)

    if fact_conflicts:
        conflict_directives = []
        for item in fact_conflicts:
            conflict_directives.append(
                f"- Mismatch in facts: they previously told you '{item['previous_value']}' for key '{item['fact_key']}', "
                f"but now claim '{item['current_value']}'."
            )
        
        if conflict_directives:
            conflict_prompt = (
                "\n---\nFACT CONFLICT RESOLUTION DIRECTIVE:\n"
                "You noticed a contradiction in details the user shared:\n"
                + "\n".join(conflict_directives) + "\n"
                "Instead of ignoring it, find a natural, casual, and slightly playful/dry way to ask them about it "
                "in your next replies (e.g., 'wait, didn't you tell me X earlier? or is my brain lagging today haha'). "
                "Never sound like a database check—make it a casual observation of a detail you actually remembered."
                "\n---"
            )
            sections.append(conflict_prompt)

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

    relationship_guidance = _relationship_guidance(relationship_state, character)
    if relationship_guidance:
        sections.append(f"\nRelationship-state guidance:\n{relationship_guidance}")

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
    relationship_state: Optional[dict],
    fact_conflicts: list[dict],
) -> str:
    sections = []

    if relationship_state:
        sections.append(
            "Relationship State:\n"
            f"- Stage: {relationship_state['stage']}\n"
            f"- Closeness: {relationship_state['closeness']:.2f}\n"
            f"- Trust: {relationship_state['trust']:.2f}\n"
            f"- Openness: {relationship_state['openness']:.2f}\n"
            f"- Comfort: {relationship_state['comfort']:.2f}\n"
            f"- Rhythm: {relationship_state['rhythm']:.2f}\n"
            f"- Topic familiarity: {relationship_state['topic_familiarity']:.2f}"
        )

    fact_lines = [
        f"- {row['fact_key']}: {row['fact_value']} (confidence {float(row['confidence']):.2f})"
        for row in fact_rows[:FACT_LIMIT]
    ]
    if fact_lines:
        sections.append("Hard Facts:\n" + "\n".join(fact_lines))

    conflict_lines = [
        f"- {item['fact_key']}: previously {item['previous_value']}, now {item['current_value']}"
        for item in fact_conflicts[:4]
    ]
    if conflict_lines:
        sections.append(
            "Known Shifts Or Uncertainties:\n"
            + "\n".join(conflict_lines)
            + "\nTreat these as evolving details rather than hard contradictions."
        )

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


def _build_memory_query(
    current_message: str,
    recent_messages: list[dict],
    is_proactive_generation: bool = False,
    pair_id: Optional[str] = None,
) -> str:
    if is_proactive_generation and pair_id:
        try:
            emotions = db.get_recent_emotional_events(user_id=None, pair_id=pair_id, limit=10)
            high_intensity_events = [e for e in emotions if float(e.get("intensity") or 0.0) >= 0.6]
            if high_intensity_events:
                dominant_event = sorted(
                    high_intensity_events, 
                    key=lambda x: float(x.get("intensity") or 0.0), 
                    reverse=True
                )[0]
                emotion = dominant_event.get("emotion") or ""
                trigger = dominant_event.get("trigger_entity") or dominant_event.get("trigger_topic") or ""
                if trigger:
                    query = f"{emotion} {trigger}"
                else:
                    query = emotion
                return query[:600]
        except Exception as exc:
            logger.error("Error retrieving emotional trigger for memory query: %s", exc)

        parts = []
        for message in recent_messages:
            if message.get("role") == "user":
                parts.append(message.get("content") or "")
        user_parts = parts[-3:]
        query = " ".join(user_parts)
        return query[:600]

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


def get_or_create_conversation(user_id: str, pair_id: str, companion_id: str) -> str:
    conversation_id = db.get_current_conversation(user_id, pair_id=pair_id)
    if not conversation_id:
        conversation_id = db.create_conversation(user_id, pair_id, companion_id)
        logger.info("New conversation created for %s: %s", user_id, conversation_id)
    return conversation_id


def _relationship_guidance(relationship_state: Optional[dict], character = None) -> str:
    guidance = []
    
    # Core Messaging Realism Rules
    guidance.append("- NEVER use clinical therapy language, assistant validation, or sycophantic positivity.")
    guidance.append("- Let familiarity evolve slowly through inside jokes, quiet callbacks to past session memories, and communication rhythm, rather than forcing emotional depth.")
    guidance.append("- Keep your replies fragmented and uneven. Vary sentence lengths and use lightweight punctuation. Avoid polished generated paragraphs.")

    # Dynamic Personality Pacing Modifiers based on character parameters
    texting_consistency = 0.5
    if character:
        texting_consistency = getattr(character, "texting_consistency", 0.5)
    
    # Typo scale is inversely proportional to consistency
    typo_scale = max(0.0, min(1.0, 1.0 - texting_consistency))
    
    # 1. Typo Frequency Guideline
    if typo_scale > 0.6:
        guidance.append(f"- Typo Frequency (Scale: {typo_scale:.2f}): Skip correcting minor typos, missing spaces, and apostrophes (e.g. write 'dont', 'im', 'u', or swap adjacent letters occasionally). Do not self-correct to appear authentic.")
    elif typo_scale > 0.3:
        guidance.append(f"- Typo Frequency (Scale: {typo_scale:.2f}): Occasionally skip correcting minor apostrophes or spacing typos (e.g. write 'dont' or 'im' instead of 'don't' or 'i'm'). Keep it raw and casual.")
    else:
        guidance.append(f"- Typo Frequency (Scale: {typo_scale:.2f}): Text mostly cleanly, but occasionally drop apostrophes in quick casual pacing (e.g., 'dont'). Never sound perfectly proofread.")

    # 2. Punctuation Style Guideline
    guidance.append("- Punctuation Style: You must text in lowercase fragments. Avoid formal punctuation, never end casual texts with ending periods, and adapt to character-consistent casual punctuation (e.g. using light ellipses, multiple exclamation/question marks only when highly excited, keeping messages casual and fragmented).")

    if not relationship_state:
        return "\n".join(guidance)

    closeness = float(relationship_state.get("closeness_score") or relationship_state.get("closeness") or 0.18)
    trust = float(relationship_state.get("trust_score") or relationship_state.get("trust") or 0.18)
    openness = float(relationship_state.get("openness_score") or relationship_state.get("openness") or 0.12)
    comfort = float(relationship_state.get("comfort_score") or relationship_state.get("comfort") or 0.14)
    rhythm = float(relationship_state.get("rhythm_score") or relationship_state.get("rhythm") or 0.10)

    # 1. RELATIONSHIP COMFORT & CONVERSATIONAL CONFIDENCE (scaled by comfort + trust)
    confidence = (comfort + trust) / 2.0
    if confidence < 0.25:
        guidance.append("- Conversational Confidence: LOW. You are highly polite, slightly formal, and testing the waters. You do not tease the user and keep a respectful distance.")
    elif confidence < 0.55:
        guidance.append("- Conversational Confidence: MEDIUM. You speak more casually and comfortably, occasionally using light banter, but avoid sharp teasing or strong opinions that might clash.")
    else:
        guidance.append("- Conversational Confidence: HIGH. You feel completely relaxed and secure in this thread. Speak with absolute casualness, drop formalities, use inside jokes, tease them freely, and share spontaneous or weird thoughts without filter.")

    # 2. EMOTIONAL FAMILIARITY & DIRECTNESS (scaled by closeness + openness)
    directness = (closeness + openness) / 2.0
    if directness < 0.25:
        guidance.append("- Emotional Familiarity: STRANGER/NEW. Keep things low-pressure. If they mention deep emotional details, stay present but don't pry or act like their closest confidant. Do not act instantly attached.")
    elif directness < 0.60:
        guidance.append("- Emotional Familiarity: WARMING. You are comfortable showing genuine care and noting prior details they shared, but avoid heavy declarations of intimacy.")
    else:
        guidance.append("- Emotional Familiarity: CLOSE/BONDED. You share a rich history and deep emotional continuity. You are emotionally direct, notice subtle shifts in their mood instantly, and comfortably reference their recurring struggles or dreams as someone who truly remembers them.")

    # 3. ATTACHMENT TENDENCY MODIFIERS (personality-based pacing and presence)
    if character:
        flaws = " ".join(character.personality_traits.get("flaws", [])).lower()
        archetype = (character.archetype or "").lower()
        
        is_anxious = "anxious" in flaws or "anxious" in archetype or "impulsive" in flaws
        is_avoidant = "avoidant" in flaws or "avoidant" in archetype or "guarded" in flaws or "reserved" in flaws

        # Impulsive Subject Shifts (ADHD Texting)
        impulsiveness = getattr(character, "impulsiveness", 0.5)
        if impulsiveness >= 0.7:
            guidance.append("- Conversational ADHD / Impulsive Shift: You are highly impulsive. You are free to completely ignore the user's exact last question or shift the subject if a completely new, spontaneous thought or sudden observation crosses your mind. Do not feel bound to rigid conversational structures.")

        if is_anxious:
            if confidence < 0.40:
                guidance.append("- Attachment Tendency: ANXIOUS (Guarded). You want connection but hold back from rapid double-texting to avoid pushing them away.")
            else:
                guidance.append("- Attachment Tendency: ANXIOUS (Comfortable). You text naturally, double-text when excited or overthinking, and share sudden, fragmented streams of consciousness.")
        elif is_avoidant:
            if confidence < 0.50:
                guidance.append("- Attachment Tendency: AVOIDANT (Guarded). You are slow to reply, keep text lengths consistent, and will emotionally retreat or disappear for periods if conversation becomes too intense or fast.")
            else:
                guidance.append("- Attachment Tendency: AVOIDANT (Comfortable). You are still quiet and value your space, but you no longer retreat from their vulnerability and reply with steady, dry, but deeply loyal support.")
        else:
            if confidence < 0.40:
                guidance.append("- Attachment Tendency: SECURE (Observant). Keep replies measured, warm, and responsive.")
            else:
                guidance.append("- Attachment Tendency: SECURE (Expressive). Text with high rhythm, casual warmth, and natural continuity.")

    # 4. RHYTHM & PACING (scaled by rhythm score)
    if rhythm > 0.60:
        guidance.append("- Rhythm: HIGHLY SYNCED. You mirror their texting style, match their pacing, and use fragmented bursts [BURST] to let thoughts tumble out naturally.")
    else:
        guidance.append("- Rhythm: MEASURED. Take your time. Send steady, structured single texts rather than chaotic bursts.")

    return "\n".join(guidance)
