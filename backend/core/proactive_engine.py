import json
import logging
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Optional
from zoneinfo import ZoneInfo

from firebase_admin import messaging as firebase_messaging

from config import settings
from core.burst_engine import plan_burst_response
from core.context_builder import build_context
from core.llm import generate_reply
from memory.relationship_engine import on_message_saved, on_session_started
from memory.store import db
from personality.loader import load_character

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class ProactiveDecision:
    should_send: bool
    reason: Optional[str]
    cooldown_hours: int
    blocked_by: Optional[str] = None


def decide_proactive_outreach(
    *,
    proactive_enabled: bool,
    pair_enabled: bool,
    global_quiet_block: bool,
    has_pending_event: bool,
    inactivity_hours: float,
    minimum_inactivity_hours: int,
    cooldown_active: bool,
    relationship_stage: str,
    closeness: float,
    trust: float,
    emotional_callback_ready: bool,
    callbacks_enabled: bool,
    cadence: str,
) -> ProactiveDecision:
    if not proactive_enabled or not pair_enabled:
        return ProactiveDecision(False, None, 0, "disabled")
    if global_quiet_block:
        return ProactiveDecision(False, None, 0, "quiet_hours")
    if has_pending_event:
        return ProactiveDecision(False, None, 0, "pending_event")
    if cooldown_active:
        return ProactiveDecision(False, None, 0, "cooldown")
    if inactivity_hours < minimum_inactivity_hours:
        return ProactiveDecision(False, None, 0, "too_soon")
    if relationship_stage == "new" and max(closeness, trust) < 0.28:
        return ProactiveDecision(False, None, 0, "relationship_too_early")

    if callbacks_enabled and emotional_callback_ready and trust >= 0.34:
        return ProactiveDecision(True, "emotional_callback", _cadence_cooldown_hours(cadence, closeness, trust))

    if inactivity_hours >= max(minimum_inactivity_hours, 28):
        return ProactiveDecision(True, "inactivity_check_in", _cadence_cooldown_hours(cadence, closeness, trust))

    if relationship_stage in {"close", "bonded"} and inactivity_hours >= minimum_inactivity_hours:
        return ProactiveDecision(True, "gentle_presence", _cadence_cooldown_hours(cadence, closeness, trust))

    return ProactiveDecision(False, None, 0, "no_trigger")


async def maybe_generate_for_user(user_id: str, limit: int = 1, force: bool = False) -> list[dict]:
    user = db.get_user(user_id)
    if not user:
        return []

    preferences = db.get_or_create_user_preferences(user_id)
    if not settings.PROACTIVE_MESSAGES_ENABLED and not force:
        return []

    created: list[dict] = []
    for pair in _sorted_pairs_for_outreach(user_id):
        if len(created) >= limit:
            break

        if not force and not int(preferences.get("allow_proactive_messages") or 0):
            break

        now_local = _user_local_now(user.get("timezone"))
        quiet_block = _is_within_quiet_hours(
            now_local.hour,
            int(preferences.get("quiet_hours_start") or settings.PROACTIVE_DEFAULT_QUIET_HOURS_START),
            int(preferences.get("quiet_hours_end") or settings.PROACTIVE_DEFAULT_QUIET_HOURS_END),
        )
        inactivity_hours = _inactivity_hours(pair.get("last_user_message_at") or pair.get("last_interaction_at"))
        emotional_callback_ready = _emotional_callback_ready(pair["user_id"], pair["id"])
        cooldown_active = _cooldown_active(pair.get("proactive_cooldown_until"))
        has_pending = bool(db.list_pending_proactive_events(user_id, pair_id=pair["id"]))

        decision = decide_proactive_outreach(
            proactive_enabled=bool(int(preferences.get("allow_proactive_messages") or 0)) or force,
            pair_enabled=bool(int(pair.get("proactive_enabled") or 0)) or force,
            global_quiet_block=quiet_block and not force,
            has_pending_event=has_pending,
            inactivity_hours=inactivity_hours,
            minimum_inactivity_hours=settings.PROACTIVE_INACTIVITY_HOURS_MIN,
            cooldown_active=cooldown_active and not force,
            relationship_stage=pair.get("current_stage") or "new",
            closeness=float(pair.get("closeness_score") or 0.0),
            trust=float(pair.get("trust_score") or 0.0),
            emotional_callback_ready=emotional_callback_ready,
            callbacks_enabled=bool(int(pair.get("proactive_emotional_callbacks_enabled") or 0)),
            cadence=(pair.get("proactive_cadence") or "balanced"),
        )
        if not decision.should_send:
            continue

        try:
            event = await _generate_proactive_event(
                user=user,
                pair=pair,
                decision=decision,
                allow_push=bool(int(preferences.get("allow_push_notifications") or 0)),
            )
        except Exception as exc:
            db.log_system_event(
                "proactive_generation_failed",
                "error",
                user_id=user_id,
                pair_id=pair["id"],
                payload={"error": str(exc), "reason": decision.reason},
            )
            logger.error("Proactive generation failed for pair %s: %s", pair["id"], exc, exc_info=True)
            continue
        if event:
            created.append(event)

    return created


