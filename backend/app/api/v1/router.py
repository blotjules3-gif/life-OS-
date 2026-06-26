from fastapi import APIRouter

from app.api.v1.endpoints import chat, modules, goals, challenges

router = APIRouter(prefix="/api/v1")
router.include_router(chat.router)
router.include_router(modules.router)
router.include_router(goals.router)
router.include_router(challenges.router)
