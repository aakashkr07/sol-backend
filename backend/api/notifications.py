from datetime import datetime, timedelta
import json
import logging
import uuid
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException

from auth.firebase import AuthenticatedIdentity, get_authenticated_identity
from memory.store import db

logger = logging.getLogger(__name__)

router = APIRouter()

# In-memory registry of active user presence
# key: user_id -> datetime
_ACTIVE_SESSIONS = {}


def update_user_presence(user_id: str):
    _ACTIVE_SESSIONS[user_id] = datetime.utcnow()
    logger.debug("Updated active presence for user %s", user_id)


def is_user_active(user_id: str) -> bool:
    last_seen = _ACTIVE_SESSIONS.get(user_id)
    if not last_seen:
        return False
    # User is considered active if their last API interaction was within 15 seconds
    active = datetime.utcnow() - last_seen < timedelta(seconds=15)
    return active


def queue_and_send_notification(
    user_id: str,
    pair_id: str,
    companion_id: str,
    sender_name: str,
    message_preview: str,
    payload_dict: dict,
) -> dict:
    # 1. Queue it as pending first in the database
    notif = db.queue_notification(
        user_id=user_id,
        pair_id=pair_id,
        companion_id=companion_id,
        sender_name=sender_name,
        message_preview=message_preview,
        payload_dict=payload_dict,
    )

    # 2. Check if the user is currently active (looking at the screen)
    if is_user_active(user_id):
        logger.info("User %s is active on screen. Skipping FCM push.", user_id)
        db.mark_notification_status(notif["id"], "skipped")
        row = db.conn.execute("SELECT * FROM queued_notifications WHERE id = ?", (notif["id"],)).fetchone()
        return dict(row)

    # 3. Check for coalescing: check if another notification for this pair_id was queued within the last 15 seconds
    now = datetime.utcnow()
    recent_row = db.conn.execute(
        """
        SELECT * FROM queued_notifications
        WHERE pair_id = ? AND id != ? AND status != 'coalesced' AND status != 'skipped'
        ORDER BY timestamp DESC
        LIMIT 1
        """,
        (pair_id, notif["id"]),
    ).fetchone()

    # Import the FCM dispatch helper locally to prevent circular dependencies
    from core.proactive_engine import _send_push_hooks

    if recent_row:
        recent = dict(recent_row)
        try:
            recent_time = datetime.fromisoformat(recent["timestamp"])
        except ValueError:
            recent_time = None

        if recent_time and now - recent_time < timedelta(seconds=15):
            # Coalesce!
            try:
                prev_payload = json.loads(recent["payload_json"] or "{}")
            except Exception:
                prev_payload = {}

            messages = prev_payload.get("messages", [])
            if not messages:
                # Seed with previous preview if list doesn't exist
                messages.append(recent["message_preview"])
            messages.append(message_preview)
            count = len(messages)

            # Grouped preview text format
            grouped_preview = f"{sender_name}: [{count} messages] {message_preview}"

            new_payload = {
                **prev_payload,
                "messages": messages,
                "grouped_count": count,
            }

            # Update the recent notification
            db.conn.execute(
                """
                UPDATE queued_notifications
                SET message_preview = ?,
                    payload_json = ?,
                    status = 'pending'
                WHERE id = ?
                """,
                (grouped_preview, json.dumps(new_payload), recent["id"]),
            )

            # Mark the new notification as 'coalesced'
            db.mark_notification_status(notif["id"], "coalesced")

            # Attempt immediate FCM dispatch of the coalesced notification
            outcome = _send_push_hooks(
                user_id=user_id,
                title=sender_name,
                body=grouped_preview,
                data={
                    "pair_id": pair_id,
                    "companion_id": companion_id,
                    "notification_id": recent["id"],
                    "coalesced": "true",
                    "grouped_count": str(count),
                },
            )

            # Update status on the coalesced notification
            db.mark_notification_status(recent["id"], outcome)

            row = db.conn.execute("SELECT * FROM queued_notifications WHERE id = ?", (recent["id"],)).fetchone()
            return dict(row)

    # Normal dispatch
    outcome = _send_push_hooks(
        user_id=user_id,
        title=sender_name,
        body=message_preview,
        data={
            "pair_id": pair_id,
            "companion_id": companion_id,
            "notification_id": notif["id"],
        },
    )

    db.mark_notification_status(notif["id"], outcome)
    row = db.conn.execute("SELECT * FROM queued_notifications WHERE id = ?", (notif["id"],)).fetchone()
    return dict(row)


@router.post("/me/notifications/{notification_id}/receipt")
async def confirm_notification_receipt(
    notification_id: str,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    row = db.conn.execute("SELECT * FROM queued_notifications WHERE id = ?", (notification_id,)).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Notification not found")

    notification = dict(row)
    if notification["user_id"] != identity.uid:
        raise HTTPException(status_code=403, detail="Forbidden")

    # Log system event "notification_delivered_receipt"
    db.log_system_event(
        kind="notification_delivered_receipt",
        severity="info",
        user_id=identity.uid,
        pair_id=notification.get("pair_id"),
        payload={"notification_id": notification_id},
    )

    # Confirm notification delivery
    updated = db.confirm_notification_delivery(notification_id)
    return {"status": "success", "notification": updated}


@router.post("/me/presence")
async def report_presence(
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    update_user_presence(identity.uid)
    return {"status": "active"}
