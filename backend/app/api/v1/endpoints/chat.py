from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.agents.orchestrator import AgentOrchestrator
from app.core.exceptions import AgentMaxIterationsError
from app.database import get_session
from app.dependencies import get_orchestrator, verify_api_key
from app.models.db import Conversation, Message
from app.schemas.chat import ChatAction, ChatRequest, ChatResponse, ConversationOut
from app.services import module_config as config_svc
from app.services.user import get_or_create_user
from app.core.logging import get_logger

router = APIRouter(prefix="/chat", tags=["chat"])
log = get_logger(__name__)


@router.post("", response_model=ChatResponse, dependencies=[Depends(verify_api_key)])
async def chat(
    body: ChatRequest,
    session: AsyncSession = Depends(get_session),
    orchestrator: AgentOrchestrator = Depends(get_orchestrator),
) -> ChatResponse:
    """Main chat endpoint — processes a user message through the AI agent."""

    # ── 1. Ensure user exists ─────────────────────────────────────────────────
    user = await get_or_create_user(session, body.device_id, apns_token=body.apns_token)

    # ── 2. Resolve or create conversation ─────────────────────────────────────
    conversation: Conversation | None = None
    if body.conversation_id:
        result = await session.execute(
            select(Conversation)
            .options(selectinload(Conversation.messages))
            .where(Conversation.id == body.conversation_id, Conversation.user_id == user.id)
        )
        conversation = result.scalar_one_or_none()
        if not conversation:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Conversation {body.conversation_id} not found for this user.",
            )

    if not conversation:
        conversation = Conversation(
            user_id=user.id,
            module_type=body.module,
            title=body.message[:60],
        )
        session.add(conversation)
        await session.flush()

    # ── 3. Build conversation history (last 20 messages) ──────────────────────
    history_result = await session.execute(
        select(Message)
        .where(Message.conversation_id == conversation.id)
        .order_by(Message.created_at.asc())
        .limit(20)
    )
    history_messages = history_result.scalars().all()
    conversation_history = [
        {"role": m.role, "content": m.content}
        for m in history_messages
    ]

    # ── 4. Get current module config ──────────────────────────────────────────
    module_config: dict = {}
    if body.module:
        module_config = await config_svc.get_config(session, user.id, body.module)

    # ── 5. Persist user message ───────────────────────────────────────────────
    user_msg = Message(
        conversation_id=conversation.id,
        role="user",
        content=body.message,
    )
    session.add(user_msg)
    await session.flush()

    # ── 6. Run agent ──────────────────────────────────────────────────────────
    try:
        result = await orchestrator.run(
            user_message=body.message,
            conversation_history=conversation_history,
            module_type=body.module,
            module_config=module_config,
            user_id=user.id,
            user_name=user.name,
            user_gender=user.gender,
            conversation_id=conversation.id,
            session=session,
        )
    except AgentMaxIterationsError as exc:
        log.error("chat_agent_max_iterations", user_id=str(user.id))
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="L'agent n'a pas pu conclure. Réessaie.",
        ) from exc

    # ── 7. Persist assistant reply ────────────────────────────────────────────
    assistant_msg = Message(
        conversation_id=conversation.id,
        role="assistant",
        content=result.reply,
    )
    session.add(assistant_msg)

    log.info(
        "chat_complete",
        user_id=str(user.id),
        module=body.module,
        tools=result.tools_executed,
    )

    return ChatResponse(
        conversation_id=conversation.id,
        reply=result.reply,
        tool_calls_executed=result.tools_executed,
        module_config_updated=result.module_config_updated,
        goals_updated=result.goals_updated,
        actions=[ChatAction(**a) for a in result.actions],
    )


@router.get(
    "/history/{conversation_id}",
    response_model=ConversationOut,
    dependencies=[Depends(verify_api_key)],
)
async def get_conversation(
    conversation_id: uuid.UUID,
    device_id: str,
    session: AsyncSession = Depends(get_session),
) -> ConversationOut:
    user = await get_or_create_user(session, device_id)
    result = await session.execute(
        select(Conversation)
        .options(selectinload(Conversation.messages))
        .where(Conversation.id == conversation_id, Conversation.user_id == user.id)
    )
    conv = result.scalar_one_or_none()
    if not conv:
        raise HTTPException(status_code=404, detail="Conversation not found.")
    return ConversationOut.model_validate(conv)
