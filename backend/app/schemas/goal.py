from __future__ import annotations

import uuid
from datetime import datetime
from typing import from pydantic import BaseModel, Field


class GoalCreate(BaseModel):
    module_type: str
    title: str = Field(..., min_length=1, max_length=255)
    description: str | None = None
    target_value: float | None = None
    unit: str | None = None
    frequency: str | None = Field(None, pattern=r"^(daily|weekly|monthly|once)$")
    priority: int = Field(1, ge=1, le=5)
    due_date: datetime | None = None


class GoalUpdate(BaseModel):
    title: str | None = Field(None, max_length=255)
    description: str | None = None
    target_value: float | None = None
    current_value: float | None = None
    priority: int | None = Field(None, ge=1, le=5)
    is_active: bool | None = None
    due_date: datetime | None = None


class GoalOut(BaseModel):
    id: uuid.UUID
    module_type: str
    title: str
    description: str | None
    target_value: float | None
    current_value: float
    unit: str | None
    frequency: str | None
    priority: int
    is_active: bool
    due_date: datetime | None
    progress_pct: float
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}

    @classmethod
    def from_orm_with_progress(cls, goal) -> "GoalOut":
        obj = cls.model_validate(goal)
        if goal.target_value and goal.target_value > 0:
            obj.progress_pct = min(100.0, round(float(goal.current_value) / float(goal.target_value) * 100, 1))
        else:
            obj.progress_pct = 0.0
        return obj
