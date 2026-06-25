from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.db import Goal
from app.core.logging import get_logger

log = get_logger(__name__)


async def list_goals(
    session: AsyncSession,
    user_id: uuid.UUID,
    module_type: str | None = None,
    active_only: bool = True,
) -> list[dict[str, Any]]:
    q = select(Goal).where(Goal.user_id == user_id)
    if module_type:
        q = q.where(Goal.module_type == module_type)
    if active_only:
        q = q.where(Goal.is_active.is_(True))
    q = q.order_by(Goal.priority.desc(), Goal.created_at.desc())
    result = await session.execute(q)
    goals = result.scalars().all()

    return [
        {
            "id": str(g.id),
            "title": g.title,
            "module": g.module_type,
            "target_value": float(g.target_value) if g.target_value else None,
            "current_value": float(g.current_value),
            "unit": g.unit,
            "frequency": g.frequency,
            "priority": g.priority,
            "progress_pct": (
                round(float(g.current_value) / float(g.target_value) * 100, 1)
                if g.target_value and float(g.target_value) > 0 else 0.0
            ),
        }
        for g in goals
    ]


async def create_goal(
    session: AsyncSession,
    user_id: uuid.UUID,
    module_type: str,
    title: str,
    description: str | None = None,
    target_value: float | None = None,
    unit: str | None = None,
    frequency: str | None = None,
    priority: int = 1,
) -> dict[str, Any]:
    goal = Goal(
        user_id=user_id,
        module_type=module_type,
        title=title,
        description=description,
        target_value=target_value,
        unit=unit,
        frequency=frequency,
        priority=priority,
    )
    session.add(goal)
    await session.flush()
    log.info("goal_created", user_id=str(user_id), module=module_type, title=title)
    return {"created": True, "id": str(goal.id), "title": title}


async def deactivate_goal(
    session: AsyncSession,
    user_id: uuid.UUID,
    goal_id: str,
) -> dict[str, Any]:
    try:
        gid = uuid.UUID(goal_id)
    except ValueError:
        return {"error": "ID d'objectif invalide."}

    result = await session.execute(
        select(Goal).where(Goal.id == gid, Goal.user_id == user_id)
    )
    goal = result.scalar_one_or_none()
    if not goal:
        return {"error": "Objectif non trouvé."}

    goal.is_active = False
    await session.flush()
    log.info("goal_deactivated", goal_id=goal_id)
    return {"deleted": True, "id": goal_id, "title": goal.title}
