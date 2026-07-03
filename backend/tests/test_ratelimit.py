from __future__ import annotations

import app.core.ratelimit as rl
from app.core.ratelimit import SlidingWindowLimiter


def test_limiter_allows_up_to_max():
    lim = SlidingWindowLimiter(3, 60.0)
    assert all(lim.allow("device-a") for _ in range(3))
    assert not lim.allow("device-a")


def test_limiter_keys_are_independent():
    lim = SlidingWindowLimiter(1, 60.0)
    assert lim.allow("device-a")
    assert not lim.allow("device-a")
    assert lim.allow("device-b")


def test_limiter_window_slides(monkeypatch):
    now = [0.0]
    monkeypatch.setattr(rl.time, "monotonic", lambda: now[0])
    lim = SlidingWindowLimiter(2, 10.0)

    assert lim.allow("device-a")
    assert lim.allow("device-a")
    assert not lim.allow("device-a")

    now[0] = 11.0  # la fenêtre est passée
    assert lim.allow("device-a")


def test_limiter_purges_stale_keys(monkeypatch):
    now = [0.0]
    monkeypatch.setattr(rl.time, "monotonic", lambda: now[0])
    monkeypatch.setattr(rl, "_PURGE_THRESHOLD", 2)
    lim = SlidingWindowLimiter(5, 10.0)

    lim.allow("old-1")
    lim.allow("old-2")
    now[0] = 20.0  # les deux clés sont expirées
    lim.allow("fresh")  # dépasse le seuil → purge

    assert set(lim._hits) == {"fresh"}
