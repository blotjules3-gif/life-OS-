from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import ToolRejectedError
from app.modules.finance.service import FinanceService

_DISCLAIMER = (
    "SIMULATION UNIQUEMENT — pas un conseil financier. "
    "Consulte un conseiller agréé pour toute décision d'investissement."
)


async def handle_analyze_cashflow(
    args: dict[str, Any],
    user_id: uuid.UUID,
    session: AsyncSession,
    context: dict[str, Any],
) -> dict[str, Any]:
    svc = FinanceService(session=session, user_id=user_id)
    return await svc.analyze_cashflow(
        income=float(args["income"]),
        fixed_expenses=float(args["fixed_expenses"]),
        variable_expenses=float(args["variable_expenses"]),
        period_label=args.get("period_label"),
    )


async def handle_compute_investable_amount(
    args: dict[str, Any],
    user_id: uuid.UUID,
    session: AsyncSession,
    context: dict[str, Any],
) -> dict[str, Any]:
    svc = FinanceService(session=session, user_id=user_id)
    return await svc.compute_investable_amount(
        income=float(args["income"]),
        total_expenses=float(args["total_expenses"]),
        savings_goal_pct=float(args["savings_goal_pct"]),
    )


async def handle_simulate_allocation(
    args: dict[str, Any],
    user_id: uuid.UUID,
    session: AsyncSession,
    context: dict[str, Any],
) -> dict[str, Any]:
    amount = float(args["amount"])
    if amount < 0:
        raise ToolRejectedError("Le montant doit être positif.")

    svc = FinanceService(session=session, user_id=user_id)
    return await svc.simulate_allocation(
        amount=amount,
        risk_profile=args["risk_profile"],
    )
