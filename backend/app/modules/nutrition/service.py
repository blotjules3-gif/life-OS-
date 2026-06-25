from __future__ import annotations

import uuid
from datetime import date, datetime, timezone
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.db import NutritionLog
from app.modules.base import BaseModuleService


class NutritionService(BaseModuleService):

    async def add_meal(
        self,
        meal_name: str,
        meal_type: str | None = None,
        calories: int | None = None,
        protein_g: float | None = None,
        carbs_g: float | None = None,
        fat_g: float | None = None,
    ) -> dict[str, Any]:
        entry = NutritionLog(
            user_id=self.user_id,
            meal_name=meal_name,
            meal_type=meal_type,
            calories=calories,
            protein_g=protein_g,
            carbs_g=carbs_g,
            fat_g=fat_g,
        )
        self.session.add(entry)
        await self.session.flush()
        return {
            "logged": True,
            "id": str(entry.id),
            "meal_name": meal_name,
            "calories": calories,
        }

    async def compute_calorie_balance(self, kcal_goal: int = 2000) -> dict[str, Any]:
        today_start = datetime.combine(date.today(), datetime.min.time(), tzinfo=timezone.utc)
        result = await self.session.execute(
            select(
                func.sum(NutritionLog.calories).label("total_kcal"),
                func.sum(NutritionLog.protein_g).label("total_protein"),
                func.count(NutritionLog.id).label("meal_count"),
            ).where(
                NutritionLog.user_id == self.user_id,
                NutritionLog.logged_at >= today_start,
            )
        )
        row = result.one()
        consumed = int(row.total_kcal or 0)
        remaining = kcal_goal - consumed
        return {
            "consumed_kcal": consumed,
            "goal_kcal": kcal_goal,
            "remaining_kcal": remaining,
            "balance_pct": round(consumed / kcal_goal * 100, 1) if kcal_goal > 0 else 0,
            "protein_g": float(row.total_protein or 0),
            "meal_count_today": row.meal_count or 0,
            "on_track": remaining >= 0,
        }

    async def get_stats(self, days: int = 30) -> dict[str, Any]:
        from datetime import timedelta
        since = datetime.now(tz=timezone.utc) - timedelta(days=days)
        result = await self.session.execute(
            select(
                func.avg(NutritionLog.calories).label("avg_kcal"),
                func.count(NutritionLog.id).label("total_logs"),
            ).where(NutritionLog.user_id == self.user_id, NutritionLog.logged_at >= since)
        )
        row = result.one()
        return {
            "period_days": days,
            "avg_daily_kcal": round(float(row.avg_kcal or 0), 0),
            "total_logs": row.total_logs or 0,
        }
