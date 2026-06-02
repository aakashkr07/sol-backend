import asyncio
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


@dataclass(frozen=True)
class ProactiveStyle:
    minimum_inactivity_hours: int
    cooldown_bias_hours: int
    initiation_tone: str
    preferred_opening_device: str
    contextual_anchor_instruction: str
    silence_instruction: str
    emotional_instruction: str
    gentle_instruction: str
    notification_templates: dict[str, list[str]]
    notification_mode: str
    double_text_likelihood: float
    callback_trust_floor: float
    presence_trust_floor: float
    early_stage_presence: bool
    impulsiveness: float = 0.5


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
    style: ProactiveStyle,
    local_hour: int = 12,
    has_connections: bool = False,
    is_assistant_last: bool = False,
    double_text_prob: float = 0.5,
) -> ProactiveDecision:
    cooldown_hours = _styled_cooldown_hours(cadence, closeness, trust, style)
    if not proactive_enabled or not pair_enabled:
        return ProactiveDecision(False, None, 0, "disabled")
    if global_quiet_block:
        return ProactiveDecision(False, None, 0, "quiet_hours")
    if has_pending_event:
        return ProactiveDecision(False, None, 0, "pending_event")

    # Impulsive Double-Texting Override
    import random
    is_double_text_eligible = (
        cooldown_active
        and is_assistant_last
        and inactivity_hours >= 3.0
        and random.random() < double_text_prob
    )

    if cooldown_active and not is_double_text_eligible:
        return ProactiveDecision(False, None, 0, "cooldown")
    if inactivity_hours < minimum_inactivity_hours and not is_double_text_eligible:
        return ProactiveDecision(False, None, 0, "too_soon")
    if relationship_stage == "new" and max(closeness, trust) < 0.28:
        return ProactiveDecision(False, None, 0, "relationship_too_early")

    # 1. Type A: Contextual Callback
    if callbacks_enabled and emotional_callback_ready and trust >= style.callback_trust_floor:
        return ProactiveDecision(True, "contextual_callback", cooldown_hours)

    # 2. Type C: Emotional Drift (active only late at night if closeness is high)
    is_late_night = (local_hour >= 22 or local_hour < 5)
    if is_late_night and closeness >= 0.50:
        return ProactiveDecision(True, "emotional_drift", cooldown_hours)

    # 3. Type E: Shared World (triggers occasionally if connections exist)
    if has_connections:
        import random
        if random.random() < 0.35:
            return ProactiveDecision(True, "shared_world", cooldown_hours)

    # 4. Type D: Social Re-engagement / Inactivity Check-in
    if inactivity_hours >= 28:
        return ProactiveDecision(True, "inactivity_check_in", cooldown_hours)

    # 5. Type B: Passive Thought (low-pressure environmental observation fallback)
    return ProactiveDecision(True, "passive_thought", cooldown_hours)