async def pull_pending_events(user_id: str, pair_id: Optional[str] = None) -> list[dict]:
    user = db.get_user(user_id)
    if user:
        await maybe_generate_for_user(user_id, limit=1)

    rows = db.list_pending_proactive_events(user_id, pair_id=pair_id)
    events = []
    delivered_ids = []
    for row in rows:
        try:
            payload = json.loads(row.get("payload_json") or "{}")
        except json.JSONDecodeError:
            payload = {}
        row["payload"] = payload
        events.append(row)
        delivered_ids.append(row["id"])

    db.mark_proactive_events_delivered(delivered_ids)
    return events


async def _generate_proactive_event(
    *,
    user: dict,
    pair: dict,
    decision: ProactiveDecision,
    allow_push: bool,
) -> Optional[dict]:
    pair_id = pair["id"]
    companion = load_character(pair["companion_id"])
    conversation_id = db.get_current_conversation(user["id"], pair_id=pair_id)
    if not conversation_id:
        conversation_id = db.create_conversation(user["id"], pair_id, pair["companion_id"])
        on_session_started(pair_id)

    system_prompt, messages = await build_context(
        user_id=user["id"],
        pair_id=pair_id,
        current_message=_proactive_context_instruction(decision.reason),
        conversation_id=conversation_id,
        character_id=pair["companion_id"],
    )
    prompt = (
        "You are reaching out first after some silence.\n"
        f"Reason: {decision.reason}.\n"
        "Send a natural, low-pressure text that feels like a real person. "
        "Do not mention systems, reminders, inactivity metrics, or that you were told to check in. "
        "Keep it subtle, warm, and believable. If the emotional context is heavy, be gentle and specific without sounding clinical."
    )
    reply = await generate_reply(
        messages=[*messages, {"role": "user", "content": prompt}],
        system_prompt=system_prompt,
    )
    burst_plan = plan_burst_response(raw_text=reply, character=companion, is_opening=True)

    for burst in burst_plan.bursts:
        db.save_message(
            conversation_id=conversation_id,
            user_id=user["id"],
            pair_id=pair_id,
            companion_id=pair["companion_id"],
            role="assistant",
            content=burst.text,
        )
        on_message_saved(pair_id, "assistant", burst.text)

    event_id = str(uuid.uuid4())
    cooldown_until = (datetime.utcnow() + timedelta(hours=decision.cooldown_hours)).isoformat(timespec="milliseconds")
    payload = {
        "bursts": [
            {
                "text": burst.text,
                "pre_burst_delay_ms": burst.pre_burst_delay_ms,
                "typing_duration_ms": burst.typing_duration_ms,
                "pause_intensity": burst.pause_intensity,
                "is_follow_up": burst.is_follow_up,
            }
            for burst in burst_plan.bursts
        ],
        "companion_name": companion.name,
        "conversation_id": conversation_id,
        "pair_id": pair_id,
        "reason": decision.reason,
    }
    notification_status = "skipped"
    if allow_push:
        notification_status = _send_push_hooks(
            user_id=user["id"],
            title=companion.name,
            body=burst_plan.bursts[0].text if burst_plan.bursts else reply,
            data={
                "pair_id": pair_id,
                "companion_id": pair["companion_id"],
                "event_id": event_id,
            },
        )

    db.log_proactive_event(
        event_id=event_id,
        user_id=user["id"],
        pair_id=pair_id,
        companion_id=pair["companion_id"],
        conversation_id=conversation_id,
        reason=decision.reason,
        message_text=burst_plan.combined_text,
        payload_json=json.dumps(payload),
        notification_status=notification_status,
    )
    db.touch_pair_proactive(pair_id, decision.reason, cooldown_until=cooldown_until)
    return {
        "id": event_id,
        "pair_id": pair_id,
        "conversation_id": conversation_id,
        "reason": decision.reason,
        "payload": payload,
    }


