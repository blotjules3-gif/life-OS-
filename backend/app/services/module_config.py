from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.db import ModuleConfig
from app.schemas.module import MODULE_CONFIG_VALIDATORS
from app.core.logging import get_logger

log = get_logger(__name__)


async def get_config(session: AsyncSession, user_id: uuid.UUID, module: str) -> dict[str, Any]:
    result = await session.execute(
        select(ModuleConfig).where(ModuleConfig.user_id == user_id, ModuleConfig.module_type == module)
    )
    obj = result.scalar_one_or_none()
    return obj.config if obj else {}


async def upsert_config(
    session: AsyncSession,
    user_id: uuid.UUID,
    module: str,
    config_delta: dict[str, Any],
) -> dict[str, Any]:
    current = await get_config(session, user_id, module)
    merged = {**current, **config_delta}

    # Validate merged config against module schema if available
    validator = MODULE_CONFIG_VALIDATORS.get(module)
    if validator:
        try:
            validator(**merged)
        except Exception as exc:
            log.warning("module_config_validation_failed", module=module, error=str(exc))
            raise ValueError(f"Config invalide pour le module {module}: {exc}") from exc

    stmt = (
        insert(ModuleConfig)
        .values(user_id=user_id, module_type=module, config=merged)
        .on_conflict_do_update(
            index_elements=["user_id", "module_type"],
            set_={"config": merged},
        )
        .returning(ModuleConfig.config)
    )
    result = await session.execute(stmt)
    saved = result.scalar_one()
    log.info("module_config_saved", user_id=str(user_id), module=module)
    return saved
