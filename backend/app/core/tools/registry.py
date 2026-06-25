from __future__ import annotations

from collections.abc import Awaitable, Callable
from typing import Any

from app.core.exceptions import ToolNotFoundError
from app.core.logging import get_logger

log = get_logger(__name__)

# Type for tool handler functions
ToolHandler = Callable[..., Awaitable[dict[str, Any]]]


class ToolRegistry:
    """Central registry mapping tool names to async handler functions.

    Tools are registered at startup. The executor calls `get(name)` to
    retrieve the handler before running it.
    """

    def __init__(self) -> None:
        self._tools: dict[str, ToolHandler] = {}

    def register(self, name: str, handler: ToolHandler) -> None:
        if name in self._tools:
            raise ValueError(f"Tool '{name}' is already registered.")
        self._tools[name] = handler
        log.debug("tool_registered", tool=name)

    def get(self, name: str) -> ToolHandler:
        try:
            return self._tools[name]
        except KeyError:
            raise ToolNotFoundError(f"Tool '{name}' not found in registry. Available: {sorted(self._tools)}")

    def list_tools(self) -> list[str]:
        return sorted(self._tools.keys())

    def has(self, name: str) -> bool:
        return name in self._tools


# ── Global singleton ──────────────────────────────────────────────────────────

registry = ToolRegistry()
