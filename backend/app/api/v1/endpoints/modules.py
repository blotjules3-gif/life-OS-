from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_session
from app.dependencies import verify_api_key
from app.models.db import ModuleConfig
from app.schemas.module import ModuleConfigOut, UpdateModuleConfigRequest, VALID_MODULES
from app.services import module_config as config_svc
from app.services.user import get_or_create_user

router = APIRouter(prefix="/modules", tags=["modules"])


@router.get("/{module}", response_model=ModuleConfigOut, dependencies=[Depends(verify_api_key)])
async def get_module_config(
    module: str,
    device_id: str,
    session: AsyncSession = Depends(get_session),
) -> ModuleConfigOut:
    if module not in VALID_MODULES:
        raise HTTPException(status_code=400, detail=f"Unknown module: {module}")
    user = await get_or_create_user(session, device_id)
    result = await session.execute(
        select(ModuleConfig).where(ModuleConfig.user_id == user.id, ModuleConfig.module_type == module)
    )
    obj = result.scalar_one_or_none()
    if not obj:
        import uuid as _uuid
        from datetime import datetime, timezone
        # Return empty config object
        return ModuleConfigOut(
            id=_uuid.uuid4(), module_type=module, config={}, updated_at=datetime.now(tz=timezone.utc)
        )
    return ModuleConfigOut.model_validate(obj)


@router.patch("/{module}", response_model=ModuleConfigOut, dependencies=[Depends(verify_api_key)])
async def update_module_config(
    module: str,
    body: UpdateModuleConfigRequest,
    device_id: str,
    session: AsyncSession = Depends(get_session),
) -> ModuleConfigOut:
    if module not in VALID_MODULES:
        raise HTTPException(status_code=400, detail=f"Unknown module: {module}")
    user = await get_or_create_user(session, device_id)
    try:
        saved = await config_svc.upsert_config(session, user.id, module, body.config)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    result = await session.execute(
        select(ModuleConfig).where(ModuleConfig.user_id == user.id, ModuleConfig.module_type == module)
    )
    obj = result.scalar_one()
    return ModuleConfigOut.model_validate(obj)
