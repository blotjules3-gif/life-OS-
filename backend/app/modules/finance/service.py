from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.db import FinanceLog
from app.modules.base import BaseModuleService


# ── Allocation presets by risk profile ──────────────────────────────────────
# These are generic educational splits — NOT investment advice.
_ALLOCATION_PRESETS: dict[str, dict[str, float]] = {
    "conservative": {
        "fonds_monétaires": 0.50,
        "obligations": 0.35,
        "actions": 0.10,
        "autres": 0.05,
    },
    "moderate": {
        "fonds_monétaires": 0.20,
        "obligations": 0.30,
        "actions": 0.40,
        "immobilier_scpi": 0.10,
    },
    "aggressive": {
        "fonds_monétaires": 0.05,
        "obligations": 0.10,
        "actions": 0.70,
        "actifs_alternatifs": 0.15,
    },
}


class FinanceService(BaseModuleService):

    async def analyze_cashflow(
        self,
        income: float,
        fixed_expenses: float,
        variable_expenses: float,
        period_label: str | None = None,
    ) -> dict[str, Any]:
        total_expenses = fixed_expenses + variable_expenses
        balance = income - total_expenses
        savings_capacity = max(0.0, balance)
        expense_ratio = round(total_expenses / income * 100, 1) if income > 0 else 0.0

        entry = FinanceLog(
            user_id=self.user_id,
            income=income,
            fixed_expenses=fixed_expenses,
            variable_expenses=variable_expenses,
            period_label=period_label,
        )
        self.session.add(entry)
        await self.session.flush()

        return {
            "income": income,
            "total_expenses": total_expenses,
            "fixed_expenses": fixed_expenses,
            "variable_expenses": variable_expenses,
            "balance": round(balance, 2),
            "savings_capacity": round(savings_capacity, 2),
            "expense_ratio_pct": expense_ratio,
            "health": "sain" if expense_ratio <= 70 else ("tendu" if expense_ratio <= 90 else "critique"),
        }

    async def compute_investable_amount(
        self,
        income: float,
        total_expenses: float,
        savings_goal_pct: float,
    ) -> dict[str, Any]:
        balance = max(0.0, income - total_expenses)
        savings_amount = round(balance * savings_goal_pct / 100, 2)
        investable = round(max(0.0, balance - savings_amount), 2)
        return {
            "balance": round(balance, 2),
            "savings_amount": savings_amount,
            "savings_goal_pct": savings_goal_pct,
            "investable_amount": investable,
            "note": "Montant disponible AVANT frais de courtage et fiscalité.",
        }

    async def simulate_allocation(
        self,
        amount: float,
        risk_profile: str,
    ) -> dict[str, Any]:
        if risk_profile not in _ALLOCATION_PRESETS:
            return {"error": f"Profil inconnu: {risk_profile}. Choix: conservative, moderate, aggressive"}

        preset = _ALLOCATION_PRESETS[risk_profile]
        split = {category: round(amount * pct, 2) for category, pct in preset.items()}

        return {
            "total_amount": round(amount, 2),
            "risk_profile": risk_profile,
            "allocation": split,
            "is_simulation": True,
        }

    async def get_stats(self, days: int = 30) -> dict[str, Any]:
        return {"note": "Finance stats require cashflow entries."}
