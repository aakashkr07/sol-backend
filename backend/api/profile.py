import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from auth.firebase import AuthenticatedIdentity, get_authenticated_identity
from memory.retriever import clear_all_memories, delete_memory, get_memory_count
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
    facts = {}
    fact_rows = []
    conflicts = []
    memories = []
    relationship_state = None
    narrative = None
    session_summaries = []
    memory_count = 0

    if pair:
        selected_pair = build_pair_payload(pair)
        facts = db.get_user_facts(identity.uid, pair_id=pair["id"])
        fact_rows = db.get_user_fact_rows(identity.uid, pair_id=pair["id"], limit=12)
        conflicts = db.get_fact_conflicts(pair["id"], limit=6)
        memories = db.list_pair_memories(pair["id"], limit=20)
        relationship_state = db.get_relationship_state_snapshot(pair["id"])
        narrative = db.get_current_narrative(identity.uid, pair_id=pair["id"])
        session_summaries = db.get_recent_conversation_summaries(pair["id"], limit=5)
        memory_count = get_memory_count(pair["id"], user_id=identity.uid)

    return {
        "user": {
            "id": user["id"],
            "name": user.get("preferred_name") or user.get("name") or user.get("display_name"),
            "email": user.get("email"),
            "display_name": user.get("display_name"),
            "timezone": user.get("timezone"),
            "total_sessions": user.get("total_sessions", 0),
            "total_messages": user.get("total_messages", 0),
        },
        "preferences": preferences,
        "pairs": pairs,
        "selected_pair": selected_pair,
        "what_sol_knows": facts,
        "fact_rows": fact_rows,
        "fact_conflicts": conflicts,
        "memories": memories,
        "memory_count": memory_count,
        "relationship_state": relationship_state,
        "current_narrative": narrative,
        "recent_session_summaries": session_summaries,
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


@router.post("/me/pairs/{pair_id}/reset")
async def reset_pair_data(
    pair_id: str,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    pair = _resolve_owned_pair(identity, pair_id)
    clear_all_memories(pair["id"])
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
