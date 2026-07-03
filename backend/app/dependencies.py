from __future__ import annotations

from collections.abc import AsyncGenerator

from fastapi import Depends, HTTPException, Security, status
from fastapi.security import APIKeyHeader
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings, get_settings
from app.core.agents.orchestrator import AgentOrchestrator
from app.database import get_session
from app.services.notification import APNsClient

api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)


async def verify_api_key(
    key: str | None = Security(api_key_header),
    settings: Settings = Depends(get_settings),
) -> None:
    valid_keys = {settings.internal_api_key}
    if settings.internal_api_key_secondary:
        valid_keys.add(settings.internal_api_key_secondary)
    if not key or key not in valid_keys:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing API key.",
        )


def get_orchestrator(settings: Settings = Depends(get_settings)) -> AgentOrchestrator:
    return AgentOrchestrator(settings)


def get_apns_client(settings: Settings = Depends(get_settings)) -> APNsClient:
    return APNsClient(settings)
