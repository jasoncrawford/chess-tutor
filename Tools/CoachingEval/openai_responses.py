#!/usr/bin/env python3
"""Narrow, trace-free OpenAI Responses API transport for coaching pilots."""

import json
import socket
import urllib.error
import urllib.parse
import urllib.request

try:
    from .http_security import SameOriginAuthorizationRedirectHandler
except ImportError:
    from http_security import SameOriginAuthorizationRedirectHandler


__all__ = ["OpenAIResponsesClient", "OpenAIResponsesError"]

_ERROR_CATEGORIES = frozenset(
    (
        "httpError",
        "timeout",
        "transportError",
        "invalidResponse",
        "incompleteResponse",
        "refusal",
        "multipleOutputTexts",
    )
)
_MAXIMUM_ERROR_BODY_BYTES = 64 * 1024
_MAXIMUM_RESPONSE_BODY_BYTES = 1024 * 1024
_MAXIMUM_IDENTIFIER_BYTES = 256
_MAXIMUM_OUTPUT_TEXT_BYTES = 64 * 1024
_MAXIMUM_TOKEN_COUNT = 1_000_000_000


class OpenAIResponsesError(RuntimeError):
    """A bounded provider failure that never retains provider response content."""

    def __init__(self, message, *, category="invalidResponse", http_status=None):
        super().__init__(message)
        self.category = category if category in _ERROR_CATEGORIES else "invalidResponse"
        self.http_status = http_status if isinstance(http_status, int) else None


class OpenAIResponsesClient:
    """Send one role-separated, strict-schema request and return only final output."""

    def __init__(self, base_url="https://api.openai.com", *, api_key=None):
        if api_key is not None and (not isinstance(api_key, str) or not api_key):
            raise ValueError("API key must be a non-empty string")

        base_url = _validated_base_url(base_url)
        if api_key is not None:
            parsed = urllib.parse.urlparse(base_url)
            if parsed.scheme.lower() != "https":
                raise ValueError("OpenAI credentials require an HTTPS endpoint")
            if (
                parsed.hostname.lower() != "api.openai.com"
                or parsed.username is not None
                or parsed.password is not None
                or parsed.port not in {None, 443}
            ):
                raise ValueError(
                    "OpenAI credentials require the official OpenAI API origin"
                )

        if base_url.endswith("/v1/responses"):
            self.url = base_url
        elif base_url.endswith("/v1"):
            self.url = base_url + "/responses"
        else:
            self.url = base_url + "/v1/responses"
        self.api_key = api_key
        self.opener = urllib.request.build_opener(
            SameOriginAuthorizationRedirectHandler()
        )

    def complete(
        self,
        *,
        system_prompt,
        user_prompt,
        schema,
        model,
        reasoning_effort,
        maximum_output_tokens,
        timeout,
    ):
        _validate_arguments(
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            schema=schema,
            model=model,
            reasoning_effort=reasoning_effort,
            maximum_output_tokens=maximum_output_tokens,
            timeout=timeout,
        )
        payload = {
            "model": model,
            "input": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            "reasoning": {"effort": reasoning_effort},
            "max_output_tokens": maximum_output_tokens,
            "text": {
                "format": {
                    "type": "json_schema",
                    "name": "chess_coaching_turn",
                    "strict": True,
                    "schema": schema,
                }
            },
            "store": False,
        }
        try:
            request_body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        except (TypeError, ValueError):
            raise ValueError("Responses API request must be JSON serializable") from None

        headers = {"Content-Type": "application/json"}
        if self.api_key is not None:
            headers["Authorization"] = f"Bearer {self.api_key}"
        request = urllib.request.Request(
            self.url,
            data=request_body,
            headers=headers,
            method="POST",
        )
        try:
            with self.opener.open(request, timeout=timeout) as response:
                body = _read_bounded_response(response)
        except urllib.error.HTTPError as error:
            _discard_http_error(error)
            raise OpenAIResponsesError(
                f"OpenAI Responses API returned HTTP {error.code}",
                category="httpError",
                http_status=error.code,
            ) from None
        except (TimeoutError, socket.timeout):
            raise OpenAIResponsesError(
                "OpenAI Responses API request timed out",
                category="timeout",
            ) from None
        except urllib.error.URLError as error:
            category = (
                "timeout"
                if isinstance(error.reason, (TimeoutError, socket.timeout))
                else "transportError"
            )
            message = (
                "OpenAI Responses API request timed out"
                if category == "timeout"
                else "OpenAI Responses API request failed"
            )
            raise OpenAIResponsesError(message, category=category) from None
        except (OSError, ValueError):
            raise OpenAIResponsesError(
                "OpenAI Responses API request failed",
                category="transportError",
            ) from None

        return _extract_completed_output(body)


def _validated_base_url(base_url):
    if not isinstance(base_url, str) or not base_url:
        raise ValueError("Responses API base URL must be a non-empty string")
    normalized = base_url.rstrip("/")
    parsed = urllib.parse.urlparse(normalized)
    if parsed.scheme.lower() not in {"http", "https"} or not parsed.hostname:
        raise ValueError("Responses API base URL must be HTTP or HTTPS")
    if parsed.query or parsed.fragment:
        raise ValueError("Responses API base URL cannot contain a query or fragment")
    return normalized


