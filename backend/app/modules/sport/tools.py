from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.sport.service import SportService


async def handle_log_workout(
    args: dict[str, Any],
    user_id: uuid.UUID,
    session: AsyncSession,
    context: dict[str, Any],
) -> dict[str, Any]:
    svc = SportService(session=session, user_id=user_id)
    return await svc.log_workout(
        workout_type=args["workout_type"],
        duration_minutes=int(args["duration_minutes"]),
        sets=args.get("sets"),
        reps=args.get("reps"),
        weight_kg=args.get("weight_kg"),
        distance_km=args.get("distance_km"),
        calories_burned=args.get("calories_burned"),
        notes=args.get("notes"),
    )


async def handle_analyze_sport_progress(
    args: dict[str, Any],
    user_id: uuid.UUID,
    session: AsyncSession,
    context: dict[str, Any],
) -> dict[str, Any]:
    svc = SportService(session=session, user_id=user_id)
    return await svc.analyze_progress(days=int(args.get("days", 30)))
