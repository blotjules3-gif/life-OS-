from __future__ import annotations

import uuid
from datetime import datetime, timezone, timedelta

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_session
from app.dependencies import verify_api_key
from app.models.db import LifeChallenge
from app.services.user import get_or_create_user

router = APIRouter(prefix="/challenges", tags=["challenges"])


def _challenge_to_dict(c: LifeChallenge) -> dict:
    now = datetime.now(tz=timezone.utc)
    started = c.started_at.replace(tzinfo=timezone.utc) if c.started_at.tzinfo is None else c.started_at
    days_elapsed = (now - started).days

    last = None
    days_since_checkin: int | None = None
    if c.last_checkin_at:
        last = c.last_checkin_at.replace(tzinfo=timezone.utc) if c.last_checkin_at.tzinfo is None else c.last_checkin_at
        days_since_checkin = (now - last).days

    return {
        "id": str(c.id),
        "title": c.title,
        "challenge_type": c.challenge_type,
        "daily_target": float(c.daily_target) if c.daily_target is not None else None,
        "unit": c.unit,
        "duration_days": c.duration_days,
        "streak_days": c.streak_days,
        "days_elapsed": days_elapsed,
        "days_since_checkin": days_since_checkin,
        "last_checkin_at": c.last_checkin_at.isoformat() if c.last_checkin_at else None,
        "notes": c.notes,
        "is_active": c.is_active,
        "started_at": c.started_at.isoformat(),
    }


@router.get("", dependencies=[Depends(verify_api_key)])
async def list_challenges(
    device_id: str,
    active_only: bool = True,
    session: AsyncSession = Depends(get_session),
) -> dict:
    user = await get_or_create_user(session, device_id)
    q = select(LifeChallenge).where(LifeChallenge.user_id == user.id)
    if active_only:
        q = q.where(LifeChallenge.is_active == True)
    q = q.order_by(LifeChallenge.started_at.desc())
    result = await session.execute(q)
    challenges = result.scalars().all()
    return {"challenges": [_challenge_to_dict(c) for c in challenges]}


@router.post("/{challenge_id}/checkin", dependencies=[Depends(verify_api_key)])
async def checkin_challenge(
    challenge_id: uuid.UUID,
    device_id: str,
    session: AsyncSession = Depends(get_session),
) -> dict:
    user = await get_or_create_user(session, device_id)
    result = await session.execute(
        select(LifeChallenge).where(
            LifeChallenge.id == challenge_id,
            LifeChallenge.user_id == user.id,
        )
    )
    challenge = result.scalar_one_or_none()
    if not challenge:
        raise HTTPException(status_code=404, detail="Challenge not found")

    now = datetime.now(tz=timezone.utc)

    if challenge.last_checkin_at:
        last = challenge.last_checkin_at.replace(tzinfo=timezone.utc) if challenge.last_checkin_at.tzinfo is None else challenge.last_checkin_at
        days_since = (now - last).days
        if days_since == 0:
            return {"already_checked_in": True, "streak_days": challenge.streak_days}
        elif days_since == 1:
            challenge.streak_days += 1
        else:
            challenge.streak_days = 1
    else:
        challenge.streak_days = 1

    challenge.last_checkin_at = now
    await session.flush()

    return {
        "checked_in": True,
        "streak_days": challenge.streak_days,
        "challenge_id": str(challenge.id),
    }
