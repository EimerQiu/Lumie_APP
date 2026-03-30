"""Unified LLM client for PaleBlueDot's OpenAI-compatible chat API."""
import json
import logging
from dataclasses import dataclass, field
from typing import Any, Optional

import httpx

from ..core.config import settings

logger = logging.getLogger(__name__)


@dataclass
class LLMToolCall:
    """Normalized tool call from a chat completion response."""

    id: str
    name: str
    arguments: dict[str, Any] = field(default_factory=dict)


@dataclass
class LLMUsage:
    """Normalized usage counters."""

    input_tokens: int = 0
    output_tokens: int = 0


@dataclass
class LLMResponse:
    """Normalized response payload for backend services."""

    text: str
    tool_calls: list[LLMToolCall] = field(default_factory=list)
    usage: LLMUsage = field(default_factory=LLMUsage)
    raw: dict[str, Any] = field(default_factory=dict)


def _get_api_key() -> str:
    api_key = settings.PALEBLUEDOT_API_KEY or settings.ANTHROPIC_API_KEY
    if not api_key:
        raise RuntimeError("PALEBLUEDOT_API_KEY is not set.")
    return api_key


def _extract_text(content: Any) -> str:
    if content is None:
        return ""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts: list[str] = []
        for item in content:
            if isinstance(item, str):
                parts.append(item)
            elif isinstance(item, dict):
                text = item.get("text")
                if isinstance(text, str):
                    parts.append(text)
        return "".join(parts)
    return str(content)


def _normalize_tools(tools: Optional[list[dict[str, Any]]]) -> Optional[list[dict[str, Any]]]:
    if not tools:
        return None

    normalized: list[dict[str, Any]] = []
    for tool in tools:
        normalized.append(
            {
                "type": "function",
                "function": {
                    "name": tool["name"],
                    "description": tool.get("description", ""),
                    "parameters": tool.get("input_schema", {"type": "object", "properties": {}}),
                },
            }
        )
    return normalized


def _parse_tool_calls(message: dict[str, Any]) -> list[LLMToolCall]:
    parsed: list[LLMToolCall] = []
    for tool_call in message.get("tool_calls") or []:
        function = tool_call.get("function") or {}
        args_raw = function.get("arguments") or "{}"
        try:
            arguments = json.loads(args_raw) if isinstance(args_raw, str) else dict(args_raw)
        except (TypeError, ValueError, json.JSONDecodeError):
            arguments = {}
        parsed.append(
            LLMToolCall(
                id=tool_call.get("id", ""),
                name=function.get("name", ""),
                arguments=arguments,
            )
        )
    return parsed


async def chat_completion(
    *,
    messages: list[dict[str, Any]],
    system: Optional[str] = None,
    model: Optional[str] = None,
    max_tokens: Optional[int] = None,
    temperature: Optional[float] = None,
    tools: Optional[list[dict[str, Any]]] = None,
) -> LLMResponse:
    """Call PaleBlueDot's OpenAI-compatible chat/completions endpoint."""

    api_key = _get_api_key()
    url = f"{settings.PALEBLUEDOT_API_BASE_URL.rstrip('/')}/chat/completions"

    payload_messages: list[dict[str, Any]] = []
    if system:
        payload_messages.append({"role": "system", "content": system})
    payload_messages.extend(messages)

    payload: dict[str, Any] = {
        "model": model or settings.PALEBLUEDOT_MODEL,
        "messages": payload_messages,
    }
    if max_tokens is not None:
        payload["max_tokens"] = max_tokens
    if temperature is not None:
        payload["temperature"] = temperature

    normalized_tools = _normalize_tools(tools)
    if normalized_tools:
        payload["tools"] = normalized_tools
        payload["tool_choice"] = "auto"

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }

    logger.info(
        "LLM request: provider=palebluedot url=%s model=%s messages=%d tools=%d",
        url,
        payload["model"],
        len(payload_messages),
        len(normalized_tools or []),
    )

    async with httpx.AsyncClient(timeout=120.0) as client:
        response = await client.post(url, headers=headers, json=payload)
        response.raise_for_status()
        data = response.json()

    choice = (data.get("choices") or [{}])[0]
    message = choice.get("message") or {}
    usage = data.get("usage") or {}

    normalized = LLMResponse(
        text=_extract_text(message.get("content")),
        tool_calls=_parse_tool_calls(message),
        usage=LLMUsage(
            input_tokens=int(usage.get("prompt_tokens") or 0),
            output_tokens=int(usage.get("completion_tokens") or 0),
        ),
        raw=data,
    )
    logger.info(
        "LLM response: provider=palebluedot model=%s tool_calls=%d input_tokens=%d output_tokens=%d",
        payload["model"],
        len(normalized.tool_calls),
        normalized.usage.input_tokens,
        normalized.usage.output_tokens,
    )
    return normalized
