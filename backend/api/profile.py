import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from auth.firebase import AuthenticatedIdentity, get_authenticated_identity
from memory.retriever import clear_all_memories, delete_memory, get_memory_count, update_memory_document
from memory.store import db
from personality.registry import build_pair_payload

logger = logging.getLogger(__name__)

router = APIRouter()


class UserPreferencesUpdate(BaseModel):
    allow_memory_storage: Optional[bool] = None
    show_memory_overview: Optional[bool] = None
    allow_proactive_messages: Optional[bool] = None
    allow_push_notifications: Optional[bool] = None
    quiet_hours_start: Optional[int] = Field(None, ge=0, le=23)
    quiet_hours_end: Optional[int] = Field(None, ge=0, le=23)
    allow_sensitive_proactive: Optional[bool] = None


class PairPreferencesUpdate(BaseModel):
    proactive_enabled: Optional[bool] = None
    proactive_cadence: Optional[str] = Field(None, pattern="^(gentle|balanced|frequent)$")
    proactive_emotional_callbacks_enabled: Optional[bool] = None


class DeviceTokenRegistration(BaseModel):
    platform: str = Field(..., min_length=2, max_length=32)
    push_token: str = Field(..., min_length=8, max_length=4096)


class FactUpdate(BaseModel):
    value: str = Field(..., min_length=1, max_length=500)


class MemoryUpdate(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=120)
    content: Optional[str] = Field(None, min_length=1, max_length=2000)


def _resolve_owned_pair(identity: AuthenticatedIdentity, pair_id: Optional[str]) -> Optional[dict]:
    if not pair_id:
        return db.get_primary_pair(identity.uid)
    pair = db.get_pair_by_id(pair_id)
    if not pair or pair["user_id"] != identity.uid:
        raise HTTPException(status_code=404, detail="Relationship not found")
    return pair


