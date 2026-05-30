import logging
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from pydantic import BaseModel, Field

from auth.firebase import AuthenticatedIdentity, get_authenticated_identity
from config import settings
from core.burst_engine import BurstSegment, plan_burst_response
from core.context_builder import build_context, get_or_create_conversation
from core.llm import LLMError, generate_reply
from memory.extractor import extract_and_save
from memory.relationship_engine import on_message_saved, on_session_started
from memory.retriever import get_memory_count
from memory.store import db
from personality.loader import load_character
from personality.registry import (
    build_inbox_entries,
    build_opening_line,
    build_pair_payload,
    get_active_companion_summaries,
    resolve_or_assign_primary_pair,
)

logger = logging.getLogger(__name__)

router = APIRouter()


class ChatRequest(BaseModel):
    user_id: Optional[str] = Field(None, min_length=1, max_length=256)
    message: str = Field(..., min_length=1, max_length=2000)
    conversation_id: Optional[str] = None
    character_id: Optional[str] = None
    client_sent_at: Optional[str] = None
    draft_duration_ms: Optional[int] = Field(default=None, ge=0, le=600000)
    reply_latency_ms: Optional[int] = Field(default=None, ge=0, le=86400000)


class BurstPayload(BaseModel):
    text: str
    pre_burst_delay_ms: int
    typing_duration_ms: int
    pause_intensity: str
    is_follow_up: bool = False


class ChatResponse(BaseModel):
    reply: str
    bursts: list[BurstPayload]
    conversation_id: str
    memory_count: int = 0
    pair_id: str
    companion_id: str
    companion_name: str


class SessionStartRequest(BaseModel):
    user_id: Optional[str] = None
    character_id: Optional[str] = None
    resume_existing: bool = True


class SessionHistoryMessage(BaseModel):
    role: str
    content: str
    created_at: Optional[str] = None


class SessionStartResponse(BaseModel):
    conversation_id: str
    user_name: Optional[str]
    session_number: int
    memory_count: int
    is_first_session: bool
    pair_id: str
    companion_id: str
    companion_name: str
    companion_summary: str
    opening_message: str
    opening_bursts: list[BurstPayload]
    resumed_existing: bool = False
    history_messages: list[SessionHistoryMessage] = []


def _ensure_request_matches_auth(request_user_id: Optional[str], identity: AuthenticatedIdentity) -> None:
    if request_user_id and request_user_id != identity.uid:
        raise HTTPException(status_code=403, detail="Authenticated uid does not match request user_id")


def _resolve_pair(identity: AuthenticatedIdentity, requested_character_id: Optional[str] = None) -> dict:
    return resolve_or_assign_primary_pair(
        user_id=identity.uid,
        requested_companion_id=requested_character_id,
    )


