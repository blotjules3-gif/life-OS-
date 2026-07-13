"""Remote feature flags — permet de désactiver le coach côté serveur
sans nouveau build iOS si Apple rejette la review ou en cas d'incident.

Actuellement statique. Ajouter un backing store (env var, DB, Redis) si
besoin de flip dynamique. Kill switch : passer CHAT_ENABLED=false dans
les env vars Railway et redémarrer.
"""
from __future__ import annotations

import os

from fastapi import APIRouter, Depends

from app.dependencies import verify_api_key

router = APIRouter(prefix="/config", tags=["config"])


def _env_bool(key: str, default: bool) -> bool:
    raw = os.environ.get(key)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


@router.get("", dependencies=[Depends(verify_api_key)])
async def get_config(device_id: str | None = None) -> dict[str, bool]:
    return {
        "chat_enabled": _env_bool("CHAT_ENABLED", True),
    }
