from __future__ import annotations

import json
from typing import Any

import jsonschema

from app.core.exceptions import LLMValidationError
from app.core.logging import get_logger
from app.schemas.tool import ToolCall

log = get_logger(__name__)

TOOL_CALL_SCHEMA = {
    "type": "object",
    "required": ["tool", "args"],
    "additionalProperties": False,
    "properties": {
        "tool": {"type": "string", "minLength": 1, "maxLength": 100},
        "args": {"type": "object"},
    },
}


def validate_tool_call_json(raw: str) -> ToolCall:
    """Parse and validate a raw JSON string as a ToolCall.
    Raises LLMValidationError on any failure.
    """
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise LLMValidationError(f"Invalid JSON from LLM: {exc}") from exc

    try:
        jsonschema.validate(data, TOOL_CALL_SCHEMA)
    except jsonschema.ValidationError as exc:
        raise LLMValidationError(f"Tool call schema violation: {exc.message}") from exc

    return ToolCall(**data)


def extract_text_or_tool_calls(
    response_message: Any,
) -> tuple[str | None, list[Any]]:
    """Extract either a text reply or a list of tool calls from a Mistral response message.

    Returns:
        (text_reply, tool_calls) — exactly one will be non-empty.
    """
    tool_calls = getattr(response_message, "tool_calls", None) or []
    content = getattr(response_message, "content", None) or ""

    if tool_calls:
        log.debug("llm_returned_tool_calls", count=len(tool_calls))
        return None, tool_calls

    if content:
        log.debug("llm_returned_text", length=len(content))
        return str(content).strip(), []

    raise LLMValidationError("LLM response contained neither text content nor tool calls.")


def parse_mistral_tool_args(arguments_str: str) -> dict[str, Any]:
    """Parse the JSON arguments string from a Mistral tool call."""
    try:
        args = json.loads(arguments_str)
        if not isinstance(args, dict):
            raise LLMValidationError("Tool call arguments must be a JSON object, not a list or scalar.")
        return args
    except json.JSONDecodeError as exc:
        raise LLMValidationError(f"Cannot parse tool arguments JSON: {exc}") from exc
