from __future__ import annotations

import time
from collections import deque
from functools import lru_cache

from app.config import get_settings

# Nombre de clés au-delà duquel on purge les entrées expirées.
# Protège la mémoire si des device_id jetables spamment l'API.
_PURGE_THRESHOLD = 10_000


class SlidingWindowLimiter:
    """Limiteur en mémoire à fenêtre glissante, par clé.

    Valide tant que l'API tourne dans un seul process uvicorn (cas Railway) :
    aucune coordination inter-process nécessaire. À remplacer par Redis
    si l'API passe un jour en multi-workers.
    """

    def __init__(self, max_calls: int, window_seconds: float) -> None:
        self._max_calls = max_calls
        self._window = window_seconds
        self._hits: dict[str, deque[float]] = {}

    def allow(self, key: str) -> bool:
        now = time.monotonic()
        cutoff = now - self._window
        hits = self._hits.setdefault(key, deque())
        while hits and hits[0] <= cutoff:
            hits.popleft()
        if len(hits) >= self._max_calls:
            return False
        hits.append(now)
        if len(self._hits) > _PURGE_THRESHOLD:
            self._purge(cutoff)
        return True

    def _purge(self, cutoff: float) -> None:
        stale = [k for k, v in self._hits.items() if not v or v[-1] <= cutoff]
        for k in stale:
            del self._hits[k]


@lru_cache(maxsize=1)
def get_chat_limiters() -> tuple[SlidingWindowLimiter, SlidingWindowLimiter]:
    settings = get_settings()
    return (
        SlidingWindowLimiter(settings.chat_rate_limit_per_minute, 60.0),
        SlidingWindowLimiter(settings.chat_rate_limit_per_hour, 3600.0),
    )