@router.get("/me/profile")
async def get_my_profile(
    pair_id: Optional[str] = Query(default=None),
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    user = db.get_user(identity.uid)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    pair = _resolve_owned_pair(identity, pair_id)
    preferences = db.get_or_create_user_preferences(identity.uid)
    pairs = [build_pair_payload(item) for item in db.list_pairs_for_user(identity.uid)]

    selected_pair = None
    memory_count = 0
    relationship_state = None
    what_sol_knows = {}
    fact_rows = []
    fact_conflicts = []
    memories = []
    current_narrative = None

    if pair:
        selected_pair = build_pair_payload(pair)
        memory_count = get_memory_count(pair["id"], user_id=identity.uid)
        relationship_state = db.get_relationship_state_snapshot(pair["id"])
        what_sol_knows = db.get_user_facts(identity.uid, pair_id=pair["id"])
        fact_rows = db.get_user_fact_rows(identity.uid, pair_id=pair["id"], limit=40)
        fact_conflicts = db.get_fact_conflicts(pair["id"], limit=10)
        memories = db.list_pair_memories(pair["id"], limit=40)
        current_narrative = db.get_current_narrative(identity.uid, pair_id=pair["id"])

    return {
        "user": {
            "id": user["id"],
            "name": user.get("preferred_name") or user.get("name") or user.get("display_name"),
            "email": user.get("email"),
            "display_name": user.get("display_name"),
            "timezone": user.get("timezone"),
            "created_at": user.get("created_at"),
            "total_sessions": user.get("total_sessions", 0),
            "total_messages": user.get("total_messages", 0),
            "onboarding_completed": bool(user.get("onboarding_completed", 0)),
        },
        "preferences": preferences,
        "pairs": pairs,
        "selected_pair": selected_pair,
        "memory_count": memory_count,
        "relationship_state": relationship_state,
        "what_sol_knows": what_sol_knows,
        "fact_rows": fact_rows,
        "fact_conflicts": fact_conflicts,
        "memories": memories,
        "current_narrative": current_narrative,
    }


@router.get("/me/pairs/{pair_id}/memories")
async def get_pair_memories(
    pair_id: str,
    limit: int = Query(default=40, ge=1, le=100),
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    pair = _resolve_owned_pair(identity, pair_id)
    return {
        "pair": build_pair_payload(pair),
        "memories": db.list_pair_memories(pair["id"], limit=limit),
    }


@router.patch("/me/preferences")
async def update_my_preferences(
    payload: UserPreferencesUpdate,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    updated = db.update_user_preferences(identity.uid, **payload.model_dump(exclude_none=True))
    return {"preferences": updated}


@router.patch("/me/pairs/{pair_id}/preferences")
async def update_pair_preferences(
    pair_id: str,
    payload: PairPreferencesUpdate,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    pair = _resolve_owned_pair(identity, pair_id)
    updated = db.update_pair_proactive_settings(pair["id"], **payload.model_dump(exclude_none=True))
    return {"pair": build_pair_payload(updated or pair)}


@router.post("/me/device-token")
@router.post("/profile/device")
async def register_device_token(
    payload: DeviceTokenRegistration,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    registration = db.register_device_token(
        user_id=identity.uid,
        platform=payload.platform.strip().lower(),
        push_token=payload.push_token.strip(),
    )
    return {"device_registration": registration}


@router.delete("/me/pairs/{pair_id}/memories/{memory_id}")
async def remove_pair_memory(
    pair_id: str,
    memory_id: str,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    pair = _resolve_owned_pair(identity, pair_id)
    deleted_vector = delete_memory(pair["id"], memory_id, user_id=identity.uid)
    deleted_record = db.delete_memory_record(pair["id"], memory_id)
    return {"deleted": deleted_vector or deleted_record}


@router.patch("/me/pairs/{pair_id}/facts/{fact_id}")
async def correct_pair_fact(
    pair_id: str,
    fact_id: int,
    payload: FactUpdate,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    pair = _resolve_owned_pair(identity, pair_id)
    updated = db.update_user_fact_value(
        user_id=identity.uid,
        pair_id=pair["id"],
        fact_id=fact_id,
        value=payload.value,
    )
    if not updated:
        raise HTTPException(status_code=404, detail="Fact not found")
    return {"fact": updated}


@router.patch("/me/pairs/{pair_id}/memories/{memory_id}")
async def correct_pair_memory(
    pair_id: str,
    memory_id: str,
    payload: MemoryUpdate,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    pair = _resolve_owned_pair(identity, pair_id)
    if payload.title is None and payload.content is None:
        raise HTTPException(status_code=400, detail="Nothing to update")

    current = next(
        (
            item for item in db.list_pair_memories(pair["id"], limit=100)
            if item.get("chroma_id") == memory_id
        ),
        None,
    )
    if not current:
        raise HTTPException(status_code=404, detail="Memory not found")

    title = payload.title if payload.title is not None else current.get("title")
    content = payload.content if payload.content is not None else current.get("content")
    updated_vector = update_memory_document(
        pair["id"],
        memory_id,
        title=title,
        content=content or "",
        user_id=identity.uid,
    )
    updated_record = db.update_memory_record(
        pair_id=pair["id"],
        chroma_id=memory_id,
        title=payload.title,
        content=payload.content,
    )
    if not updated_record:
        raise HTTPException(status_code=404, detail="Memory not found")
    updated_record["vector_updated"] = updated_vector
    return {"memory": updated_record}


@router.post("/me/pairs/{pair_id}/reset")
async def reset_pair_data(
    pair_id: str,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    pair = _resolve_owned_pair(identity, pair_id)
    clear_all_memories(pair["id"])
    
    with db.transaction():
        cleared = db.reset_pair_memory(pair["id"])
        db.log_system_event(
            "pair_memory_reset",
            "info",
            user_id=identity.uid,
            pair_id=pair["id"],
            payload={"cleared": cleared},
        )
    return {"reset": True, "cleared": cleared}


@router.delete("/me/account")
async def delete_my_account(
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    pairs = db.list_pairs_for_user(identity.uid)
    
    with db.transaction():
        db.log_system_event(
            "account_deleted",
            "warning",
            user_id=identity.uid,
            payload={"pair_count": len(pairs)},
        )
        for pair in pairs:
            clear_all_memories(pair["id"])

        deleted = db.delete_user_account(identity.uid)
    return {"deleted": True, "counts": deleted}
