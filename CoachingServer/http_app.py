"""Authenticated Flask application for hosted coaching."""

from __future__ import annotations

import hmac
import json
import logging
import os
from pathlib import Path
import re
import time
import uuid

from flask import Flask, Response, request
from werkzeug.exceptions import BadRequest, RequestEntityTooLarge

from CoachingServer.service import (
    HostedCoachingCompletion,
    HostedCoachingService,
    HostedCoachingServiceError,
)
from CoachingServer.structured_logging import emit_event


_MAXIMUM_BODY_BYTES = 128 * 1024
_ERROR_STATUS = {
    "invalidRequest": "400 Bad Request",
    "invalidProviderResponse": "502 Bad Gateway",
    "providerTimeout": "504 Gateway Timeout",
    "providerUnavailable": "503 Service Unavailable",
}
_TRACE_ID_PATTERN = re.compile(r"^[A-Za-z0-9-]{1,64}$")


def create_application(
    *,
    service,
    access_token: str,
    clock=time.monotonic,
    trace_id_factory=lambda: uuid.uuid4().hex[:12],
):
    if not callable(getattr(service, "complete", None)):
        raise ValueError("service must implement complete")
    if not isinstance(access_token, str) or not access_token:
        raise ValueError("access_token must be a nonempty string")

    application = Flask(__name__)
    application.config["MAX_CONTENT_LENGTH"] = _MAXIMUM_BODY_BYTES

    @application.before_request
    def preserve_api_method_contract():
        if request.path == "/health":
            if request.method != "GET":
                return _error_response("404 Not Found", "notFound")
            return None
        if request.path == "/v1/coaching-turn":
            if request.method != "POST":
                return _error_response(
                    "405 Method Not Allowed",
                    "methodNotAllowed",
                )
            return None
        return _error_response("404 Not Found", "notFound")

    @application.errorhandler(404)
    def not_found(_error):
        return _error_response("404 Not Found", "notFound")

    @application.errorhandler(405)
    def method_not_allowed(_error):
        return _error_response("405 Method Not Allowed", "methodNotAllowed")

    @application.errorhandler(RequestEntityTooLarge)
    def body_too_large(_error):
        return _error_response("413 Payload Too Large", "bodyTooLarge")

    @application.get("/health")
    def health():
        return _response("200 OK", {"status": "ok"})

    @application.post("/v1/coaching-turn")
    def coaching_turn():
        if not _authorized(request.headers.get("Authorization"), access_token):
            return _error_response("401 Unauthorized", "unauthorized")
        if request.mimetype != "application/json":
            return _error_response(
                "415 Unsupported Media Type",
                "unsupportedMediaType",
            )
        try:
            raw_body = request.get_data(cache=False)
        except RequestEntityTooLarge:
            return _error_response("413 Payload Too Large", "bodyTooLarge")
        except BadRequest:
            return _error_response("400 Bad Request", "invalidJSON")
        try:
            request_object = json.loads(
                raw_body.decode("utf-8"),
                object_pairs_hook=_strict_json_object,
                parse_constant=_reject_json_constant,
            )
        except (UnicodeDecodeError, ValueError):
            return _error_response("400 Bad Request", "invalidJSON")
        if not isinstance(request_object, dict):
            return _error_response("400 Bad Request", "invalidJSON")

        trace_id = _safe_trace_id(trace_id_factory())
        correlation = _safe_correlation_fields(request_object)
        started = clock()
        emit_event("http_request_started", trace_id=trace_id, **correlation)
        try:
            completion = service.complete(request_object, trace_id=trace_id)
            if not isinstance(completion, HostedCoachingCompletion):
                raise TypeError("Invalid hosted coaching service completion")
        except HostedCoachingServiceError as error:
            status = _ERROR_STATUS[error.code]
            elapsed_milliseconds = _elapsed_milliseconds(clock(), started)
            _log_http_completed(
                trace_id=trace_id,
                correlation=correlation,
                elapsed_milliseconds=elapsed_milliseconds,
                outcome=error.code,
                status=status,
            )
            _log_coaching_turn(
                trace_id=trace_id,
                correlation=correlation,
                diagnostics=error.diagnostics,
                outcome=error.code,
                status=status,
                elapsed_milliseconds=elapsed_milliseconds,
            )
            return _error_response(status, error.code)
        except Exception:
            status = "503 Service Unavailable"
            elapsed_milliseconds = _elapsed_milliseconds(clock(), started)
            _log_http_completed(
                trace_id=trace_id,
                correlation=correlation,
                elapsed_milliseconds=elapsed_milliseconds,
                outcome="providerUnavailable",
                status=status,
            )
            _log_coaching_turn(
                trace_id=trace_id,
                correlation=correlation,
                diagnostics=None,
                outcome="providerUnavailable",
                status=status,
                elapsed_milliseconds=elapsed_milliseconds,
            )
            return _error_response(status, "providerUnavailable")

        elapsed_milliseconds = _elapsed_milliseconds(clock(), started)
        _log_http_completed(
            trace_id=trace_id,
            correlation=correlation,
            elapsed_milliseconds=elapsed_milliseconds,
            outcome="success",
            status="200 OK",
        )
        _log_coaching_turn(
            trace_id=trace_id,
            correlation=correlation,
            diagnostics=completion.diagnostics,
            outcome="success",
            status="200 OK",
            elapsed_milliseconds=elapsed_milliseconds,
        )
        return _response("200 OK", completion.response)

    return application


