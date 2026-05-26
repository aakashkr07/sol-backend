# =============================================================================
# core/context_builder.py — The Brain: Full Prompt Assembly Engine
# =============================================================================
#
# PURPOSE:
#   This is the most important file in the entire backend.
#   It takes inputs from every layer and assembles the final, complete prompt
#   that gets sent to the LLM on every single message.
#
# THIS IS WHERE THE MAGIC HAPPENS:
#   The prompt = personality + user facts + retrieved memories + conversation history
#
# THE ASSEMBLY ORDER (matters for LLM attention):
#   1. System prompt (personality, character rules, who Nova is)
#   2. User facts (always-on structured knowledge)
#   3. Relevant memories (retrieved from ChromaDB by semantic similarity)
#   4. Conversation summary (if prior sessions exist — compressed long-term memory)
#   5. Recent message history (the last N turns of actual conversation)
#   [User's current message is added by the API layer, not here]
#
# WHY ORDER MATTERS:
#   LLMs pay more attention to content at the START and END of the prompt.
#   - System prompt at top: establishes the "who" strongly
#   - Memories in the middle: available but not overriding personality
#   - Recent history near the bottom: gives current conversation context
#   - User message at the very end: what the model responds to
#
# TOKEN BUDGET MANAGEMENT:
#   Free tier Groq has a token limit. We track budget here and trim gracefully:
#   - Memories trimmed first if budget tight
#   - History trimmed second
#   - Facts and personality NEVER trimmed (core identity)
#
# USAGE:
#   from core.context_builder import build_context
#   system_prompt, messages = await build_context(user_id, user_message)
# =============================================================================

import logging
from typing import Optional

from config import settings
from memory.store import db
from memory.retriever import retrieve_relevant_memories, format_memories_for_prompt
from personality.loader import load_character, build_system_prompt

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Token budget constants
# ---------------------------------------------------------------------------
# Rough estimates: 1 token ≈ 4 characters in English
# These aren't exact — they're conservative budgets to stay safe on free tier.

TOTAL_TOKEN_BUDGET = 6000         # Total prompt tokens (safe for 8192 context models)
SYSTEM_PROMPT_BUDGET = 1500       # Reserved for personality system prompt
FACTS_BUDGET = 400                # Reserved for user facts injection
MEMORIES_BUDGET = 800             # Reserved for retrieved episodic memories
HISTORY_BUDGET = 2500             # Reserved for recent conversation turns
RESPONSE_BUFFER = 400             # Leave room for the response (max_tokens)


# ---------------------------------------------------------------------------
# Main context builder
# ---------------------------------------------------------------------------

async def build_context(
    user_id: str,
    current_message: str,
    conversation_id: Optional[str] = None,
    character_id: Optional[str] = None,
) -> tuple[str, list[dict]]:
    """
    Assembles the complete prompt for an LLM call.

    Args:
        user_id: The user's ID (used to query all their data).
        current_message: The message the user just sent.
                         Used for: memory retrieval query + added to history.
        conversation_id: Current conversation session ID.
        character_id: Which character to use (defaults to user's assigned character).

    Returns:
        Tuple of (system_prompt: str, messages: list[dict])
        - system_prompt: Full personality + injected context prompt
        - messages: [{role, content}, ...] conversation history for the LLM
    """

    # ── Step 1: Load user data ─────────────────────────────────────────────
    user = db.get_user(user_id)
    if not user:
        # First message ever — create the user
        user = db.get_or_create_user(user_id)

    cid = character_id or user.get("character_id") or settings.DEFAULT_CHARACTER
    session_count = db.get_total_sessions(user_id)
    user_facts = db.get_user_facts(user_id)
    user_name = user.get("preferred_name") or user.get("name")

    # ── Step 2: Load character and build base system prompt ────────────────
    character = load_character(cid)

    base_system_prompt = build_system_prompt(
        character=character,
        user_name=user_name,
        session_count=session_count,
        user_facts=user_facts,
    )

    # ── Step 3: Retrieve relevant memories from ChromaDB ───────────────────
    # Query = current message + last assistant message (gives richer context)
    # to find memories relevant to what's being discussed RIGHT NOW
    recent_msgs = db.get_recent_messages(user_id, limit=3)
    memory_query = _build_memory_query(current_message, recent_msgs)

    memories = retrieve_relevant_memories(
        user_id=user_id,
        query_text=memory_query,
        n_results=settings.MEMORY_RETRIEVAL_COUNT,
    )

    # ── Step 4: Build the memory injection block ───────────────────────────
    memory_block = _build_memory_block(memories)

    # ── Step 5: Get conversation history for the messages array ───────────
    history_messages = db.get_recent_messages(user_id, limit=settings.RECENT_HISTORY_TURNS)

    # ── Step 6: Assemble the final system prompt ───────────────────────────
    final_system_prompt = _assemble_system_prompt(
        base_prompt=base_system_prompt,
        memory_block=memory_block,
        user_facts=user_facts,
        session_count=session_count,
        user_name=user_name,
    )

    # ── Step 7: Format history as LLM messages array ──────────────────────
    messages = _format_history_as_messages(history_messages)

    # ── Step 8: Add current user message ──────────────────────────────────
    # chat.py saves the current user message before calling build_context(),
    # so appending here would duplicate it in the model input.

    # ── Debug logging (remove in production) ──────────────────────────────
    if settings.DEBUG:
        logger.debug(
            f"Context built for {user_id}: "
            f"{len(memories)} memories, {len(history_messages)} history turns, "
            f"~{_estimate_tokens(final_system_prompt)} system tokens"
        )

    return final_system_prompt, messages


