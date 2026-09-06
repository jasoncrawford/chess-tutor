"""Validation shared by hosted coaching provider-response consumers."""

from __future__ import annotations

import re
from collections.abc import Mapping


_CONTINUATION_ID = re.compile(r"resp_[A-Za-z0-9_-]{1,251}\Z")


def validate_provider_envelope(value: object) -> tuple[str, str]:
    if not isinstance(value, Mapping):
        raise ValueError("Provider response must be an object")
    if value.get("status") != "completed":
        raise ValueError("Provider response is not completed")
    output_text = value.get("output_text")
    if not isinstance(output_text, str):
        raise ValueError("Provider response output must be a string")
    response_id = validate_continuation_id(value.get("id"))
    return response_id, output_text


def validate_continuation_id(value: object) -> str:
    if not isinstance(value, str) or not _CONTINUATION_ID.fullmatch(value):
        raise ValueError("Invalid continuation ID")
    return value
