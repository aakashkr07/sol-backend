# =============================================================================
# memory/extractor.py — Conversation Memory Extraction Engine
# =============================================================================
#
# PURPOSE:
#   After every exchange, this runs asynchronously to extract two things:
#   1. USER FACTS — structured data (name, job, relationships, preferences)
#      → stored in SQLite via db.save_user_fact()
#   2. EPISODIC MEMORIES — emotional moments, events, stories
#      → stored in ChromaDB via retriever.py for semantic retrieval later
#
# HOW IT WORKS:
#   1. Gets unprocessed messages from SQLite
#   2. Sends them to the LLM with an extraction prompt
#   3. LLM returns JSON with structured facts and episodic memories
#   4. We save facts to SQLite, memories to ChromaDB
#   5. Mark messages as processed
#
# WHY ASYNC:
#   This runs AFTER the response is sent to the user. The user never waits
#   for extraction — they get Nova's reply instantly, and memory saves happen
#   in the background. This is critical for perceived speed.
#
# RATE LIMIT PROTECTION:
#   We use a separate lightweight LLM call for extraction. If Groq rate-limits
#   us, extraction fails silently (with logging) — the conversation still works.
#
# USAGE:
#   from memory.extractor import extract_and_save
#   asyncio.create_task(extract_and_save(user_id, conversation_id))
# =============================================================================

import json
import uuid
import logging
import asyncio
from typing import Optional

import httpx

from config import settings
from memory.store import db

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Extraction prompt
# ---------------------------------------------------------------------------

EXTRACTION_SYSTEM_PROMPT = """You are a memory extraction engine for an AI companion app.
Your job is to analyze a conversation and extract two types of information.

Return ONLY valid JSON, no explanation, no markdown. Format:
{
  "facts": [
    {"category": "personal|work|relationships|preferences|goals|struggles",
     "key": "snake_case_key",
     "value": "the value",
     "confidence": 0.0-1.0}
  ],
  "memories": [
    {"content": "A single clear sentence describing what happened or was shared",
     "emotion_tag": "joy|sadness|anxiety|excitement|anger|grief|pride|loneliness|null",
     "importance": 0.0-1.0}
  ]
}

FACTS guidelines:
- Only extract FACTS that are explicitly stated or very strongly implied
- key must be snake_case (e.g. "job", "sister_name", "favorite_food", "current_struggle")
- confidence: 1.0 = explicitly stated, 0.7 = strongly implied, 0.5 = uncertain
- categories: personal (age/location/name), work (job/company), relationships (family/friends),
  preferences (likes/dislikes), goals (aspirations), struggles (problems/pain points)
- Do NOT extract facts that are already common knowledge
- SKIP if nothing factual was shared

MEMORIES guidelines:
- Each memory = one meaningful moment, emotion, or story from this exchange
- Write in third person: "User said their dog Mango died last year and they still miss her"
- importance: 1.0 = deeply personal/emotional, 0.5 = meaningful, 0.2 = casual mention
- emotion_tag: the PRIMARY emotion present (null if purely factual)
- Only extract memories worth remembering — skip small talk, filler
- Max 3 memories per extraction call

If there's nothing worth extracting for either category, return empty arrays []."""


# ---------------------------------------------------------------------------
# Main extraction function
# ---------------------------------------------------------------------------

async def extract_and_save(
    user_id: str,
    conversation_id: str,
) -> None:
    """
    Main entry point. Called as a background task after every message exchange.

    Pipeline:
    1. Fetch unextracted messages from SQLite
    2. Build extraction prompt
    3. Call LLM (lightweight, fast model)
    4. Parse JSON response
    5. Save facts to SQLite, memories to ChromaDB
    6. Mark messages as extracted
    """
    try:
        # 1. Get messages that haven't been processed yet
        unextracted = db.get_unextracted_messages(user_id)
        if not unextracted:
            return

        message_ids = [m["id"] for m in unextracted]

        # 2. Build the conversation text for the extraction prompt
        convo_text = _format_messages_for_extraction(unextracted)

        # 3. Call LLM for extraction
        extracted = await _run_extraction_llm(convo_text)
        if not extracted:
            logger.warning(f"Extraction returned nothing for user {user_id}")
            return

        # 4. Save facts to SQLite
        facts = extracted.get("facts", [])
        for fact in facts:
            if _is_valid_fact(fact):
                db.save_user_fact(
                    user_id=user_id,
                    category=fact.get("category", "personal"),
                    key=fact["key"],
                    value=str(fact["value"]),
                    confidence=float(fact.get("confidence", 0.8)),
                    source="extracted",
                )
                logger.debug(f"Fact saved: {fact['key']} = {fact['value']}")

                # Special case: if we extracted the user's name, update the user record
                if fact["key"] in ("name", "preferred_name", "first_name"):
                    db.update_user_name(user_id, str(fact["value"]))

        # 5. Save episodic memories to ChromaDB
        memories = extracted.get("memories", [])
        if memories:
            await _save_memories_to_chroma(user_id, conversation_id, memories, message_ids)

        # 6. Mark messages as processed
        db.mark_messages_extracted(message_ids)

        logger.info(
            f"Extraction complete for user {user_id}: "
            f"{len(facts)} facts, {len(memories)} memories"
        )

    except Exception as e:
        # CRITICAL: Never let extraction failure break the main chat loop
        logger.error(f"Memory extraction failed for user {user_id}: {e}", exc_info=True)


