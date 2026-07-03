from __future__ import annotations

import time
import uuid
from collections.abc import AsyncIterator
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings
from app.core.exceptions import (
    AgentMaxIterationsError,
    LLMMaxRetriesError,
    ToolExecutionError,
    ToolRejectedError,
)
from app.core.llm.prompts import build_system_prompt
from app.core.llm.validator import parse_mistral_tool_args
from app.core.llm.wrapper import LLMWrapper
from app.core.tools.definitions import get_tools_for_module
from app.core.tools.executor import execute_tool, tool_result_to_json
from app.core.logging import get_logger

log = get_logger(__name__)

_TECHNICAL_ERROR_REPLY = "Je rencontre un problème technique. Réessaie dans quelques instants."
_EMPTY_RESPONSE_REPLY = "Je n'arrive pas à formuler une réponse. Reformule ta demande."
_BUDGET_REPLY = "Cette demande me prend trop de temps. Ce qui a déjà été fait est enregistré — découpe ta demande et réessaie."


class _TurnState:
    """État mutable partagé par run() et run_stream() pendant un tour d'agent."""

    __slots__ = (
        "messages", "tool_context", "tools_executed", "module_config_updated",
        "goals_updated", "pending_actions", "recent_tool_calls", "empty_response_count",
    )

    def __init__(self, messages: list[dict[str, Any]], tool_context: dict[str, Any]) -> None:
        self.messages = messages
        self.tool_context = tool_context
        self.tools_executed: list[str] = []
        self.module_config_updated = False
        self.goals_updated = False
        self.pending_actions: list[dict[str, Any]] = []
        self.recent_tool_calls: list[str] = []  # dedup identical consecutive calls
        self.empty_response_count = 0

    def result(self, reply: str) -> AgentResult:
        return AgentResult(
            reply=reply,
            tools_executed=self.tools_executed,
            module_config_updated=self.module_config_updated,
            goals_updated=self.goals_updated,
            actions=self.pending_actions,
        )


