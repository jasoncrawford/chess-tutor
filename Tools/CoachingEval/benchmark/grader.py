"""Calibrated absolute and blinded pairwise grading for coaching benchmarks."""

import hashlib
import json
import math
import os
import time
import uuid
from dataclasses import dataclass
from decimal import Decimal
from pathlib import Path
from typing import Any, Mapping

from Tools.CoachingEval.chess_native_response import ChessNativeResponseContract


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


@dataclass(frozen=True)
class CalibrationResult:
    passed: bool
    severe_agreement: float
    dimension_within_one: float
    row_count: int
    calibration_sha256: str
    judge_metrics: Mapping[str, Any]


def calibrate_judge(configuration, client, price_table=None):
    rows = _load_calibration(configuration.calibration_path)
    severe_matches = 0
    dimension_matches = 0
    dimension_count = len(rows) * len(RUBRIC_DIMENSIONS)
    metrics = _empty_metrics()
    for row in rows:
        payload = {
            "kind": "absolute",
            "graderBrief": row["graderBrief"],
            "availableUI": row["uiContract"],
            "candidateTurn": row["candidateTurn"],
        }
        output, call_metrics = _judge_call(
            configuration,
            client,
            payload,
            _absolute_schema(),
            price_table,
        )
        grade = _validate_absolute(output)
        severe_matches += (
            grade["flags"]["severeError"] == row["humanFlags"]["severeError"]
        )
        for dimension in RUBRIC_DIMENSIONS:
            dimension_matches += abs(
                grade["scores"][dimension] - row["humanScores"][dimension]
            ) <= 1
        _add_metrics(metrics, call_metrics)
    severe_agreement = severe_matches / len(rows)
    dimension_within_one = dimension_matches / dimension_count
    return CalibrationResult(
        passed=severe_agreement >= 0.90 and dimension_within_one >= 0.80,
        severe_agreement=severe_agreement,
        dimension_within_one=dimension_within_one,
        row_count=len(rows),
        calibration_sha256=configuration.calibration_sha256,
        judge_metrics=metrics,
    )


def grade_run(
    *,
    run_root: Path,
    corpus,
    judge_configuration,
    client,
    destination: Path,
    price_table=None,
):
    destination = Path(destination)
    if os.path.lexists(destination):
        raise ValueError(f"Refusing to overwrite benchmark grades: {destination}")
    run_manifest, records = _load_run(run_root, corpus)
    calibration = calibrate_judge(judge_configuration, client, price_table)
    if not calibration.passed:
        raise ValueError("Judge calibration failed; candidate grading was not started")
    turns = corpus.by_id()
    absolute = []
    for record in records:
        turn = turns.get(record.get("caseID"))
        if turn is None:
            raise ValueError("Candidate record points to an unknown benchmark case")
        if not _mechanically_valid(record):
            absolute.append(_automatic_unusable(record))
            continue
        payload = _absolute_payload(turn, record)
        output, metrics = _judge_call(
            judge_configuration,
            client,
            payload,
            _absolute_schema(),
            price_table,
        )
        grade = _validate_absolute(output)
        _reject_identity_leakage(
            grade,
            run_manifest.get("configurations", ()),
        )
        absolute.append(
            {
                "schemaVersion": "coaching-quality-absolute-grade.v1",
                "cellID": record["cellID"],
                "disposition": "judged",
                "scores": grade["scores"],
                "flags": grade["flags"],
                "evidence": grade["evidence"],
                "judgeMetrics": metrics,
            }
        )
    pairwise = _pairwise_grades(
        run_manifest,
        records,
        turns,
        judge_configuration,
        client,
        price_table,
    )
    calibration_json = _calibration_json(calibration)
    manifest = _grade_manifest(
        run_manifest,
        judge_configuration,
        calibration_json,
        absolute,
        pairwise,
    )
    _publish(destination, calibration_json, absolute, pairwise, manifest)
    return destination