def _validate_arguments(
    *,
    system_prompt,
    user_prompt,
    schema,
    model,
    reasoning_effort,
    maximum_output_tokens,
    timeout,
):
    if not isinstance(system_prompt, str) or not isinstance(user_prompt, str):
        raise ValueError("Responses API prompts must be strings")
    if not isinstance(schema, dict):
        raise ValueError("Responses API schema must be an object")
    if not isinstance(model, str) or not model:
        raise ValueError("Responses API model must be a non-empty string")
    if not isinstance(reasoning_effort, str) or not reasoning_effort:
        raise ValueError("Responses API reasoning effort must be a non-empty string")
    if (
        isinstance(maximum_output_tokens, bool)
        or not isinstance(maximum_output_tokens, int)
        or maximum_output_tokens <= 0
    ):
        raise ValueError("Responses API maximum output tokens must be positive")
    if isinstance(timeout, bool) or not isinstance(timeout, (int, float)) or timeout <= 0:
        raise ValueError("Responses API timeout must be positive")


def _read_bounded_response(response):
    try:
        raw_body = response.read(_MAXIMUM_RESPONSE_BODY_BYTES + 1)
    except OSError:
        raise OpenAIResponsesError(
            "OpenAI Responses API request failed",
            category="transportError",
        ) from None
    if len(raw_body) > _MAXIMUM_RESPONSE_BODY_BYTES:
        raise _invalid_response()
    try:
        decoded = raw_body.decode("utf-8")
        body = json.loads(decoded)
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise _invalid_response() from None
    if not isinstance(body, dict):
        raise _invalid_response()
    return body


def _discard_http_error(error):
    try:
        error.read(_MAXIMUM_ERROR_BODY_BYTES)
    except (OSError, ValueError):
        pass
    try:
        error.close()
    except (OSError, ValueError):
        pass


def _extract_completed_output(response):
    if response.get("status") != "completed":
        raise OpenAIResponsesError(
            "OpenAI Responses API did not return a completed response",
            category="incompleteResponse",
        )
    if response.get("error") is not None or response.get("incomplete_details") is not None:
        raise _invalid_response()

    response_id = _bounded_identifier(response.get("id"))
    model = _bounded_identifier(response.get("model"))
    candidates = []
    saw_refusal = False
    output = response.get("output")
    if not isinstance(output, list):
        raise _invalid_response()
    for item in output:
        if not isinstance(item, dict):
            raise _invalid_response()
        item_type = item.get("type")
        if item_type == "reasoning":
            continue
        if item_type != "message":
            raise _invalid_response()
        if item.get("status") != "completed":
            raise OpenAIResponsesError(
                "OpenAI Responses API did not return a completed response",
                category="incompleteResponse",
            )
        content = item.get("content")
        if not isinstance(content, list):
            raise _invalid_response()
        for part in content:
            if not isinstance(part, dict):
                raise _invalid_response()
            part_type = part.get("type")
            if part_type == "refusal":
                saw_refusal = True
            elif part_type == "output_text":
                text = part.get("text")
                if not isinstance(text, str) or not text:
                    raise _invalid_response()
                if _utf8_size(text) > _MAXIMUM_OUTPUT_TEXT_BYTES:
                    raise _invalid_response()
                candidates.append(text)
            else:
                raise _invalid_response()

    if saw_refusal:
        raise OpenAIResponsesError(
            "OpenAI Responses API returned a refusal",
            category="refusal",
        )
    if len(candidates) > 1:
        raise OpenAIResponsesError(
            "OpenAI Responses API returned multiple output texts",
            category="multipleOutputTexts",
        )
    if not candidates:
        raise _invalid_response()

    usage = response.get("usage")
    if not isinstance(usage, dict):
        raise _invalid_response()
    bounded_usage = {
        key: _bounded_token_count(usage.get(key))
        for key in ("input_tokens", "output_tokens", "total_tokens")
    }
    output_details = usage.get("output_tokens_details")
    if output_details is None:
        reasoning_tokens = 0
    elif isinstance(output_details, dict):
        reasoning_tokens = _bounded_token_count(
            output_details.get("reasoning_tokens", 0)
        )
    else:
        raise _invalid_response()
    bounded_usage["reasoning_tokens"] = reasoning_tokens
    return {
        "id": response_id,
        "model": model,
        "status": "completed",
        "output_text": candidates[0],
        "usage": bounded_usage,
    }


def _bounded_identifier(value):
    if (
        not isinstance(value, str)
        or not value
        or _utf8_size(value) > _MAXIMUM_IDENTIFIER_BYTES
    ):
        raise _invalid_response()
    return value


def _bounded_token_count(value):
    if (
        isinstance(value, bool)
        or not isinstance(value, int)
        or value < 0
        or value > _MAXIMUM_TOKEN_COUNT
    ):
        raise _invalid_response()
    return value


def _utf8_size(value):
    try:
        return len(value.encode("utf-8"))
    except UnicodeEncodeError:
        raise _invalid_response() from None


def _invalid_response():
    return OpenAIResponsesError(
        "OpenAI Responses API returned an invalid response",
        category="invalidResponse",
    )
