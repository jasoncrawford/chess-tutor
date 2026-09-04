"""Provider-facing domain service for one hosted coaching turn."""

from __future__ import annotations

from dataclasses import dataclass
import logging
import re
import socket
import time
import uuid
from collections.abc import Mapping

from CoachingServer.chess_native_compiler import (
    compile_context,
    compile_follow_up_context,
    parse_neutral_request,
)
from CoachingServer.model_configuration import HostedModelConfiguration
from CoachingServer.structured_logging import emit_event
from Tools.CoachingEval.chess_native_response import (
    ChessNativeResponseContract,
    ChessNativeResponseValidationError,
)


_MAXIMUM_TOKEN_COUNT = 1_000_000_000
_MAXIMUM_LATENCY_MILLISECONDS = 120_000.0
_CONTINUATION_ID = re.compile(r"resp_[A-Za-z0-9_-]{1,251}\Z")
_ENVELOPE_FIELDS = {
    "schemaVersion",
    "gameID",
    "episodeID",
    "request",
    "previousResponseID",
}


class HostedCoachingServiceError(RuntimeError):
    """A stable public failure without provider or request content."""

    _MESSAGES = {
        "invalidRequest": "The coaching request is invalid.",
        "providerTimeout": "Coaching took too long to respond.",
        "providerUnavailable": "Coaching is temporarily unavailable.",
        "invalidProviderResponse": "The coaching response was invalid.",
    }

    def __init__(self, code: str, diagnostics: dict[str, object] | None = None):
        if code not in self._MESSAGES:
            code = "providerUnavailable"
        super().__init__(self._MESSAGES[code])
        self.code = code
        self.diagnostics = diagnostics


@dataclass(frozen=True)
class HostedCoachingCompletion:
    response: dict[str, object]
    diagnostics: dict[str, object]


