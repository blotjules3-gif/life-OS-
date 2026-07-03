from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator
from typing import Any

import httpx
from mistralai import Mistral
from mistralai.models import AssistantMessage, SDKError, SystemMessage, ToolMessage, UserMessage
from tenacity import (
    AsyncRetrying,
    RetryError,
    retry_if_exception,
    stop_after_attempt,
    wait_exponential,
)

from app.config import Settings
from app.core.exceptions import LLMMaxRetriesError, LLMValidationError
from app.core.llm.validator import extract_text_or_tool_calls
from app.core.logging import get_logger

log = get_logger(__name__)


def _is_transient(exc: BaseException) -> bool:
    # Ne rejouer que ce qui peut réussir au 2e essai : réponse malformée,
    # timeout, erreur réseau, rate limit ou 5xx. Un 400/401 rejoué 3 fois
    # ne fait que tripler la facture Mistral.
    if isinstance(exc, (LLMValidationError, asyncio.TimeoutError, httpx.TransportError)):
        return True
    if isinstance(exc, SDKError):
        return exc.status_code == 429 or exc.status_code >= 500
    return False


class _StreamedFunction:
    __slots__ = ("name", "arguments")

    def __init__(self, name: str, arguments: str) -> None:
        self.name = name
        self.arguments = arguments


class _StreamedToolCall:
    # Même forme que le ToolCall du SDK (id + function.name/arguments) pour que
    # l'orchestrateur traite indifféremment stream et non-stream.
    __slots__ = ("id", "function")

    def __init__(self, id: str, name: str, arguments: str) -> None:
        self.id = id
        self.function = _StreamedFunction(name, arguments)


