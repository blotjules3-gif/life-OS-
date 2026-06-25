from __future__ import annotations


class LifeOSBaseError(Exception):
    pass


class LLMValidationError(LifeOSBaseError):
    """LLM returned output that failed JSON / schema validation."""


class LLMMaxRetriesError(LifeOSBaseError):
    """LLM failed validation after max retries."""


class ToolNotFoundError(LifeOSBaseError):
    """Requested tool does not exist in registry."""


class ToolExecutionError(LifeOSBaseError):
    """Tool ran but encountered a domain error."""


class ToolRejectedError(LifeOSBaseError):
    """Tool call rejected by safety layer (e.g. finance guardrail)."""


class UserNotFoundError(LifeOSBaseError):
    pass


class ModuleNotFoundError(LifeOSBaseError):
    pass


class AgentMaxIterationsError(LifeOSBaseError):
    """Agent loop exceeded max_iterations without reaching a final response."""
