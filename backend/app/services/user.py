from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.db import User
from app.core.logging import get_logger

log = get_logger(__name__)


async def get_or_create_user(
    session: AsyncSession,
    device_id: str,
    apns_token: str | None = None,
) -> User:
    result = await session.execute(select(User).where(User.device_id == device_id))
    user = result.scalar_one_or_none()

    if user:
        if apns_token and user.apns_token != apns_token:
            user.apns_token = apns_token
            await session.flush()
        return user

    user = User(device_id=device_id, apns_token=apns_token)
    session.add(user)
    await session.flush()
    log.info("user_created", user_id=str(user.id), device_id=device_id)
    return user


async def update_user_profile(
    session: AsyncSession,
    user_id: uuid.UUID,
    name: str | None = None,
    gender: str | None = None,
    apns_token: str | None = None,
) -> dict[str, Any]:
    result = await session.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise ValueError(f"User {user_id} not found")

    if name is not None:
        user.name = name
    if gender is not None:
        user.gender = gender
    if apns_token is not None:
        user.apns_token = apns_token

    await session.flush()
    return {"updated": True, "name": user.name, "gender": user.gender}
