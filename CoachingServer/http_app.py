"""Authenticated, dependency-free WSGI adapter for hosted coaching."""

from __future__ import annotations

import hmac
import json
import logging
import os
from pathlib import Path
import re
import time
import uuid

from CoachingServer.service import HostedCoachingService, HostedCoachingServiceError


_MAXIMUM_BODY_BYTES = 128 * 1024
_ERROR_STATUS = {
    "invalidRequest": "400 Bad Request",
    "invalidProviderResponse": "502 Bad Gateway",
    "providerTimeout": "504 Gateway Timeout",
    "providerUnavailable": "503 Service Unavailable",
}
_LOGGER = logging.getLogger("ChessTutor.CoachingServer")
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

    def application(environ, start_response):
        method = environ.get("REQUEST_METHOD", "")
        path = environ.get("PATH_INFO", "")
        if method == "GET" and path == "/health":
            return _respond(start_response, "200 OK", {"status": "ok"})
        if path != "/v1/coaching-turn":
            return _error(start_response, "404 Not Found", "notFound")
        if method != "POST":
            return _error(start_response, "405 Method Not Allowed", "methodNotAllowed")
        if not _authorized(environ.get("HTTP_AUTHORIZATION"), access_token):
            return _error(start_response, "401 Unauthorized", "unauthorized")
        content_type = environ.get("CONTENT_TYPE", "").split(";", 1)[0].strip().lower()
        if content_type != "application/json":
            return _error(
                start_response,
                "415 Unsupported Media Type",
                "unsupportedMediaType",
            )
        try:
            content_length = int(environ.get("CONTENT_LENGTH", ""))
        except (TypeError, ValueError):
            return _error(start_response, "400 Bad Request", "invalidJSON")
        if content_length < 0:
            return _error(start_response, "400 Bad Request", "invalidJSON")
        if content_length > _MAXIMUM_BODY_BYTES:
            return _error(start_response, "413 Payload Too Large", "bodyTooLarge")
        try:
            raw_body = environ["wsgi.input"].read(content_length + 1)
        except (KeyError, OSError, ValueError):
            return _error(start_response, "400 Bad Request", "invalidJSON")
        if len(raw_body) != content_length:
            return _error(start_response, "400 Bad Request", "invalidJSON")
        try:
            request = json.loads(
                raw_body.decode("utf-8"),
                object_pairs_hook=_strict_json_object,
                parse_constant=_reject_json_constant,
            )
        except (UnicodeDecodeError, ValueError):
            return _error(start_response, "400 Bad Request", "invalidJSON")
        if not isinstance(request, dict):
            return _error(start_response, "400 Bad Request", "invalidJSON")
        trace_id = _safe_trace_id(trace_id_factory())
        started = clock()
        _LOGGER.info("event=http_request_started trace_id=%s", trace_id)
        try:
            response = service.complete(request, trace_id=trace_id)
        except HostedCoachingServiceError as error:
            status = _ERROR_STATUS[error.code]
            _log_http_completed(
                trace_id=trace_id,
                elapsed_milliseconds=_elapsed_milliseconds(clock(), started),
                outcome=error.code,
                status=status,
            )
            return _error(
                start_response,
                status,
                error.code,
            )
        except Exception:
            status = "503 Service Unavailable"
            _log_http_completed(
                trace_id=trace_id,
                elapsed_milliseconds=_elapsed_milliseconds(clock(), started),
                outcome="providerUnavailable",
                status=status,
            )
            return _error(
                start_response,
                status,
                "providerUnavailable",
            )
        _log_http_completed(
            trace_id=trace_id,
            elapsed_milliseconds=_elapsed_milliseconds(clock(), started),
            outcome="success",
            status="200 OK",
        )
        return _respond(start_response, "200 OK", response)

    return application


def create_environment_application():
    api_key = _required_environment("OPENAI_API_KEY")
    access_token = _required_environment("CHESS_TUTOR_COACHING_ACCESS_TOKEN")
    root = Path(__file__).resolve().parents[1]
    system_prompt = (
        root / "Tools/CoachingEval/prompts/tutor-v6.md"
    ).read_text(encoding="utf-8")
    from Tools.CoachingEval.openai_responses import OpenAIResponsesClient

    service = HostedCoachingService(
        provider=OpenAIResponsesClient(api_key=api_key),
        system_prompt=system_prompt,
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


def _error(start_response, status: str, code: str):
    return _respond(start_response, status, {"error": {"code": code}})


def _respond(start_response, status: str, value: object):
    body = json.dumps(value, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    start_response(
        status,
        [
            ("Content-Type", "application/json; charset=utf-8"),
            ("Content-Length", str(len(body))),
            ("Cache-Control", "no-store"),
        ],
    )
    return [body]


def _safe_trace_id(value: object) -> str:
    if isinstance(value, str) and _TRACE_ID_PATTERN.fullmatch(value):
        return value
    return "invalid"


def _elapsed_milliseconds(finished: float, started: float) -> float:
    return round(max(0.0, (finished - started) * 1000.0), 3)


def _log_http_completed(
    *,
    trace_id: str,
    elapsed_milliseconds: float,
    outcome: str,
    status: str,
) -> None:
    _LOGGER.info(
        (
            "event=http_request_completed trace_id=%s "
            "elapsed_ms=%s outcome=%s status=%s"
        ),
        trace_id,
        elapsed_milliseconds,
        outcome,
        status.split(" ", 1)[0],
    )