def _pairwise_grades(
    run_manifest,
    records,
    turns,
    configuration,
    client,
    price_table,
):
    configurations = run_manifest.get("configurations")
    if not isinstance(configurations, list):
        raise ValueError("Run manifest configurations are invalid")
    baselines = [value.get("id") for value in configurations if value.get("baseline") is True]
    candidates = [value.get("id") for value in configurations if value.get("baseline") is False]
    if run_manifest.get("mode") != "comparison" or not candidates:
        return []
    if len(baselines) != 1 or any(not isinstance(value, str) for value in candidates):
        raise ValueError("Comparison grading requires one baseline")
    baseline_id = baselines[0]
    records_by_key = {
        (record["configurationID"], record["caseID"], record["repetition"]): record
        for record in records
    }
    results = []
    baseline_keys = [
        key for key in records_by_key if key[0] == baseline_id
    ]
    for candidate_id in candidates:
        for _baseline, case_id, repetition in baseline_keys:
            baseline = records_by_key[(_baseline, case_id, repetition)]
            candidate = records_by_key.get((candidate_id, case_id, repetition))
            if candidate is None:
                raise ValueError("Comparison run is missing a candidate pair")
            pair_id = f"{candidate_id}|{case_id}|r{repetition}|vs|{baseline_id}"
            baseline_valid = _mechanically_valid(baseline)
            candidate_valid = _mechanically_valid(candidate)
            if candidate_valid and not baseline_valid:
                results.append(_automatic_pair(pair_id, "candidateWin"))
                continue
            if baseline_valid and not candidate_valid:
                results.append(_automatic_pair(pair_id, "candidateLoss"))
                continue
            if not baseline_valid and not candidate_valid:
                results.append(_automatic_pair(pair_id, "unusableTie"))
                continue
            candidate_is_a = _candidate_is_a(
                configuration.review_seed, candidate_id, case_id, repetition
            )
            response_a = candidate["parsedTurn"] if candidate_is_a else baseline["parsedTurn"]
            response_b = baseline["parsedTurn"] if candidate_is_a else candidate["parsedTurn"]
            turn = turns[case_id]
            payload = {
                "kind": "pairwise",
                "graderBrief": _brief_payload(turn.grader_brief),
                "availableUI": _available_ui(candidate),
                "responseA": response_a,
                "responseB": response_b,
            }
            output, metrics = _judge_call(
                configuration,
                client,
                payload,
                _pairwise_schema(),
                price_table,
            )
            grade = _validate_pairwise(output)
            _reject_identity_leakage(grade, configurations)
            if grade["winner"] == "tie":
                outcome = "tie"
            elif (grade["winner"] == "A") == candidate_is_a:
                outcome = "candidateWin"
            else:
                outcome = "candidateLoss"
            results.append(
                {
                    "schemaVersion": "coaching-quality-pairwise-grade.v1",
                    "pairID": pair_id,
                    "outcome": outcome,
                    "candidatePresentedAs": "A" if candidate_is_a else "B",
                    "evidence": grade["evidence"],
                    "judgeMetrics": metrics,
                }
            )
    return results


def _load_calibration(path):
    rows = []
    expected_keys = {
        "id",
        "graderBrief",
        "uiContract",
        "candidateTurn",
        "humanScores",
        "humanFlags",
    }
    for index, line in enumerate(Path(path).read_text(encoding="utf-8").splitlines(), start=1):
        try:
            row = json.loads(line)
        except json.JSONDecodeError as error:
            raise ValueError("Judge calibration contains invalid JSON") from error
        if not isinstance(row, dict) or set(row) != expected_keys:
            raise ValueError("Judge calibration fields do not match")
        if row["id"] != f"cal-{index:02}":
            raise ValueError("Judge calibration IDs or order do not match")
        _validate_scores(row["humanScores"])
        _validate_flags(row["humanFlags"])
        if not isinstance(row["graderBrief"], dict) or not isinstance(row["uiContract"], dict):
            raise ValueError("Judge calibration context must be structured")
        if not isinstance(row["candidateTurn"], dict):
            raise ValueError("Judge calibration turn must be structured")
        rows.append(row)
    if len(rows) != 20:
        raise ValueError("Judge calibration must contain exactly 20 rows")
    severe_count = sum(row["humanFlags"]["severeError"] for row in rows)
    if severe_count < 5 or len(rows) - severe_count < 5:
        raise ValueError("Judge calibration needs at least five severe and five non-severe rows")
    return rows


def _absolute_payload(turn, record):
    return {
        "kind": "absolute",
        "graderBrief": _brief_payload(turn.grader_brief),
        "availableUI": _available_ui(record),
        "candidateTurn": record["parsedTurn"],
    }


def _brief_payload(brief):
    return {
        "verifiedFacts": list(brief.verified_facts),
        "coachingPurpose": brief.coaching_purpose,
        "acceptableAlternatives": list(brief.acceptable_alternatives),
        "successCriteria": list(brief.success_criteria),
        "severeFailureCriteria": list(brief.severe_failure_criteria),
    }


def _available_ui(record):
    contract = ChessNativeResponseContract.from_markdown(record["userPrompt"])
    return {
        "actions": list(contract.actions),
        "expectedResponses": list(contract.expected_responses),
        "allowableMoveFocus": [list(move) for move in contract.allowable_moves],
    }


