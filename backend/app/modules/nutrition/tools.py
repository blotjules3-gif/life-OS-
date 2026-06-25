from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.nutrition.service import NutritionService


async def handle_add_meal(
    args: dict[str, Any],
    user_id: uuid.UUID,
    session: AsyncSession,
    context: dict[str, Any],
) -> dict[str, Any]:
    svc = NutritionService(session=session, user_id=user_id)
    return await svc.add_meal(
        meal_name=args["meal_name"],
        meal_type=args.get("meal_type"),
        calories=args.get("calories"),
        protein_g=args.get("protein_g"),
        carbs_g=args.get("carbs_g"),
        fat_g=args.get("fat_g"),
    )


async def handle_compute_calorie_balance(
    args: dict[str, Any],
    user_id: uuid.UUID,
    session: AsyncSession,
    context: dict[str, Any],
) -> dict[str, Any]:
    kcal_goal = int(context.get("module_config", {}).get("daily_kcal_goal", 2000))
    svc = NutritionService(session=session, user_id=user_id)
    return await svc.compute_calorie_balance(kcal_goal=kcal_goal)
