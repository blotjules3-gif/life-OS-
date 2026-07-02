from __future__ import annotations

import asyncio
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

                    log.info(
                        "llm_call_success",
                        has_text=bool(text),
                        tool_call_count=len(tool_calls),
                        finish_reason=response.choices[0].finish_reason,
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
