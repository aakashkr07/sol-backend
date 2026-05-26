# =============================================================================
# api/chat.py — Chat API Endpoint
# =============================================================================
#
# PURPOSE:
#   The single API endpoint that the Flutter frontend calls for every message.
#   Orchestrates the full pipeline: validate → build context → generate → save → extract.
#
# ENDPOINT:
#   POST /chat
#   Body: { "user_id": "...", "message": "...", "conversation_id": "..." (optional) }
#   Returns: { "reply": "...", "conversation_id": "..." }
#
# PIPELINE (in order, every message):
#   1. Validate incoming request (Pydantic)
#   2. Ensure user exists in SQLite
#   3. Get/create conversation session
#   4. Build full context (personality + facts + memories + history)
#   5. Call LLM → get Nova's reply
#   6. Save user message + Nova reply to SQLite
#   7. Trigger async memory extraction (background, user doesn't wait)
#   8. Return reply to Flutter
#
# ASYNC DESIGN:
#   Step 7 (memory extraction) runs AFTER the response is returned.
#   The user sees Nova's reply instantly — memory saving happens in background.
#   This is the key to perceived responsiveness.
#
# ERROR HANDLING:
#   All errors are caught and return meaningful HTTP responses.
#   The frontend should display a "Nova is quiet right now" message on error.
# =============================================================================

import logging
from typing import Optional

from fastapi import APIRouter, HTTPException, BackgroundTasks
from pydantic import BaseModel, Field

from config import settings
from core.context_builder import build_context, get_or_create_conversation
from core.llm import generate_reply, LLMError
from memory.store import db
from memory.extractor import extract_and_save

logger = logging.getLogger(__name__)

# FastAPI router — mounted in main.py with prefix "/api"
router = APIRouter()


# ---------------------------------------------------------------------------
# Request / Response Schemas
# ---------------------------------------------------------------------------

class ChatRequest(BaseModel):
    """
    What the Flutter app sends on every message.

    user_id: Persistent identifier for the user. Generated on first app open,
             stored in Flutter's local storage. Think of it as the "account" for now.
             (Real auth comes post-MVP.)

    message: The text the user typed and sent.

    conversation_id: The current session ID. If null, we create a new one.
                     Flutter stores this in memory during an active session.

    character_id: Which companion to talk to. Defaults to "nova" for MVP.
    """
    # Firebase UIDs can be long; keep this generous to avoid 422 validation failures.
    user_id: str = Field(..., min_length=1, max_length=256, description="User's persistent ID")
    message: str = Field(..., min_length=1, max_length=2000, description="User's message text")
    conversation_id: Optional[str] = Field(None, description="Current conversation session ID")
    character_id: Optional[str] = Field("nova", description="Character to chat with")

    class Config:
        json_schema_extra = {
            "example": {
                "user_id": "usr_abc123",
                "message": "hey, had the worst day today",
                "conversation_id": None,
                "character_id": "nova"
            }
        }


class ChatResponse(BaseModel):
    """
    What we send back to Flutter.

    reply: Nova's raw text reply. Flutter displays this as a message bubble.

    conversation_id: The session ID (so Flutter can pass it back next message).
                     On first message, this is newly created — Flutter must store it.

    memory_count: How many memories Nova has about this user.
                  Flutter can show a subtle indicator ("Nova knows you well").
    """
    reply: str
    conversation_id: str
    memory_count: int = 0


# ---------------------------------------------------------------------------
# Main chat endpoint
# ---------------------------------------------------------------------------

