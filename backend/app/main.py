from __future__ import annotations

from contextlib import asynccontextmanager
from typing import AsyncGenerator

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response
from prometheus_fastapi_instrumentator import Instrumentator
from starlette.middleware.base import BaseHTTPMiddleware

from app.api.v1.router import router as v1_router
from app.config import get_settings
from app.core.exceptions import LifeOSBaseError
from app.core.logging import configure_logging, get_logger
from app.core.tools.registry import registry
from app.database import Base, engine

settings = get_settings()
configure_logging(debug=settings.debug)
log = get_logger(__name__)


def _register_all_tools() -> None:
    """Wire every tool handler into the global registry.
    Called once at startup — order doesn't matter.
    """
    from app.core.tools.meta_tools import (
        handle_add_module,
        handle_ask_clarification,
        handle_check_in_challenge,
        handle_create_goal,
        handle_create_habit,
        handle_create_life_challenge,
        handle_create_todo,
        handle_delete_goal,
        handle_get_module_config,
        handle_get_user_context,
        handle_list_goals,
        handle_remember_user_info,
        handle_remove_module,
        handle_schedule_followup,
        handle_update_module_config,
        handle_update_user_profile,
    )
    from app.modules.finance.tools import (
        handle_analyze_cashflow,
        handle_compute_investable_amount,
        handle_simulate_allocation,
    )
    from app.modules.mobility.tools import handle_add_km, handle_estimate_fuel_remaining
    from app.modules.nutrition.tools import handle_add_meal, handle_compute_calorie_balance
    from app.modules.sport.tools import handle_analyze_sport_progress, handle_log_workout

    registry.register("get_module_config", handle_get_module_config)
    registry.register("update_module_config", handle_update_module_config)
    registry.register("list_goals", handle_list_goals)
    registry.register("create_goal", handle_create_goal)
    registry.register("delete_goal", handle_delete_goal)
    registry.register("ask_clarification", handle_ask_clarification)
    registry.register("create_todo", handle_create_todo)
    registry.register("create_habit", handle_create_habit)
    registry.register("schedule_followup", handle_schedule_followup)
    registry.register("get_user_context", handle_get_user_context)
    registry.register("update_user_profile", handle_update_user_profile)
    registry.register("remember_user_info", handle_remember_user_info)
    registry.register("create_life_challenge", handle_create_life_challenge)
    registry.register("check_in_challenge", handle_check_in_challenge)
    registry.register("add_module", handle_add_module)
    registry.register("remove_module", handle_remove_module)

    registry.register("log_workout", handle_log_workout)
    registry.register("analyze_sport_progress", handle_analyze_sport_progress)

    registry.register("add_meal", handle_add_meal)
    registry.register("compute_calorie_balance", handle_compute_calorie_balance)

    registry.register("analyze_cashflow", handle_analyze_cashflow)
    registry.register("compute_investable_amount", handle_compute_investable_amount)
    registry.register("simulate_allocation", handle_simulate_allocation)

    registry.register("add_km", handle_add_km)
    registry.register("estimate_fuel_remaining", handle_estimate_fuel_remaining)

    log.info("tools_registered", tools=registry.list_tools())


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    log.info("lifeos_agent_starting", version="1.0.0", debug=settings.debug)
    _register_all_tools()
    yield
    log.info("lifeos_agent_shutdown")


app = FastAPI(
    title="LifeOS Agent Backend",
    version="1.0.0",
    description="AI agent backend for LifeOS personalization and module management.",
    docs_url="/docs" if settings.debug else None,
    redoc_url="/redoc" if settings.debug else None,
    lifespan=lifespan,
)

# ── Middleware ────────────────────────────────────────────────────────────────

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_methods=["GET", "POST", "PATCH", "DELETE"],
    allow_headers=["*"],
)

# ── Metrics ───────────────────────────────────────────────────────────────────


class MetricsAuthMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if request.url.path == "/metrics":
            key = request.headers.get("X-Metrics-Key", "")
            if key != settings.internal_api_key:
                return Response(content="Unauthorized", status_code=401)
        return await call_next(request)


app.add_middleware(MetricsAuthMiddleware)
Instrumentator().instrument(app).expose(app, endpoint="/metrics")

# ── Routes ────────────────────────────────────────────────────────────────────

app.include_router(v1_router)


# ── Health check (no auth required) ──────────────────────────────────────────

@app.get("/health", tags=["system"])
@app.head("/health", tags=["system"])
async def health() -> dict:
    return {"status": "ok", "version": "1.0.0"}


# ── Exception handlers ────────────────────────────────────────────────────────

@app.exception_handler(LifeOSBaseError)
async def lifeos_error_handler(request: Request, exc: LifeOSBaseError) -> JSONResponse:
    log.error("lifeos_error", error=str(exc), path=request.url.path)
    return JSONResponse(status_code=500, content={"detail": "Erreur interne. Réessaie."})


@app.exception_handler(Exception)
async def generic_error_handler(request: Request, exc: Exception) -> JSONResponse:
    log.error("unhandled_error", error=str(exc), path=request.url.path, exc_info=True)
    return JSONResponse(status_code=500, content={"detail": "Erreur inattendue."})


@app.get("/health")
async def health() -> dict:
    return {"status": "ok", "tools": len(registry.list_tools())}