# ---------------------------------------------------------------------------
# LLM call for extraction
# ---------------------------------------------------------------------------

async def _run_extraction_llm(conversation_text: str) -> Optional[dict]:
    """
    Calls Groq with the extraction prompt.
    Uses the FASTER/cheaper model (llama3-8b) because:
    - extraction doesn't need 70B quality
    - we're already using 70B for the main chat
    - free tier rate limits are per model, so we spread the load
    """
    if not settings.GROQ_API_KEY:
        logger.error("No GROQ_API_KEY — cannot run extraction")
        return None

    payload = {
        "model": settings.LLM_FALLBACK_MODEL,   # 8B for extraction (fast + cheap)
        "temperature": 0.1,                       # Low temp = consistent JSON output
        "max_tokens": 500,
        "messages": [
            {"role": "system", "content": EXTRACTION_SYSTEM_PROMPT},
            {"role": "user", "content": f"Extract from this conversation:\n\n{conversation_text}"}
        ]
    }

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.post(
                f"{settings.GROQ_BASE_URL}/chat/completions",
                headers={
                    "Authorization": f"Bearer {settings.GROQ_API_KEY}",
                    "Content-Type": "application/json",
                },
                json=payload
            )
            response.raise_for_status()
            data = response.json()

            raw_text = data["choices"][0]["message"]["content"].strip()

            # Strip markdown code blocks if present (LLM sometimes adds them)
            if raw_text.startswith("```"):
                raw_text = raw_text.split("```")[1]
                if raw_text.startswith("json"):
                    raw_text = raw_text[4:]

            return json.loads(raw_text)

    except json.JSONDecodeError as e:
        logger.error(f"Extraction LLM returned invalid JSON: {e}")
        return None
    except Exception as e:
        logger.error(f"Extraction LLM call failed: {e}")
        return None


# ---------------------------------------------------------------------------
# ChromaDB memory saving
# ---------------------------------------------------------------------------

async def _save_memories_to_chroma(
    user_id: str,
    conversation_id: str,
    memories: list[dict],
    source_message_ids: list[int],
) -> None:
    """
    Saves episodic memories to ChromaDB for semantic retrieval.
    Also indexes them in SQLite for bookkeeping.

    ChromaDB handles the embedding automatically — we just give it text.
    """
    try:
        # Import here to avoid circular imports and to lazy-load ChromaDB
        from memory.retriever import get_chroma_collection

        collection = get_chroma_collection(user_id)

        for memory in memories:
            content = memory.get("content", "").strip()
            if not content or len(content) < 10:
                continue

            memory_id = str(uuid.uuid4())
            importance = float(memory.get("importance", 0.5))
            emotion_tag = memory.get("emotion_tag") or ""

            # Add to ChromaDB (handles embedding automatically)
            collection.add(
                ids=[memory_id],
                documents=[content],
                metadatas=[{
                    "user_id": user_id,
                    "conversation_id": conversation_id,
                    "emotion_tag": emotion_tag,
                    "importance": importance,
                }]
            )

            # Log in SQLite for bookkeeping
            db.log_memory(
                memory_id=memory_id,
                user_id=user_id,
                content=content,
                emotion_tag=emotion_tag or None,
                importance=importance,
                conversation_id=conversation_id,
                source_message_ids=source_message_ids,
            )

            logger.debug(f"Memory saved: [{emotion_tag}] {content[:60]}...")

    except Exception as e:
        logger.error(f"Failed to save memories to ChromaDB: {e}", exc_info=True)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _format_messages_for_extraction(messages: list[dict]) -> str:
    """Formats a list of message dicts into a clean conversation string."""
    lines = []
    for msg in messages:
        role = "User" if msg["role"] == "user" else "Nova"
        lines.append(f"{role}: {msg['content']}")
    return "\n".join(lines)


def _is_valid_fact(fact: dict) -> bool:
    """Validates that a fact has the required fields and non-empty values."""
    return (
        isinstance(fact, dict)
        and "key" in fact
        and "value" in fact
        and fact["key"]
        and fact["value"]
        and str(fact["value"]).strip()
        and len(str(fact["key"])) < 60    # Sanity check on key length
        and len(str(fact["value"])) < 500  # Sanity check on value length
    )