@router.post("/chat", response_model=ChatResponse)
async def chat(
    request: ChatRequest,
    background_tasks: BackgroundTasks,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    _ensure_request_matches_auth(request.user_id, identity)

    pair = _resolve_pair(identity, requested_character_id=request.character_id)
    companion = load_character(pair["companion_id"])
    user = db.get_or_create_user(
        user_id=identity.uid,
        character_id=pair["companion_id"],
        display_name=identity.display_name,
        email=identity.email,
    )

    conversation_id = request.conversation_id
    if conversation_id:
        conversation = db.get_conversation(conversation_id)
        if not conversation or conversation["user_id"] != identity.uid or conversation["pair_id"] != pair["id"]:
            raise HTTPException(status_code=404, detail="Conversation not found for this relationship")
    else:
        existing_conversation_id = db.get_current_conversation(identity.uid, pair_id=pair["id"])
        conversation_id = get_or_create_conversation(
            user_id=identity.uid,
            pair_id=pair["id"],
            companion_id=pair["companion_id"],
        )
        if not existing_conversation_id:
            on_session_started(pair["id"])
        logger.info("New session started for pair %s: %s", pair["id"], conversation_id)

    db.save_message(
        conversation_id=conversation_id,
        user_id=identity.uid,
        pair_id=pair["id"],
        companion_id=pair["companion_id"],
        role="user",
        content=request.message,
        client_sent_at=request.client_sent_at,
        draft_duration_ms=request.draft_duration_ms,
        reply_latency_ms=request.reply_latency_ms,
    )
    on_message_saved(pair["id"], "user", request.message)

    try:
        system_prompt, messages = await build_context(
            user_id=identity.uid,
            pair_id=pair["id"],
            current_message=request.message,
            conversation_id=conversation_id,
            character_id=pair["companion_id"],
        )
    except Exception as exc:
        logger.error("Context building failed for pair %s: %s", pair["id"], exc, exc_info=True)
        db.log_system_event(
            "context_build_failed",
            "error",
            user_id=identity.uid,
            pair_id=pair["id"],
            conversation_id=conversation_id,
            payload={"error": str(exc)},
        )
        raise HTTPException(status_code=500, detail="Failed to build conversation context. Please try again.")

    try:
        reply = await generate_reply(messages=messages, system_prompt=system_prompt)
    except LLMError as exc:
        logger.error("LLM generation failed for pair %s: %s", pair["id"], exc)
        db.log_system_event(
            "llm_generation_failed",
            "error",
            user_id=identity.uid,
            pair_id=pair["id"],
            conversation_id=conversation_id,
            payload={"error": str(exc)},
        )
        raise HTTPException(status_code=503, detail="Your companion is having a moment. Try again in a few seconds.")

    burst_plan = plan_burst_response(
        raw_text=reply,
        character=companion,
        user_message=request.message,
    )
    for burst in burst_plan.bursts:
        db.save_message(
            conversation_id=conversation_id,
            user_id=identity.uid,
            pair_id=pair["id"],
            companion_id=pair["companion_id"],
            role="assistant",
            content=burst.text,
        )
        on_message_saved(pair["id"], "assistant", burst.text)

    updated_pair = db.get_pair_by_id(pair["id"]) or pair
    total_messages = int(updated_pair.get("total_messages") or 0)
    should_extract = total_messages % settings.MEMORY_EXTRACTION_EVERY_N_TURNS == 0
    if should_extract:
        background_tasks.add_task(
            extract_and_save,
            user_id=identity.uid,
            pair_id=pair["id"],
            companion_id=pair["companion_id"],
            conversation_id=conversation_id,
        )

    mem_count = get_memory_count(pair_id=pair["id"], user_id=identity.uid)

    return ChatResponse(
        reply=burst_plan.combined_text,
        bursts=[_burst_payload(burst) for burst in burst_plan.bursts],
        conversation_id=conversation_id,
        memory_count=mem_count,
        pair_id=pair["id"],
        companion_id=companion.id,
        companion_name=companion.name,
    )


@router.post("/session/start", response_model=SessionStartResponse)
async def start_session(
    request: SessionStartRequest,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    _ensure_request_matches_auth(request.user_id, identity)

    pair = _resolve_pair(identity, requested_character_id=request.character_id)
    user = db.get_or_create_user(
        user_id=identity.uid,
        character_id=pair["companion_id"],
        display_name=identity.display_name,
        email=identity.email,
    )
    existing_conversation_id = (
        db.get_current_conversation(identity.uid, pair_id=pair["id"])
        if request.resume_existing
        else None
    )
    character = load_character(pair["companion_id"])
    mem_count = get_memory_count(pair_id=pair["id"], user_id=identity.uid)

    if existing_conversation_id:
        history_messages = db.get_recent_messages(
            user_id=identity.uid,
            pair_id=pair["id"],
            conversation_id=existing_conversation_id,
            limit=settings.RECENT_HISTORY_TURNS,
        )
        pair = db.get_pair_by_id(pair["id"]) or pair
        return SessionStartResponse(
            conversation_id=existing_conversation_id,
            user_name=user.get("preferred_name") or user.get("name") or identity.display_name,
            session_number=int(pair.get("total_sessions") or 1),
            memory_count=mem_count,
            is_first_session=int(pair.get("total_sessions") or 1) <= 1,
            pair_id=pair["id"],
            companion_id=character.id,
            companion_name=character.name,
            companion_summary=character.summary or character.core_identity.get("vibe", ""),
            opening_message="",
            opening_bursts=[],
            resumed_existing=True,
            history_messages=[
                SessionHistoryMessage(
                    role=message.get("role") or "assistant",
                    content=message.get("content") or "",
                    created_at=message.get("created_at"),
                )
                for message in history_messages
                if (message.get("content") or "").strip()
            ],
        )

    conversation_id = db.create_conversation(
        user_id=identity.uid,
        pair_id=pair["id"],
        companion_id=pair["companion_id"],
    )
    on_session_started(pair["id"])
    pair = db.get_pair_by_id(pair["id"]) or pair
    opening_message = build_opening_line(character, session_count=int(pair.get("total_sessions") or 1))
    opening_plan = plan_burst_response(
        raw_text=opening_message,
        character=character,
        is_opening=True,
    )
    for burst in opening_plan.bursts:
        db.save_message(
            conversation_id=conversation_id,
            user_id=identity.uid,
            pair_id=pair["id"],
            companion_id=pair["companion_id"],
            role="assistant",
            content=burst.text,
        )
        on_message_saved(pair["id"], "assistant", burst.text)

    return SessionStartResponse(
        conversation_id=conversation_id,
        user_name=user.get("preferred_name") or user.get("name") or identity.display_name,
        session_number=int(pair.get("total_sessions") or 1),
        memory_count=mem_count,
        is_first_session=int(pair.get("total_sessions") or 1) <= 1,
        pair_id=pair["id"],
        companion_id=character.id,
        companion_name=character.name,
        companion_summary=character.summary or character.core_identity.get("vibe", ""),
        opening_message=opening_plan.combined_text,
        opening_bursts=[_burst_payload(burst) for burst in opening_plan.bursts],
        resumed_existing=False,
        history_messages=[],
    )


@router.get("/user/{user_id}/profile")
async def get_user_profile(
    user_id: str,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    if user_id != identity.uid:
        raise HTTPException(status_code=403, detail="You can only read your own profile")

    user = db.get_user(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    primary_pair = db.get_primary_pair(user_id)
    pair_id = primary_pair["id"] if primary_pair else None
    facts = db.get_user_facts(user_id, pair_id=pair_id)
    mem_count = get_memory_count(pair_id=pair_id, user_id=user_id) if pair_id else 0
    pairs = [build_pair_payload(pair) for pair in db.list_pairs_for_user(user_id)]

    return {
        "user": {
            "id": user["id"],
            "name": user.get("preferred_name") or user.get("name") or user.get("display_name"),
            "email": user.get("email"),
            "total_sessions": user.get("total_sessions", 0),
            "total_messages": user.get("total_messages", 0),
            "onboarding_completed": bool(user.get("onboarding_completed", 0)),
        },
        "primary_pair_id": pair_id,
        "pairs": pairs,
        "what_sol_knows": facts,
        "memory_count": mem_count,
    }


@router.get("/companions/me")
async def get_my_companions(identity: AuthenticatedIdentity = Depends(get_authenticated_identity)):
    user = db.get_or_create_user(
        user_id=identity.uid,
        display_name=identity.display_name,
        email=identity.email,
    )
    primary_pair = db.get_primary_pair(identity.uid)
    if not primary_pair:
        primary_pair = _resolve_pair(identity)

    return {
        "available_companions": get_active_companion_summaries(),
        "pairs": [build_pair_payload(pair) for pair in db.list_pairs_for_user(identity.uid)],
        "primary_pair": build_pair_payload(primary_pair),
        "inbox_entries": build_inbox_entries(identity.uid),
        "user_name": user.get("preferred_name") or user.get("name") or user.get("display_name"),
        "onboarding_completed": bool(user.get("onboarding_completed", 0)),
    }


def _burst_payload(burst: BurstSegment) -> BurstPayload:
    return BurstPayload(
        text=burst.text,
        pre_burst_delay_ms=burst.pre_burst_delay_ms,
        typing_duration_ms=burst.typing_duration_ms,
        pause_intensity=burst.pause_intensity,
        is_follow_up=burst.is_follow_up,
    )
