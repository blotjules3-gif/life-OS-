from __future__ import annotations

from datetime import date, datetime, timezone

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_session
from app.dependencies import verify_api_key
from app.models.db import DailyCheckin
from app.services.behavioral_insights import compute_insights
from app.services.energy import compute_energy_score, score_color, score_label
from app.services.user import get_or_create_user

router = APIRouter(prefix="/energy", tags=["energy"])


class CheckinRequest(BaseModel):
    device_id: str
    checkin_date: date | None = None  # défaut = aujourd'hui
    sleep_quality: int | None = None
    sleep_hours: float | None = None
    mood: int | None = None
    fatigue: int | None = None
    water_ml: int | None = None
    habits_done: int | None = None
    habits_total: int | None = None
    sport_minutes: int | None = None


def _to_dict(c: DailyCheckin) -> dict:
    score = c.energy_score or 0
    return {
        "checkin_date": c.checkin_date.date().isoformat() if hasattr(c.checkin_date, "date") else str(c.checkin_date),
        "sleep_quality": c.sleep_quality,
        "sleep_hours": float(c.sleep_hours) if c.sleep_hours is not None else None,
        "mood": c.mood,
        "fatigue": c.fatigue,
        "water_ml": c.water_ml,
        "habits_done": c.habits_done,
        "habits_total": c.habits_total,
        "sport_minutes": c.sport_minutes,
        "energy_score": score,
        "label": score_label(score),
        "color": score_color(score),
    }


@router.post("/checkin", dependencies=[Depends(verify_api_key)])
async def upsert_checkin(
    body: CheckinRequest,
    session: AsyncSession = Depends(get_session),
) -> dict:
    user = await get_or_create_user(session, body.device_id)
    target_date = body.checkin_date or date.today()

    result = await session.execute(
        select(DailyCheckin).where(
            DailyCheckin.user_id == user.id,
            DailyCheckin.checkin_date == target_date,
        )
    )
    checkin = result.scalar_one_or_none()

    if checkin is None:
        checkin = DailyCheckin(
            user_id=user.id,
            checkin_date=datetime.combine(target_date, datetime.min.time()),
        )
        session.add(checkin)

    # Merge — seuls les champs fournis écrasent l'existant
    if body.sleep_quality is not None:
        checkin.sleep_quality = body.sleep_quality
    if body.sleep_hours is not None:
        checkin.sleep_hours = body.sleep_hours
    if body.mood is not None:
        checkin.mood = body.mood
    if body.fatigue is not None:
        checkin.fatigue = body.fatigue
    if body.water_ml is not None:
        checkin.water_ml = body.water_ml
    if body.habits_done is not None:
        checkin.habits_done = body.habits_done
    if body.habits_total is not None:
        checkin.habits_total = body.habits_total
    if body.sport_minutes is not None:
        checkin.sport_minutes = body.sport_minutes

    checkin.energy_score = compute_energy_score(checkin)
    checkin.updated_at = datetime.now(tz=timezone.utc)

    await session.flush()
    return _to_dict(checkin)


@router.get("/score", dependencies=[Depends(verify_api_key)])
async def get_score(
    device_id: str,
    target_date: date | None = None,
    session: AsyncSession = Depends(get_session),
) -> dict:
    user = await get_or_create_user(session, device_id)
    d = target_date or date.today()

    result = await session.execute(
        select(DailyCheckin).where(
            DailyCheckin.user_id == user.id,
            DailyCheckin.checkin_date == d,
        )
    )
    checkin = result.scalar_one_or_none()

    if checkin is None:
        return {
            "checkin_date": d.isoformat(),
            "energy_score": None,
            "label": None,
            "color": None,
        }

    return _to_dict(checkin)


@router.get("/insights", dependencies=[Depends(verify_api_key)])
async def get_insights(
    device_id: str,
    session: AsyncSession = Depends(get_session),
) -> dict:
    user = await get_or_create_user(session, device_id)
    insights = await compute_insights(session, user.id)
    return {"insights": insights}


@router.get("/history", dependencies=[Depends(verify_api_key)])
async def get_history(
    device_id: str,
    days: int = Query(default=7, ge=1, le=90),
    session: AsyncSession = Depends(get_session),
) -> dict:
    user = await get_or_create_user(session, device_id)
    result = await session.execute(
        select(DailyCheckin)
        .where(DailyCheckin.user_id == user.id)
        .order_by(DailyCheckin.checkin_date.desc())
        .limit(days)
    )
    checkins = result.scalars().all()
    return {"history": [_to_dict(c) for c in checkins]}
