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
) -> ProactiveDecision:
    cooldown_hours = _styled_cooldown_hours(cadence, closeness, trust, style)
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

    if callbacks_enabled and emotional_callback_ready and trust >= style.callback_trust_floor:
        return ProactiveDecision(True, "emotional_callback", cooldown_hours)

    if inactivity_hours >= max(minimum_inactivity_hours, 28):
        return ProactiveDecision(True, "inactivity_check_in", cooldown_hours)

    if relationship_stage in {"close", "bonded"} and closeness >= style.presence_trust_floor:
        if inactivity_hours >= minimum_inactivity_hours:
            return ProactiveDecision(True, "gentle_presence", cooldown_hours)

    if (
        style.early_stage_presence
        and relationship_stage in {"new", "acquaintance"}
        and max(closeness, trust) >= style.presence_trust_floor
        and inactivity_hours >= max(minimum_inactivity_hours, 18)
    ):
        return ProactiveDecision(True, "gentle_presence", cooldown_hours)

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
            minimum_inactivity_hours=style.minimum_inactivity_hours,
            cooldown_active=cooldown_active and not force,
            relationship_stage=pair.get("current_stage") or "new",
            closeness=float(pair.get("closeness_score") or 0.0),
            trust=float(pair.get("trust_score") or 0.0),
            emotional_callback_ready=emotional_callback_ready,
            callbacks_enabled=bool(int(pair.get("proactive_emotional_callbacks_enabled") or 0)),
            cadence=(pair.get("proactive_cadence") or "balanced"),
            style=style,
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
    companion,
    decision: ProactiveDecision,
    style: ProactiveStyle,
    allow_push: bool,
) -> Optional[dict]:
    pair_id = pair["id"]
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
        f"Your initiation tone: {style.initiation_tone}.\n"
        f"Your natural opening shape: {style.preferred_opening_device}.\n"
        f"Ground the message in this kind of human motive: {style.contextual_anchor_instruction}.\n"
        "Send a natural, low-pressure text that feels like a real person. "
        "Do not mention systems, reminders, inactivity metrics, or that you were told to check in. "
        "Keep it subtle, warm, and believable. "
        "Make it feel like you had an actual reason to text, even if the reason is small. "
        "A remembered detail, an unfinished thought, an opinion, or a passing mood is better than a generic check-in. "
        f"If the reason is silence, follow this: {style.silence_instruction}. "
        f"If the reason is emotional_callback, follow this: {style.emotional_instruction}. "
        f"If the reason is gentle_presence, follow this: {style.gentle_instruction}. "
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
        notification_body = _notification_body_for_style(
            style=style,
            reason=decision.reason,
            burst_plan=burst_plan,
            fallback=reply,
        )
        notification_status = _send_push_hooks(
            user_id=user["id"],
            title=companion.name,
            body=notification_body,
            data={
                "pair_id": pair_id,
                "companion_id": pair["companion_id"],
                "event_id": event_id,
                "reason": decision.reason or "",
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

    minimum_inactivity = int(profile.get("minimum_inactivity_hours") or settings.PROACTIVE_INACTIVITY_HOURS_MIN)
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
    double_text_likelihood = float(profile.get("double_text_likelihood") or _default_double_text_likelihood(rhythm, energy))
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
    return max(12, base + style.cooldown_bias_hours)


def _notification_body_for_style(
    *,
    style: ProactiveStyle,
    reason: Optional[str],
    burst_plan,
    fallback: str,
) -> str:
    templates = style.notification_templates.get(reason or "", [])
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
        if reason == "emotional_callback" or style.double_text_likelihood > 0.55:
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
