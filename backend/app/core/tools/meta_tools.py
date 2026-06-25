from __future__ import annotations

"""
Tool handlers for meta / personalization tools:
- get_module_config
- update_module_config
- list_goals
- create_goal
- delete_goal
- ask_clarification
"""

import uuid
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.services import goal as goal_svc
from app.services import module_config as config_svc
from app.core.logging import get_logger

log = get_logger(__name__)


async def handle_get_module_config(
    args: dict[str, Any],
    user_id: uuid.UUID,
    session: AsyncSession,
    context: dict[str, Any],
) -> dict[str, Any]:
    module = args["module"]
    config = await config_svc.get_config(session, user_id, module)
    return {"module": module, "config": config}


async def handle_update_module_config(
    args: dict[str, Any],
    user_id: uuid.UUID,
    session: AsyncSession,
    context: dict[str, Any],
) -> dict[str, Any]:
    module = args["module"]
    config_delta = args["config"]
    saved = await config_svc.upsert_config(session, user_id, module, config_delta)
    return {"module": module, "updated": True, "config": saved}


async def handle_list_goals(
    args: dict[str, Any],
    user_id: uuid.UUID,
    session: AsyncSession,
    context: dict[str, Any],
) -> dict[str, Any]:
    module = args.get("module") or context.get("module_type")
    active_only = bool(args.get("active_only", True))
    goals = await goal_svc.list_goals(session, user_id, module_type=module, active_only=active_only)
    return {"goals": goals, "count": len(goals)}


async def handle_create_goal(
    args: dict[str, Any],
    user_id: uuid.UUID,
    session: AsyncSession,
    context: dict[str, Any],
) -> dict[str, Any]:
    module = args.get("module") or context.get("module_type", "general")
    return await goal_svc.create_goal(
        session=session,
        user_id=user_id,
        module_type=module,
        title=args["title"],
        description=args.get("description"),
        target_value=args.get("target_value"),
        unit=args.get("unit"),
        frequency=args.get("frequency"),
        priority=int(args.get("priority", 1)),
    )


async def handle_delete_goal(
    args: dict[str, Any],
    user_id: uuid.UUID,
    session: AsyncSession,
    context: dict[str, Any],
) -> dict[str, Any]:
    return await goal_svc.deactivate_goal(session, user_id, args["goal_id"])


async def handle_ask_clarification(
    args: dict[str, Any],
    user_id: uuid.UUID,
    session: AsyncSession,
    context: dict[str, Any],
) -> dict[str, Any]:
    # This tool is a signal to the orchestrator — the result becomes the LLM's next prompt context
    return {
        "clarification_needed": True,
        "question": args["question"],
        "options": args.get("options", []),
    }