class LLMWrapper:
    """Thin, safe wrapper around Mistral AI.

    Responsibilities:
    - Async chat completion with function calling
    - Automatic retry on transient errors
    - Timeout enforcement
    - Logging of every call
    - No business logic — only transport
    """

    def __init__(self, settings: Settings) -> None:
        self._client = Mistral(api_key=settings.mistral_api_key)
        self._model = settings.mistral_model
        self._timeout = settings.llm_timeout_seconds
        self._max_retries = settings.llm_max_retries
        self._temperature = settings.llm_temperature
        self._max_completion_tokens = settings.llm_max_completion_tokens

    @staticmethod
    def _build_mistral_messages(messages: list[dict[str, Any]]) -> list[Any]:
        """Convert our internal message dicts to Mistral SDK objects."""
        result = []
        for msg in messages:
            role = msg["role"]
            content = msg.get("content", "")
            if role == "system":
                result.append(SystemMessage(content=content))
            elif role == "user":
                result.append(UserMessage(content=content))
            elif role == "assistant":
                tool_calls = msg.get("tool_calls")
                result.append(AssistantMessage(content=content or "", tool_calls=tool_calls))
            elif role == "tool":
                result.append(ToolMessage(
                    content=content,
                    tool_call_id=msg.get("tool_call_id", ""),
                    name=msg.get("name", ""),
                ))
        return result

    async def chat(
        self,
        messages: list[dict[str, Any]],
        tools: list[dict[str, Any]] | None = None,
    ) -> tuple[str | None, list[Any]]:
        """Call Mistral and return (text_reply, tool_calls).

        Exactly one of the two will be non-None/non-empty.
        Raises LLMMaxRetriesError if all retries are exhausted.
        """
        mistral_messages = self._build_mistral_messages(messages)
        tool_choice = "auto" if tools else "none"

        try:
            async for attempt in AsyncRetrying(
                stop=stop_after_attempt(self._max_retries),
                wait=wait_exponential(multiplier=1, min=1, max=8),
                retry=retry_if_exception(_is_transient),
                reraise=False,
            ):
                with attempt:
                    log.info(
                        "llm_call_start",
                        model=self._model,
                        message_count=len(mistral_messages),
                        has_tools=bool(tools),
                        attempt_number=attempt.retry_state.attempt_number,
                    )

                    response = await asyncio.wait_for(
                        self._client.chat.complete_async(
                            model=self._model,
                            messages=mistral_messages,
                            tools=tools or [],
                            tool_choice=tool_choice,
                            temperature=self._temperature,
                            max_tokens=self._max_completion_tokens,
                        ),
                        timeout=self._timeout,
                    )

                    message = response.choices[0].message
                    text, tool_calls = extract_text_or_tool_calls(message)

                    usage = getattr(response, "usage", None)
                    log.info(
                        "llm_call_success",
                        has_text=bool(text),
                        tool_call_count=len(tool_calls),
                        finish_reason=response.choices[0].finish_reason,
                        prompt_tokens=getattr(usage, "prompt_tokens", None),
                        completion_tokens=getattr(usage, "completion_tokens", None),
                    )

                    return text, tool_calls

        except RetryError as exc:
            log.error("llm_max_retries_exhausted", max_retries=self._max_retries)
            raise LLMMaxRetriesError("LLM failed after max retries") from exc
        except asyncio.TimeoutError as exc:
            log.error("llm_timeout", timeout_s=self._timeout)
            raise LLMMaxRetriesError(f"LLM timed out after {self._timeout}s") from exc

        # Should never reach here — satisfy type checker
        raise LLMMaxRetriesError("Unexpected state in LLMWrapper.chat")

    async def chat_stream(
        self,
        messages: list[dict[str, Any]],
        tools: list[dict[str, Any]] | None = None,
    ) -> AsyncIterator[tuple[str, Any]]:
        """Stream one LLM call. Yields ("token", str) as text arrives, then
        exactly one terminal event: ("text", full_text) or ("tool_calls", [...]).

        Pas de retry ici : un stream interrompu à mi-réponse ne se rejoue pas
        proprement — l'appelant (endpoint SSE) émet un event error et le client
        iOS retombe sur l'endpoint non-streamé.
        """
        mistral_messages = self._build_mistral_messages(messages)
        tool_choice = "auto" if tools else "none"

        log.info(
            "llm_stream_start",
            model=self._model,
            message_count=len(mistral_messages),
            has_tools=bool(tools),
        )

        stream = await asyncio.wait_for(
            self._client.chat.stream_async(
                model=self._model,
                messages=mistral_messages,
                tools=tools or [],
                tool_choice=tool_choice,
                temperature=self._temperature,
                max_tokens=self._max_completion_tokens,
            ),
            timeout=self._timeout,
        )

        text_parts: list[str] = []
        # Les tool calls arrivent en deltas indexés : on les recompose par index.
        pending_tools: dict[int, dict[str, Any]] = {}

        async for event in stream:
            chunk = getattr(event, "data", event)
            choices = getattr(chunk, "choices", None)
            if not choices:
                continue
            delta = choices[0].delta

            content = getattr(delta, "content", None)
            if content:
                text_parts.append(content)
                yield ("token", content)

            for i, tc in enumerate(getattr(delta, "tool_calls", None) or []):
                idx = getattr(tc, "index", None)
                idx = idx if idx is not None else i
                slot = pending_tools.setdefault(idx, {"id": "", "name": "", "arguments": ""})
                if getattr(tc, "id", None):
                    slot["id"] = tc.id
                fn = getattr(tc, "function", None)
                if fn is not None:
                    if getattr(fn, "name", None):
                        slot["name"] = fn.name
                    args = getattr(fn, "arguments", None)
                    if args:
                        slot["arguments"] += args if isinstance(args, str) else str(args)

        if pending_tools:
            tool_calls = [
                _StreamedToolCall(slot["id"], slot["name"], slot["arguments"])
                for _, slot in sorted(pending_tools.items())
            ]
            log.info("llm_stream_success", has_text=False, tool_call_count=len(tool_calls))
            yield ("tool_calls", tool_calls)
        else:
            full_text = "".join(text_parts)
            log.info("llm_stream_success", has_text=bool(full_text), tool_call_count=0)
            yield ("text", full_text)

    def build_tool_result_message(
        self,
        tool_call_id: str,
        tool_name: str,
        result_json: str,
    ) -> dict[str, Any]:
        return {
            "role": "tool",
            "tool_call_id": tool_call_id,
            "name": tool_name,
            "content": result_json,
        }
