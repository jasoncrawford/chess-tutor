"""Shared structured-output contract for benchmark judge calls."""

import json
import math
import time
from decimal import Decimal
from typing import Mapping


RUBRIC_DIMENSIONS = (
    "chessCorrectness",
    "coachingJudgment",
    "latestActionResponsiveness",
    "discoveryAndIndependence",
    "coherenceAndAnswerability",
    "childClarity",
)
RUBRIC_FLAGS = (
    "factualOrIllegalAdvice",
    "wrongUrgentPriority",
    "obsoleteStage",
    "mixedStages",
    "answerRevealingGuidance",
    "unavailableUIOrDeadEnd",
    "severeError",
)


class JudgeCallError(ValueError):
    """A sanitized judge-response failure that retains bounded call metrics."""

    def __init__(self, message, metrics):
        super().__init__(message)
        self.metrics = metrics


def judge_call(configuration, client, payload, schema, price_table):
    started = time.monotonic()
    response = client.complete(
        system_prompt=configuration.system_prompt,
        user_prompt=json.dumps(payload, sort_keys=True, separators=(",", ":")),
        schema=schema,
        model=configuration.model,
        reasoning_effort=configuration.reasoning_effort,
        maximum_output_tokens=configuration.maximum_output_tokens,
        timeout=configuration.timeout_seconds,
        previous_response_id=None,
        store=False,
    )
    latency = _bounded_float((time.monotonic() - started) * 1000)
    usage = _usage(response.get("usage") if isinstance(response, dict) else None)
    metrics = {
        "callCount": 1,
        "usage": usage,
        "latencyMilliseconds": latency,
        "estimatedCostUSD": (
            str(price_table.estimate(configuration.model, usage))
            if price_table is not None
            else None
        ),
    }
    output_text = response.get("output_text") if isinstance(response, dict) else None
    if not isinstance(output_text, str) or not output_text:
        raise JudgeCallError("Judge returned no structured output", metrics)
    try:
        output = json.loads(output_text, object_pairs_hook=_strict_object)
    except (TypeError, ValueError, _DuplicateKey) as error:
        raise JudgeCallError(
            "Judge returned malformed structured output", metrics
        ) from error
    return output, metrics


def preflight_price(configuration, price_table):
    if price_table is not None:
        price_table.estimate(configuration.model, empty_metrics()["usage"])


def validate_absolute(value):
    if not isinstance(value, dict) or set(value) != {"scores", "flags", "evidence"}:
        raise ValueError("Absolute judge fields do not match")
    validate_scores(value["scores"])
    validate_flags(value["flags"])
    evidence = validate_evidence(value["evidence"])
    return {
        "scores": dict(value["scores"]),
        "flags": dict(value["flags"]),
        "evidence": evidence,
    }


def validate_pairwise(value):
    if not isinstance(value, dict) or set(value) != {"winner", "evidence"}:
        raise ValueError("Pairwise judge fields do not match")
    if value["winner"] not in ("A", "B", "tie"):
        raise ValueError("Pairwise winner is invalid")
    return {"winner": value["winner"], "evidence": validate_evidence(value["evidence"])}


def validate_scores(value):
    if not isinstance(value, dict) or tuple(sorted(value)) != tuple(
        sorted(RUBRIC_DIMENSIONS)
    ):
        raise ValueError("Judge score fields do not match")
    if any(
        isinstance(score, bool) or not isinstance(score, int) or not 1 <= score <= 5
        for score in value.values()
    ):
        raise ValueError("Judge scores must be integers from 1 to 5")


def validate_flags(value):
    if not isinstance(value, dict) or tuple(sorted(value)) != tuple(
        sorted(RUBRIC_FLAGS)
    ):
        raise ValueError("Judge flag fields do not match")
    if any(not isinstance(flag, bool) for flag in value.values()):
        raise ValueError("Judge flags must be booleans")


def validate_evidence(value):
    if not isinstance(value, list) or not 1 <= len(value) <= 3:
        raise ValueError("Judge evidence must contain one to three items")
    if any(
        not isinstance(item, str) or not item or len(item) > 500 for item in value
    ):
        raise ValueError("Judge evidence is invalid")
    return list(value)


def absolute_schema():
    return {
        "type": "object",
        "properties": {
            "scores": {
                "type": "object",
                "properties": {
                    dimension: {"type": "integer", "minimum": 1, "maximum": 5}
                    for dimension in RUBRIC_DIMENSIONS
                },
                "required": list(RUBRIC_DIMENSIONS),
                "additionalProperties": False,
            },
            "flags": {
                "type": "object",
                "properties": {
                    flag: {"type": "boolean"} for flag in RUBRIC_FLAGS
                },
                "required": list(RUBRIC_FLAGS),
                "additionalProperties": False,
            },
            "evidence": {
                "type": "array",
                "items": {"type": "string", "maxLength": 500},
                "minItems": 1,
                "maxItems": 3,
            },
        },
        "required": ["scores", "flags", "evidence"],
        "additionalProperties": False,
    }


def pairwise_schema():
    return {
        "type": "object",
        "properties": {
            "winner": {"type": "string", "enum": ["A", "B", "tie"]},
            "evidence": {
                "type": "array",
                "items": {"type": "string", "maxLength": 500},
                "minItems": 1,
                "maxItems": 3,
            },
        },
        "required": ["winner", "evidence"],
        "additionalProperties": False,
    }


def empty_metrics():
    return {
        "callCount": 0,
        "usage": {
            "inputTokens": 0,
            "cachedInputTokens": 0,
            "outputTokens": 0,
            "reasoningTokens": 0,
            "totalTokens": 0,
        },
        "latencyMilliseconds": 0.0,
        "estimatedCostUSD": None,
    }


def add_metrics(total, current):
    total["callCount"] += current["callCount"]
    for key in total["usage"]:
        total["usage"][key] += current["usage"][key]
    total["latencyMilliseconds"] += current["latencyMilliseconds"]
    if current["estimatedCostUSD"] is not None:
        prior = total["estimatedCostUSD"] or "0"
        total["estimatedCostUSD"] = str(
            Decimal(prior) + Decimal(current["estimatedCostUSD"])
        )


def canonical_json_bytes(value):
    return json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode("utf-8")


def pretty_json_bytes(value):
    return (
        json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    ).encode("utf-8")


class _DuplicateKey(ValueError):
    pass


def _strict_object(pairs):
    value = {}
    for key, child in pairs:
        if key in value:
            raise _DuplicateKey()
        value[key] = child
    return value


def _usage(value):
    value = value if isinstance(value, Mapping) else {}
    return {
        "inputTokens": _bounded_int(value.get("input_tokens")),
        "cachedInputTokens": _bounded_int(value.get("cached_input_tokens")),
        "outputTokens": _bounded_int(value.get("output_tokens")),
        "reasoningTokens": _bounded_int(value.get("reasoning_tokens")),
        "totalTokens": _bounded_int(value.get("total_tokens")),
    }


def _bounded_int(value):
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        return 0
    return min(value, 1_000_000_000)


def _bounded_float(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return 0.0
    value = float(value)
    return value if math.isfinite(value) and 0 <= value <= 86_400_000 else 0.0