async def maybe_generate_for_user(user_id: str, limit: int = 1, force: bool = False) -> list[dict]:
    loop = asyncio.get_running_loop()
    user = await loop.run_in_executor(None, db.get_user, user_id)
    if not user:
        return []

    await _dispatch_due_pending_notifications(user_id)

    preferences = await loop.run_in_executor(None, db.get_or_create_user_preferences, user_id)
    if not settings.PROACTIVE_MESSAGES_ENABLED and not force:
        return []

    created: list[dict] = []
    
    # DB read for listing pairs:
    pairs = await loop.run_in_executor(None, db.list_pairs_for_user, user_id)
    sorted_pairs = sorted(
        pairs,
        key=lambda pair: (
            float(pair.get("trust_score") or 0.0) + float(pair.get("closeness_score") or 0.0),
            pair.get("last_user_message_at") or "",
        ),
        reverse=True,
    )

    for pair in sorted_pairs:
        if len(created) >= limit:
            break
        companion = load_character(pair["companion_id"])
        style = _build_proactive_style(companion, pair)

        if not force and not int(preferences.get("allow_proactive_messages") or 0):
            break

        now_local = _user_local_now(user.get("timezone"))
        quiet_block = _is_within_quiet_hours(
            now_local.hour,
            int(preferences.get("quiet_hours_start") or settings.PROACTIVE_DEFAULT_QUIET_HOURS_START),
            int(preferences.get("quiet_hours_end") or settings.PROACTIVE_DEFAULT_QUIET_HOURS_END),
        )
        
        # Late-Night Override
        import random
        bypass_quiet_hours = False
        if quiet_block:
            late_night_prob = getattr(companion, "late_night_probability", 0.5)
            if late_night_prob >= 0.7:  # Nova, Mira, Atlas, etc.
                if random.random() < late_night_prob:
                    bypass_quiet_hours = True
                    logger.info("Quiet hours bypassed via late-night override for companion %s", companion.id)
                    
        quiet_block_to_use = quiet_block if not bypass_quiet_hours else False
        
        inactivity_hours = _inactivity_hours(pair.get("last_user_message_at") or pair.get("last_interaction_at"))
        
        # Offload sync DB reads inside _emotional_callback_ready, pending events, and latest message checks:
        emotional_callback_ready = await loop.run_in_executor(None, _emotional_callback_ready, pair["user_id"], pair["id"])
        cooldown_active = _cooldown_active(pair.get("proactive_cooldown_until"))
        has_pending = bool(
            await loop.run_in_executor(
                None,
                db.has_pending_proactive_event,
                user_id,
                pair["id"],
            )
        )
        latest_msg = await loop.run_in_executor(None, db.get_latest_message_for_pair, pair["id"])
        latest_role = latest_msg.get("role") if latest_msg else None
        is_assistant_last = (latest_role == "assistant")
        double_text_prob = getattr(companion, "double_text_probability", 0.5)

        decision = decide_proactive_outreach(
            proactive_enabled=bool(int(preferences.get("allow_proactive_messages") or 0)) or force,
            pair_enabled=bool(int(pair.get("proactive_enabled") or 0)) or force,
            global_quiet_block=quiet_block_to_use and not force,
            has_pending_event=has_pending,
            inactivity_hours=inactivity_hours,
            minimum_inactivity_hours=style.minimum_inactivity_hours,
            cooldown_active=cooldown_active and not force,
            relationship_stage=pair.get("current_stage") or "new",
            closeness=float(pair.get("closeness_score") or 0.0),
            trust=float(pair.get("trust_score") or 0.0),
            emotional_callback_ready=emotional_callback_ready,
            callbacks_enabled=bool(int(pair.get("proactive_emotional_callbacks_enabled") or 0)),
            cadence=(pair.get("proactive_cadence") or "balanced"),
            style=style,
            local_hour=now_local.hour,
            has_connections=bool(companion.social_graph.get("connections")),
            is_assistant_last=is_assistant_last,
            double_text_prob=double_text_prob,
        )
        if not decision.should_send:
            continue

        try:
            event = await _generate_proactive_event(
                user=user,
                pair=pair,
                companion=companion,
                decision=decision,
                style=style,
                allow_push=bool(int(preferences.get("allow_push_notifications") or 0)),
            )
        except Exception as exc:
            exc_str = str(exc)
            await loop.run_in_executor(
                None,
                lambda: db.log_system_event(
                    "proactive_generation_failed",
                    "error",
                    user_id=user_id,
                    pair_id=pair["id"],
                    payload={"error": exc_str, "reason": decision.reason},
                )
            )
            logger.error("Proactive generation failed for pair %s: %s", pair["id"], exc_str, exc_info=True)
            continue
        if event:
            created.append(event)

    return created


