import logging
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from auth.firebase import AuthenticatedIdentity, get_authenticated_identity
from memory.store import db
from personality.loader import load_character
from personality.registry import resolve_or_assign_primary_pair, build_opening_line

logger = logging.getLogger(__name__)

router = APIRouter()

class OnboardingCompleteRequest(BaseModel):
    preferred_name: str
    connection_style: str
    presence_frequency: str
    depth_preference: str
    behavioral_guardrail: str

@router.get("/onboarding/status")
async def get_onboarding_status(
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    try:
        user = db.get_user(identity.uid)
        if not user:
            return {"onboarding_completed": False}
        return {"onboarding_completed": bool(user.get("onboarding_completed", 0))}
    except Exception as e:
        logger.exception("Failed to get onboarding status for user %s", identity.uid)
        raise HTTPException(status_code=500, detail=f"Failed to get status: {str(e)}")

@router.post("/onboarding/complete")
async def complete_onboarding(
    payload: OnboardingCompleteRequest,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    try:
        user_id = identity.uid
        logger.info("Completing onboarding for user: %s", user_id)
        
        # 1. Ensure user row exists
        db.get_or_create_user(user_id)
        
        # 2. Save onboarding signals + preferred name
        signals = {
            "connection_style": payload.connection_style,
            "presence_frequency": payload.presence_frequency,
            "depth_preference": payload.depth_preference,
            "behavioral_guardrail": payload.behavioral_guardrail,
        }
        db.save_onboarding_signals(user_id, payload.preferred_name, signals, onboarding_completed=1)
        
        # 3. Resolve companion matching using seeded chemistry
        pair = resolve_or_assign_primary_pair(user_id=user_id, make_primary=True)
        
        # 4. Apply cadence to the new pair
        cadence_map = {
            "every_now_and_then": "light",
            "when_it_matters": "light",
            "fairly_often": "balanced",
            "always_around": "frequent",
        }
        cadence = cadence_map.get(payload.presence_frequency, "balanced")
        db.update_pair_proactive_settings(pair["id"], proactive_cadence=cadence)
        
        # 5. Load character to construct response payload
        character = load_character(pair["companion_id"])
        discovery = character.discovery or {}
        humanizing_details = discovery.get("humanizing_details") or []
        opening_line = build_opening_line(character, session_count=1)
        
        return {
            "companion_id": character.id,
            "companion_name": character.name,
            "companion_summary": character.summary or character.core_identity.get("vibe", ""),
            "humanizing_details": humanizing_details,
            "conversational_vibe": character.archetype or character.core_identity.get("vibe", ""),
            "opening_line": opening_line,
            "pair_id": pair["id"],
        }
    except Exception as e:
        logger.exception("Failed to complete onboarding for user %s", identity.uid)
        raise HTTPException(status_code=500, detail=f"Failed to complete onboarding: {str(e)}")
