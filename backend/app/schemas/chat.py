from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any, Optional

from pydantic import BaseModel, Field


class ChatRequest(BaseModel):
    device_id: str = Field(..., min_length=1, max_length=255)
    message: str = Field(..., min_length=1, max_length=4000)
    module: str | None = None  # 'sport', 'nutrition', etc. — None = general
    conversation_id: uuid.UUID | None = None
    apns_token: str | None = None  # update token on each request
    # Snapshot iOS + expertise coach injectée (méta + jusqu'à 3 blocs domaine).
    # Passe de 2000 à 20000 pour laisser passer les blocs d'expertise scientifiques.
    user_context: str | None = Field(None, max_length=20000)


class MessageOut(BaseModel):
    id: uuid.UUID
    role: str
    content: str
    tool_call: Optional[dict[str, Any]] = None
    created_at: datetime

    model_config = {"from_attributes": True}


class ChatAction(BaseModel):
    type: str  # "create_todo" | "open_module" | "schedule_reminder" | "update_config"
    title: str | None = None
    module: str | None = None
    priority: int | None = None
    reminder_body: str | None = None
    delay_seconds: int | None = None  # pour schedule_reminder : délai réel en secondes
    challenge_id: str | None = None
    daily_target: float | None = None
    unit: str | None = None
    duration_days: int | None = None


class ChatResponse(BaseModel):
    conversation_id: uuid.UUID
    reply: str
    tool_calls_executed: list[str] = Field(default_factory=list)
    module_config_updated: bool = False
    goals_updated: bool = False
    actions: list[ChatAction] = Field(default_factory=list)


class ConversationOut(BaseModel):
    id: uuid.UUID
    module_type: str | None
    title: str | None
    created_at: datetime
    messages: list[MessageOut] = Field(default_factory=list)

    model_config = {"from_attributes": True}


class ReportRequest(BaseModel):
    device_id: str
    conversation_id: uuid.UUID | None = None
    message_content: str = Field(..., max_length=8000)
    reason: str = Field(default="user_flagged", max_length=64)


class RemoteConfigResponse(BaseModel):
    chat_enabled: bool