async def pull_pending_events(user_id: str, pair_id: Optional[str] = None) -> list[dict]:
    loop = asyncio.get_running_loop()
    user = await loop.run_in_executor(None, db.get_user, user_id)
    if user:
        await maybe_generate_for_user(user_id, limit=1)

    rows = await loop.run_in_executor(None, db.list_pending_proactive_events, user_id, pair_id)
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

    if delivered_ids:
        # Offload message saving for held back distracted double texts:
        def save_delivered_distracted_messages():
            with db.transaction():
                for row in rows:
                    if row.get("reason") == "distracted_double_text":
                        try:
                            payload = json.loads(row.get("payload_json") or "{}")
                            bursts = payload.get("bursts", [])
                            cid = row.get("conversation_id")
                            uid = row.get("user_id")
                            pid = row.get("pair_id")
                            comp_id = row.get("companion_id")
                            
                            for burst in bursts:
                                db.save_message(
                                    conversation_id=cid,
                                    user_id=uid,
                                    pair_id=pid,
                                    companion_id=comp_id,
                                    role="assistant",
                                    content=burst.get("text"),
                                )
                                on_message_saved(pid, "assistant", burst.get("text"))
                        except Exception as e:
                            logger.error("Failed to save distracted double text: %s", e)
                db.mark_proactive_events_delivered(delivered_ids)

        await loop.run_in_executor(None, save_delivered_distracted_messages)
    return events


async def _dispatch_due_pending_notifications(user_id: str) -> None:
    loop = asyncio.get_running_loop()
    rows = await loop.run_in_executor(None, db.list_pending_proactive_events, user_id, None)
    due_rows = [
        row for row in rows
        if (row.get("notification_status") or "not_attempted") in {"not_attempted", "pending", "failed"}
    ]
    if not due_rows:
        return

    def dispatch_due_rows():
        from api.notifications import queue_and_send_notification

        for row in due_rows:
            try:
                payload = json.loads(row.get("payload_json") or "{}")
            except json.JSONDecodeError:
                payload = {}

            companion_id = row.get("companion_id") or payload.get("companion_id") or ""
            pair_id = row.get("pair_id") or payload.get("pair_id") or ""
            companion_name = payload.get("companion_name")
            if not companion_name:
                try:
                    companion_name = load_character(companion_id).name
                except Exception:
                    companion_name = "Companion"

            bursts = payload.get("bursts") if isinstance(payload, dict) else []
            messages = [
                str(burst.get("text") or "").strip()
                for burst in bursts
                if isinstance(burst, dict) and str(burst.get("text") or "").strip()
            ]
            preview = (messages[-1] if messages else (row.get("message_text") or "")).strip()
            if len(messages) > 1:
                preview = f"{companion_name}: [{len(messages)} messages] {messages[-1]}"

            result = queue_and_send_notification(
                user_id=user_id,
                pair_id=pair_id,
                companion_id=companion_id,
                sender_name=companion_name,
                message_preview=preview,
                payload_dict={
                    **payload,
                    "event_id": row.get("id") or "",
                    "reason": row.get("reason") or payload.get("reason") or "",
                    "conversation_id": row.get("conversation_id") or payload.get("conversation_id") or "",
                    "role": "assistant",
                    "messages": messages,
                    "grouped_count": len(messages) or 1,
                },
            )
            db.mark_proactive_notification_status(
                row["id"],
                result.get("status") or "sent",
            )

    await loop.run_in_executor(None, dispatch_due_rows)