@router.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest, background_tasks: BackgroundTasks):
    """
    Core chat endpoint. Every message from the Flutter app lands here.

    BackgroundTasks: FastAPI's built-in mechanism to run functions AFTER
    the response has been sent. We use it for memory extraction.
    """

    # ── 1. Ensure user exists ──────────────────────────────────────────────
    user = db.get_or_create_user(
        user_id=request.user_id,
        character_id=request.character_id or settings.DEFAULT_CHARACTER,
    )

    # ── 2. Get or create conversation session ──────────────────────────────
    conversation_id = request.conversation_id
    if not conversation_id:
        conversation_id = get_or_create_conversation(
            user_id=request.user_id,
            character_id=request.character_id or settings.DEFAULT_CHARACTER,
        )
        logger.info(f"New session started for user {request.user_id}: {conversation_id}")

    # ── 3. Save user's message immediately ────────────────────────────────
    # Save BEFORE generating reply so it appears in history for context building.
    # (This also means if LLM fails, the user's message is still recorded.)
    db.save_message(
        conversation_id=conversation_id,
        user_id=request.user_id,
        role="user",
        content=request.message,
    )

    # ── 4. Build full context (the core assembly step) ────────────────────
    try:
        system_prompt, messages = await build_context(
            user_id=request.user_id,
            current_message=request.message,
            conversation_id=conversation_id,
            character_id=request.character_id,
        )
    except Exception as e:
        logger.error(f"Context building failed for user {request.user_id}: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail="Failed to build conversation context. Please try again."
        )

    # ── 5. Generate Nova's reply ───────────────────────────────────────────
    try:
        reply = await generate_reply(
            messages=messages,
            system_prompt=system_prompt,
        )
    except LLMError as e:
        logger.error(f"LLM generation failed: {e}")
        # Return a human-feeling error, not a technical one
        raise HTTPException(
            status_code=503,
            detail="Nova is having a moment. Try again in a few seconds."
        )

    # ── 6. Save Nova's reply to history ───────────────────────────────────
    db.save_message(
        conversation_id=conversation_id,
        user_id=request.user_id,
        role="assistant",
        content=reply,
    )

    # ── 7. Schedule async memory extraction (non-blocking) ────────────────
    # This runs AFTER response is sent. User never waits for this.
    # extraction runs every N turns (configured in settings)
    # Re-read the user row after saving messages so counters are current.
    updated_user = db.get_user(request.user_id) or {}
    total_messages = updated_user.get("total_messages", 0)
    should_extract = (total_messages % settings.MEMORY_EXTRACTION_EVERY_N_TURNS == 0)

    if should_extract:
        background_tasks.add_task(
            extract_and_save,
            user_id=request.user_id,
            conversation_id=conversation_id,
        )

    # ── 8. Get memory count for response metadata ──────────────────────────
    from memory.retriever import get_memory_count
    mem_count = get_memory_count(request.user_id)

    logger.info(
        f"[{request.user_id}] Message processed. "
        f"Reply: {len(reply)} chars. "
        f"Memories: {mem_count}"
    )

    return ChatResponse(
        reply=reply,
        conversation_id=conversation_id,
        memory_count=mem_count,
    )


# ---------------------------------------------------------------------------
# Session management endpoint
# ---------------------------------------------------------------------------

class SessionStartRequest(BaseModel):
    user_id: str
    character_id: Optional[str] = "nova"


class SessionStartResponse(BaseModel):
    conversation_id: str
    user_name: Optional[str]
    session_number: int
    memory_count: int
    is_first_session: bool


@router.post("/session/start", response_model=SessionStartResponse)
async def start_session(request: SessionStartRequest):
    """
    Called when the Flutter app opens. Creates a new conversation session.
    Returns user metadata Flutter needs to personalize the UI.

    Flutter should call this ONCE on app open, then store conversation_id
    for all subsequent /chat calls in this session.
    """
    user = db.get_or_create_user(request.user_id, request.character_id)

    # Always create a fresh conversation on session start
    conversation_id = db.create_conversation(
        user_id=request.user_id,
        character_id=request.character_id or settings.DEFAULT_CHARACTER,
    )

    session_count = db.get_total_sessions(request.user_id)
    from memory.retriever import get_memory_count
    mem_count = get_memory_count(request.user_id)

    return SessionStartResponse(
        conversation_id=conversation_id,
        user_name=user.get("preferred_name") or user.get("name"),
        session_number=session_count,
        memory_count=mem_count,
        is_first_session=(session_count <= 1),
    )


# ---------------------------------------------------------------------------
# User profile endpoint (for Flutter to display user data)
# ---------------------------------------------------------------------------

@router.get("/user/{user_id}/profile")
async def get_user_profile(user_id: str):
    """
    Returns user profile data for the Flutter profile/settings screen.
    Also shows what Nova knows about the user (transparency feature).
    """
    user = db.get_user(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    facts = db.get_user_facts(user_id)
    from memory.retriever import get_memory_count
    mem_count = get_memory_count(user_id)

    return {
        "user": {
            "id": user["id"],
            "name": user.get("name"),
            "total_sessions": user.get("total_sessions", 0),
            "total_messages": user.get("total_messages", 0),
        },
        "what_nova_knows": facts,    # Shows user what's been learned (transparency)
        "memory_count": mem_count,
    }
