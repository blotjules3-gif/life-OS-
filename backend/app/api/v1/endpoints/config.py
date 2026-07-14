"""Feature flags serveur : kill switch coach sans redéploiement iOS."""
from __future__ import annotations

import os

from fastapi import APIRouter, Depends

from app.dependencies import verify_api_key
from app.schemas.chat import RemoteConfigResponse

router = APIRouter(prefix="/config", tags=["config"])


def _env_bool(key: str, default: bool) -> bool:
    raw = os.environ.get(key)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


@router.get("", response_model=RemoteConfigResponse, dependencies=[Depends(verify_api_key)])
async def get_config() -> RemoteConfigResponse:
    return RemoteConfigResponse(chat_enabled=_env_bool("CHAT_ENABLED", True))