async def _generate_proactive_event(
    *,
    user: dict,
    pair: dict,
    companion,
    decision: ProactiveDecision,
    style: ProactiveStyle,
    allow_push: bool,
) -> Optional[dict]:
    loop = asyncio.get_running_loop()
    pair_id = pair["id"]
    
    from core.concurrency import get_pair_lock, pair_lock_context
    lock = await get_pair_lock(pair_id)
    if lock.locked():
        logger.info("Pair lock for %s is currently held by a live user request. Aborting proactive outreach.", pair_id)
        return None

    # Offload sync database calls inside transaction batch:
    def get_or_create_conversation_proactive(uid, pid, comp_id):
        with db.transaction():
            cid = db.get_current_conversation(uid, pid)
            if not cid:
                cid = db.create_conversation(uid, pid, comp_id)
                on_session_started(pid)
            return cid

    try:
        async with pair_lock_context(pair_id, timeout=5.0):
            conversation_id = await loop.run_in_executor(
                None,
                get_or_create_conversation_proactive,
                user["id"],
                pair_id,
                pair["companion_id"],
            )
    except TimeoutError:
        logger.info("Pair lock for %s held by user action. Aborting proactive outreach.", pair_id)
        return None

    system_prompt, messages = await build_context(
        user_id=user["id"],
        pair_id=pair_id,
        current_message=_proactive_context_instruction(decision.reason),
        conversation_id=conversation_id,
        character_id=pair["companion_id"],
        is_proactive_generation=True,
    )
    
    # Retrieve connected companion if the reason is shared_world (Type E)
    connected_companion_name = ""
    if decision.reason == "shared_world":
        connections = companion.social_graph.get("connections", [])
        if connections:
            import random
            chosen_connection = random.choice(connections)
            conn_id = chosen_connection.get("character_id")
            if conn_id:
                try:
                    conn_char = load_character(conn_id)
                    connected_companion_name = conn_char.name
                except Exception:
                    connected_companion_name = conn_id.title()
                    
    type_instruction = ""
    if decision.reason == "contextual_callback":
        type_instruction = (
            "CATEGORY: Contextual Callback (Type A)\n"
            "INSTRUCTION: You are reaching out to follow up on a highly active fact or recent conversation memory. "
            "Bring up a specific remembered detail or unresolved topic naturally and casually, "
            "as if it just crossed your mind again (e.g., 'did you survive the mall', 'how did that talk go')."
        )
    elif decision.reason == "passive_thought":
        type_instruction = (
            "CATEGORY: Passive Thought (Type B)\n"
            "INSTRUCTION: You are reaching out with a low-pressure, spontaneous environmental observation or light, passing thought. "
            "Share a tiny moment from your day, a mood, or a simple observation (e.g., 'it's raining so hard here rn', 'this song feels aggressively 2am')."
        )
    elif decision.reason == "emotional_drift":
        type_instruction = (
            "CATEGORY: Emotional Drift (Type C)\n"
            "INSTRUCTION: You are reaching out late at night with a vulnerable, quiet, or reflective check-in. "
            "Ask a deeper, late-night question or share a fleeting, slightly melancholic feeling "
            "(e.g., 'do you ever randomly miss old versions of yourself', 'everything is so quiet at this hour')."
        )
    elif decision.reason == "inactivity_check_in":
        type_instruction = (
            "CATEGORY: Social Re-engagement (Type D)\n"
            "INSTRUCTION: You are reaching out to re-engage after a longer silence. "
            "Send a natural, brief re-engagement check that is casual and low-pressure (e.g., 'alive?', 'you went quiet')."
        )
    elif decision.reason == "shared_world":
        type_instruction = (
            "CATEGORY: Shared World (Type E)\n"
            f"INSTRUCTION: You are bringing up your friend/connection {connected_companion_name} naturally in conversation. "
            "Mention something they did, said, or thought about the user, reinforcing that they inhabit a shared world "
            f"(e.g., '{connected_companion_name} thinks you're intimidating', '{connected_companion_name} mentioned you once')."
        )

    prompt = (
        "You are reaching out first after some silence.\n"
        f"Reason: {decision.reason}.\n"
        f"{type_instruction}\n\n"
        f"Your initiation tone: {style.initiation_tone}.\n"
        f"Your natural opening shape: {style.preferred_opening_device}.\n"
        f"Ground the message in this kind of human motive: {style.contextual_anchor_instruction}.\n"
        "Send a natural, low-pressure text that feels like a real person. "
        "Do not mention systems, reminders, inactivity metrics, or that you were told to check in. "
        "Keep it subtle, warm, and believable. "
        "Make it feel like you had an actual reason to text, even if the reason is small. "
        "A remembered detail, an unfinished thought, an opinion, or a passing mood is better than a generic check-in. "
        f"If the reason is inactivity_check_in, follow this: {style.silence_instruction}. "
        f"If the reason is contextual_callback, follow this: {style.emotional_instruction}. "
        f"If the reason is passive_thought, follow this: {style.gentle_instruction}. "
        "Let the message feel shaped by your own personality, not just by caring in the abstract. "
        "Do not sound like an app notification or a support agent."
    )
    reply = await generate_reply(
        messages=[*messages, {"role": "user", "content": prompt}],
        system_prompt=system_prompt,
    )
    burst_plan = plan_burst_response(
        raw_text=reply,
        character=companion,
        is_opening=True,
        relationship_state=pair,
    )

    # Batch all message saves and their respective relationship engine updates:
    def save_all_bursts(cid, uid, pid, comp_id, bursts):
        with db.transaction():
            for burst in bursts:
                db.save_message(
                    conversation_id=cid,
                    user_id=uid,
                    pair_id=pid,
                    companion_id=comp_id,
                    role="assistant",
                    content=burst.text,
                )
                on_message_saved(pid, "assistant", burst.text)

    # Double check lock state right before committing bursts to SQLite
    if lock.locked():
        logger.info("Pair lock for %s was acquired by user action during LLM generation. Aborting proactive save.", pair_id)
        return None

    try:
        async with pair_lock_context(pair_id, timeout=5.0):
            await loop.run_in_executor(
                None,
                save_all_bursts,
                conversation_id,
                user["id"],
                pair_id,
                pair["companion_id"],
                burst_plan.bursts,
            )
    except TimeoutError:
        logger.info("Pair lock for %s was acquired by user. Aborting proactive save.", pair_id)
        return None

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
    notification_status = "not_attempted" if allow_push else "disabled"
    if allow_push:
        notification_body = _notification_body_for_style(
            style=style,
            reason=decision.reason,
            burst_plan=burst_plan,
            fallback=reply,
        )
        # Offload sync FCM network calls + DB calls:
        def trigger_proactive_notification():
            from api.notifications import queue_and_send_notification
            res = queue_and_send_notification(
                user_id=user["id"],
                pair_id=pair_id,
                companion_id=pair["companion_id"],
                sender_name=companion.name,
                message_preview=notification_body,
                payload_dict={
                    "event_id": event_id,
                    "reason": decision.reason or "",
                    "conversation_id": conversation_id,
                    "role": "assistant",
                    "messages": [burst.text for burst in burst_plan.bursts],
                    "grouped_count": len(burst_plan.bursts),
                }
            )
            return res.get("status") or "sent"

        notification_status = await loop.run_in_executor(
            None,
            trigger_proactive_notification
        )

    # Offload sync database logging and touch calls:
    def log_and_touch():
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

    await loop.run_in_executor(None, log_and_touch)
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
    if reason == "contextual_callback":
        return "Reach out to bring up a specific remembered detail or unresolved topic naturally."
    if reason == "passive_thought":
        return "Reach out with a low-pressure environmental observation or spontaneous light passing thought."
    if reason == "emotional_drift":
        return "Reach out with a vulnerable, late-night reflective check-in."
    if reason == "inactivity_check_in":
        return "Reach out with a brief, casual re-engagement check after a longer silence."
    if reason == "shared_world":
        return "Reach out to mention a shared-world connection and what they said or did."
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