def _send_push_hooks(user_id: str, title: str, body: str, data: dict[str, str]) -> str:
    tokens = db.list_device_tokens(user_id, enabled_only=True)
    if not tokens:
        return "no_tokens"

    outcome = "sent"
    for token in tokens:
        try:
            firebase_messaging.send(
                firebase_messaging.Message(
                    token=token["push_token"],
                    notification=firebase_messaging.Notification(title=title, body=body[:120]),
                    data={key: str(value) for key, value in data.items()},
                )
            )
        except Exception as exc:
            outcome = "failed"
            db.log_system_event(
                "push_notification_failed",
                "warning",
                user_id=user_id,
                payload={"error": str(exc), "token_id": token.get("id")},
            )
            logger.warning("Push notification failed for %s: %s", user_id, exc)
    return outcome


def _sorted_pairs_for_outreach(user_id: str) -> list[dict]:
    pairs = db.list_pairs_for_user(user_id)
    return sorted(
        pairs,
        key=lambda pair: (
            float(pair.get("trust_score") or 0.0) + float(pair.get("closeness_score") or 0.0),
            pair.get("last_user_message_at") or "",
        ),
        reverse=True,
    )


def _proactive_context_instruction(reason: Optional[str]) -> str:
    if reason == "emotional_callback":
        return "Reach out because something emotionally unresolved may still be sitting with them."
    if reason == "gentle_presence":
        return "Reach out with light continuity, like someone who knows them and thought of them."
    return "Reach out with a believable low-pressure check-in after some silence."


def _user_local_now(timezone_name: Optional[str]) -> datetime:
    if timezone_name:
        try:
            return datetime.now(ZoneInfo(timezone_name))
        except Exception:
            pass
    return datetime.utcnow()


def _is_within_quiet_hours(hour: int, start_hour: int, end_hour: int) -> bool:
    if start_hour == end_hour:
        return False
    if start_hour < end_hour:
        return start_hour <= hour < end_hour
    return hour >= start_hour or hour < end_hour


def _inactivity_hours(anchor: Optional[str]) -> float:
    if not anchor:
        return 999.0
    try:
        then = datetime.fromisoformat(anchor)
    except ValueError:
        return 999.0
    return max(0.0, (datetime.utcnow() - then).total_seconds() / 3600.0)


def _cooldown_active(value: Optional[str]) -> bool:
    if not value:
        return False
    try:
        return datetime.utcnow() < datetime.fromisoformat(value)
    except ValueError:
        return False


def _cadence_cooldown_hours(cadence: str, closeness: float, trust: float) -> int:
    cadence = (cadence or "balanced").lower()
    if cadence == "gentle":
        base = 72
    elif cadence == "frequent":
        base = 24
    else:
        base = 42
    if closeness + trust > 1.3:
        base = max(18, base - 8)
    return base


def _emotional_callback_ready(user_id: str, pair_id: str) -> bool:
    emotions = db.get_recent_emotional_events(user_id, pair_id=pair_id, limit=4)
    if any(
        float(item.get("intensity") or 0.0) >= 0.64 and float(item.get("valence") or 0.0) <= -0.28
        for item in emotions
    ):
        return True

    narrative = db.get_current_narrative(user_id, pair_id=pair_id) or {}
    summary = (narrative.get("summary") or "").lower()
    return any(token in summary for token in ["unresolved", "strain", "distance", "grief", "heavy"])