class AgentOrchestrator:
    """Runs the LLM agent loop for a single user turn.

    Loop:
      1. Build system prompt + conversation history + user message
      2. Call LLM with module-scoped tools
      3. If tool calls → execute each → append results → loop
      4. If text reply → return it
      5. Stop after max_iterations to prevent runaway loops

    The orchestrator is stateless per request — it receives all context from
    the caller and returns a result dict. Persistence (messages, tool logs) is
    handled by the session passed in.
    """

    def __init__(self, settings: Settings) -> None:
        self._llm = LLMWrapper(settings)
        self._max_iterations = settings.llm_max_agent_iterations
        self._soft_budget = settings.agent_soft_budget_seconds
        self._hard_budget = settings.agent_hard_budget_seconds

    @staticmethod
    def _init_state(
        module_type: str | None,
        module_config: dict[str, Any],
        user_name: str | None,
        user_gender: str | None,
        user_context: str | None,
        memory_context: str | None,
        conversation_history: list[dict[str, Any]],
        user_message: str,
        user_id: uuid.UUID,
    ) -> tuple[list[dict[str, Any]], _TurnState]:
        system_prompt = build_system_prompt(
            module_type, module_config, user_name, user_gender, user_context, memory_context,
        )
        tools = get_tools_for_module(module_type)
        messages: list[dict[str, Any]] = [
            {"role": "system", "content": system_prompt},
            *conversation_history,
            {"role": "user", "content": user_message},
        ]
        tool_context: dict[str, Any] = {
            "user_id": str(user_id),
            "module_type": module_type,
            "module_config": module_config,
        }
        return tools, _TurnState(messages, tool_context)

    async def run(
        self,
        user_message: str,
        conversation_history: list[dict[str, Any]],
        module_type: str | None,
        module_config: dict[str, Any],
        user_id: uuid.UUID,
        user_name: str | None,
        user_gender: str | None,
        conversation_id: uuid.UUID,
        session: AsyncSession,
        user_context: str | None = None,
        memory_context: str | None = None,
    ) -> AgentResult:
        """Execute one full agent turn and return the result.

        Returns AgentResult containing the final text reply and metadata.
        """
        tools, state = self._init_state(
            module_type, module_config, user_name, user_gender,
            user_context, memory_context, conversation_history, user_message, user_id,
        )

        for iteration in range(self._max_iterations):
            log.info(
                "agent_iteration",
                iteration=iteration + 1,
                max=self._max_iterations,
                message_count=len(state.messages),
            )

            try:
                text_reply, llm_tool_calls = await self._llm.chat(messages=state.messages, tools=tools)
            except LLMMaxRetriesError as exc:
                log.error("agent_llm_failed", error=str(exc))
                return AgentResult(
                    reply=_TECHNICAL_ERROR_REPLY,
                    tools_executed=[],
                    module_config_updated=False,
                    goals_updated=False,
                    error=str(exc),
                )

            # ── Terminal: text response ────────────────────────────────────────
            if text_reply:
                log.info("agent_completed", iterations=iteration + 1)
                return state.result(text_reply)

            # ── Tool calls ────────────────────────────────────────────────────
            if not llm_tool_calls:
                state.empty_response_count += 1
                log.warning("agent_empty_response", iteration=iteration + 1, count=state.empty_response_count)
                if state.empty_response_count >= 2:
                    log.error("agent_repeated_empty_response", iterations=iteration + 1)
                    return state.result(_EMPTY_RESPONSE_REPLY)
                continue
            state.empty_response_count = 0

            await self._process_tool_calls(state, llm_tool_calls, user_id, conversation_id, session)

        # Exceeded max iterations
        log.error("agent_max_iterations_exceeded", max=self._max_iterations)
        raise AgentMaxIterationsError(
            f"Agent did not reach a conclusion after {self._max_iterations} iterations."
        )

    async def run_stream(
        self,
        user_message: str,
        conversation_history: list[dict[str, Any]],
        module_type: str | None,
        module_config: dict[str, Any],
        user_id: uuid.UUID,
        user_name: str | None,
        user_gender: str | None,
        conversation_id: uuid.UUID,
        session: AsyncSession,
        user_context: str | None = None,
        memory_context: str | None = None,
    ) -> AsyncIterator[tuple[str, Any]]:
        """Version streamée de run().

        Yields:
          ("token", str)          — delta de texte de la réponse finale
          ("tool", str)           — nom d'un outil sur le point de s'exécuter
          ("result", AgentResult) — terminal, réponse complète pour persistance
          ("error", str)          — terminal, échec (le client retombe sur /chat)
        """
        tools, state = self._init_state(
            module_type, module_config, user_name, user_gender,
            user_context, memory_context, conversation_history, user_message, user_id,
        )

        for iteration in range(self._max_iterations):
            log.info(
                "agent_stream_iteration",
                iteration=iteration + 1,
                max=self._max_iterations,
                message_count=len(state.messages),
            )

            text_reply: str | None = None
            llm_tool_calls: list[Any] = []
            streamed_tokens = False
            try:
                async for kind, payload in self._llm.chat_stream(messages=state.messages, tools=tools):
                    if kind == "token":
                        streamed_tokens = True
                        yield ("token", payload)
                    elif kind == "text":
                        text_reply = payload
                    elif kind == "tool_calls":
                        llm_tool_calls = payload
            except Exception as exc:
                log.error("agent_stream_llm_failed", error=str(exc), mid_reply=streamed_tokens)
                yield ("error", _TECHNICAL_ERROR_REPLY)
                return

            if text_reply:
                log.info("agent_stream_completed", iterations=iteration + 1)
                yield ("result", state.result(text_reply))
                return

            if not llm_tool_calls:
                state.empty_response_count += 1
                log.warning("agent_stream_empty_response", iteration=iteration + 1, count=state.empty_response_count)
                if state.empty_response_count >= 2:
                    yield ("result", state.result(_EMPTY_RESPONSE_REPLY))
                    return
                continue
            state.empty_response_count = 0

            for tc in llm_tool_calls:
                yield ("tool", tc.function.name)

            await self._process_tool_calls(state, llm_tool_calls, user_id, conversation_id, session)

        log.error("agent_stream_max_iterations_exceeded", max=self._max_iterations)
        yield ("error", "L'agent n'a pas pu conclure. Réessaie.")

    async def _process_tool_calls(
        self,
        state: _TurnState,
        llm_tool_calls: list[Any],
        user_id: uuid.UUID,
        conversation_id: uuid.UUID,
        session: AsyncSession,
    ) -> None:
        """Execute every tool call and append results to the message list."""
        state.messages.append({
            "role": "assistant",
            "content": "",
            "tool_calls": llm_tool_calls,
        })

        for tc in llm_tool_calls:
            tool_name = tc.function.name
            try:
                tool_args = parse_mistral_tool_args(tc.function.arguments)
            except Exception as exc:
                log.warning("tool_arg_parse_error", tool=tool_name, error=str(exc))
                state.messages.append(self._llm.build_tool_result_message(
                    tc.id, tool_name,
                    tool_result_to_json({
                        "error": f"Arguments invalides pour {tool_name}: {exc}. Réessaie avec des arguments corrects.",
                    }),
                ))
                continue

            # Dedup: skip if we're calling the same no-arg tool twice in a row
            call_signature = f"{tool_name}:{tool_args}"
            if call_signature in state.recent_tool_calls[-3:] and not tool_args:
                log.warning("agent_duplicate_tool_call", tool=tool_name)
                state.messages.append(self._llm.build_tool_result_message(
                    tc.id, tool_name,
                    tool_result_to_json({"info": "Résultat identique au précédent appel — utilise le contexte déjà reçu."}),
                ))
                continue
            state.recent_tool_calls.append(call_signature)
            if len(state.recent_tool_calls) > 10:
                state.recent_tool_calls.pop(0)

            log.info("agent_calling_tool", tool=tool_name, args=tool_args)

            try:
                result = await execute_tool(
                    tool_name=tool_name,
                    args=tool_args,
                    user_id=user_id,
                    conversation_id=conversation_id,
                    session=session,
                    context=state.tool_context,
                )
                state.tools_executed.append(tool_name)

                if tool_name == "update_module_config":
                    state.module_config_updated = True
                if tool_name in ("create_goal", "delete_goal"):
                    state.goals_updated = True
                if tool_name == "create_habit" and isinstance(result, dict):
                    state.pending_actions.append({
                        "type": "create_habit",
                        "title": result.get("title"),
                        "module": result.get("module"),
                    })
                if tool_name == "create_todo" and isinstance(result, dict):
                    state.pending_actions.append({
                        "type": "create_todo",
                        "title": result.get("title"),
                        "module": result.get("module"),
                        "priority": result.get("priority", 2),
                    })
                if tool_name == "schedule_followup" and isinstance(result, dict):
                    delay_h = float(result.get("delay_hours", 1))
                    state.pending_actions.append({
                        "type": "schedule_reminder",
                        "reminder_body": result.get("message"),
                        "module": result.get("module"),
                        "delay_seconds": int(delay_h * 3600),
                    })
                if tool_name == "add_module" and isinstance(result, dict):
                    state.pending_actions.append({
                        "type": "add_module",
                        "module": result.get("module"),
                        "title": result.get("reason") or "Module ajouté",
                    })
                if tool_name == "remove_module" and isinstance(result, dict):
                    state.pending_actions.append({
                        "type": "remove_module",
                        "module": result.get("module"),
                        "title": result.get("reason") or "Module retiré",
                    })
                if tool_name == "create_life_challenge" and isinstance(result, dict):
                    state.pending_actions.append({
                        "type": "create_challenge",
                        "title": result.get("title"),
                        "module": result.get("challenge_type"),
                        "challenge_id": result.get("challenge_id"),
                        "daily_target": result.get("daily_target"),
                        "unit": result.get("unit"),
                        "duration_days": result.get("duration_days"),
                    })
                if tool_name == "update_user_profile" and isinstance(result, dict):
                    if result.get("gender"):
                        state.tool_context["user_gender"] = result["gender"]

            except ToolRejectedError as exc:
                log.warning("tool_rejected", tool=tool_name, reason=str(exc))
                result = {
                    "error": f"Outil refusé : {exc}",
                    "rejected": True,
                    "action_requise": "Ne renouvelle pas cet appel. Informe l'utilisateur que cette action n'est pas disponible ou propose une alternative.",
                }
            except (ToolExecutionError, Exception) as exc:
                log.error("tool_execution_failed", tool=tool_name, error=str(exc))
                result = {
                    "error": str(exc),
                    "action_requise": f"L'outil {tool_name} a échoué. Essaie une approche différente ou explique à l'utilisateur ce qui ne fonctionne pas.",
                }

            state.messages.append(self._llm.build_tool_result_message(
                tc.id, tool_name, tool_result_to_json(result),
            ))


class AgentResult:
    __slots__ = ("reply", "tools_executed", "module_config_updated", "goals_updated", "actions", "error")

    def __init__(
        self,
        reply: str,
        tools_executed: list[str],
        module_config_updated: bool,
        goals_updated: bool,
        actions: list[dict[str, Any]] | None = None,
        error: str | None = None,
    ) -> None:
        self.reply = reply
        self.tools_executed = tools_executed
        self.module_config_updated = module_config_updated
        self.goals_updated = goals_updated
        self.actions = actions or []
        self.error = error