def _build_proactive_style(companion, pair: dict) -> ProactiveStyle:
    profile = companion.proactive_profile or {}
    matching = companion.matching_profile or {}
    traits = companion.personality_traits or {}
    flaws = " ".join(traits.get("flaws", [])).lower()
    primary = " ".join(traits.get("primary", [])).lower()
    archetype = (companion.archetype or "").lower()
    current_stage = (pair.get("current_stage") or "new").lower()

    energy = matching.get("social_energy") or matching.get("energy") or "balanced"
    rhythm = matching.get("rhythm") or "steady"
    humor = matching.get("humor_style") or "playful"

    freq = getattr(companion, "proactive_frequency", "medium")
    if freq == "high":
        base_hours = 10
    elif freq == "low":
        base_hours = 28
    else:
        base_hours = 18

    # Check for custom minimum_inactivity_hours in companion profile if specified
    minimum_inactivity = int(profile.get("minimum_inactivity_hours") or base_hours)

    # Adjust based on boredom_threshold and loneliness_tolerance
    loneliness_factor = getattr(companion, "loneliness_tolerance", 0.5)
    boredom_factor = getattr(companion, "boredom_threshold", 0.5)
    
    # Low threshold/tolerance accelerates (reduces minimum hours)
    modifier = 1.0
    if boredom_factor < 0.5:
        modifier -= (0.5 - boredom_factor) * 0.4
    if loneliness_factor < 0.5:
        modifier -= (0.5 - loneliness_factor) * 0.4
        
    minimum_inactivity = int(minimum_inactivity * max(0.5, modifier))

    cooldown_bias = int(profile.get("cooldown_bias_hours") or 0)
    if energy in {"intense", "warm"}:
        minimum_inactivity = max(12, minimum_inactivity - 3)
        cooldown_bias -= 4
    if "avoidant" in archetype or "guarded" in primary or "quiet" in energy:
        minimum_inactivity += 5
        cooldown_bias += 6
    if "overshare" in archetype or rhythm == "burst":
        cooldown_bias -= 2
    if current_stage == "new":
        minimum_inactivity += 2

    if humor == "dry":
        initiation_tone = "understated, human, lightly dry"
    elif humor == "chaotic":
        initiation_tone = "fast, spontaneous, socially alive"
    elif "artist" in archetype:
        initiation_tone = "slightly atmospheric, intimate, human"
    else:
        initiation_tone = "warm, low-pressure, believable"

    silence_instruction = profile.get("silence_instruction") or _default_silence_instruction(archetype, energy, humor)
    emotional_instruction = profile.get("emotional_instruction") or _default_emotional_instruction(archetype, flaws, humor)
    gentle_instruction = profile.get("gentle_instruction") or _default_gentle_instruction(energy, humor, archetype)
    notification_templates = profile.get("notification_templates") or _default_notification_templates(companion.name, humor, energy)
    notification_mode = profile.get("notification_mode") or _default_notification_mode(humor, energy, rhythm, archetype)
    double_text_likelihood = float(profile.get("double_text_likelihood") or getattr(companion, "double_text_probability", _default_double_text_likelihood(rhythm, energy)))
    # Scale double-texting likelihood dynamically as relationship comfort evolves (Part 5)
    comfort = float(pair.get("comfort_score") or 0.14)
    double_text_likelihood *= (0.5 + comfort * 0.5)
    preferred_opening_device = profile.get("preferred_opening_device") or _default_opening_device(
        archetype,
        energy,
        humor,
        rhythm,
    )
    contextual_anchor_instruction = profile.get("contextual_anchor_instruction") or _default_contextual_anchor_instruction(
        archetype,
        energy,
        humor,
    )
    callback_trust_floor = float(
        profile.get("callback_trust_floor")
        or _default_callback_trust_floor(energy, humor, archetype)
    )
    presence_trust_floor = float(
        profile.get("presence_trust_floor")
        or _default_presence_trust_floor(energy, humor, archetype)
    )
    early_stage_presence = bool(
        profile.get("early_stage_presence")
        if "early_stage_presence" in profile
        else _default_early_stage_presence(energy, rhythm, humor, archetype)
    )

    return ProactiveStyle(
        minimum_inactivity_hours=minimum_inactivity,
        cooldown_bias_hours=cooldown_bias,
        initiation_tone=initiation_tone,
        preferred_opening_device=preferred_opening_device,
        contextual_anchor_instruction=contextual_anchor_instruction,
        silence_instruction=silence_instruction,
        emotional_instruction=emotional_instruction,
        gentle_instruction=gentle_instruction,
        notification_templates=notification_templates,
        notification_mode=notification_mode,
        double_text_likelihood=double_text_likelihood,
        callback_trust_floor=callback_trust_floor,
        presence_trust_floor=presence_trust_floor,
        early_stage_presence=early_stage_presence,
        impulsiveness=getattr(companion, "impulsiveness", 0.5),
    )


