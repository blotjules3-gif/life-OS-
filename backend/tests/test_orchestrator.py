from __future__ import annotations

import uuid
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.core.agents.orchestrator import AgentOrchestrator, AgentResult
from app.core.exceptions import AgentMaxIterationsError


class FakeSettings:
    mistral_api_key = "test"
    mistral_model = "mistral-large-latest"
    llm_timeout_seconds = 10
    llm_max_retries = 1
    llm_max_agent_iterations = 3


@pytest.mark.asyncio
async def test_orchestrator_returns_text_reply():
    orchestrator = AgentOrchestrator(FakeSettings())

    # LLM returns text on first call
    with patch.object(orchestrator._llm, "chat", new_callable=AsyncMock) as mock_chat:
        mock_chat.return_value = ("Voici ta config mise à jour.", [])

        result = await orchestrator.run(
            user_message="Je veux m'entraîner 3x par semaine",
            conversation_history=[],
            module_type="sport",
            module_config={},
            user_id=uuid.uuid4(),
            user_name="Jules",
            conversation_id=uuid.uuid4(),
            session=AsyncMock(),
        )

    assert isinstance(result, AgentResult)
    assert result.reply == "Voici ta config mise à jour."
    assert result.tools_executed == []


@pytest.mark.asyncio
async def test_orchestrator_executes_tool_then_replies():
    orchestrator = AgentOrchestrator(FakeSettings())

    fake_tool_call = MagicMock()
    fake_tool_call.function.name = "update_module_config"
    fake_tool_call.function.arguments = '{"module": "sport", "config": {"sessions_per_week": 3}}'
    fake_tool_call.id = "call_123"

    call_count = 0

    async def fake_chat(messages, tools):
        nonlocal call_count
        call_count += 1
        if call_count == 1:
            return None, [fake_tool_call]
        return "Parfait, j'ai sauvegardé 3 séances par semaine.", []

    with (
        patch.object(orchestrator._llm, "chat", new_callable=AsyncMock, side_effect=fake_chat),
        patch("app.core.agents.orchestrator.execute_tool", new_callable=AsyncMock) as mock_exec,
    ):
        mock_exec.return_value = {"module": "sport", "updated": True, "config": {"sessions_per_week": 3}}

        result = await orchestrator.run(
            user_message="Je veux m'entraîner 3x par semaine",
            conversation_history=[],
            module_type="sport",
            module_config={},
            user_id=uuid.uuid4(),
            user_name="Jules",
            conversation_id=uuid.uuid4(),
            session=AsyncMock(),
        )

    assert "Parfait" in result.reply
    assert "update_module_config" in result.tools_executed
    assert result.module_config_updated is True


@pytest.mark.asyncio
async def test_orchestrator_raises_on_max_iterations():
    orchestrator = AgentOrchestrator(FakeSettings())
    orchestrator._max_iterations = 2

    fake_tool_call = MagicMock()
    fake_tool_call.function.name = "list_goals"
    fake_tool_call.function.arguments = "{}"
    fake_tool_call.id = "call_999"

    async def always_tool(messages, tools):
        return None, [fake_tool_call]

    with (
        patch.object(orchestrator._llm, "chat", new_callable=AsyncMock, side_effect=always_tool),
        patch("app.core.agents.orchestrator.execute_tool", new_callable=AsyncMock) as mock_exec,
    ):
        mock_exec.return_value = {"goals": []}

        with pytest.raises(AgentMaxIterationsError):
            await orchestrator.run(
                user_message="test",
                conversation_history=[],
                module_type=None,
                module_config={},
                user_id=uuid.uuid4(),
                user_name=None,
                conversation_id=uuid.uuid4(),
                session=AsyncMock(),
            )


@pytest.mark.asyncio
async def test_finance_tool_rejected_with_asset_arg():
    from app.core.tools.executor import _apply_safety_guardrails
    from app.core.exceptions import ToolRejectedError

    with pytest.raises(ToolRejectedError):
        _apply_safety_guardrails("simulate_allocation", {"amount": 1000, "risk_profile": "moderate", "asset": "BTC"})


def test_finance_tool_clean_args_pass():
    from app.core.tools.executor import _apply_safety_guardrails
    # Should not raise
    _apply_safety_guardrails("simulate_allocation", {"amount": 1000, "risk_profile": "moderate"})