class HostedCoachingService:
    def __init__(
        self,
        *,
        provider,
        configuration: HostedModelConfiguration,
        clock=time.monotonic,
    ):
        if not callable(getattr(provider, "complete", None)):
            raise ValueError("provider must implement complete")
        if not isinstance(configuration, HostedModelConfiguration):
            raise ValueError("configuration must be a HostedModelConfiguration")
        if not callable(clock):
            raise ValueError("clock must be callable")
        self._provider = provider
        self._configuration = configuration
        self._clock = clock

    def complete(
        self,
        request: Mapping[str, object],
        *,
        trace_id: str = "direct",
    ) -> HostedCoachingCompletion:
        try:
            (
                neutral_request,
                previous_response_id,
                game_id,
                episode_id,
            ) = _parse_envelope(request)
            normalized_request = parse_neutral_request(neutral_request)
            is_follow_up = previous_response_id is not None
            compiler = compile_follow_up_context if is_follow_up else compile_context
            compilation = compiler(
                neutral_request,
                self._configuration.prompt_version,
            )
        except (TypeError, ValueError):
            raise HostedCoachingServiceError("invalidRequest") from None
        request_kind = "follow_up" if is_follow_up else "initial"
        correlation = {
            "trace_id": trace_id,
            "game_id": game_id,
            "episode_id": episode_id,
        }
        request_summary = _request_summary(
            normalized_request,
            compilation=compilation,
            request_kind=request_kind,
        )
        reasoning_effort = self._configuration.reasoning_effort(
            normalized_request,
            is_follow_up,
        )
        emit_event(
            "request_compiled",
            **correlation,
            request_kind=request_kind,
        )

        contract = ChessNativeResponseContract(
            actions=compilation.actions,
            allowable_moves=compilation.allowable_moves,
            expected_responses=compilation.expected_responses,
        )
        started = self._clock()
        emit_event(
            "provider_request_started",
            **correlation,
            request_kind=request_kind,
            model=self._configuration.model,
            reasoning_effort=reasoning_effort,
            timeout_seconds=self._configuration.timeout_seconds,
        )
        provider_response = None
        provider_error = None
        provider_returned = False
        for _attempt in range(self._configuration.maximum_attempts):
            try:
                provider_response = self._provider.complete(
                    system_prompt=self._configuration.system_prompt,
                    user_prompt=compilation.markdown,
                    schema=contract.json_schema(),
                    model=self._configuration.model,
                    reasoning_effort=reasoning_effort,
                    maximum_output_tokens=self._configuration.maximum_output_tokens,
                    timeout=self._configuration.timeout_seconds,
                    previous_response_id=(
                        previous_response_id
                        if self._configuration.conversation_reuse
                        else None
                    ),
                    store=self._configuration.store,
                )
                provider_returned = True
                break
            except Exception as error:
                provider_error = error
        if not provider_returned:
            elapsed_milliseconds = _elapsed_milliseconds(self._clock(), started)
            is_timeout = (
                isinstance(provider_error, (TimeoutError, socket.timeout))
                or getattr(provider_error, "category", None) == "timeout"
                or getattr(provider_error, "http_status", None) == 504
            )
            emit_event(
                "provider_request_failed",
                level=logging.WARNING,
                **correlation,
                elapsed_ms=elapsed_milliseconds,
                outcome="timeout" if is_timeout else "unavailable",
            )
            if is_timeout:
                raise HostedCoachingServiceError(
                    "providerTimeout",
                    _diagnostics(
                        request=request_summary,
                        provider=_provider_summary(
                            model=self._configuration.model,
                            reasoning_effort=reasoning_effort,
                            metrics=_metrics(None, elapsed_milliseconds),
                        ),
                    ),
                ) from None
            raise HostedCoachingServiceError(
                "providerUnavailable",
                _diagnostics(
                    request=request_summary,
                    provider=_provider_summary(
                        model=self._configuration.model,
                        reasoning_effort=reasoning_effort,
                        metrics=_metrics(None, elapsed_milliseconds),
                    ),
                ),
            ) from None
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
        provider_summary = _provider_summary(
            model=self._configuration.model,
            reasoning_effort=reasoning_effort,
            metrics=metrics,
        )
        emit_event(
            "provider_request_completed",
            **correlation,
            elapsed_ms=elapsed_milliseconds,
            outcome=provider_outcome,
            input_tokens=metrics["inputTokens"],
            cached_input_tokens=metrics["cachedInputTokens"],
            output_tokens=metrics["outputTokens"],
            reasoning_tokens=metrics["reasoningTokens"],
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
            emit_event(
                "provider_response_failed",
                level=logging.WARNING,
                **correlation,
                outcome="invalid_response",
                reasons=list(error.categories),
            )
            invalid_provider = {
                **provider_summary,
                "validation_reasons": list(error.categories),
            }
            raise HostedCoachingServiceError(
                "invalidProviderResponse",
                _diagnostics(request=request_summary, provider=invalid_provider),
            ) from None
        except (KeyError, TypeError, ValueError):
            emit_event(
                "provider_response_failed",
                level=logging.WARNING,
                **correlation,
                outcome="invalid_response",
                reasons=["providerEnvelope"],
            )
            invalid_provider = {
                **provider_summary,
                "validation_reasons": ["providerEnvelope"],
            }
            raise HostedCoachingServiceError(
                "invalidProviderResponse",
                _diagnostics(request=request_summary, provider=invalid_provider),
            ) from None
        emit_event("provider_response_validated", **correlation)
        response = {
            "schemaVersion": "hosted-coaching-turn.v3",
            "requestID": compilation.request_id,
            "positionRevision": compilation.position_revision,
            "promptVersion": compilation.prompt_version,
            "continuationID": continuation_id,
            "turn": turn,
            "metrics": metrics,
        }
        return HostedCoachingCompletion(
            response=response,
            diagnostics=_diagnostics(
                request=request_summary,
                response=turn,
                provider=provider_summary,
            ),
        )


def _request_summary(
    request: Mapping[str, object],
    *,
    compilation,
    request_kind: str,
) -> dict[str, object]:
    position = request["position"]
    interaction = request["interaction"]
    latest = interaction["latestEvent"]
    tentative = interaction["tentativeMove"]
    staged_move = None
    if tentative is not None:
        staged_move = {
            "move": tentative["canonicalMove"],
            "notation": tentative["san"],
            "legal": tentative["isLegal"],
        }
    latest_interaction = None
    if latest is not None:
        latest_interaction = {
            "sequence": latest["sequence"],
            "kind": latest["kind"],
            "references": list(latest["referencedIDs"]),
        }
    return {
        "kind": request_kind,
        "request_id": compilation.request_id,
        "prompt_version": compilation.prompt_version,
        "position_revision": compilation.position_revision,
        "fen": position["fen"],
        "moves": [move["displayNotation"] for move in request["gameHistory"]],
        "side_to_move": position["sideToMove"],
        "status": position["status"],
        "latest_interaction": latest_interaction,
        "selected_piece": interaction["selectedPieceReference"],
        "selected_square": interaction["selectedSquare"],
        "staged_move": staged_move,
    }


def _provider_summary(
    *,
    model: str,
    reasoning_effort: str,
    metrics: Mapping[str, object],
) -> dict[str, object]:
    return {
        "model": model,
        "reasoning_effort": reasoning_effort,
        "input_tokens": metrics["inputTokens"],
        "cached_input_tokens": metrics["cachedInputTokens"],
        "output_tokens": metrics["outputTokens"],
        "reasoning_tokens": metrics["reasoningTokens"],
        "total_tokens": metrics["totalTokens"],
        "latency_ms": metrics["latencyMilliseconds"],
    }


def _diagnostics(
    *,
    request: dict[str, object] | None,
    response: dict[str, object] | None = None,
    provider: dict[str, object] | None = None,
) -> dict[str, object]:
    return {
        "request": request,
        "response": response,
        "provider": provider,
    }


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


def _elapsed_milliseconds(finished: float, started: float) -> float:
    return round(max(0.0, (finished - started) * 1000.0), 3)


def _bounded_int(value: object) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        return 0
    return min(value, _MAXIMUM_TOKEN_COUNT)


def _parse_envelope(
    value: Mapping[str, object],
) -> tuple[Mapping[str, object], str | None, str, str]:
    if not isinstance(value, Mapping) or set(value.keys()) != _ENVELOPE_FIELDS:
        raise ValueError("Invalid hosted coaching request envelope")
    if value["schemaVersion"] != "hosted-coaching-request.v3":
        raise ValueError("Unsupported hosted coaching request schema")
    game_id = _canonical_uuid(value["gameID"])
    episode_id = _canonical_uuid(value["episodeID"])
    neutral_request = value["request"]
    if not isinstance(neutral_request, Mapping):
        raise ValueError("Hosted coaching request must be an object")
    previous_response_id = value["previousResponseID"]
    if previous_response_id is not None:
        previous_response_id = _continuation_id(previous_response_id)
    return neutral_request, previous_response_id, game_id, episode_id


def _canonical_uuid(value: object) -> str:
    if not isinstance(value, str):
        raise ValueError("Invalid correlation ID")
    try:
        canonical = str(uuid.UUID(value))
    except (AttributeError, ValueError):
        raise ValueError("Invalid correlation ID") from None
    if value != canonical:
        raise ValueError("Correlation ID must use canonical lowercase UUID form")
    return canonical


def _continuation_id(value: object) -> str:
    if not isinstance(value, str) or not _CONTINUATION_ID.fullmatch(value):
        raise ValueError("Invalid continuation ID")
    return value
