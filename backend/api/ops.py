from typing import Optional

from fastapi import APIRouter, Depends, Header, HTTPException, Query

from auth.firebase import AuthenticatedIdentity, get_authenticated_identity
from config import settings
from core.proactive_engine import maybe_generate_for_user
from memory.store import db

router = APIRouter()


def _require_ops_access(x_admin_token: Optional[str] = Header(default=None)) -> None:
    if settings.DEBUG:
        return
    if settings.ADMIN_DEBUG_TOKEN and x_admin_token == settings.ADMIN_DEBUG_TOKEN:
        return
    raise HTTPException(status_code=403, detail="Ops access denied")


@router.get("/ops/summary")
async def get_ops_summary(
    x_admin_token: Optional[str] = Header(default=None),
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    _require_ops_access(x_admin_token)
    return {
        "users": len(db.list_users(limit=100000)),
        "pairs": len(db.conn.execute("SELECT id FROM relationship_pairs").fetchall()),
        "conversations": int(db.conn.execute("SELECT COUNT(*) AS count FROM conversations").fetchone()["count"]),
        "messages": int(db.conn.execute("SELECT COUNT(*) AS count FROM messages").fetchone()["count"]),
        "memories": int(db.conn.execute("SELECT COUNT(*) AS count FROM memory_index WHERE archived = 0").fetchone()["count"]),
        "pending_proactive_events": int(
            db.conn.execute(
                "SELECT COUNT(*) AS count FROM proactive_events WHERE status = 'pending'"
            ).fetchone()["count"]
        ),
    }


@router.get("/ops/debug/users")
async def debug_users(
    limit: int = Query(default=25, ge=1, le=200),
    x_admin_token: Optional[str] = Header(default=None),
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    _require_ops_access(x_admin_token)
    return {"users": db.list_users(limit=limit)}


@router.get("/ops/debug/pair/{pair_id}")
async def debug_pair(
    pair_id: str,
    x_admin_token: Optional[str] = Header(default=None),
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    _require_ops_access(x_admin_token)
    pair = db.get_pair_by_id(pair_id)
    if not pair:
        raise HTTPException(status_code=404, detail="Pair not found")
    return {
        "pair": pair,
        "relationship_state": db.get_relationship_state_snapshot(pair_id),
        "facts": db.get_user_fact_rows(pair["user_id"], pair_id=pair_id, limit=20),
        "conflicts": db.get_fact_conflicts(pair_id, limit=10),
        "memories": db.list_pair_memories(pair_id, limit=20),
        "narrative": db.get_current_narrative(pair["user_id"], pair_id=pair_id),
        "recent_sessions": db.get_recent_conversation_summaries(pair_id, limit=6),
    }


@router.get("/ops/events")
async def ops_events(
    kind: Optional[str] = Query(default=None),
    severity: Optional[str] = Query(default=None),
    limit: int = Query(default=100, ge=1, le=500),
    x_admin_token: Optional[str] = Header(default=None),
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    _require_ops_access(x_admin_token)
    return {"events": db.list_system_events(limit=limit, kind=kind, severity=severity)}


@router.post("/ops/proactive/run")
async def run_proactive_job(
    user_id: Optional[str] = Query(default=None),
    force: bool = Query(default=False),
    limit: int = Query(default=4, ge=1, le=20),
    x_admin_token: Optional[str] = Header(default=None),
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    _require_ops_access(x_admin_token)

    created = []
    if user_id:
        created = await maybe_generate_for_user(user_id, limit=limit, force=force)
    else:
        for user in db.list_users(limit=settings.PROACTIVE_MAX_PER_RUN):
            created.extend(await maybe_generate_for_user(user["id"], limit=1, force=force))
            if len(created) >= limit:
                break

    return {"created": created, "count": len(created)}