def create_environment_application():
    api_key = _required_environment("OPENAI_API_KEY")
    access_token = _required_environment("CHESS_TUTOR_COACHING_ACCESS_TOKEN")
    root = Path(__file__).resolve().parents[1]
    system_prompt = (
        root / "Tools/CoachingEval/prompts/tutor-v13.md"
    ).read_text(encoding="utf-8")
    from Tools.CoachingEval.openai_responses import OpenAIResponsesClient

    service = HostedCoachingService(
        provider=OpenAIResponsesClient(api_key=api_key),
        system_prompt=system_prompt,
        follow_up_reasoning_effort=os.environ.get(
            "CHESS_TUTOR_COACHING_FOLLOWUP_REASONING_EFFORT",
            "none",
        ),
    )
    return create_application(service=service, access_token=access_token)


def _required_environment(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def _authorized(header: object, expected_token: str) -> bool:
    if not isinstance(header, str) or not header.startswith("Bearer "):
        return False
    token = header.removeprefix("Bearer ")
    return bool(token) and hmac.compare_digest(token, expected_token)


def _strict_json_object(pairs):
    value = {}
    for key, child in pairs:
        if key in value:
            raise ValueError("Duplicate JSON key")
        value[key] = child
    return value


def _reject_json_constant(_value):
    raise ValueError("Invalid JSON constant")


def _error_response(status: str, code: str) -> Response:
    return _response(status, {"error": {"code": code}})


def _response(status: str, value: object) -> Response:
    body = json.dumps(value, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    response = Response(body, status=status, content_type="application/json; charset=utf-8")
    response.headers["Cache-Control"] = "no-store"
    return response


def _safe_trace_id(value: object) -> str:
    if isinstance(value, str) and _TRACE_ID_PATTERN.fullmatch(value):
        return value
    return "invalid"


def _elapsed_milliseconds(finished: float, started: float) -> float:
    return round(max(0.0, (finished - started) * 1000.0), 3)


def _log_http_completed(
    *,
    trace_id: str,
    correlation: dict[str, str],
    elapsed_milliseconds: float,
    outcome: str,
    status: str,
) -> None:
    emit_event(
        "http_request_completed",
        trace_id=trace_id,
        **correlation,
        elapsed_ms=elapsed_milliseconds,
        outcome=outcome,
        status=int(status.split(" ", 1)[0]),
    )


def _safe_correlation_fields(value: dict[str, object]) -> dict[str, str]:
    fields = {}
    for source, target in (("gameID", "game_id"), ("episodeID", "episode_id")):
        candidate = value.get(source)
        if not isinstance(candidate, str):
            continue
        try:
            canonical = str(uuid.UUID(candidate))
        except (AttributeError, ValueError):
            continue
        if candidate == canonical:
            fields[target] = canonical
    return fields


def _log_coaching_turn(
    *,
    trace_id: str,
    correlation: dict[str, str],
    diagnostics: dict[str, object] | None,
    outcome: str,
    status: str,
    elapsed_milliseconds: float,
) -> None:
    safe = diagnostics if isinstance(diagnostics, dict) else {}
    emit_event(
        "coaching_turn",
        level=logging.INFO if outcome == "success" else logging.WARNING,
        trace_id=trace_id,
        **correlation,
        request=safe.get("request"),
        response=safe.get("response") if outcome == "success" else None,
        provider=safe.get("provider"),
        outcome=outcome,
        http_status=int(status.split(" ", 1)[0]),
        elapsed_ms=elapsed_milliseconds,
    )
