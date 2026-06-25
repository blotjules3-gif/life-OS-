from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.mobility.service import MobilityService


async def handle_add_km(
    args: dict[str, Any],
    user_id: uuid.UUID,
    session: AsyncSession,
    context: dict[str, Any],
) -> dict[str, Any]:
    svc = MobilityService(session=session, user_id=user_id)
    return await svc.add_km(
        km_added=float(args["km_added"]),
        fuel_level_before=args.get("fuel_level_before"),
        vehicle_label=args.get("vehicle_label"),
        notes=args.get("notes"),
    )


async def handle_estimate_fuel_remaining(
    args: dict[str, Any],
    user_id: uuid.UUID,
    session: AsyncSession,
    context: dict[str, Any],
) -> dict[str, Any]:
    cfg = context.get("module_config", {})
    svc = MobilityService(session=session, user_id=user_id)
    return await svc.estimate_fuel_remaining(
        tank_capacity_l=float(cfg.get("vehicle_fuel_capacity_l", 50.0)),
        consumption_per_100km=float(cfg.get("fuel_consumption_per_100km", 7.0)),
    )
