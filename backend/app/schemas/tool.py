from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


class ToolCall(BaseModel):
    tool: str = Field(..., min_length=1, max_length=100)
    args: dict[str, Any] = Field(default_factory=dict)


class ToolResult(BaseModel):
    tool: str
    success: bool
    data: dict[str, Any] = Field(default_factory=dict)
    error: str | None = None


class MistralToolFunction(BaseModel):
    name: str
    arguments: str  # JSON string from Mistral


class MistralToolCall(BaseModel):
    id: str
    type: str = "function"
    function: MistralToolFunction
