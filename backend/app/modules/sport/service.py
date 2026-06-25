from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.db import SportLog
from app.modules.base import BaseModuleService


class SportService(BaseModuleService):

    async def log_workout(
        self,
        workout_type: str,
        duration_minutes: int,
        sets: int | None = None,
        reps: int | None = None,
        weight_kg: float | None = None,
        distance_km: float | None = None,
        calories_burned: int | None = None,
        notes: str | None = None,
    ) -> dict[str, Any]:
        log = SportLog(
            user_id=self.user_id,
            workout_type=workout_type,
            duration_minutes=duration_minutes,
            sets=sets,
            reps=reps,
            weight_kg=weight_kg,
            distance_km=distance_km,
            calories_burned=calories_burned,
            notes=notes,
        )
        self.session.add(log)
        await self.session.flush()
        return {
            "logged": True,
            "id": str(log.id),
            "workout_type": workout_type,
            "duration_minutes": duration_minutes,
        }

    async def analyze_progress(self, days: int = 30) -> dict[str, Any]:
        return await self.get_stats(days)

    async def get_stats(self, days: int = 30) -> dict[str, Any]:
        since = datetime.now(tz=timezone.utc) - timedelta(days=days)

        result = await self.session.execute(
            select(
                func.count(SportLog.id).label("total_sessions"),
                func.sum(SportLog.duration_minutes).label("total_minutes"),
                func.sum(SportLog.distance_km).label("total_km"),
                func.sum(SportLog.calories_burned).label("total_calories"),
            ).where(
                SportLog.user_id == self.user_id,
                SportLog.logged_at >= since,
            )
        )
        row = result.one()

        # Workout type breakdown
        type_result = await self.session.execute(
            select(SportLog.workout_type, func.count(SportLog.id).label("count"))
            .where(SportLog.user_id == self.user_id, SportLog.logged_at >= since)
            .group_by(SportLog.workout_type)
            .order_by(func.count(SportLog.id).desc())
        )
        types = [{"type": r.workout_type, "count": r.count} for r in type_result]

        return {
            "period_days": days,
            "total_sessions": row.total_sessions or 0,
            "total_minutes": int(row.total_minutes or 0),
            "total_km": float(row.total_km or 0),
            "total_calories": int(row.total_calories or 0),
            "sessions_per_week": round((row.total_sessions or 0) / (days / 7), 1),
            "workout_types": types,
        }
