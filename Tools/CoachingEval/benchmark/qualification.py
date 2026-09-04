"""Reusable qualification for the benchmark's LLM judge."""

import hashlib
import json
import os
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Mapping

from Tools.CoachingEval.benchmark.judge_contract import (
    RUBRIC_DIMENSIONS,
    absolute_schema as _absolute_schema,
    add_metrics as _add_metrics,
    canonical_json_bytes as _canonical_json_bytes,
    empty_metrics as _empty_metrics,
    judge_call as _judge_call,
    pairwise_schema as _pairwise_schema,
    pretty_json_bytes as _pretty_json_bytes,
    validate_absolute as _validate_absolute,
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

        minimum_severe = min(result["severeAgreement"] for result in passes)
        minimum_dimension = min(result["dimensionWithinOne"] for result in passes)
        accepted = all(result["passed"] for result in passes)
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
        cls._load_reference(configuration)
        path = Path(path)
        if path.is_dir():
            path = path / "qualification.json"
        try:
            artifact = json.loads(path.read_text(encoding="utf-8"))
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
        if artifact["bindings"] != _bindings(configuration):
            raise ValueError("Judge qualification is not compatible")
        created_at = _parse_datetime(artifact["createdAt"])
        expires_at = _parse_datetime(artifact["expiresAt"])
        if expires_at <= created_at or now >= expires_at:
            raise ValueError("Judge qualification has expired")
        cls._validate_accepted_results(artifact, configuration)
        return cls(
            path=path,
            created_at=created_at,
            expires_at=expires_at,
            minimum_severe_agreement=artifact["minimumSevereAgreement"],
            minimum_dimension_agreement=artifact["minimumDimensionAgreement"],
            artifact=artifact,
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
                "availableUI": _plain(case["availableUI"]),
                "candidateTurn": _plain(case["candidateTurn"]),
            }
            output, call_metrics = _judge_call(
                configuration,
                client,
                payload,
                _absolute_schema(),
                price_table,
            )
            grade = _validate_absolute(output)
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
        return {
            "repetition": repetition,
            "passed": (
                severe_agreement >= configuration.minimum_severe_agreement
                and dimension_agreement >= configuration.minimum_dimension_agreement
            ),
            "severeAgreement": severe_agreement,
            "dimensionWithinOne": dimension_agreement,
            "judgeMetrics": metrics,
            "rows": rows,
        }

    @classmethod
    def _validate_accepted_results(cls, artifact, configuration):
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
        for index, result in enumerate(passes, start=1):
            if not isinstance(result, dict) or result.get("repetition") != index:
                raise ValueError("Judge qualification pass is invalid")
            severe = result.get("severeAgreement")
            dimension = result.get("dimensionWithinOne")
            if (
                not _agreement(severe)
                or not _agreement(dimension)
                or result.get("passed") is not True
                or severe < criteria["minimumSevereAgreement"]
                or dimension < criteria["minimumDimensionAgreement"]
                or not isinstance(result.get("rows"), list)
                or len(result["rows"]) != 20
            ):
                raise ValueError("Judge qualification pass is invalid")
            severe_values.append(severe)
            dimension_values.append(dimension)
        if (
            artifact["minimumSevereAgreement"] != min(severe_values)
            or artifact["minimumDimensionAgreement"] != min(dimension_values)
        ):
            raise ValueError("Judge qualification minimum agreement is invalid")


def _bindings(configuration):
    return {
        "judgeConfigurationSHA256": configuration.sha256,
        "judgePromptSHA256": configuration.system_prompt_sha256,
        "referenceSetSHA256": configuration.reference_set_sha256,
        "absoluteSchemaSHA256": _sha256(_canonical_json_bytes(_absolute_schema())),
        "pairwiseSchemaSHA256": _sha256(_canonical_json_bytes(_pairwise_schema())),
    }


def _publish(artifact_root, artifact, now):
    artifact_root = Path(artifact_root)
    artifact_root.mkdir(parents=True, exist_ok=True)
    timestamp = now.strftime("%Y%m%dT%H%M%SZ")
    destination = artifact_root / f"{timestamp}-{uuid.uuid4().hex[:12]}"
    temporary = artifact_root / f".{destination.name}.tmp-{uuid.uuid4().hex}"
    if os.path.lexists(destination):
        raise ValueError("Refusing to overwrite judge qualification")
    temporary.mkdir()
    try:
        (temporary / "qualification.json").write_bytes(_pretty_json_bytes(artifact))
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
