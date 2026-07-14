from __future__ import annotations

from functools import lru_cache

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
    # Clé de transition pendant une rotation : les builds installés avec
    # l'ancienne clé continuent de fonctionner. À vider une fois les apps rebuildées.
    internal_api_key_secondary: str | None = None

    # ── Database ──────────────────────────────────────────────────────────────
    database_url: str  # postgresql+asyncpg://...

    # ── LLM ───────────────────────────────────────────────────────────────────
    mistral_api_key: str
    mistral_model: str = "mistral-large-latest"
    llm_max_retries: int = 3
    llm_timeout_seconds: int = 30
    llm_max_agent_iterations: int = 12  # enough for first-launch bulk config
    llm_temperature: float = 0.3        # deterministic coaching (default Mistral is 0.7)
    llm_max_completion_tokens: int = 500  # enforce brevity — prompt says max 2 sentences

    # ── Agent time budget ─────────────────────────────────────────────────────
    # Soft: on retire les tools pour forcer une réponse texte finale.
    # Hard: on clôt le tour avec les actions déjà exécutées.
    # 50s soft + 30s de timeout LLM = 80s, sous le timeout chat iOS de 90s.
    agent_soft_budget_seconds: float = 50.0
    agent_hard_budget_seconds: float = 80.0

    # ── Rate limiting chat ────────────────────────────────────────────────────
    chat_rate_limit_per_minute: int = 10
    chat_rate_limit_per_hour: int = 80

    # ── Redis ─────────────────────────────────────────────────────────────────
    redis_url: str = "redis://localhost:6379/0"

    # ── APNs ─────────────────────────────────────────────────────────────────
    apns_key_id: str | None = None
    apns_team_id: str | None = None
    apns_bundle_id: str = "com.yourcompany.lifeos"
    apns_private_key_path: str | None = None
    apns_use_sandbox: bool = True

    # L'app iOS n'a pas d'origine web ; on ne s'ouvre à des domaines qu'à la demande.
    # Override via env var ALLOWED_ORIGINS='https://lifeos.app,https://admin.lifeos.app'.
    allowed_origins: list[str] = Field(default_factory=list)

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
