from __future__ import annotations

import uuid
from abc import ABC, abstractmethod
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession


class BaseModuleService(ABC):
    """Abstract base for all module services.

    Each module service:
    - Owns its domain data (reads/writes to its DB tables)
    - Exposes tool handler methods matching the tool definitions
    - Never calls the LLM directly
    """

    def __init__(self, session: AsyncSession, user_id: uuid.UUID) -> None:
        self.session = session
        self.user_id = user_id

    @abstractmethod
    async def get_stats(self, days: int = 30) -> dict[str, Any]:
        """Return a summary dict used for habit analysis and notifications."""
        ...
