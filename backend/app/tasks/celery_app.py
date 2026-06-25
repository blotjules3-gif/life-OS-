from __future__ import annotations

import asyncio

from celery import Celery
from celery.schedules import crontab

from app.config import get_settings

settings = get_settings()

celery_app = Celery(
    "lifeos_agent",
    broker=settings.redis_url,
    backend=settings.redis_url,
)

celery_app.conf.update(
    task_serializer="json",
    result_serializer="json",
    accept_content=["json"],
    timezone="UTC",
    enable_utc=True,
    beat_schedule={
        "dispatch-notifications-every-5-min": {
            "task": "app.tasks.celery_app.dispatch_notifications_task",
            "schedule": crontab(minute="*/5"),
        },
        "analyze-habits-daily": {
            "task": "app.tasks.celery_app.analyze_habits_task",
            "schedule": crontab(hour="7", minute="0"),
        },
    },
)


def _run_async(coro):
    """Run an async function in a new event loop from Celery (sync context)."""
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


@celery_app.task(name="app.tasks.celery_app.dispatch_notifications_task", bind=True, max_retries=3)
def dispatch_notifications_task(self):
    async def _run():
        from app.database import async_session_factory
        from app.services.notification import APNsClient, dispatch_pending_notifications

        apns = APNsClient(settings)
        async with async_session_factory() as session:
            count = await dispatch_pending_notifications(session, apns)
        return count

    try:
        return _run_async(_run())
    except Exception as exc:
        raise self.retry(exc=exc, countdown=60)


@celery_app.task(name="app.tasks.celery_app.analyze_habits_task", bind=True, max_retries=2)
def analyze_habits_task(self):
    async def _run():
        from sqlalchemy import select
        from app.database import async_session_factory
        from app.models.db import User
        from app.services.habit_analyzer import analyze_and_schedule

        async with async_session_factory() as session:
            result = await session.execute(
                select(User).where(User.apns_token.isnot(None))
            )
            users = result.scalars().all()
            total = 0
            for user in users:
                ids = await analyze_and_schedule(session, user.id, user.apns_token)
                total += len(ids)
            await session.commit()
        return total

    try:
        return _run_async(_run())
    except Exception as exc:
        raise self.retry(exc=exc, countdown=300)
