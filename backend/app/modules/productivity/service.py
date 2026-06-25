from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.base import BaseModuleService


class ProductivityService(BaseModuleService):
    """Productivity module — habits and focus sessions.
    Actual habit data lives in the iOS app (SwiftData). This service handles
    goal/config management and stats derived from what the app reports.
    """

    async def get_stats(self, days: int = 30) -> dict[str, Any]:
        return {
            "period_days": days,
            "note": "Stats de productivité synchronisées depuis l'app iOS.",
        }
