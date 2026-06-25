from __future__ import annotations

import asyncio
import json
import time
import uuid
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import ToolExecutionError, ToolNotFoundError, ToolRejectedError
from app.core.logging import get_logger
from app.core.tools.registry import registry
from app.models.db import ToolExecution

log = get_logger(__name__)

TOOL_TIMEOUT_SECONDS = 10

# Tools that are ALWAYS safe to run without safety checks
_SAFE_TOOLS = frozenset({
    "get_module_config",
    "list_goals",
    "ask_clarification",
    "compute_calorie_balance",
    "analyze_sport_progress",
    "estimate_fuel_remaining",
})

# Finance tools with mandatory disclaimer injection
_FINANCE_TOOLS = frozenset({
    "analyze_cashflow",
    "compute_investable_amount",
    "simulate_allocation",
})


async def execute_tool(
    tool_name: str,
    args: dict[str, Any],
    user_id: uuid.UUID,
    conversation_id: uuid.UUID | None,
    session: AsyncSession,
    context: dict[str, Any],
) -> dict[str, Any]:
    """Safely execute a registered tool.

    Steps:
    1. Resolve handler from registry
    2. Apply safety guardrails (finance tools)
    3. Execute with timeout
    4. Persist audit log
    5. Inject finance disclaimer if applicable
    6. Return result dict

    Raises ToolExecutionError on domain errors, ToolRejectedError on safety violations.
    """
    handler = registry.get(tool_name)  # raises ToolNotFoundError if absent

    _apply_safety_guardrails(tool_name, args)

    start = time.monotonic()
    status = "success"
    result: dict[str, Any] = {}
    error_message: str | None = None

    try:
        result = await asyncio.wait_for(
            handler(args=args, user_id=user_id, session=session, context=context),
            timeout=TOOL_TIMEOUT_SECONDS,
        )
        log.info("tool_executed", tool=tool_name, user_id=str(user_id), duration_ms=int((time.monotonic() - start) * 1000))
    except asyncio.TimeoutError as exc:
        status = "timeout"
        error_message = f"Tool '{tool_name}' timed out after {TOOL_TIMEOUT_SECONDS}s"
        log.error("tool_timeout", tool=tool_name)
        raise ToolExecutionError(error_message) from exc
    except ToolRejectedError:
        status = "rejected"
        raise
    except Exception as exc:
        status = "error"
        error_message = str(exc)
        log.error("tool_error", tool=tool_name, error=str(exc))
        raise ToolExecutionError(f"Tool '{tool_name}' failed: {exc}") from exc
    finally:
        duration_ms = int((time.monotonic() - start) * 1000)
        audit = ToolExecution(
            user_id=user_id,
            conversation_id=conversation_id,
            tool_name=tool_name,
            args=args,
            result=result if status == "success" else None,
            status=status,
            error_message=error_message,
            duration_ms=duration_ms,
        )
        session.add(audit)
        # Flush without commit — the caller's session manages the transaction

    if tool_name in _FINANCE_TOOLS:
        result = _inject_finance_disclaimer(result)

    return result


def _apply_safety_guardrails(tool_name: str, args: dict[str, Any]) -> None:
    """Raise ToolRejectedError if a tool call violates safety rules."""
    if tool_name in _FINANCE_TOOLS:
        # Finance tools must never receive recommendation-style args
        forbidden_keys = {"asset", "ticker", "buy", "sell", "stock", "crypto_symbol"}
        overlap = forbidden_keys & set(args.keys())
        if overlap:
            raise ToolRejectedError(
                f"Finance tool '{tool_name}' received forbidden args: {overlap}. "
                "This tool only performs simulations, not asset-specific recommendations."
            )


def _inject_finance_disclaimer(result: dict[str, Any]) -> dict[str, Any]:
    result["_disclaimer"] = (
        "SIMULATION UNIQUEMENT. Ceci n'est pas un conseil financier. "
        "Consulte un conseiller agréé avant toute décision d'investissement."
    )
    return result


def tool_result_to_json(result: dict[str, Any]) -> str:
    return json.dumps(result, ensure_ascii=False, default=str)
