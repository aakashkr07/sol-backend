from typing import Optional

from fastapi import APIRouter, Depends, Query

from auth.firebase import AuthenticatedIdentity, get_authenticated_identity
from core.proactive_engine import pull_pending_events

router = APIRouter()


@router.get("/me/proactive/pending")
async def get_pending_proactive_events(
    pair_id: Optional[str] = Query(default=None),
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    events = await pull_pending_events(identity.uid, pair_id=pair_id)
    return {
        "events": events,
        "count": len(events),
    }
