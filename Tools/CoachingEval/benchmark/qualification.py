"""Reusable qualification for the benchmark's LLM judge."""

import hashlib
import json
import math
import os
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any, Mapping

from Tools.CoachingEval.benchmark.judge_contract import (
    JudgeCallError,
    RUBRIC_DIMENSIONS,
    absolute_schema as _absolute_schema,
    add_metrics as _add_metrics,
    canonical_json_bytes as _canonical_json_bytes,
    empty_metrics as _empty_metrics,
    judge_call as _judge_call,
    pairwise_schema as _pairwise_schema,
    preflight_price as _preflight_price,
    pretty_json_bytes as _pretty_json_bytes,
    validate_absolute as _validate_absolute,
    validate_evidence as _validate_evidence,
    validate_flags as _validate_flags,
    validate_scores as _validate_scores,
)
from Tools.CoachingEval.benchmark.reference_set import JudgeReferenceSet


_ARTIFACT_KEYS = frozenset(
    (
        "schemaVersion",
        "status",
        "judgeConfigurationID",
        "referenceSetID",
        "createdAt",
        "expiresAt",
        "criteria",
        "bindings",
        "minimumSevereAgreement",
        "minimumDimensionAgreement",
        "qualificationMetrics",
        "passes",
    )
)
_PASS_KEYS = frozenset(
    (
        "repetition",
        "completed",
        "passed",
        "severeAgreement",
        "dimensionWithinOne",
        "failureCategory",
        "judgeMetrics",
        "rows",
    )
)
_ROW_KEYS = frozenset(
    (
        "rowID",
        "severeMatch",
        "dimensionsWithinOne",
        "referenceScores",
        "judgeScores",
        "referenceFlags",
        "judgeFlags",
        "evidence",
    )
)
_METRICS_KEYS = frozenset(
    ("callCount", "usage", "latencyMilliseconds", "estimatedCostUSD")
)
_USAGE_KEYS = frozenset(
    (
        "inputTokens",
        "cachedInputTokens",
        "outputTokens",
        "reasoningTokens",
        "totalTokens",
    )
)


class QualificationFailed(ValueError):
    def __init__(self, artifact_path: Path):
        super().__init__("Judge qualification failed")
        self.artifact_path = artifact_path


