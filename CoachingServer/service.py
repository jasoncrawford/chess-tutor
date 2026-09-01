"""Provider-facing domain service for one hosted coaching turn."""

from __future__ import annotations

import json
import logging
import re
import time
import socket
from collections.abc import Mapping

from CoachingServer.chess_native_compiler import compile_context, compile_follow_up_context
from Tools.CoachingEval.chess_native_response import (
    ChessNativeResponseContract,
    ChessNativeResponseValidationError,
)


_MAXIMUM_TOKEN_COUNT = 1_000_000_000
_MAXIMUM_LATENCY_MILLISECONDS = 120_000.0
_LOGGER = logging.getLogger("ChessTutor.CoachingServer")
_CONTINUATION_ID = re.compile(r"resp_[A-Za-z0-9_-]{1,251}\Z")
_ENVELOPE_FIELDS = {"schemaVersion", "request", "previousResponseID"}
_TACTICAL_FOLLOW_UP_EVENTS = {"moveStaged", "moveReplaced", "squareInspected"}


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
        follow_up_reasoning_effort: str = "none",
        log_content: bool = False,
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
        if follow_up_reasoning_effort not in {"low", "none"}:
            raise ValueError("follow-up reasoning effort must be low or none")
        if not isinstance(log_content, bool):
            raise ValueError("log_content must be a boolean")
        self._provider = provider
        self._system_prompt = system_prompt
        self._timeout = float(timeout)
        self._follow_up_reasoning_effort = follow_up_reasoning_effort
        self._log_content = log_content
        self._clock = clock

    def complete(
        self,
        request: Mapping[str, object],
        *,
        trace_id: str = "direct",
    ) -> dict[str, object]:
        try:
            neutral_request, previous_response_id = _parse_envelope(request)
            is_follow_up = previous_response_id is not None
            compiler = compile_follow_up_context if is_follow_up else compile_context
            compilation = compiler(neutral_request, "tutor-v11")
        except (TypeError, ValueError):
            raise HostedCoachingServiceError("invalidRequest") from None
        request_kind = "follow_up" if is_follow_up else "initial"
        reasoning_effort = _reasoning_effort(
            neutral_request,
            is_follow_up=is_follow_up,
            simple_follow_up_effort=self._follow_up_reasoning_effort,
        )
        _LOGGER.info(
            "event=request_compiled trace_id=%s request_kind=%s",
            trace_id,
            request_kind,
        )

        contract = ChessNativeResponseContract(
            actions=compilation.actions,
            allowable_moves=compilation.allowable_moves,
            expected_responses=compilation.expected_responses,
        )
        started = self._clock()
        _LOGGER.info(
            (
                "event=provider_request_started trace_id=%s "
                "request_kind=%s model=gpt-5.6-sol "
                "reasoning_effort=%s timeout_seconds=%s"
            ),
            trace_id,
            request_kind,
            reasoning_effort,
            f"{self._timeout:g}",
        )
        try:
            provider_response = self._provider.complete(
                system_prompt=self._system_prompt,
                user_prompt=compilation.markdown,
                schema=contract.json_schema(),
                model="gpt-5.6-sol",
                reasoning_effort=reasoning_effort,
                maximum_output_tokens=2048,
                timeout=self._timeout,
                previous_response_id=previous_response_id,
                store=True,
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
        metrics = _metrics(
            provider_response.get("usage") if isinstance(provider_response, dict) else None,
            elapsed_milliseconds,
        )
        _LOGGER.info(
            (
                "event=provider_request_completed trace_id=%s "
                "elapsed_ms=%s outcome=%s input_tokens=%s "
                "cached_input_tokens=%s output_tokens=%s reasoning_tokens=%s"
            ),
            trace_id,
            elapsed_milliseconds,
            provider_outcome,
            metrics["inputTokens"],
            metrics["cachedInputTokens"],
            metrics["outputTokens"],
            metrics["reasoningTokens"],
        )

        try:
            if not isinstance(provider_response, dict):
                raise ValueError
            if provider_response.get("status") != "completed":
                raise ValueError
            output_text = provider_response.get("output_text")
            if not isinstance(output_text, str):
                raise ValueError
            continuation_id = _continuation_id(provider_response.get("id"))
            turn = contract.parse_and_validate(output_text)
        except ChessNativeResponseValidationError as error:
            _LOGGER.info(
                (
                    "event=provider_response_failed trace_id=%s "
                    "outcome=invalid_response reasons=%s"
                ),
                trace_id,
                ",".join(error.categories),
            )
            raise HostedCoachingServiceError("invalidProviderResponse") from None
        except (KeyError, TypeError, ValueError):
            _LOGGER.info(
                (
                    "event=provider_response_failed trace_id=%s "
                    "outcome=invalid_response reasons=providerEnvelope"
                ),
                trace_id,
            )
            raise HostedCoachingServiceError("invalidProviderResponse") from None
        _LOGGER.info("event=provider_response_validated trace_id=%s", trace_id)
        response = {
            "schemaVersion": "hosted-coaching-turn.v3",
            "requestID": compilation.request_id,
            "positionRevision": compilation.position_revision,
            "promptVersion": compilation.prompt_version,
            "continuationID": continuation_id,
            "turn": turn,
            "metrics": metrics,
        }
        if self._log_content:
            _LOGGER.info(
                "%s",
                _content_trace(
                    trace_id=trace_id,
                    request_kind=request_kind,
                    reasoning_effort=reasoning_effort,
                    client_request=neutral_request,
                    server_response=response,
                ),
            )

        return response


def _content_trace(
    *,
    trace_id: str,
    request_kind: str,
    reasoning_effort: str,
    client_request: Mapping[str, object],
    server_response: Mapping[str, object],
) -> str:
    position = client_request["position"]
    history = client_request["gameHistory"]
    interaction = client_request["interaction"]
    tentative = interaction.get("tentativeMove")
    staged = None
    if tentative is not None:
        staged = {
            "move": tentative["canonicalMove"],
            "notation": tentative["san"],
            "legal": tentative["isLegal"],
        }
    trace = {
        "kind": request_kind,
        "reasoning": reasoning_effort,
        "revision": client_request["positionRevision"],
        "position": {
            "fen": position["fen"],
            "moves": [move["displayNotation"] for move in history],
            "side": position["sideToMove"],
            "status": position["status"],
        },
        "interaction": {
            "selected": interaction.get("selectedPieceReference"),
            "selectedSquare": interaction.get("selectedSquare"),
            "staged": staged,
            "events": [
                {
                    "sequence": event["sequence"],
                    "kind": event["kind"],
                    "references": event["referencedIDs"],
                }
                for event in interaction["episodeEvents"]
            ],
        },
        "advice": server_response["turn"],
        "latencyMs": server_response["metrics"]["latencyMilliseconds"],
    }
    return "event=coaching_trace trace_id={} data={}".format(
        trace_id,
        json.dumps(trace, ensure_ascii=False, separators=(",", ":")),
    )


def _metrics(usage: object, elapsed_milliseconds: float) -> dict[str, object]:
    usage = usage if isinstance(usage, dict) else {}
    return {
        "inputTokens": _bounded_int(usage.get("input_tokens")),
        "cachedInputTokens": _bounded_int(usage.get("cached_input_tokens")),
        "outputTokens": _bounded_int(usage.get("output_tokens")),
        "reasoningTokens": _bounded_int(usage.get("reasoning_tokens")),
        "totalTokens": _bounded_int(usage.get("total_tokens")),
        "latencyMilliseconds": round(
            min(elapsed_milliseconds, _MAXIMUM_LATENCY_MILLISECONDS),
            3,
        ),
    }


def _reasoning_effort(
    request: Mapping[str, object],
    *,
    is_follow_up: bool,
    simple_follow_up_effort: str,
) -> str:
    if not is_follow_up:
        return "high"
    interaction = request["interaction"]
    latest_event = interaction["latestEvent"]
    kind = latest_event["kind"]
    references = latest_event["referencedIDs"]
    if kind in _TACTICAL_FOLLOW_UP_EVENTS:
        return "low"
    if kind == "actionChosen" and "action:hint" in references:
        return "low"
    return simple_follow_up_effort


def _elapsed_milliseconds(finished: float, started: float) -> float:
    return round(max(0.0, (finished - started) * 1000.0), 3)


def _bounded_int(value: object) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        return 0
    return min(value, _MAXIMUM_TOKEN_COUNT)


def _parse_envelope(value: Mapping[str, object]) -> tuple[Mapping[str, object], str | None]:
    if not isinstance(value, Mapping) or set(value.keys()) != _ENVELOPE_FIELDS:
        raise ValueError("Invalid hosted coaching request envelope")
    if value["schemaVersion"] != "hosted-coaching-request.v2":
        raise ValueError("Unsupported hosted coaching request schema")
    neutral_request = value["request"]
    if not isinstance(neutral_request, Mapping):
        raise ValueError("Hosted coaching request must be an object")
    previous_response_id = value["previousResponseID"]
    if previous_response_id is not None:
        previous_response_id = _continuation_id(previous_response_id)
    return neutral_request, previous_response_id


def _continuation_id(value: object) -> str:
    if not isinstance(value, str) or not _CONTINUATION_ID.fullmatch(value):
        raise ValueError("Invalid continuation ID")
    return value