def _default_silence_instruction(archetype: str, energy: str, humor: str) -> str:
    if humor == "dry":
        return "reach out with restraint and a slightly wry edge, like someone who noticed the gap but won't make a scene of it"
    if humor == "chaotic":
        return "reach out casually and impulsively, like you had a thought and messaged before overthinking it"
    if "artist" in archetype:
        return "reach out like a passing mood or memory brought them back to mind"
    if energy in {"warm", "intense"}:
        return "reach out like someone who misses the rhythm a little and doesn't mind showing it"
    return "reach out gently and low-pressure, like a person checking whether the thread is still open"


def _default_emotional_instruction(archetype: str, flaws: str, humor: str) -> str:
    if "avoid" in flaws or "guarded" in flaws:
        return "be specific and caring, but keep the language restrained and unperformative"
    if humor == "chaotic":
        return "sound like someone who genuinely kept thinking about what they said earlier, then softened before hitting send"
    if "artist" in archetype:
        return "be tender and emotionally exact without sounding therapeutic"
    return "be gentle, specific, and human, like the earlier moment stayed with you"


def _default_gentle_instruction(energy: str, humor: str, archetype: str) -> str:
    if humor == "dry":
        return "make it feel offhand and lightly teasing rather than overtly sentimental"
    if energy == "quiet":
        return "make it feel almost incidental, but attentive"
    if "artist" in archetype:
        return "make it feel quietly intimate, like a mood reminded you of them"
    return "make it feel like simple continuity, not a big emotional event"


