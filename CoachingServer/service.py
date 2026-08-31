"""Provider-facing domain service for one hosted coaching turn."""

from __future__ import annotations

import logging
import time
import socket
from collections.abc import Mapping

from CoachingServer.chess_native_compiler import compile_context
from Tools.CoachingEval.chess_native_response import ChessNativeResponseContract


_MAXIMUM_TOKEN_COUNT = 1_000_000_000
_MAXIMUM_LATENCY_MILLISECONDS = 120_000.0
_LOGGER = logging.getLogger("ChessTutor.CoachingServer")


class HostedCoachingServiceError(RuntimeError):
    """A stable public failure without provider or request content."""

    _MESSAGES = {
        "invalidRequest": "The coaching request is invalid.",
        "providerTimeout": "Coaching took too long to respond.",
        "providerUnavailable": "Coaching is temporarily unavailable.",
        "invalidProviderResponse": "The coaching response was invalid.",
    }

    def __init__(self, code: str):
        if code not in self._MESSAGES:
            code = "providerUnavailable"
        super().__init__(self._MESSAGES[code])
        self.code = code


class HostedCoachingService:
    def __init__(
        self,
        *,
        provider,
        system_prompt: str,
        timeout: float = 30.0,
        clock=time.monotonic,
    ):
        if not callable(getattr(provider, "complete", None)):
            raise ValueError("provider must implement complete")
        if not isinstance(system_prompt, str) or not system_prompt.strip():
            raise ValueError("system_prompt must be a nonempty string")
        if isinstance(timeout, bool) or not isinstance(timeout, (int, float)) or timeout <= 0:
            raise ValueError("timeout must be positive")
        if not callable(clock):
            raise ValueError("clock must be callable")
        self._provider = provider
        self._system_prompt = system_prompt
        self._timeout = float(timeout)
        self._clock = clock

    def complete(
        self,
        request: Mapping[str, object],
        *,
        trace_id: str = "direct",
    ) -> dict[str, object]:
        try:
            compilation = compile_context(request, "tutor-v6")
        except (TypeError, ValueError):
            raise HostedCoachingServiceError("invalidRequest") from None
        _LOGGER.info("event=request_compiled trace_id=%s", trace_id)

        contract = ChessNativeResponseContract(
            actions=compilation.actions,
            allowable_moves=compilation.allowable_moves,
        )
        started = self._clock()
        _LOGGER.info(
            (
                "event=provider_request_started trace_id=%s "
                "model=gpt-5.6-sol reasoning_effort=high timeout_seconds=%s"
            ),
            trace_id,
            f"{self._timeout:g}",
        )
        try:
            provider_response = self._provider.complete(
                system_prompt=self._system_prompt,
                user_prompt=compilation.markdown,
                schema=contract.json_schema(),
                model="gpt-5.6-sol",
                reasoning_effort="high",
                maximum_output_tokens=2048,
                timeout=self._timeout,
            )
        except Exception as error:
            elapsed_milliseconds = _elapsed_milliseconds(self._clock(), started)
            is_timeout = (
                isinstance(error, (TimeoutError, socket.timeout))
                or getattr(error, "category", None) == "timeout"
                or getattr(error, "http_status", None) == 504
            )
            _LOGGER.info(
                (
                    "event=provider_request_failed trace_id=%s "
                    "elapsed_ms=%s outcome=%s"
                ),
                trace_id,
                elapsed_milliseconds,
                "timeout" if is_timeout else "unavailable",
            )
            if is_timeout:
                raise HostedCoachingServiceError("providerTimeout") from None
            raise HostedCoachingServiceError("providerUnavailable") from None
        elapsed_milliseconds = _elapsed_milliseconds(self._clock(), started)
        provider_outcome = (
            "completed"
            if isinstance(provider_response, dict)
            and provider_response.get("status") == "completed"
            else "noncompleted"
        )
        _LOGGER.info(
            (
                "event=provider_request_completed trace_id=%s "
                "elapsed_ms=%s outcome=%s"
            ),
            trace_id,
            elapsed_milliseconds,
            provider_outcome,
        )

        try:
            if not isinstance(provider_response, dict):
                raise ValueError
            if provider_response.get("status") != "completed":
                raise ValueError
            output_text = provider_response.get("output_text")
            if not isinstance(output_text, str):
                raise ValueError
            turn = contract.parse_and_validate(output_text)
        except (KeyError, TypeError, ValueError):
            _LOGGER.info(
                "event=provider_response_failed trace_id=%s outcome=invalid_response",
                trace_id,
            )
            raise HostedCoachingServiceError("invalidProviderResponse") from None
        _LOGGER.info("event=provider_response_validated trace_id=%s", trace_id)

        return {
            "schemaVersion": "hosted-coaching-turn.v1",
            "requestID": compilation.request_id,
            "positionRevision": compilation.position_revision,
            "promptVersion": compilation.prompt_version,
            "turn": turn,
            "metrics": _metrics(
                provider_response.get("usage"),
                elapsed_milliseconds,
            ),
        }


def _metrics(usage: object, elapsed_milliseconds: float) -> dict[str, object]:
    usage = usage if isinstance(usage, dict) else {}
    return {
        "inputTokens": _bounded_int(usage.get("input_tokens")),
        "outputTokens": _bounded_int(usage.get("output_tokens")),
        "reasoningTokens": _bounded_int(usage.get("reasoning_tokens")),
        "totalTokens": _bounded_int(usage.get("total_tokens")),
        "latencyMilliseconds": round(
            min(elapsed_milliseconds, _MAXIMUM_LATENCY_MILLISECONDS),
            3,
        ),
    }


def _elapsed_milliseconds(finished: float, started: float) -> float:
    return round(max(0.0, (finished - started) * 1000.0), 3)


def _bounded_int(value: object) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        return 0
    return min(value, _MAXIMUM_TOKEN_COUNT)
