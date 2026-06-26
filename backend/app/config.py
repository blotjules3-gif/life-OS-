from __future__ import annotations

from functools import lru_cache
from typing import Optional

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
    )

    # ── App ───────────────────────────────────────────────────────────────────
    app_name: str = "LifeOS Agent"
    debug: bool = False
    secret_key: str = Field(..., min_length=32)
    internal_api_key: str = Field(..., min_length=16)

    # ── Database ──────────────────────────────────────────────────────────────
    database_url: str  # postgresql+asyncpg://...

    # ── LLM ───────────────────────────────────────────────────────────────────
    mistral_api_key: str
    mistral_model: str = "mistral-large-latest"
    llm_max_retries: int = 3
    llm_timeout_seconds: int = 30
    llm_max_agent_iterations: int = 12  # enough for first-launch bulk config

    # ── Redis ─────────────────────────────────────────────────────────────────
    redis_url: str = "redis://localhost:6379/0"

    # ── APNs ─────────────────────────────────────────────────────────────────
    apns_key_id: Optional[str] = None
    apns_team_id: Optional[str] = None
    apns_bundle_id: str = "com.yourcompany.lifeos"
    apns_private_key_path: Optional[str] = None
    apns_use_sandbox: bool = True

    # ── CORS ──────────────────────────────────────────────────────────────────
    allowed_origins: list[str] = ["*"]

    @field_validator("database_url")
    @classmethod
    def validate_db_url(cls, v: str) -> str:
        if not v.startswith("postgresql+asyncpg://"):
            raise ValueError("database_url must use postgresql+asyncpg:// driver")
        return v

    @property
    def apns_configured(self) -> bool:
        return all([
            self.apns_key_id,
            self.apns_team_id,
            self.apns_private_key_path,
        ])


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
