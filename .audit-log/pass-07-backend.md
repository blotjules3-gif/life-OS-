# Passe 07 — Secteur Backend Python (FastAPI)

Date : 2026-07-13
Fichiers audités : ~40 (backend/app/, ~5673 lignes)
Méthode : lecture des points d'entrée (main, config, dependencies, database, ratelimit, endpoints/chat, endpoints/energy) + grep transverse (bare except, SQL injection, TODO/FIXME, unbounded query params).

## Constatations

### Important (risque DoS / DB pressure)

**I1. `endpoints/energy.py:140` — `days: int = 7` sans borne**

```python
async def get_history(
    device_id: str,
    days: int = 7,
    ...
```

Query param `days` non validé → un client peut envoyer `days=1000000` et déclencher un `SELECT ... LIMIT 1000000` qui rame ou explose la mémoire. Autres endpoints déjà bornés (rate limit chat, `min_length/max_length` sur les schemas). Seul point d'entrée oublié.

Fix : `days: int = Query(default=7, ge=1, le=90)` + import Query.

## Application

- `endpoints/energy.py:5` — ajout `Query` à l'import fastapi
- `endpoints/energy.py:140` — validation borne 1..90
- Syntaxe Python vérifiée (`python3 -c "ast.parse(...)"` OK)

## Absents / vérifiés

- **CORS** : `settings.allowed_origins` par défaut vide, override env (fixé passe 01 côté Services + fixed dans main.py par les commits précédents)
- **API key** : `X-API-Key` avec key primaire + secondaire (rotation propre), 401 sur invalid
- **Rate limiting** : `SlidingWindowLimiter` per-device, minute + heure, mémoire single-process (documenté), purge auto au-delà de 10k clés
- **SQL** : SQLAlchemy async partout, pas de f-string dans les queries, pas de format()
- **Bare except** : 1 seule occurrence (`database.py:44`) et légitime (rollback + reraise)
- **Docs** : `/docs` et `/redoc` masqués en prod via `settings.debug`
- **Metrics** : `/metrics` derrière header `X-Metrics-Key`
- **LLM key check** : ping au démarrage → log warning si invalide
- **Schemas** : Pydantic Field avec min/max_length sur toutes les entrées user
- **checkin_date** : datetime column vs date query param → SQLAlchemy/asyncpg cast → OK

## Bilan Backend

Backend en bon état sécuritaire. 1 hardening simple appliqué (borne sur days). Le reste des endpoints est déjà propre (validation Pydantic, dépendances auth, dépendances rate-limit).
