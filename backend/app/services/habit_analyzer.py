from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.db import ModuleConfig, ScheduledNotification, SportLog, NutritionLog
from app.core.logging import get_logger

log = get_logger(__name__)

# ── Notification templates per module ────────────────────────────────────────

_NOTIF_TEMPLATES: dict[str, list[dict[str, str]]] = {
    "fitness": [
        {"title": "Séance prévue aujourd'hui", "body": "Tu n'as pas encore enregistré de séance. Lance-toi !"},
        {"title": "Bravo pour ta régularité", "body": "Continue sur ta lancée — tu progresses chaque semaine."},
        {"title": "Rappel sport", "body": "Une courte séance vaut mieux que pas de séance."},
    ],
    "nutrition": [
        {"title": "Bilan calorique", "body": "N'oublie pas de logger ton dernier repas de la journée."},
        {"title": "Hydratation", "body": "As-tu bu suffisamment d'eau aujourd'hui ?"},
        {"title": "Repas du soir", "body": "Pense à enregistrer ton dîner pour rester dans tes objectifs."},
    ],
    "finance": [
        {"title": "Revue mensuelle", "body": "Prends 5 min pour analyser tes dépenses du mois."},
        {"title": "Objectif épargne", "body": "As-tu mis de côté ta cible épargne ce mois-ci ?"},
    ],
    "mobility": [
        {"title": "Niveau carburant", "body": "Pense à vérifier ton carburant avant ta prochaine sortie."},
    ],
    "productivity": [
        {"title": "Habitudes du jour", "body": "Quelques habitudes attendent d'être cochées aujourd'hui."},
        {"title": "Focus du soir", "body": "Fais le point sur tes tâches avant de terminer ta journée."},
    ],
}


async def analyze_and_schedule(
    session: AsyncSession,
    user_id: uuid.UUID,
    apns_token: str,
) -> list[str]:
    """Analyze user habits and schedule relevant notifications.

    Returns list of notification IDs scheduled.
    """
    scheduled_ids: list[str] = []

    # Get module configs to know which modules are active
    config_result = await session.execute(
        select(ModuleConfig).where(ModuleConfig.user_id == user_id)
    )
    configs = {mc.module_type: mc.config for mc in config_result.scalars().all()}

    now = datetime.now(tz=timezone.utc)

    # ── Fitness : le module s'appelle "fitness" partout (cf. _VALID_MODULES),
    # l'ancienne clé "sport" ne matchait jamais aucune config réelle.
    if "fitness" in configs:
        sport_cfg = configs["fitness"]
        sessions_per_week = int(sport_cfg.get("sessions_per_week", 3))
        last_session = await session.execute(
            select(func.max(SportLog.logged_at)).where(SportLog.user_id == user_id)
        )
        last_ts = last_session.scalar_one()
        days_since = (now - last_ts).days if last_ts else 99
        ideal_gap_days = 7 / sessions_per_week

        if days_since >= ideal_gap_days:
            reminder_time_str = sport_cfg.get("reminder_time", "18:00")
            scheduled_for = _next_occurrence(reminder_time_str)
            notif = _pick_template("fitness", 0)
            nid = await _schedule_notification(
                session, user_id, notif, "fitness", "lifeos://module/fitness", scheduled_for
            )
            if nid:
                scheduled_ids.append(nid)

    # ── Nutrition: daily calorie log reminder at 20:00 ───────────────────────
    if "nutrition" in configs:
        today_logs = await session.execute(
            select(func.count(NutritionLog.id)).where(
                NutritionLog.user_id == user_id,
                NutritionLog.logged_at >= now.replace(hour=0, minute=0, second=0, microsecond=0),
            )
        )
        log_count = today_logs.scalar_one() or 0
        if log_count < 2:
            scheduled_for = _next_occurrence("20:00")
            notif = _pick_template("nutrition", 0)
            nid = await _schedule_notification(
                session, user_id, notif, "nutrition", "lifeos://module/nutrition", scheduled_for
            )
            if nid:
                scheduled_ids.append(nid)

    # ── Other modules: generic weekly reminder ────────────────────────────────
    for module in ("finance", "productivity"):
        if module in configs:
            templates = _NOTIF_TEMPLATES.get(module, [])
            if templates:
                scheduled_for = now + timedelta(days=7)
                notif = templates[0]
                nid = await _schedule_notification(
                    session, user_id, notif, module, f"lifeos://module/{module}", scheduled_for
                )
                if nid:
                    scheduled_ids.append(nid)

    log.info("notifications_scheduled", user_id=str(user_id), count=len(scheduled_ids))
    return scheduled_ids


async def _schedule_notification(
    session: AsyncSession,
    user_id: uuid.UUID,
    template: dict[str, str],
    module_type: str,
    deep_link: str,
    scheduled_for: datetime,
) -> str | None:
    # Avoid duplicate: check if same module notification is already pending
    existing = await session.execute(
        select(ScheduledNotification).where(
            ScheduledNotification.user_id == user_id,
            ScheduledNotification.module_type == module_type,
            ScheduledNotification.sent.is_(False),
            ScheduledNotification.scheduled_for > datetime.now(tz=timezone.utc),
        )
    )
    if existing.scalar_one_or_none():
        return None  # already scheduled

    notif = ScheduledNotification(
        user_id=user_id,
        title=template["title"],
        body=template["body"],
        module_type=module_type,
        deep_link=deep_link,
        scheduled_for=scheduled_for,
    )
    session.add(notif)
    await session.flush()
    return str(notif.id)


def _next_occurrence(time_str: str) -> datetime:
    """Return the next datetime for a HH:MM time string (today or tomorrow)."""
    now = datetime.now(tz=timezone.utc)
    h, m = map(int, time_str.split(":"))
    candidate = now.replace(hour=h, minute=m, second=0, microsecond=0)
    if candidate <= now:
        candidate += timedelta(days=1)
    return candidate


def _pick_template(module: str, index: int) -> dict[str, str]:
    templates = _NOTIF_TEMPLATES.get(module, [])
    if not templates:
        return {"title": "LifeOS", "body": "N'oublie pas de mettre à jour ton module."}
    return templates[index % len(templates)]