def _judge_call(configuration, client, payload, schema, price_table):
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
    output_text = response.get("output_text") if isinstance(response, dict) else None
    if not isinstance(output_text, str) or not output_text:
        raise ValueError("Judge returned no structured output")
    try:
        output = json.loads(output_text, object_pairs_hook=_strict_object)
    except (TypeError, ValueError, _DuplicateKey) as error:
        raise ValueError("Judge returned malformed structured output") from error
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
    return output, metrics


def _validate_absolute(value):
    if not isinstance(value, dict) or set(value) != {"scores", "flags", "evidence"}:
        raise ValueError("Absolute judge fields do not match")
    _validate_scores(value["scores"])
    _validate_flags(value["flags"])
    evidence = _validate_evidence(value["evidence"])
    return {"scores": dict(value["scores"]), "flags": dict(value["flags"]), "evidence": evidence}


def _validate_pairwise(value):
    if not isinstance(value, dict) or set(value) != {"winner", "evidence"}:
        raise ValueError("Pairwise judge fields do not match")
    if value["winner"] not in ("A", "B", "tie"):
        raise ValueError("Pairwise winner is invalid")
    return {"winner": value["winner"], "evidence": _validate_evidence(value["evidence"])}


def _validate_scores(value):
    if not isinstance(value, dict) or tuple(sorted(value)) != tuple(sorted(RUBRIC_DIMENSIONS)):
        raise ValueError("Judge score fields do not match")
    if any(isinstance(score, bool) or not isinstance(score, int) or not 1 <= score <= 5 for score in value.values()):
        raise ValueError("Judge scores must be integers from 1 to 5")


def _validate_flags(value):
    if not isinstance(value, dict) or tuple(sorted(value)) != tuple(sorted(RUBRIC_FLAGS)):
        raise ValueError("Judge flag fields do not match")
    if any(not isinstance(flag, bool) for flag in value.values()):
        raise ValueError("Judge flags must be booleans")


def _validate_evidence(value):
    if not isinstance(value, list) or not 1 <= len(value) <= 3:
        raise ValueError("Judge evidence must contain one to three items")
    if any(not isinstance(item, str) or not item or len(item) > 500 for item in value):
        raise ValueError("Judge evidence is invalid")
    return list(value)


def _absolute_schema():
    return {
        "type": "object",
        "properties": {
            "scores": {
                "type": "object",
                "properties": {dimension: {"type": "integer", "minimum": 1, "maximum": 5} for dimension in RUBRIC_DIMENSIONS},
                "required": list(RUBRIC_DIMENSIONS),
                "additionalProperties": False,
            },
            "flags": {
                "type": "object",
                "properties": {flag: {"type": "boolean"} for flag in RUBRIC_FLAGS},
                "required": list(RUBRIC_FLAGS),
                "additionalProperties": False,
            },
            "evidence": {"type": "array", "items": {"type": "string", "maxLength": 500}, "minItems": 1, "maxItems": 3},
        },
        "required": ["scores", "flags", "evidence"],
        "additionalProperties": False,
    }


def _pairwise_schema():
    return {
        "type": "object",
        "properties": {
            "winner": {"type": "string", "enum": ["A", "B", "tie"]},
            "evidence": {"type": "array", "items": {"type": "string", "maxLength": 500}, "minItems": 1, "maxItems": 3},
        },
        "required": ["winner", "evidence"],
        "additionalProperties": False,
    }


def _mechanically_valid(record):
    validation = record.get("mechanicalValidation")
    return isinstance(validation, dict) and validation.get("valid") is True


def _automatic_unusable(record):
    flags = {flag: False for flag in RUBRIC_FLAGS}
    flags["severeError"] = True
    return {
        "schemaVersion": "coaching-quality-absolute-grade.v1",
        "cellID": record["cellID"],
        "disposition": "unusable",
        "scores": {dimension: 1 for dimension in RUBRIC_DIMENSIONS},
        "flags": flags,
        "evidence": ["The candidate response failed the mechanical app contract."],
        "judgeMetrics": _empty_metrics(),
    }


def _automatic_pair(pair_id, outcome):
    return {
        "schemaVersion": "coaching-quality-pairwise-grade.v1",
        "pairID": pair_id,
        "outcome": outcome,
        "candidatePresentedAs": None,
        "evidence": ["Mechanical validity determined this pair without a judge call."],
        "judgeMetrics": _empty_metrics(),
    }


def _candidate_is_a(seed, candidate_id, case_id, repetition):
    digest = hashlib.sha256(f"{seed}|{candidate_id}|{case_id}|{repetition}".encode()).digest()
    return digest[0] % 2 == 0


