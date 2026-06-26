from __future__ import annotations

from collections import defaultdict
from datetime import date, timedelta
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.db import DailyCheckin


async def compute_insights(session: AsyncSession, user_id: Any) -> list[str]:
    """Analyse les 30 derniers check-ins et retourne des patterns naturels détectés.

    Exemples de sortie :
        "Ton énergie a progressé de 14 pts cette semaine par rapport à la semaine dernière."
        "Tu dors en moyenne 7,2 heures. Tes meilleurs scores arrivent avec 8h+"
        "Les jours où tu bois plus de 2L d'eau, ton énergie est 18 pts plus élevée en moyenne."
        "Tu as complété tes habitudes 5 jours sur 7 cette semaine. C'est ta meilleure série."
    """
    today = date.today()
    thirty_ago = today - timedelta(days=30)

    result = await session.execute(
        select(DailyCheckin)
        .where(
            DailyCheckin.user_id == user_id,
            DailyCheckin.checkin_date >= thirty_ago,
        )
        .order_by(DailyCheckin.checkin_date.asc())
    )
    rows = result.scalars().all()

    if len(rows) < 3:
        return []

    insights: list[str] = []

    # --- 1. Tendance score d'énergie : 7 derniers jours vs 7 précédents ---
    scored = [r for r in rows if r.energy_score is not None]
    if len(scored) >= 6:
        last7 = [r for r in scored if r.checkin_date >= (today - timedelta(days=7)).isoformat()[:10] or
                 (hasattr(r.checkin_date, 'date') and r.checkin_date.date() >= today - timedelta(days=7))]
        prev7 = [r for r in scored if _days_ago(r, today) >= 7 and _days_ago(r, today) < 14]
        if last7 and prev7:
            avg_last = sum(r.energy_score for r in last7) / len(last7)
            avg_prev = sum(r.energy_score for r in prev7) / len(prev7)
            delta = round(avg_last - avg_prev)
            if abs(delta) >= 5:
                direction = "progressé" if delta > 0 else "baissé"
                insights.append(
                    f"Ton Score d'Énergie a {direction} de {abs(delta)} pts cette semaine "
                    f"par rapport à la semaine dernière ({round(avg_last)}/100 vs {round(avg_prev)}/100)."
                )

    # --- 2. Durée de sommeil et corrélation avec le score ---
    sleep_rows = [r for r in rows if r.sleep_hours is not None and r.energy_score is not None]
    if len(sleep_rows) >= 5:
        avg_hours = sum(float(r.sleep_hours) for r in sleep_rows) / len(sleep_rows)
        short = [r for r in sleep_rows if float(r.sleep_hours) < 7]
        long_ = [r for r in sleep_rows if float(r.sleep_hours) >= 8]
        if short and long_:
            avg_short_score = sum(r.energy_score for r in short) / len(short)
            avg_long_score  = sum(r.energy_score for r in long_) / len(long_)
            diff = round(avg_long_score - avg_short_score)
            if diff >= 8:
                insights.append(
                    f"Avec 8h+ de sommeil, ton énergie est {diff} pts plus élevée qu'avec moins de 7h "
                    f"(tu dors en moyenne {avg_hours:.1f}h)."
                )
        elif len(sleep_rows) >= 3:
            insights.append(f"Tu dors en moyenne {avg_hours:.1f} heures selon tes bilans.")

    # --- 3. Hydratation vs score d'énergie ---
    water_rows = [r for r in rows if r.water_ml is not None and r.energy_score is not None]
    if len(water_rows) >= 5:
        well_hydrated = [r for r in water_rows if r.water_ml >= 2000]
        less_hydrated = [r for r in water_rows if r.water_ml < 1500]
        if well_hydrated and less_hydrated:
            avg_wh = sum(r.energy_score for r in well_hydrated) / len(well_hydrated)
            avg_lh = sum(r.energy_score for r in less_hydrated) / len(less_hydrated)
            diff = round(avg_wh - avg_lh)
            if diff >= 8:
                insights.append(
                    f"Les jours où tu bois plus de 2L d'eau, ton énergie est {diff} pts plus élevée en moyenne."
                )

    # --- 4. Habitudes : meilleure série de la période ---
    habit_rows = [r for r in rows if r.habits_done is not None and r.habits_total and r.habits_total > 0]
    if habit_rows:
        full_days = [r for r in habit_rows if r.habits_done >= r.habits_total]
        pct = round(len(full_days) / len(habit_rows) * 100)
        if pct >= 70:
            insights.append(
                f"Tu complètes toutes tes habitudes {pct}% des jours sur les 30 derniers jours. Excellent rythme."
            )
        elif pct < 40 and len(habit_rows) >= 7:
            insights.append(
                f"Tu complètes toutes tes habitudes seulement {pct}% des jours. "
                "Essaie de réduire leur nombre pour augmenter ta régularité."
            )

    # --- 5. Humeur vs score ---
    mood_rows = [r for r in rows if r.mood is not None and r.energy_score is not None]
    if len(mood_rows) >= 7:
        good_mood = [r for r in mood_rows if r.mood >= 4]
        bad_mood  = [r for r in mood_rows if r.mood <= 2]
        if good_mood and bad_mood:
            avg_gm = sum(r.energy_score for r in good_mood) / len(good_mood)
            avg_bm = sum(r.energy_score for r in bad_mood) / len(bad_mood)
            diff = round(avg_gm - avg_bm)
            if diff >= 10:
                insights.append(
                    f"Quand ton humeur est bonne, ton Score d'Énergie est {diff} pts plus élevé. "
                    "L'état mental a un impact direct sur ton énergie."
                )

    return insights[:4]  # max 4 insights pour ne pas noyer


def _days_ago(row: DailyCheckin, today: date) -> int:
    d = row.checkin_date
    if hasattr(d, 'date'):
        d = d.date()
    return (today - d).days