@dataclass(frozen=True)
class JudgeQualification:
    path: Path
    created_at: datetime
    expires_at: datetime
    minimum_severe_agreement: float
    minimum_dimension_agreement: float
    artifact: Mapping[str, Any]
    artifact_bytes: bytes

    @classmethod
    def ensure(
        cls,
        configuration,
        client,
        price_table,
        artifact_root: Path,
        now: datetime,
    ) -> Path:
        now = _utc_datetime(now)
        reference = cls._load_reference(configuration)
        _preflight_price(configuration, price_table)
        reusable = cls._newest_compatible(artifact_root, configuration, now)
        if reusable is not None:
            return reusable.path

        passes = []
        qualification_metrics = _empty_metrics()
        for repetition in range(1, configuration.qualification_repetitions + 1):
            result = cls._evaluate_pass(
                configuration,
                reference,
                client,
                price_table,
                repetition,
            )
            passes.append(result)
            _add_metrics(qualification_metrics, result["judgeMetrics"])
            if not result["completed"]:
                break

        minimum_severe = min(result["severeAgreement"] for result in passes)
        minimum_dimension = min(result["dimensionWithinOne"] for result in passes)
        accepted = (
            len(passes) == configuration.qualification_repetitions
            and all(result["passed"] for result in passes)
        )
        expires = now + timedelta(days=configuration.qualification_valid_days)
        artifact = {
            "schemaVersion": "coaching-quality-judge-qualification.v2",
            "status": "accepted" if accepted else "rejected",
            "judgeConfigurationID": configuration.identifier,
            "referenceSetID": reference.identifier,
            "createdAt": _format_datetime(now),
            "expiresAt": _format_datetime(expires),
            "criteria": {
                "repetitions": configuration.qualification_repetitions,
                "minimumSevereAgreement": configuration.minimum_severe_agreement,
                "minimumDimensionAgreement": configuration.minimum_dimension_agreement,
                "validDays": configuration.qualification_valid_days,
            },
            "bindings": _bindings(configuration),
            "minimumSevereAgreement": minimum_severe,
            "minimumDimensionAgreement": minimum_dimension,
            "qualificationMetrics": qualification_metrics,
            "passes": passes,
        }
        path = _publish(artifact_root, artifact, now)
        if not accepted:
            raise QualificationFailed(path)
        return path

    @classmethod
    def load_compatible(cls, path: Path, configuration, now: datetime):
        now = _utc_datetime(now)
        reference = cls._load_reference(configuration)
        path = Path(path)
        if path.is_dir():
            path = path / "qualification.json"
        try:
            artifact_bytes = path.read_bytes()
            artifact = json.loads(artifact_bytes.decode("utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as error:
            raise ValueError("Cannot load judge qualification") from error
        if not isinstance(artifact, dict) or set(artifact) != _ARTIFACT_KEYS:
            raise ValueError("Judge qualification fields do not match")
        if artifact["schemaVersion"] != "coaching-quality-judge-qualification.v2":
            raise ValueError("Unsupported judge qualification schema")
        if artifact["status"] == "rejected":
            raise ValueError("Judge qualification was rejected")
        if artifact["status"] != "accepted":
            raise ValueError("Judge qualification status is invalid")
        if artifact["judgeConfigurationID"] != configuration.identifier:
            raise ValueError("Judge qualification is not compatible")
        if artifact["referenceSetID"] != reference.identifier:
            raise ValueError("Judge qualification is not compatible")
        if artifact["bindings"] != _bindings(configuration):
            raise ValueError("Judge qualification is not compatible")
        created_at = _parse_datetime(artifact["createdAt"])
        expires_at = _parse_datetime(artifact["expiresAt"])
        if created_at > now:
            raise ValueError("Judge qualification was created in the future")
        expected_expiration = created_at + timedelta(
            days=configuration.qualification_valid_days
        )
        if expires_at != expected_expiration:
            raise ValueError("Judge qualification validity interval is invalid")
        if now >= expires_at:
            raise ValueError("Judge qualification has expired")
        cls._validate_accepted_results(artifact, configuration, reference)
        if not path.parent.name.endswith(f"-{_sha256(artifact_bytes)}"):
            raise ValueError("Judge qualification content address is invalid")
        return cls(
            path=path,
            created_at=created_at,
            expires_at=expires_at,
            minimum_severe_agreement=artifact["minimumSevereAgreement"],
            minimum_dimension_agreement=artifact["minimumDimensionAgreement"],
            artifact=artifact,
            artifact_bytes=artifact_bytes,
        )

    @classmethod
    def _load_reference(cls, configuration):
        if (
            configuration.schema_version != "coaching-quality-judge.v2"
            or configuration.reference_set_path is None
            or configuration.reference_set_sha256 is None
        ):
            raise ValueError("Judge qualification requires a v2 judge configuration")
        return JudgeReferenceSet.load(
            configuration.reference_set_path,
            configuration.reference_set_sha256,
            require_reviewed=True,
        )

    @classmethod
    def _newest_compatible(cls, artifact_root, configuration, now):
        artifact_root = Path(artifact_root)
        compatible = []
        if artifact_root.exists():
            for path in artifact_root.glob("*/qualification.json"):
                try:
                    compatible.append(cls.load_compatible(path, configuration, now))
                except ValueError:
                    continue
        return max(compatible, key=lambda value: value.created_at, default=None)

    @classmethod
    def _evaluate_pass(
        cls,
        configuration,
        reference,
        client,
        price_table,
        repetition,
    ):
        severe_matches = 0
        dimension_matches = 0
        metrics = _empty_metrics()
        rows = []
        for case in reference.cases:
            payload = {
                "kind": "absolute",
                "graderBrief": _plain(case["graderBrief"]),
                "judgeContext": _plain(case["judgeContext"]),
                "availableUI": _plain(case["availableUI"]),
                "candidateTurn": _plain(case["candidateTurn"]),
            }
            call_started = time.monotonic()
            call_metrics = None
            try:
                output, call_metrics = _judge_call(
                    configuration,
                    client,
                    payload,
                    _absolute_schema(),
                    price_table,
                )
                grade = _validate_absolute(output)
            except Exception as error:
                if isinstance(error, JudgeCallError):
                    failed_metrics = error.metrics
                elif call_metrics is not None:
                    failed_metrics = call_metrics
                else:
                    failed_metrics = _empty_metrics()
                    failed_metrics["callCount"] = 1
                    failed_metrics["latencyMilliseconds"] = min(
                        max((time.monotonic() - call_started) * 1000, 0.0),
                        86_400_000.0,
                    )
                _add_metrics(metrics, failed_metrics)
                return _pass_result(
                    repetition,
                    False,
                    0.0,
                    0.0,
                    metrics,
                    rows,
                    "judgeCallFailed",
                )
            reference_scores = dict(case["referenceScores"])
            reference_flags = dict(case["referenceFlags"])
            severe_match = (
                grade["flags"]["severeError"] == reference_flags["severeError"]
            )
            dimensions_within_one = sum(
                abs(grade["scores"][dimension] - reference_scores[dimension]) <= 1
                for dimension in RUBRIC_DIMENSIONS
            )
            severe_matches += severe_match
            dimension_matches += dimensions_within_one
            _add_metrics(metrics, call_metrics)
            rows.append(
                {
                    "rowID": case["id"],
                    "severeMatch": severe_match,
                    "dimensionsWithinOne": dimensions_within_one,
                    "referenceScores": reference_scores,
                    "judgeScores": grade["scores"],
                    "referenceFlags": reference_flags,
                    "judgeFlags": grade["flags"],
                    "evidence": grade["evidence"],
                }
            )
        severe_agreement = severe_matches / len(reference.cases)
        dimension_agreement = dimension_matches / (
            len(reference.cases) * len(RUBRIC_DIMENSIONS)
        )
        return _pass_result(
            repetition,
            True,
            severe_agreement,
            dimension_agreement,
            metrics,
            rows,
            None,
            passed=(
                severe_agreement >= configuration.minimum_severe_agreement
                and dimension_agreement >= configuration.minimum_dimension_agreement
            ),
        )

    @classmethod
    def _validate_accepted_results(cls, artifact, configuration, reference):
        criteria = artifact["criteria"]
        expected_criteria = {
            "repetitions": configuration.qualification_repetitions,
            "minimumSevereAgreement": configuration.minimum_severe_agreement,
            "minimumDimensionAgreement": configuration.minimum_dimension_agreement,
            "validDays": configuration.qualification_valid_days,
        }
        if criteria != expected_criteria:
            raise ValueError("Judge qualification is not compatible")
        passes = artifact["passes"]
        if not isinstance(passes, list) or len(passes) != criteria["repetitions"]:
            raise ValueError("Judge qualification pass inventory is invalid")
        severe_values = []
        dimension_values = []
        qualification_metrics = _empty_metrics()
        for index, result in enumerate(passes, start=1):
            if (
                not isinstance(result, dict)
                or set(result) != _PASS_KEYS
                or result["repetition"] != index
                or result["completed"] is not True
                or result["failureCategory"] is not None
            ):
                raise ValueError("Judge qualification pass is invalid")
            rows = result["rows"]
            if not isinstance(rows, list) or len(rows) != len(reference.cases):
                raise ValueError("Judge qualification pass is invalid")
            severe_matches = 0
            dimension_matches = 0
            for case, row in zip(reference.cases, rows):
                if (
                    not isinstance(row, dict)
                    or set(row) != _ROW_KEYS
                    or row["rowID"] != case["id"]
                    or not isinstance(row["severeMatch"], bool)
                    or isinstance(row["dimensionsWithinOne"], bool)
                    or not isinstance(row["dimensionsWithinOne"], int)
                    or not 0 <= row["dimensionsWithinOne"] <= len(RUBRIC_DIMENSIONS)
                ):
                    raise ValueError("Judge qualification row is invalid")
                _validate_scores(row["referenceScores"])
                _validate_scores(row["judgeScores"])
                _validate_flags(row["referenceFlags"])
                _validate_flags(row["judgeFlags"])
                _validate_evidence(row["evidence"])
                if (
                    row["referenceScores"] != dict(case["referenceScores"])
                    or row["referenceFlags"] != dict(case["referenceFlags"])
                ):
                    raise ValueError("Judge qualification row reference is invalid")
                severe_match = (
                    row["judgeFlags"]["severeError"]
                    == row["referenceFlags"]["severeError"]
                )
                dimensions_within_one = sum(
                    abs(
                        row["judgeScores"][dimension]
                        - row["referenceScores"][dimension]
                    )
                    <= 1
                    for dimension in RUBRIC_DIMENSIONS
                )
                if (
                    row["severeMatch"] is not severe_match
                    or row["dimensionsWithinOne"] != dimensions_within_one
                ):
                    raise ValueError("Judge qualification row agreement is invalid")
                severe_matches += severe_match
                dimension_matches += dimensions_within_one
            severe = severe_matches / len(rows)
            dimension = dimension_matches / (len(rows) * len(RUBRIC_DIMENSIONS))
            if (
                result["severeAgreement"] != severe
                or result["dimensionWithinOne"] != dimension
                or result["passed"] is not True
                or severe < criteria["minimumSevereAgreement"]
                or dimension < criteria["minimumDimensionAgreement"]
            ):
                raise ValueError("Judge qualification pass is invalid")
            _validate_metrics(result["judgeMetrics"])
            _add_metrics(qualification_metrics, result["judgeMetrics"])
            severe_values.append(severe)
            dimension_values.append(dimension)
        if (
            not _agreement(artifact["minimumSevereAgreement"])
            or not _agreement(artifact["minimumDimensionAgreement"])
            or artifact["minimumSevereAgreement"] != min(severe_values)
            or artifact["minimumDimensionAgreement"] != min(dimension_values)
        ):
            raise ValueError("Judge qualification minimum agreement is invalid")
        _validate_metrics(artifact["qualificationMetrics"])
        if artifact["qualificationMetrics"] != qualification_metrics:
            raise ValueError("Judge qualification metrics are invalid")


def _bindings(configuration):
    return {
        "judgeConfigurationSHA256": configuration.sha256,
        "judgePromptSHA256": configuration.system_prompt_sha256,
        "referenceSetSHA256": configuration.reference_set_sha256,
        "absoluteSchemaSHA256": _sha256(_canonical_json_bytes(_absolute_schema())),
        "pairwiseSchemaSHA256": _sha256(_canonical_json_bytes(_pairwise_schema())),
    }


def _pass_result(
    repetition,
    completed,
    severe_agreement,
    dimension_agreement,
    metrics,
    rows,
    failure_category,
    *,
    passed=False,
):
    return {
        "repetition": repetition,
        "completed": completed,
        "passed": passed,
        "severeAgreement": severe_agreement,
        "dimensionWithinOne": dimension_agreement,
        "failureCategory": failure_category,
        "judgeMetrics": metrics,
        "rows": rows,
    }


def _validate_metrics(value):
    if not isinstance(value, dict) or set(value) != _METRICS_KEYS:
        raise ValueError("Judge qualification metrics are invalid")
    call_count = value["callCount"]
    latency = value["latencyMilliseconds"]
    usage = value["usage"]
    if (
        isinstance(call_count, bool)
        or not isinstance(call_count, int)
        or call_count < 0
        or isinstance(latency, bool)
        or not isinstance(latency, (int, float))
        or not math.isfinite(latency)
        or not 0 <= latency <= 86_400_000
        or not isinstance(usage, dict)
        or set(usage) != _USAGE_KEYS
        or any(
            isinstance(amount, bool)
            or not isinstance(amount, int)
            or not 0 <= amount <= 1_000_000_000
            for amount in usage.values()
        )
    ):
        raise ValueError("Judge qualification metrics are invalid")
    cost = value["estimatedCostUSD"]
    if cost is None:
        return
    if not isinstance(cost, str):
        raise ValueError("Judge qualification metrics are invalid")
    try:
        parsed = Decimal(cost)
    except InvalidOperation as error:
        raise ValueError("Judge qualification metrics are invalid") from error
    if not parsed.is_finite() or parsed < 0:
        raise ValueError("Judge qualification metrics are invalid")


def _publish(artifact_root, artifact, now):
    artifact_root = Path(artifact_root)
    artifact_root.mkdir(parents=True, exist_ok=True)
    timestamp = now.strftime("%Y%m%dT%H%M%SZ")
    artifact_bytes = _pretty_json_bytes(artifact)
    destination = artifact_root / f"{timestamp}-{_sha256(artifact_bytes)}"
    temporary = artifact_root / f".{destination.name}.tmp-{uuid.uuid4().hex}"
    if os.path.lexists(destination):
        raise ValueError("Refusing to overwrite judge qualification")
    temporary.mkdir()
    try:
        (temporary / "qualification.json").write_bytes(artifact_bytes)
        temporary.rename(destination)
    except Exception:
        if temporary.exists():
            for child in temporary.iterdir():
                child.unlink()
            temporary.rmdir()
        raise
    return destination / "qualification.json"


def _plain(value):
    if isinstance(value, Mapping):
        return {key: _plain(child) for key, child in value.items()}
    if isinstance(value, tuple):
        return [_plain(child) for child in value]
    return value


def _utc_datetime(value):
    if not isinstance(value, datetime) or value.tzinfo is None:
        raise ValueError("Qualification time must be timezone-aware")
    return value.astimezone(timezone.utc)


def _format_datetime(value):
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def _parse_datetime(value):
    if not isinstance(value, str):
        raise ValueError("Judge qualification timestamp is invalid")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise ValueError("Judge qualification timestamp is invalid") from error
    return _utc_datetime(parsed)


def _agreement(value):
    return (
        not isinstance(value, bool)
        and isinstance(value, (int, float))
        and 0 <= value <= 1
    )


def _sha256(data):
    return hashlib.sha256(data).hexdigest()