def _load_run(run_root, corpus):
    run_root = Path(run_root)
    manifest = json.loads((run_root / "run-manifest.json").read_text(encoding="utf-8"))
    records_bytes = (run_root / "records.jsonl").read_bytes()
    if manifest.get("recordsSHA256") != hashlib.sha256(records_bytes).hexdigest():
        raise ValueError("Candidate run records hash does not match")
    if manifest.get("corpusSHA256") != corpus.sha256:
        raise ValueError("Candidate run corpus does not match grading corpus")
    records = [json.loads(line) for line in records_bytes.decode("utf-8").splitlines()]
    if len({record.get("cellID") for record in records}) != len(records):
        raise ValueError("Candidate run cell IDs must be unique")
    return manifest, records


def _reject_identity_leakage(grade, configurations):
    serialized = json.dumps(grade, sort_keys=True).casefold()
    identities = set()
    for configuration in configurations:
        if isinstance(configuration, dict):
            for key in ("id", "model"):
                value = configuration.get(key)
                if isinstance(value, str) and value:
                    identities.add(value.casefold())
    if any(identity in serialized for identity in identities):
        raise ValueError("Judge output leaked candidate identity")


def _calibration_json(result):
    return {
        "schemaVersion": "coaching-quality-calibration-result.v1",
        "passed": result.passed,
        "severeAgreement": result.severe_agreement,
        "dimensionWithinOne": result.dimension_within_one,
        "rowCount": result.row_count,
        "calibrationSHA256": result.calibration_sha256,
        "judgeMetrics": result.judge_metrics,
    }


def _grade_manifest(run_manifest, configuration, calibration, absolute, pairwise):
    return {
        "schemaVersion": "coaching-quality-grade-run.v1",
        "sourceRunRecordsSHA256": run_manifest["recordsSHA256"],
        "corpusSHA256": run_manifest["corpusSHA256"],
        "judgeConfigurationSHA256": configuration.sha256,
        "judgePromptSHA256": configuration.system_prompt_sha256,
        "absoluteSchemaSHA256": _sha256(_canonical_json_bytes(_absolute_schema())),
        "pairwiseSchemaSHA256": _sha256(_canonical_json_bytes(_pairwise_schema())),
        "calibrationSHA256": _sha256(_pretty_json_bytes(calibration)),
        "absoluteGradesSHA256": _sha256(_jsonl_bytes(absolute)),
        "pairwiseGradesSHA256": _sha256(_jsonl_bytes(pairwise)),
        "absoluteGradeCount": len(absolute),
        "pairwiseGradeCount": len(pairwise),
    }


def _publish(destination, calibration, absolute, pairwise, manifest):
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.parent / f".{destination.name}.tmp-{uuid.uuid4()}"
    temporary.mkdir()
    try:
        (temporary / "calibration.json").write_bytes(_pretty_json_bytes(calibration))
        (temporary / "absolute-grades.jsonl").write_bytes(_jsonl_bytes(absolute))
        (temporary / "pairwise-grades.jsonl").write_bytes(_jsonl_bytes(pairwise))
        (temporary / "grade-manifest.json").write_bytes(_pretty_json_bytes(manifest))
        temporary.rename(destination)
    except Exception:
        for child in temporary.iterdir() if temporary.exists() else ():
            child.unlink()
        if temporary.exists():
            temporary.rmdir()
        raise


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


def _empty_metrics():
    return {
        "callCount": 0,
        "usage": {"inputTokens": 0, "cachedInputTokens": 0, "outputTokens": 0, "reasoningTokens": 0, "totalTokens": 0},
        "latencyMilliseconds": 0.0,
        "estimatedCostUSD": None,
    }


def _add_metrics(total, current):
    total["callCount"] += current["callCount"]
    for key in total["usage"]:
        total["usage"][key] += current["usage"][key]
    total["latencyMilliseconds"] += current["latencyMilliseconds"]
    if current["estimatedCostUSD"] is not None:
        prior = total["estimatedCostUSD"] or "0"
        total["estimatedCostUSD"] = str(
            Decimal(prior) + Decimal(current["estimatedCostUSD"])
        )


def _bounded_int(value):
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        return 0
    return min(value, 1_000_000_000)


def _bounded_float(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return 0.0
    value = float(value)
    return value if math.isfinite(value) and 0 <= value <= 86_400_000 else 0.0


def _jsonl_bytes(values):
    return b"".join(
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8") + b"\n"
        for value in values
    )


def _pretty_json_bytes(value):
    return (json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode("utf-8")


def _canonical_json_bytes(value):
    return json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode("utf-8")


def _sha256(data):
    return hashlib.sha256(data).hexdigest()