# ---------------------------------------------------------------------------
# System prompt assembly
# ---------------------------------------------------------------------------

def _assemble_system_prompt(
    base_prompt: str,
    memory_block: str,
    user_facts: dict,
    session_count: int,
    user_name: Optional[str],
) -> str:
    """
    Combines the base personality prompt with injected context.

    The base_prompt already has facts woven in (from build_system_prompt),
    but we add the RETRIEVED MEMORIES here as a separate, clearly labeled block.
    This keeps memories distinct from always-on facts in the model's attention.
    """
    sections = [base_prompt]

    # Inject episodic memories if any were retrieved
    if memory_block:
        sections.append(f"""
---
RELEVANT MEMORIES FROM YOUR PAST CONVERSATIONS WITH THIS PERSON:
(Use these naturally — reference them when they fit the conversation.
 Don't list them robotically. Let them inform how you respond.)

{memory_block}
---""")

    # Relationship context note (helps calibrate tone)
    if session_count == 1:
        sections.append(
            "\nThis is your FIRST conversation with this person. "
            "Be warm and curious. You're just meeting them. "
            "Ask questions to start learning who they are."
        )
    elif session_count <= 3:
        sections.append(
            f"\nThis is conversation #{session_count}. "
            "You're getting to know each other. "
            "You can reference something from a previous chat if it fits naturally."
        )

    return "\n".join(sections)


def _build_memory_block(memories: list[dict]) -> str:
    """
    Converts retrieved memories into the block injected into the system prompt.
    Prioritizes high-importance emotional memories.
    """
    if not memories:
        return ""

    return format_memories_for_prompt(memories)


# ---------------------------------------------------------------------------
# Memory query construction
# ---------------------------------------------------------------------------

def _build_memory_query(current_message: str, recent_messages: list[dict]) -> str:
    """
    Builds the query text for ChromaDB semantic search.

    Using just the current message works, but using the last few turns
    gives better context for what the conversation is actually about.
    Example: if user says "yeah, me too", the query should include what
    they said "too" about — not just "yeah me too".
    """
    parts = []

    # Add last 2 turns of context (if available)
    for msg in recent_messages[-2:]:
        if msg["role"] == "user":
            parts.append(msg["content"])

    # Add current message
    parts.append(current_message)

    # Join and trim to reasonable length for embedding
    query = " ".join(parts)
    return query[:500]   # ChromaDB embedding models handle up to ~512 tokens


# ---------------------------------------------------------------------------
# History formatting
# ---------------------------------------------------------------------------

def _format_history_as_messages(history: list[dict]) -> list[dict]:
    """
    Converts database message rows into the format the LLM API expects.
    Filters out any messages with empty content (defensive).
    """
    messages = []
    for msg in history:
        role = msg.get("role", "user")
        content = msg.get("content", "").strip()
        if content and role in ("user", "assistant"):
            messages.append({"role": role, "content": content})
    return messages


# ---------------------------------------------------------------------------
# Token estimation (rough)
# ---------------------------------------------------------------------------

def _estimate_tokens(text: str) -> int:
    """
    Rough token count estimate: 1 token ≈ 4 characters.
    Good enough for budget management. Not exact.
    """
    return len(text) // 4


# ---------------------------------------------------------------------------
# Conversation initialization helper
# ---------------------------------------------------------------------------

def get_or_create_conversation(user_id: str, character_id: str = "nova") -> str:
    """
    Gets the current open conversation ID for a user, or creates a new one.
    Called at the start of every chat session.

    A "session" = app open event. We track this so we can:
    1. Associate messages with sessions for memory extraction
    2. Generate per-session summaries for long-term memory compression
    3. Track relationship arc progress (session count = intimacy level)
    """
    conv_id = db.get_current_conversation(user_id)
    if not conv_id:
        conv_id = db.create_conversation(user_id, character_id)
        logger.info(f"New conversation created for {user_id}: {conv_id}")
    return conv_id
