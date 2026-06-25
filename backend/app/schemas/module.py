from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any, Optional

from pydantic import BaseModel, Field


VALID_MODULES = frozenset({
    "sport", "nutrition", "finance", "mobility",
    "productivity", "sleep", "mind", "learning",
})


class ModuleConfigOut(BaseModel):
    id: uuid.UUID
    module_type: str
    config: dict[str, Any]
    updated_at: datetime

    model_config = {"from_attributes": True}


class UpdateModuleConfigRequest(BaseModel):
    module: str = Field(..., pattern=r"^[a-z_]{3,30}$")
    config: dict[str, Any]

    def validate_module(self) -> None:
        if self.module not in VALID_MODULES:
            raise ValueError(f"Unknown module: {self.module}. Valid: {sorted(VALID_MODULES)}")


# ── Per-module config schemas (used for validation before storing) ────────────

class SportConfig(BaseModel):
    sessions_per_week: Optional[int] = Field(None, ge=1, le=14)
    preferred_workout_types: Optional[list[str]] = None
    session_duration_minutes: Optional[int] = Field(None, ge=10, le=240)
    weight_goal_kg: Optional[float] = None
    reminder_time: Optional[str] = Field(None, pattern=r"^\d{2}:\d{2}$")


class NutritionConfig(BaseModel):
    daily_kcal_goal: Optional[int] = Field(None, ge=500, le=10000)
    protein_goal_g: Optional[int] = Field(None, ge=10, le=500)
    water_goal_ml: Optional[int] = Field(None, ge=500, le=8000)
    meal_count_per_day: Optional[int] = Field(None, ge=1, le=10)
    diet_type: Optional[str] = None  # 'standard', 'vegan', 'keto', etc.


class FinanceConfig(BaseModel):
    monthly_income: Optional[float] = Field(None, ge=0)
    fixed_expenses: Optional[float] = Field(None, ge=0)
    savings_goal_pct: Optional[float] = Field(None, ge=0, le=100)
    risk_profile: Optional[str] = Field(None, pattern=r"^(conservative|moderate|aggressive)$")


class MobilityConfig(BaseModel):
    vehicle_fuel_capacity_l: Optional[float] = Field(None, ge=1, le=200)
    fuel_consumption_per_100km: Optional[float] = Field(None, ge=1, le=50)
    odometer_km: Optional[float] = Field(None, ge=0)


class ProductivityConfig(BaseModel):
    daily_habit_target: Optional[int] = Field(None, ge=1, le=20)
    focus_block_minutes: Optional[int] = Field(None, ge=15, le=240)
    work_days: Optional[list[str]] = None  # ['mon', 'tue', ...]


MODULE_CONFIG_VALIDATORS: dict[str, type[BaseModel]] = {
    "sport": SportConfig,
    "nutrition": NutritionConfig,
    "finance": FinanceConfig,
    "mobility": MobilityConfig,
    "productivity": ProductivityConfig,
}
