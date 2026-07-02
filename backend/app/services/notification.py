from __future__ import annotations

import json
import time
import uuid
from datetime import datetime, timezone
from typing import Any

import httpx
from cryptography.hazmat.primitives.serialization import load_pem_private_key
from jose import jwt

from app.config import Settings
from app.core.logging import get_logger
from app.models.db import ScheduledNotification

log = get_logger(__name__)

APNS_HOST_PROD = "https://api.push.apple.com"
APNS_HOST_DEV = "https://api.development.push.apple.com"
APNS_PORT = 443
JWT_ALGORITHM = "ES256"
JWT_TTL_SECONDS = 3600  # APNs tokens expire after 1h


class APNsClient:
    """Async APNs HTTP/2 client using httpx.

    Manages JWT token rotation and sends push notifications.
    The token is reused until 55 minutes old (before the 1h expiry).
    """

    def __init__(self, settings: Settings) -> None:
        self._key_id = settings.apns_key_id
        self._team_id = settings.apns_team_id
        self._bundle_id = settings.apns_bundle_id
        self._use_sandbox = settings.apns_use_sandbox
        self._host = APNS_HOST_DEV if settings.apns_use_sandbox else APNS_HOST_PROD
        self._private_key_path = settings.apns_private_key_path
        self._private_key: bytes | None = None
        self._jwt_token: str | None = None
        self._jwt_generated_at: float = 0

    def _load_private_key(self) -> bytes:
        if self._private_key is None:
            if not self._private_key_path:
                raise ValueError("APNs private key path not configured.")
            with open(self._private_key_path, "rb") as f:
                self._private_key = f.read()
        return self._private_key

    def _get_jwt(self) -> str:
        now = time.time()
        if self._jwt_token and (now - self._jwt_generated_at) < 3300:  # 55 min
            return self._jwt_token

        key_bytes = self._load_private_key()
        payload = {"iss": self._team_id, "iat": int(now)}
        headers = {"alg": JWT_ALGORITHM, "kid": self._key_id}
        self._jwt_token = jwt.encode(payload, key_bytes, algorithm=JWT_ALGORITHM, headers=headers)
        self._jwt_generated_at = now
        return self._jwt_token

    async def send(
        self,
        device_token: str,
        title: str,
        body: str,
        deep_link: str | None = None,
        badge: int = 1,
    ) -> bool:
        if not all([self._key_id, self._team_id, self._private_key_path]):
            log.warning("apns_not_configured", msg="APNs credentials missing — notification not sent.")
            return False

        payload: dict[str, Any] = {
            "aps": {
                "alert": {"title": title, "body": body},
                "badge": badge,
                "sound": "default",
            }
        }
        if deep_link:
            payload["deep_link"] = deep_link

        url = f"{self._host}/3/device/{device_token}"
        headers = {
            "authorization": f"bearer {self._get_jwt()}",
            "apns-topic": self._bundle_id,
            "apns-push-type": "alert",
            "apns-priority": "10",
        }

        try:
            async with httpx.AsyncClient(http2=True, timeout=10.0) as client:
                response = await client.post(url, json=payload, headers=headers)

            if response.status_code == 200:
                log.info("apns_sent", device_token=device_token[:8] + "…", title=title)
                return True
            else:
                error_body = response.text
                log.error("apns_error", status=response.status_code, body=error_body)
                return False

        except Exception as exc:
            log.error("apns_exception", error=str(exc))
            return False


async def dispatch_pending_notifications(
    session,
    apns_client: APNsClient,
) -> int:
    """Send all due notifications. Called by Celery beat task."""
    from sqlalchemy import select, update
    from app.models.db import User

    now = datetime.now(tz=timezone.utc)

    # Ferme les notifications périmées (> 24 h de retard) sans les envoyer :
    # au premier démarrage du beat, le backlog accumulé partirait d'un coup.
    stale = await session.execute(
        update(ScheduledNotification)
        .where(
            ScheduledNotification.sent.is_(False),
            ScheduledNotification.scheduled_for < now - timedelta(hours=24),
        )
        .values(sent=True, sent_at=None)
    )
    if stale.rowcount:
        log.info("notifications_expired", count=stale.rowcount)

    result = await session.execute(
        select(ScheduledNotification)
        .join(User, ScheduledNotification.user_id == User.id)
        .where(
            ScheduledNotification.sent.is_(False),
            ScheduledNotification.scheduled_for <= now,
            User.apns_token.isnot(None),
        )
        .with_for_update(skip_locked=True)
        .limit(100)
    )
    pending = result.scalars().all()

    sent_count = 0
    for notif in pending:
        user_result = await session.execute(
            select(User).where(User.id == notif.user_id)
        )
        user = user_result.scalar_one_or_none()
        if not user or not user.apns_token:
            continue

        ok = await apns_client.send(
            device_token=user.apns_token,
            title=notif.title,
            body=notif.body,
            deep_link=notif.deep_link,
        )

        if ok:
            notif.sent = True
            notif.sent_at = now
            sent_count += 1

    await session.commit()
    log.info("notifications_dispatched", count=sent_count)
    return sent_count
