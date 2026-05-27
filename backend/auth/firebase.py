import logging
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import firebase_admin
from fastapi import Header, HTTPException
from firebase_admin import auth as firebase_auth
from firebase_admin import credentials

from config import settings

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
        cred = credentials.Certificate(Path(service_account_path))
        firebase_admin.initialize_app(cred, **app_kwargs)
        logger.info("Firebase Admin initialized with service account credentials")
        return

    firebase_admin.initialize_app(**app_kwargs)
    logger.info("Firebase Admin initialized with project id only")


def verify_id_token(id_token: str) -> AuthenticatedIdentity:
    try:
        decoded = firebase_auth.verify_id_token(id_token, check_revoked=False)
    except Exception as exc:
        logger.warning("Firebase token verification failed: %s", exc)
        raise HTTPException(status_code=401, detail="Invalid or expired Firebase token") from exc

    uid = decoded.get("uid") or decoded.get("user_id") or decoded.get("sub")
    if not uid:
        raise HTTPException(status_code=401, detail="Firebase token missing uid")

    return AuthenticatedIdentity(
        uid=uid,
        email=decoded.get("email"),
        display_name=decoded.get("name"),
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
