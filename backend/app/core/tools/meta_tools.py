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


async def handle_create_todo(
    args: dict[str, Any],
    user_id: uuid.UUID,
    session: AsyncSession,
    context: dict[str, Any],
) -> dict[str, Any]:
    # Signal to iOS to create a local TodoItem
    return {
        "action": "create_todo",
        "title": args["title"],
        "module": args.get("module"),
        "priority": args.get("priority", 2),
        "created": True,
    }


async def handle_schedule_followup(
    args: dict[str, Any],
    user_id: uuid.UUID,
    session: AsyncSession,
    context: dict[str, Any],
) -> dict[str, Any]:
    from datetime import datetime, timedelta, timezone
    from app.models.db import ScheduledNotification

    delay_hours = float(args["delay_hours"])
    scheduled_for = datetime.now(tz=timezone.utc) + timedelta(hours=delay_hours)

    notif = ScheduledNotification(
        user_id=user_id,
        title="LifeOS — Suivi",
        body=args["message"],
        module_type=args.get("module"),
        deep_link=f"lifeos://assistant",
        scheduled_for=scheduled_for,
    )
    session.add(notif)
    await session.flush()

    return {
        "scheduled": True,
        "message": args["message"],
        "delay_hours": delay_hours,
        "notification_id": str(notif.id),
    }


async def handle_get_user_context(
    args: dict[str, Any],
    user_id: uuid.UUID,
    session: AsyncSession,
    context: dict[str, Any],
) -> dict[str, Any]:
    from sqlalchemy import select
    from app.models.db import ModuleConfig, User

    config_result = await session.execute(
        select(ModuleConfig).where(ModuleConfig.user_id == user_id)
    )
    configs = {mc.module_type: mc.config for mc in config_result.scalars().all()}

    goals = await goal_svc.list_goals(session, user_id, active_only=True)

    user_result = await session.execute(select(User).where(User.id == user_id))
    user = user_result.scalar_one_or_none()
    user_notes = user.user_notes if user else {}

    return {
        "module_configs": configs,
        "active_goals": goals,
        "goal_count": len(goals),
        "user_notes": user_notes,
    }


async def handle_remember_user_info(
    args: dict[str, Any],
    user_id: uuid.UUID,
    session: AsyncSession,
    context: dict[str, Any],
) -> dict[str, Any]:
    from sqlalchemy import select
    from app.models.db import User

    result = await session.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        return {"saved": False, "error": "User not found"}

    notes = dict(user.user_notes or {})
    notes[args["key"]] = {"value": args["value"], "category": args["category"]}
    user.user_notes = notes
    await session.flush()

    log.info("user_info_remembered", user_id=str(user_id), key=args["key"], category=args["category"])
    return {"saved": True, "key": args["key"], "total_notes": len(notes)}


async def handle_update_user_profile(
    args: dict[str, Any],
    user_id: uuid.UUID,
    session: AsyncSession,
    context: dict[str, Any],
) -> dict[str, Any]:
    from app.services.user import update_user_profile
    return await update_user_profile(
        session=session,
        user_id=user_id,
        name=args.get("name"),
        gender=args.get("gender"),
    )


async def handle_add_module(
    args: dict[str, Any],
    user_id: uuid.UUID,
    session: AsyncSession,
    context: dict[str, Any],
) -> dict[str, Any]:
    module = args["module"]
    reason = args.get("reason", "")
    log.info("module_added", user_id=str(user_id), module=module)
    return {"action": "add_module", "module": module, "reason": reason, "added": True}


async def handle_remove_module(
    args: dict[str, Any],
    user_id: uuid.UUID,
    session: AsyncSession,
    context: dict[str, Any],
) -> dict[str, Any]:
    module = args["module"]
    reason_type = args["reason_type"]
    reason = args.get("reason", "")
    log.info("module_removed", user_id=str(user_id), module=module, reason_type=reason_type)
    return {"action": "remove_module", "module": module, "reason_type": reason_type, "reason": reason, "removed": True}


async def handle_create_life_challenge(
    args: dict[str, Any],
    user_id: uuid.UUID,
    session: AsyncSession,
    context: dict[str, Any],
) -> dict[str, Any]:
    from app.models.db import LifeChallenge

    challenge = LifeChallenge(
        user_id=user_id,
        title=args["title"],
        challenge_type=args["challenge_type"],
        daily_target=args.get("daily_target"),
        unit=args.get("unit"),
        duration_days=args.get("duration_days"),
        notes=args.get("notes"),
    )
    session.add(challenge)
    await session.flush()

    log.info("life_challenge_created", user_id=str(user_id), title=args["title"], type=args["challenge_type"])
    return {
        "created": True,
        "challenge_id": str(challenge.id),
        "title": args["title"],
        "challenge_type": args["challenge_type"],
        "daily_target": args.get("daily_target"),
        "unit": args.get("unit"),
        "duration_days": args.get("duration_days"),
    }


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