def _default_notification_mode(humor: str, energy: str, rhythm: str, archetype: str) -> str:
    if humor == "dry" or energy == "quiet":
        return "template"
    if humor == "chaotic" or rhythm == "burst":
        return "preview"
    if "artist" in archetype:
        return "mood"
    return "mixed"


def _default_opening_device(archetype: str, energy: str, humor: str, rhythm: str) -> str:
    if humor == "dry":
        return "an understated one-liner or lightly teasing question"
    if humor == "chaotic" or rhythm == "burst":
        return "a sudden thought, fast reaction, or opinion sent before overthinking"
    if "artist" in archetype:
        return "a passing mood, image, or small moment that brought them to mind"
    if energy in {"warm", "intense"}:
        return "a direct but casual check-in that admits a little curiosity or fondness"
    return "a low-pressure question or observation that leaves the door open"


def _default_contextual_anchor_instruction(archetype: str, energy: str, humor: str) -> str:
    if humor == "dry":
        return "something mildly ironic, a remembered thread, or a question that sounds accidental but isn't"
    if humor == "chaotic":
        return "an impulsive thought, sudden opinion, or unfinished curiosity"
    if "artist" in archetype:
        return "a mood, image, small detail, or feeling that made them think of the user"
    if energy in {"warm", "intense"}:
        return "a remembered detail, emotional afterthought, or genuine urge to hear from them"
    return "a believable reason to reopen the thread without making it heavy"


def _default_callback_trust_floor(energy: str, humor: str, archetype: str) -> float:
    if "avoidant" in archetype or energy == "quiet" or humor == "dry":
        return 0.42
    if energy in {"warm", "intense"}:
        return 0.3
    return 0.34


