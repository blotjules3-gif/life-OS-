from __future__ import annotations

import json
import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import StreamingResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.agents.orchestrator import AgentOrchestrator, AgentResult
from app.core.exceptions import AgentMaxIterationsError
from app.database import get_session
from app.dependencies import get_orchestrator, verify_api_key
from app.models.db import Conversation, Message, User
from app.schemas.chat import ChatAction, ChatRequest, ChatResponse, ConversationOut
from app.services import module_config as config_svc
from app.services.behavioral_insights import compute_insights
from app.services.user import get_or_create_user
from app.core.logging import get_logger

router = APIRouter(prefix="/chat", tags=["chat"])
log = get_logger(__name__)


async def _prepare_turn(
    body: ChatRequest,
    session: AsyncSession,
) -> tuple[User, Conversation, list[dict], dict, str | None]:
    """Étapes communes à /chat et /chat/stream : user, conversation, historique,
    config module, persistance du message utilisateur, mémoire long terme."""

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
            log.warning("conversation_not_found_creating_new", conversation_id=str(body.conversation_id))

    if not conversation:
        conversation = Conversation(
            user_id=user.id,
            module_type=body.module,
            title=body.message[:60],
        )
        session.add(conversation)
        await session.flush()

    # ── 3. Build conversation history (last 20 messages, skip system init) ────
    # desc + reversed : les 20 plus RÉCENTS en ordre chronologique — asc()
    # renvoyait les 20 plus anciens et figeait le coach sur le début de la conversation.
    history_result = await session.execute(
        select(Message)
        .where(Message.conversation_id == conversation.id)
        .order_by(Message.created_at.desc())
        .limit(20)
    )
    history_messages = list(reversed(history_result.scalars().all()))
    conversation_history = [
        {"role": m.role, "content": m.content}
        for m in history_messages
        if "[PREMIER_LANCEMENT]" not in m.content  # hide init signal from future history
    ]

    # ── 4. Get current module config ──────────────────────────────────────────
    module_config: dict = {}
    if body.module:
        module_config = await config_svc.get_config(session, user.id, body.module)

    # ── 5. Persist user message (system init stored but filtered from history) ─
    user_msg = Message(
        conversation_id=conversation.id,
        role="user",
        content=body.message,
    )
    session.add(user_msg)
    await session.flush()

    # ── 5b. Long-term memory injected directly into the system prompt ─────────
    # Avant : user_notes + insights n'atteignaient le LLM que s'il appelait
    # get_user_context (une itération LLM complète en plus, souvent jamais faite).
    memory_lines: list[str] = []
    if user.user_notes:
        for key, note in list(user.user_notes.items())[:20]:
            value = note.get("value") if isinstance(note, dict) else note
            memory_lines.append(f"- {key}: {value}")
    try:
        insights = await compute_insights(session, user.id)
    except Exception as exc:
        log.warning("behavioral_insights_failed", user_id=str(user.id), error=str(exc))
        insights = []
    if insights:
        memory_lines.append("Tendances observées (30 derniers jours) :")
        memory_lines.extend(f"- {i}" for i in insights)
    memory_context = "\n".join(memory_lines) if memory_lines else None

    return user, conversation, conversation_history, module_config, memory_context


def _build_response(conversation_id: uuid.UUID, result: AgentResult) -> ChatResponse:
    return ChatResponse(
        conversation_id=conversation_id,
        reply=result.reply,
        tool_calls_executed=result.tools_executed,
        module_config_updated=result.module_config_updated,
        goals_updated=result.goals_updated,
        actions=[ChatAction(**a) for a in result.actions],
    )


@router.post("", response_model=ChatResponse, dependencies=[Depends(verify_api_key)])
async def chat(
    body: ChatRequest,
    session: AsyncSession = Depends(get_session),
    orchestrator: AgentOrchestrator = Depends(get_orchestrator),
) -> ChatResponse:
    """Main chat endpoint — processes a user message through the AI agent."""
    user, conversation, conversation_history, module_config, memory_context = await _prepare_turn(body, session)

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
            user_context=body.user_context,
            memory_context=memory_context,
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

    return _build_response(conversation.id, result)


def _sse(event: str, data: str) -> str:
    return f"event: {event}\ndata: {data}\n\n"


@router.post("/stream", dependencies=[Depends(verify_api_key)])
async def chat_stream(
    body: ChatRequest,
    session: AsyncSession = Depends(get_session),
    orchestrator: AgentOrchestrator = Depends(get_orchestrator),
) -> StreamingResponse:
    """Streaming chat (SSE) : le texte arrive token par token.

    Events :
      token → {"t": "..."}          delta de texte
      tool  → {"name": "..."}       outil en cours d'exécution
      done  → ChatResponse JSON     terminal (réponse complète + actions)
      error → {"message": "..."}    terminal (le client retombe sur POST /chat)
    """
    user, conversation, conversation_history, module_config, memory_context = await _prepare_turn(body, session)

    async def event_generator():
        try:
            async for kind, payload in orchestrator.run_stream(
                user_message=body.message,
                conversation_history=conversation_history,
                module_type=body.module,
                module_config=module_config,
                user_id=user.id,
                user_name=user.name,
                user_gender=user.gender,
                conversation_id=conversation.id,
                session=session,
                user_context=body.user_context,
                memory_context=memory_context,
            ):
                if kind == "token":
                    yield _sse("token", json.dumps({"t": payload}, ensure_ascii=False))
                elif kind == "tool":
                    yield _sse("tool", json.dumps({"name": payload}, ensure_ascii=False))
                elif kind == "result":
                    assistant_msg = Message(
                        conversation_id=conversation.id,
                        role="assistant",
                        content=payload.reply,
                    )
                    session.add(assistant_msg)
                    await session.flush()
                    log.info(
                        "chat_stream_complete",
                        user_id=str(user.id),
                        module=body.module,
                        tools=payload.tools_executed,
                    )
                    yield _sse("done", _build_response(conversation.id, payload).model_dump_json())
                elif kind == "error":
                    yield _sse("error", json.dumps({"message": payload}, ensure_ascii=False))
        except Exception as exc:  # jamais de stacktrace dans le flux SSE
            log.error("chat_stream_failed", user_id=str(user.id), error=str(exc))
            yield _sse("error", json.dumps({"message": "Erreur interne. Réessaie."}, ensure_ascii=False))

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
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
