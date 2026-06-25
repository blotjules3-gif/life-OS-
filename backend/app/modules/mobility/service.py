from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.db import MobilityLog
from app.modules.base import BaseModuleService


class MobilityService(BaseModuleService):

    async def add_km(
        self,
        km_added: float,
        fuel_level_before: float | None = None,
        vehicle_label: str | None = None,
        notes: str | None = None,
    ) -> dict[str, Any]:
        entry = MobilityLog(
            user_id=self.user_id,
            km_added=km_added,
            fuel_level_before=fuel_level_before,
            vehicle_label=vehicle_label,
            notes=notes,
        )
        self.session.add(entry)
        await self.session.flush()
        return {"logged": True, "id": str(entry.id), "km_added": km_added}

    async def estimate_fuel_remaining(
        self,
        tank_capacity_l: float = 50.0,
        consumption_per_100km: float = 7.0,
    ) -> dict[str, Any]:
        # Get last fuel level from logs
        result = await self.session.execute(
            select(MobilityLog)
            .where(
                MobilityLog.user_id == self.user_id,
                MobilityLog.fuel_level_before.isnot(None),
            )
            .order_by(MobilityLog.logged_at.desc())
            .limit(1)
        )
        last = result.scalar_one_or_none()

        if not last or last.fuel_level_before is None:
            return {"error": "Aucun niveau de carburant enregistré. Ajoute d'abord un trajet avec le niveau de carburant."}

        # Get km driven since that log
        since_log = await self.session.execute(
            select(func.sum(MobilityLog.km_added))
            .where(
                MobilityLog.user_id == self.user_id,
                MobilityLog.logged_at > last.logged_at,
            )
        )
        km_since = float(since_log.scalar_one() or 0)

        fuel_at_last_log = float(last.fuel_level_before) / 100 * tank_capacity_l
        fuel_consumed = km_since * consumption_per_100km / 100
        fuel_remaining_l = max(0.0, fuel_at_last_log - fuel_consumed)
        fuel_remaining_pct = round(fuel_remaining_l / tank_capacity_l * 100, 1)
        range_km = round(fuel_remaining_l / consumption_per_100km * 100, 0)

        return {
            "fuel_remaining_l": round(fuel_remaining_l, 1),
            "fuel_remaining_pct": fuel_remaining_pct,
            "estimated_range_km": range_km,
            "km_driven_since_last_log": round(km_since, 1),
            "note": "Estimation basée sur ta consommation configurée.",
        }

    async def get_stats(self, days: int = 30) -> dict[str, Any]:
        since = datetime.now(tz=timezone.utc) - timedelta(days=days)
        result = await self.session.execute(
            select(func.sum(MobilityLog.km_added).label("total_km"), func.count(MobilityLog.id).label("trips"))
            .where(MobilityLog.user_id == self.user_id, MobilityLog.logged_at >= since)
        )
        row = result.one()
        return {
            "period_days": days,
            "total_km": float(row.total_km or 0),
            "trips": row.trips or 0,
        }
