import logging
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import firebase_admin
from fastapi import Header, HTTPException
from firebase_admin import auth as firebase_auth
from firebase_admin import credentials

from config import settings
from memory.store import db

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class AuthenticatedIdentity:
    uid: str
    email: Optional[str]
    display_name: Optional[str]


def initialize_firebase_auth() -> None:
    if firebase_admin._apps:
        return

    service_account_path = settings.FIREBASE_SERVICE_ACCOUNT_PATH.strip()
    app_kwargs = {"options": {"projectId": settings.FIREBASE_PROJECT_ID}}

    if service_account_path:
        path = Path(service_account_path)
        if not path.exists():
            raise RuntimeError(
                f"Firebase service account file not found at {path}. "
                "Set FIREBASE_SERVICE_ACCOUNT_PATH to a real mounted credential file."
            )
        cred = credentials.Certificate(path)
        firebase_admin.initialize_app(cred, **app_kwargs)
        logger.info("Firebase Admin initialized with service account credentials")
        return

    try:
        firebase_admin.initialize_app(**app_kwargs)
        logger.info("Firebase Admin initialized with application default credentials")
    except Exception as exc:
        hint = (
            "Firebase Admin could not initialize without explicit credentials. "
            "On Railway, mount a Firebase service account JSON and set "
            "FIREBASE_SERVICE_ACCOUNT_PATH, or provide GOOGLE_APPLICATION_CREDENTIALS."
        )
        if settings.DEBUG or os.getenv("GOOGLE_APPLICATION_CREDENTIALS"):
            hint = (
                "Firebase Admin initialization failed. Provide a valid "
                "FIREBASE_SERVICE_ACCOUNT_PATH or GOOGLE_APPLICATION_CREDENTIALS."
            )
        raise RuntimeError(hint) from exc


def verify_id_token(id_token: str) -> AuthenticatedIdentity:
    try:
        decoded = firebase_auth.verify_id_token(id_token, check_revoked=False)
    except Exception as exc:
        logger.warning("Firebase token verification failed: %s", exc)
        raise HTTPException(status_code=401, detail="Invalid or expired Firebase token") from exc

    uid = decoded.get("uid") or decoded.get("user_id") or decoded.get("sub")
    if not uid:
        raise HTTPException(status_code=401, detail="Firebase token missing uid")

    email = decoded.get("email")
    display_name = decoded.get("name")

    # Immediate User Creation upon verification / first-time login
    try:
        with db.transaction():
            db.get_or_create_user(
                user_id=uid,
                display_name=display_name,
                email=email,
            )
            # Ensure user preferences row exists
            db.get_or_create_user_preferences(user_id=uid)
    except Exception as db_exc:
        logger.exception("Failed immediate user creation / registration for uid %s", uid)
        try:
            db.log_system_event(
                "auth_registration_failed",
                "error",
                user_id=uid,
                payload={"error": str(db_exc), "email": email, "display_name": display_name}
            )
        except Exception as log_err:
            logger.error("Failed to log auth_registration_failed to system_events: %s", log_err)
        raise HTTPException(
            status_code=500,
            detail=f"Database synchronization failed during authentication: {str(db_exc)}"
        )

    return AuthenticatedIdentity(
        uid=uid,
        email=email,
        display_name=display_name,
    )


async def get_authenticated_identity(
    authorization: Optional[str] = Header(default=None),
) -> AuthenticatedIdentity:
    if not authorization:
        raise HTTPException(status_code=401, detail="Missing Authorization header")

    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        raise HTTPException(status_code=401, detail="Authorization header must use Bearer token")

    return verify_id_token(token.strip())
