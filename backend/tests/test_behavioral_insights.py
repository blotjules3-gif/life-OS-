from __future__ import annotations

from datetime import date, datetime, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest

from app.services.behavioral_insights import compute_insights


def _row(days_ago: int, energy_score: int | None = None, **extra):
    # La colonne checkin_date est un DateTime en base : les rows arrivent
    # en datetime, pas en date ni en str — c'est ce qui crashait avant.
    dt = datetime.combine(date.today() - timedelta(days=days_ago), datetime.min.time())
    defaults = dict(
        checkin_date=dt,
        energy_score=energy_score,
        sleep_hours=None,
        water_ml=None,
        habits_done=None,
        habits_total=None,
        mood=None,
    )
    defaults.update(extra)
    return SimpleNamespace(**defaults)


def _session_with(rows):
    scalars = MagicMock()
    scalars.all.return_value = rows
    result = MagicMock()
    result.scalars.return_value = scalars
    session = MagicMock()
    session.execute = AsyncMock(return_value=result)
    return session


@pytest.mark.asyncio
async def test_six_scored_checkins_datetime_rows_do_not_crash():
    # 6+ check-ins scorés = la branche tendance s'active. Avant le fix,
    # datetime >= str levait TypeError pour tout user engagé.
    rows = [_row(d, energy_score=50) for d in range(12)]
    insights = await compute_insights(_session_with(rows), user_id="u1")
    assert isinstance(insights, list)


@pytest.mark.asyncio
async def test_energy_trend_week_over_week():
    rows = [_row(d, energy_score=80) for d in range(7)] + [
        _row(d, energy_score=60) for d in range(7, 14)
    ]
    insights = await compute_insights(_session_with(rows), user_id="u1")
    trend = [i for i in insights if "progressé" in i]
    assert len(trend) == 1
    assert "20 pts" in trend[0]


@pytest.mark.asyncio
async def test_fewer_than_three_checkins_returns_empty():
    rows = [_row(0, energy_score=70), _row(1, energy_score=65)]
    insights = await compute_insights(_session_with(rows), user_id="u1")
    assert insights == []
