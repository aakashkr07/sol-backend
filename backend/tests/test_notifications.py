import json
import sys
from pathlib import Path

from fastapi.testclient import TestClient

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from api.notifications import queue_and_send_notification
from auth.firebase import AuthenticatedIdentity, get_authenticated_identity
from config import settings
from core import proactive_engine
from main import app
from memory.store import db


TEST_USER_ID = "notif-test-user"
TEST_COMPANION_ID = "nova"
TEST_PAIR_ID = f"{TEST_USER_ID}::{TEST_COMPANION_ID}"


def _reset_database(tmp_path):
    if db._conn is not None:
        db.close()
        db._conn = None
    settings.SQLITE_DB_PATH = str(tmp_path / "notifications.sqlite3")
    db.connect()
    db.upsert_companion(TEST_COMPANION_ID, "Nova")
    db.get_or_create_user(
        TEST_USER_ID,
        character_id=TEST_COMPANION_ID,
        display_name="Notification Tester",
        email="notify@example.test",
    )
    db.get_or_create_relationship_pair(TEST_USER_ID, TEST_COMPANION_ID)


def _queue(message_preview="hey", payload=None):
    return db.queue_notification(
        user_id=TEST_USER_ID,
        pair_id=TEST_PAIR_ID,
        companion_id=TEST_COMPANION_ID,
        sender_name="Nova",
        message_preview=message_preview,
        payload_dict=payload or {"kind": "test"},
    )


def test_queue_notification_inserts_pending_row(tmp_path):
    _reset_database(tmp_path)

    notification = _queue("hey")
    stored = db.get_notification(notification["id"])

    assert stored is not None
    assert stored["user_id"] == TEST_USER_ID
    assert stored["pair_id"] == TEST_PAIR_ID
    assert stored["companion_id"] == TEST_COMPANION_ID
    assert stored["sender_name"] == "Nova"
    assert stored["message_preview"] == "hey"
    assert stored["status"] == "pending"
    assert stored["retry_count"] == 0
    assert json.loads(stored["payload_json"]) == {"kind": "test"}


def test_failed_retry_attempt_increments_retry_count(tmp_path, monkeypatch):
    _reset_database(tmp_path)
    notification = _queue("try me again")

    def fail_push(*args, **kwargs):
        return "failed"

    monkeypatch.setattr(proactive_engine, "_send_push_hooks", fail_push)

    pending = db.get_pending_notifications(limit=20)
    assert [row["id"] for row in pending] == [notification["id"]]

    for row in pending:
        outcome = proactive_engine._send_push_hooks(
            row["user_id"],
            row["sender_name"],
            row["message_preview"],
            {"notification_id": row["id"]},
        )
        db.mark_notification_status(
            row["id"],
            "sent" if outcome == "sent" else "failed",
            error_message=outcome,
        )

    updated = db.get_notification(notification["id"])
    assert updated["status"] == "failed"
    assert updated["retry_count"] == 1
    assert updated["last_attempt_at"] is not None
    assert updated["delivered_at"] is None
    assert db.get_pending_notifications(limit=20)[0]["id"] == notification["id"]


def test_receipt_endpoint_marks_notification_delivered(tmp_path):
    _reset_database(tmp_path)
    notification = _queue("delivered soon")

    app.dependency_overrides[get_authenticated_identity] = lambda: AuthenticatedIdentity(
        uid=TEST_USER_ID,
        email="notify@example.test",
        display_name="Notification Tester",
    )
    try:
        client = TestClient(app)
        response = client.post(f"/api/me/notifications/{notification['id']}/receipt")
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "success"
    assert payload["notification"]["status"] == "delivered"
    assert payload["notification"]["delivered_at"] is not None

    events = db.list_system_events(kind="notification_delivered_receipt", limit=5)
    assert any(event["user_id"] == TEST_USER_ID for event in events)


def test_consecutive_notifications_are_grouped_before_dispatch(tmp_path, monkeypatch):
    _reset_database(tmp_path)

    monkeypatch.setattr(proactive_engine, "_send_push_hooks", lambda *args, **kwargs: "sent")

    first = queue_and_send_notification(
        user_id=TEST_USER_ID,
        pair_id=TEST_PAIR_ID,
        companion_id=TEST_COMPANION_ID,
        sender_name="Nova",
        message_preview="hey",
        payload_dict={"messages": ["hey"]},
    )
    second = queue_and_send_notification(
        user_id=TEST_USER_ID,
        pair_id=TEST_PAIR_ID,
        companion_id=TEST_COMPANION_ID,
        sender_name="Nova",
        message_preview="are you up?",
        payload_dict={"messages": ["are you up?"]},
    )

    assert first["status"] == "sent"
    assert second["status"] == "sent"
    assert second["message_preview"] == "Nova: [2 messages] are you up?"

    payload = json.loads(second["payload_json"])
    assert payload["coalesced"] is True
    assert payload["grouped_count"] == 2
    assert payload["messages"] == ["hey", "are you up?"]
    assert payload["coalesced_with_notification_id"] == first["id"]
