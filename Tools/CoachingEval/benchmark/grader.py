"""Calibrated absolute and blinded pairwise grading for coaching benchmarks."""

import hashlib
import json
import os
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping

from Tools.CoachingEval.chess_native_response import ChessNativeResponseContract
from Tools.CoachingEval.benchmark.judge_contract import (
    RUBRIC_DIMENSIONS,
    RUBRIC_FLAGS,
    absolute_schema as _absolute_schema,
    add_metrics as _add_metrics,
    canonical_json_bytes as _canonical_json_bytes,
    empty_metrics as _empty_metrics,
    judge_call as _judge_call,
    pairwise_schema as _pairwise_schema,
    pretty_json_bytes as _pretty_json_bytes,
    validate_absolute as _validate_absolute,
    validate_flags as _validate_flags,
    validate_pairwise as _validate_pairwise,
    validate_scores as _validate_scores,
)
from Tools.CoachingEval.benchmark.qualification import JudgeQualification


@dataclass(frozen=True)
class CalibrationResult:
    passed: bool
    severe_agreement: float
    dimension_within_one: float
    row_count: int
    calibration_sha256: str
    judge_metrics: Mapping[str, Any]
    rows: tuple


def calibrate_judge(configuration, client, price_table=None):
    rows = _load_calibration(configuration.calibration_path)
    severe_matches = 0
    dimension_matches = 0
    dimension_count = len(rows) * len(RUBRIC_DIMENSIONS)
    metrics = _empty_metrics()
    results = []
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
        results.append(
            {
                "rowID": row["id"],
                "severeMatch": (
                    grade["flags"]["severeError"]
                    == row["humanFlags"]["severeError"]
                ),
                "dimensionsWithinOne": sum(
                    abs(grade["scores"][dimension] - row["humanScores"][dimension])
                    <= 1
                    for dimension in RUBRIC_DIMENSIONS
                ),
                "humanScores": dict(row["humanScores"]),
                "judgeScores": grade["scores"],
                "humanFlags": dict(row["humanFlags"]),
                "judgeFlags": grade["flags"],
                "evidence": grade["evidence"],
            }
        )
    severe_agreement = severe_matches / len(rows)
    dimension_within_one = dimension_matches / dimension_count
    return CalibrationResult(
        passed=severe_agreement >= 0.90 and dimension_within_one >= 0.80,
        severe_agreement=severe_agreement,
        dimension_within_one=dimension_within_one,
        row_count=len(rows),
        calibration_sha256=configuration.calibration_sha256,
        judge_metrics=metrics,
        rows=tuple(results),
    )


def grade_run(
    *,
    run_root: Path,
    corpus,
    judge_configuration,
    client,
    destination: Path,
    qualification_path: Path,
    price_table=None,
    now=None,
):
    destination = Path(destination)
    if os.path.lexists(destination):
        raise ValueError(f"Refusing to overwrite benchmark grades: {destination}")
    now = now or datetime.now(timezone.utc)
    qualification = JudgeQualification.load_compatible(
        qualification_path,
        judge_configuration,
        now,
    )
    qualification_bytes = qualification.path.read_bytes()
    run_manifest, records = _load_run(run_root, corpus)
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
    manifest = _grade_manifest(
        run_manifest,
        judge_configuration,
        qualification_bytes,
        absolute,
        pairwise,
    )
    _publish(destination, qualification_bytes, absolute, pairwise, manifest)
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
        "rows": list(result.rows),
    }


def _grade_manifest(
    run_manifest,
    configuration,
    qualification_bytes,
    absolute,
    pairwise,
):
    return {
        "schemaVersion": "coaching-quality-grade-run.v2",
        "status": "completed",
        "sourceRunRecordsSHA256": run_manifest["recordsSHA256"],
        "corpusSHA256": run_manifest["corpusSHA256"],
        "judgeConfigurationSHA256": configuration.sha256,
        "judgePromptSHA256": configuration.system_prompt_sha256,
        "absoluteSchemaSHA256": _sha256(_canonical_json_bytes(_absolute_schema())),
        "pairwiseSchemaSHA256": _sha256(_canonical_json_bytes(_pairwise_schema())),
        "qualificationSHA256": _sha256(qualification_bytes),
        "absoluteGradesSHA256": _sha256(_jsonl_bytes(absolute)),
        "pairwiseGradesSHA256": _sha256(_jsonl_bytes(pairwise)),
        "absoluteGradeCount": len(absolute),
        "pairwiseGradeCount": len(pairwise),
    }


def _publish(destination, qualification_bytes, absolute, pairwise, manifest):
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.parent / f".{destination.name}.tmp-{uuid.uuid4()}"
    temporary.mkdir()
    try:
        (temporary / "qualification.json").write_bytes(qualification_bytes)
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


def _jsonl_bytes(values):
    return b"".join(
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8") + b"\n"
        for value in values
    )


def _sha256(data):
    return hashlib.sha256(data).hexdigest()
