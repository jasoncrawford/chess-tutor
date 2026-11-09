"""Versioned single-line JSON logging for hosted coaching."""

from __future__ import annotations

from datetime import datetime, timezone
import json
import logging


LOG_SCHEMA_VERSION = "coaching-log.v1"
_LOGGER = logging.getLogger("ChessTutor.CoachingServer")
_RESERVED_FIELDS = {"schema_version", "timestamp", "level", "event"}


def emit_event(event: str, *, level: int = logging.INFO, **fields: object) -> None:
    if not isinstance(event, str) or not event:
        raise ValueError("event must be a nonempty string")
    collision = _RESERVED_FIELDS.intersection(fields)
    if collision:
        raise ValueError(f"reserved log field: {sorted(collision)[0]}")

    payload = {
        "schema_version": LOG_SCHEMA_VERSION,
        "timestamp": _utc_timestamp(),
        "level": logging.getLevelName(level).lower(),
        "event": event,
        **fields,
    }
    message = json.dumps(
        payload,
        ensure_ascii=False,
        separators=(",", ":"),
        allow_nan=False,
    )
    _LOGGER.log(level, message)


def configure_application_logging(*, suppress_werkzeug: bool) -> None:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    _LOGGER.setLevel(logging.INFO)
    logging.getLogger("werkzeug").disabled = suppress_werkzeug


def _utc_timestamp() -> str:
    return (
        datetime.now(timezone.utc)
        .isoformat(timespec="milliseconds")
        .replace("+00:00", "Z")
    )
