from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any, Optional

from pydantic import BaseModel, Field


class ChatRequest(BaseModel):
    device_id: str = Field(..., min_length=1, max_length=255)
    message: str = Field(..., min_length=1, max_length=4000)
    module: Optional[str] = None  # 'sport', 'nutrition', etc. — None = general
    conversation_id: Optional[uuid.UUID] = None
    apns_token: Optional[str] = None  # update token on each request


class MessageOut(BaseModel):
    id: uuid.UUID
    role: str
    content: str
    tool_call: Optional[dict[str, Any]] = None
    created_at: datetime

    model_config = {"from_attributes": True}


class ChatResponse(BaseModel):
    conversation_id: uuid.UUID
    reply: str
    tool_calls_executed: list[str] = Field(default_factory=list)
    module_config_updated: bool = False
    goals_updated: bool = False


class ConversationOut(BaseModel):
    id: uuid.UUID
    module_type: Optional[str]
    title: Optional[str]
    created_at: datetime
    messages: list[MessageOut] = Field(default_factory=list)

    model_config = {"from_attributes": True}
