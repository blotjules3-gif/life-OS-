from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_session
from app.dependencies import verify_api_key
from app.schemas.goal import GoalCreate, GoalOut, GoalUpdate
from app.services import goal as goal_svc
from app.services.user import get_or_create_user

router = APIRouter(prefix="/goals", tags=["goals"])


@router.get("", dependencies=[Depends(verify_api_key)])
async def list_goals(
    device_id: str,
    module: str | None = None,
    active_only: bool = True,
    session: AsyncSession = Depends(get_session),
) -> dict:
    user = await get_or_create_user(session, device_id)
    goals = await goal_svc.list_goals(session, user.id, module_type=module, active_only=active_only)
    return {"goals": goals}


@router.post("", status_code=status.HTTP_201_CREATED, dependencies=[Depends(verify_api_key)])
async def create_goal(
    device_id: str,
    body: GoalCreate,
    session: AsyncSession = Depends(get_session),
) -> dict:
    user = await get_or_create_user(session, device_id)
    result = await goal_svc.create_goal(
        session=session,
        user_id=user.id,
        module_type=body.module_type,
        title=body.title,
        description=body.description,
        target_value=body.target_value,
        unit=body.unit,
        frequency=body.frequency,
        priority=body.priority,
    )
    return result


@router.delete("/{goal_id}", dependencies=[Depends(verify_api_key)])
async def delete_goal(
    goal_id: uuid.UUID,
    device_id: str,
    session: AsyncSession = Depends(get_session),
) -> dict:
    user = await get_or_create_user(session, device_id)
    result = await goal_svc.deactivate_goal(session, user.id, str(goal_id))
    if "error" in result:
        raise HTTPException(status_code=404, detail=result["error"])
    return result
