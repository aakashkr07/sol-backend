import logging
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from auth.firebase import AuthenticatedIdentity, get_authenticated_identity
from memory.store import db
from personality.registry import rank_companions_for_user, build_opening_line
from core.burst_engine import plan_burst_response
from memory.relationship_engine import on_message_saved, on_session_started

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
    user_id = identity.uid
    logger.info("Completing onboarding for user: %s", user_id)
    try:
        with db.transaction():
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
            
            # 3. Rank companions using seeded chemistry
            ranked = rank_companions_for_user(user_id)
            if not ranked:
                raise ValueError("No companions ranked for user.")
            
            companion_1 = ranked[0]
            
            # Companion 1 (Top Match): Set as the primary pair
            pair_1 = db.get_or_create_relationship_pair(
                user_id=user_id,
                companion_id=companion_1.id,
                assignment_source="matcher",
                assignment_reason=f"matched from onboarding signals ({companion_1.id})",
            )
            db.set_primary_pair(pair_1["id"])
            
            # Companion 2 & Companion 3 (Ranks 2 and 3): Initialize pairs under assignment_source="matcher"
            pairs_to_update = [pair_1]
            
            if len(ranked) > 1:
                companion_2 = ranked[1]
                pair_2 = db.get_or_create_relationship_pair(
                    user_id=user_id,
                    companion_id=companion_2.id,
                    assignment_source="matcher",
                    assignment_reason=f"matched from onboarding signals ({companion_2.id})",
                )
                pairs_to_update.append(pair_2)
                
            if len(ranked) > 2:
                companion_3 = ranked[2]
                pair_3 = db.get_or_create_relationship_pair(
                    user_id=user_id,
                    companion_id=companion_3.id,
                    assignment_source="matcher",
                    assignment_reason=f"matched from onboarding signals ({companion_3.id})",
                )
                pairs_to_update.append(pair_3)
            
            # 4. Set the proactive cadence for all three pairs in relationship_pairs
            cadence_map = {
                "every_now_and_then": "gentle",
                "when_it_matters": "gentle",
                "fairly_often": "balanced",
                "always_around": "frequent",
            }
            cadence = cadence_map.get(payload.presence_frequency, "balanced")
            for p in pairs_to_update:
                db.update_pair_proactive_settings(p["id"], proactive_cadence=cadence)
            
            # 5. Create active conversation, generate opener and save burst response
            conversation_id = db.create_conversation(
                user_id=user_id,
                pair_id=pair_1["id"],
                companion_id=companion_1.id,
            )
            on_session_started(pair_1["id"])
            
            # Reload updated pair_1 to pass to plan_burst_response
            pair_1_updated = db.get_pair_by_id(pair_1["id"]) or pair_1
            
            discovery = companion_1.discovery or {}
            humanizing_details = discovery.get("humanizing_details") or []
            
            opening_line = build_opening_line(companion_1, session_count=1)
            opening_plan = plan_burst_response(
                raw_text=opening_line,
                character=companion_1,
                is_opening=True,
                relationship_state=pair_1_updated,
            )
            for burst in opening_plan.bursts:
                db.save_message(
                    conversation_id=conversation_id,
                    user_id=user_id,
                    pair_id=pair_1["id"],
                    companion_id=companion_1.id,
                    role="assistant",
                    content=burst.text,
                )
                on_message_saved(pair_1["id"], "assistant", burst.text)
            
        return {
            "status": "success",
            "success": True,
            "companion_id": companion_1.id,
            "companion_name": companion_1.name,
            "companion_summary": companion_1.summary or companion_1.core_identity.get("vibe", ""),
            "humanizing_details": humanizing_details,
            "conversational_vibe": companion_1.archetype or companion_1.core_identity.get("vibe", ""),
            "opening_line": opening_plan.combined_text,
            "pair_id": pair_1["id"],
        }
    except Exception as e:
        logger.exception("Failed to complete onboarding for user %s", user_id)
        try:
            db.log_system_event(
                "onboarding_rollback",
                "error",
                user_id=user_id,
                payload={
                    "error": str(e),
                    "action": "rollback",
                    "preferred_name": payload.preferred_name,
                    "connection_style": payload.connection_style,
                }
            )
        except Exception as log_err:
            logger.error("Failed to log onboarding rollback to system_events: %s", log_err)
        raise HTTPException(status_code=500, detail=f"Failed to complete onboarding: {str(e)}")