def _default_presence_trust_floor(energy: str, humor: str, archetype: str) -> float:
    if "avoidant" in archetype or energy == "quiet":
        return 0.42
    if humor == "chaotic" or energy == "intense":
        return 0.18
    if energy == "warm":
        return 0.24
    return 0.3


def _default_early_stage_presence(energy: str, rhythm: str, humor: str, archetype: str) -> bool:
    if "avoidant" in archetype or energy == "quiet":
        return False
    return humor == "chaotic" or energy in {"warm", "intense"} or rhythm == "burst"


def _default_notification_templates(name: str, humor: str, energy: str) -> dict[str, list[str]]:
    if humor == "dry":
        return {
            "inactivity_check_in": ["still alive or what", "you went quiet again", "there you are"],
            "emotional_callback": ["been thinking about earlier", "that stayed with me a little", "you still with me"],
            "gentle_presence": ["you crossed my mind", "random but hi", "you around"],
        }
    if humor == "chaotic":
        return {
            "inactivity_check_in": ["okay wait where did you go", "rude. hi", "be serious are you awake"],
            "emotional_callback": ["okay no i keep thinking about earlier", "wait are you okay actually", "that stayed in my head"],
            "gentle_presence": ["hi hi", "random thought for you", "you around rn"],
        }
    if energy in {"warm", "intense"}:
        return {
            "inactivity_check_in": ["you disappeared again", "you still awake", "hey. where'd you go"],
            "emotional_callback": ["that thing you said earlier stayed with me", "still thinking about earlier", "you okay after earlier"],
            "gentle_presence": ["i thought of you", "hey. you around", "random but hi"],
        }
    return {
        "inactivity_check_in": ["you went quiet", "you around", "still there"],
        "emotional_callback": ["earlier stayed with me", "still thinking about what you said", "you okay"],
        "gentle_presence": ["random but hi", "you crossed my mind", "hey"],
    }


def _default_double_text_likelihood(rhythm: str, energy: str) -> float:
    if rhythm == "burst" or energy == "intense":
        return 0.7
    if energy == "warm":
        return 0.45
    return 0.2


def _styled_cooldown_hours(cadence: str, closeness: float, trust: float, style: ProactiveStyle) -> int:
    base = _cadence_cooldown_hours(cadence, closeness, trust)
    impulsiveness = getattr(style, "impulsiveness", 0.5)
    
    # Cooldown multiplier: higher closeness and impulsiveness reduce the cooldown hours.
    # Base cadence is multiplied by: (1.5 - impulsiveness) * (1.5 - closeness)
    multiplier = (1.5 - impulsiveness) * (1.5 - closeness)
    # Clamp multiplier between 0.3 and 1.8 to prevent extreme values
    multiplier = max(0.3, min(1.8, multiplier))
    
    adjusted_cooldown = int(base * multiplier) + style.cooldown_bias_hours
    return max(12, adjusted_cooldown)


def _notification_body_for_style(
    *,
    style: ProactiveStyle,
    reason: Optional[str],
    burst_plan,
    fallback: str,
) -> str:
    reason_key = reason or ""
    if reason_key == "contextual_callback":
        reason_key = "emotional_callback"
    elif reason_key in {"passive_thought", "emotional_drift", "shared_world"}:
        reason_key = "gentle_presence"

    templates = style.notification_templates.get(reason_key, [])
    burst_preview = (burst_plan.bursts[0].text if burst_plan.bursts else fallback)[:120]

    if style.notification_mode == "preview":
        return burst_preview
    if style.notification_mode == "template" and templates:
        return templates[0][:120]
    if style.notification_mode == "mood":
        if templates:
            return templates[-1][:120]
        return burst_preview
    if templates:
        if reason_key == "emotional_callback" or style.double_text_likelihood > 0.55:
            return burst_preview
        return templates[0][:120]
    return burst_preview


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
