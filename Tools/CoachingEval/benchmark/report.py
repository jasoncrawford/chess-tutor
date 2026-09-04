"""Deterministic benchmark aggregation and concise tradeoff reports."""

import hashlib
import json
import math
import os
import random
import re
import uuid
from collections import defaultdict
from datetime import datetime
from decimal import Decimal
from pathlib import Path
from typing import Any, Mapping, Sequence

from Tools.CoachingEval.benchmark.configuration import validate_candidate_usage
from Tools.CoachingEval.benchmark.grader import RUBRIC_DIMENSIONS


_BOOTSTRAP_DRAWS = 10_000
_BOOTSTRAP_SEED = 20260901
_PROVIDER_SUCCESS = frozenset(("completed", "invalid"))
_SHA256 = re.compile(r"[0-9a-f]{64}\Z")
_QUALIFICATION_BINDING_KEYS = frozenset(
    (
        "judgeConfigurationSHA256",
        "judgePromptSHA256",
        "referenceSetSHA256",
        "absoluteSchemaSHA256",
        "pairwiseSchemaSHA256",
    )
)
_MANIFEST_QUALIFICATION_BINDING_KEYS = _QUALIFICATION_BINDING_KEYS - {
    "referenceSetSHA256"
}
_USAGE_KEYS = (
    "inputTokens",
    "cachedInputTokens",
    "outputTokens",
    "reasoningTokens",
    "totalTokens",
)


def build_report(run_root: Path, grade_root: Path, price_table) -> dict:
    """Build a deterministic report from stored candidate and grade artifacts."""
    run_root = Path(run_root)
    grade_root = Path(grade_root)
    issues = []
    run_manifest = _read_object(run_root / "run-manifest.json", "candidate run manifest")
    grade_manifest = _read_object(grade_root / "grade-manifest.json", "grade manifest")
    grade_version = grade_manifest.get("schemaVersion")
    calibration = None
    qualification = None
    qualification_bytes = None
    if grade_version == "coaching-quality-grade-run.v1":
        issues.append("legacy grade artifacts are diagnostic only")
        calibration = _read_object(grade_root / "calibration.json", "judge calibration")
    elif grade_version == "coaching-quality-grade-run.v2":
        if grade_manifest.get("status") != "completed":
            issues.append("grade run did not complete")
        qualification_bytes, qualification = _read_object_bytes(
            grade_root / "qualification.json", "judge qualification"
        )
    else:
        issues.append("grade manifest schema is unsupported")
    records_bytes, records = _read_jsonl(run_root / "records.jsonl", "candidate records")
    absolute_bytes, absolute = _read_jsonl(
        grade_root / "absolute-grades.jsonl", "absolute grades"
    )
    pairwise_bytes, pairwise = _read_jsonl(
        grade_root / "pairwise-grades.jsonl", "pairwise grades"
    )

    _check_hash(
        issues,
        "candidate records hash mismatch",
        run_manifest.get("recordsSHA256"),
        records_bytes,
    )
    _check_hash(
        issues,
        "absolute grades hash mismatch",
        grade_manifest.get("absoluteGradesSHA256"),
        absolute_bytes,
    )
    _check_hash(
        issues,
        "pairwise grades hash mismatch",
        grade_manifest.get("pairwiseGradesSHA256"),
        pairwise_bytes,
    )
    if calibration is not None:
        calibration_bytes = _pretty_json_bytes(calibration)
        _check_hash(
            issues,
            "calibration hash mismatch",
            grade_manifest.get("calibrationSHA256"),
            calibration_bytes,
        )
        if calibration.get("passed") is not True:
            issues.append("judge calibration did not pass")
    if qualification is not None:
        _check_hash(
            issues,
            "qualification hash mismatch",
            grade_manifest.get("qualificationSHA256"),
            qualification_bytes,
        )
        _validate_qualification_binding(qualification, grade_manifest, issues)
    if grade_manifest.get("sourceRunRecordsSHA256") != run_manifest.get(
        "recordsSHA256"
    ):
        issues.append("grade source run hash mismatch")
    if grade_manifest.get("corpusSHA256") != run_manifest.get("corpusSHA256"):
        issues.append("grade corpus hash mismatch")
    configurations = _configurations(run_manifest, issues)
    _validate_configuration_policies(configurations, price_table, issues)
    record_ids = _unique_ids(records, "cellID", "candidate record", issues)
    manifest_ids = run_manifest.get("recordIDs")
    if not isinstance(manifest_ids, list) or any(
        not isinstance(value, str) for value in manifest_ids
    ):
        issues.append("candidate manifest record IDs are invalid")
        manifest_ids = []
    if manifest_ids != record_ids:
        issues.append("candidate record IDs do not match manifest")
    grade_ids = _unique_ids(absolute, "cellID", "absolute grade", issues)
    if set(grade_ids) != set(record_ids):
        issues.append("absolute grade IDs do not match candidate records")
    if grade_manifest.get("absoluteGradeCount") != len(absolute):
        issues.append("absolute grade count mismatch")
    if grade_manifest.get("pairwiseGradeCount") != len(pairwise):
        issues.append("pairwise grade count mismatch")

    records_by_id = {
        value["cellID"]: value
        for value in records
        if isinstance(value, dict) and isinstance(value.get("cellID"), str)
    }
    grades_by_id = {
        value["cellID"]: value
        for value in absolute
        if isinstance(value, dict) and isinstance(value.get("cellID"), str)
    }
    expected_pairs = _expected_pairs(records, configurations)
    observed_pair_ids = _unique_ids(pairwise, "pairID", "pairwise grade", issues)
    if set(observed_pair_ids) != expected_pairs:
        issues.append("pairwise grade IDs do not match baseline pairs")

    baseline_id = _baseline_id(
        configurations,
        issues,
        comparison=run_manifest.get("mode") == "comparison",
    )
    aggregates = {}
    for identifier, configuration in configurations.items():
        selected = [
            record for record in records if record.get("configurationID") == identifier
        ]
        aggregates[identifier] = _aggregate_configuration(
            identifier,
            configuration,
            selected,
            grades_by_id,
            pairwise,
            records,
            baseline_id,
            price_table,
            issues,
        )

    evidence = _run_evidence(run_manifest, records, configurations, issues)
    confidence = _confidence_intervals(
        records, grades_by_id, baseline_id, configurations
    )
    frontier = _pareto_frontier(aggregates)
    judge_overhead = _judge_overhead(calibration, absolute, pairwise)
    if judge_overhead["accountingComplete"] is not True:
        issues.append("judge accounting is incomplete")
    _apply_promotion_eligibility(
        aggregates,
        baseline_id,
        issues,
        evidence,
    )
    global_eligible = not issues and any(
        value.get("promotionEligible") is True for value in aggregates.values()
    )
    qualification_summary = _qualification_summary(qualification, grade_manifest)
    recommendation = _recommendation(aggregates, baseline_id)

    return {
        "schemaVersion": "coaching-quality-report.v2",
        "source": {
            "candidateRecordsSHA256": _sha256(records_bytes),
            "absoluteGradesSHA256": _sha256(absolute_bytes),
            "pairwiseGradesSHA256": _sha256(pairwise_bytes),
            "corpusSHA256": run_manifest.get("corpusSHA256"),
            "priceTableSHA256": price_table.sha256,
            "qualificationSHA256": (
                _sha256(qualification_bytes)
                if qualification_bytes is not None
                else None
            ),
        },
        "mode": run_manifest.get("mode"),
        "evidence": evidence,
        "executionPolicies": _execution_policies(configurations),
        "experimentChanges": _experiment_changes(configurations, baseline_id),
        "configurations": aggregates,
        "confidenceIntervals": confidence,
        "paretoFrontier": frontier,
        "judgeOverhead": judge_overhead,
        "judgeQualification": qualification_summary,
        "trialEligible": not issues and any(
            value.get("trialEligible") is True for value in aggregates.values()
        ),
        "promotionEligible": global_eligible,
        "recommendation": recommendation,
        "integrityIssues": _ordered_unique(issues),
        "mechanicalFailures": _mechanical_failures(records),
        "worstExamples": _worst_examples(run_root, records_by_id, grades_by_id),
    }


def write_report(
    run_root: Path,
    grade_root: Path,
    price_table,
    destination: Path,
):
    """Publish aggregate JSON and Markdown atomically without overwriting."""
    destination = Path(destination)
    if os.path.lexists(destination):
        raise ValueError(f"Refusing to overwrite benchmark report: {destination}")
    report = build_report(run_root, grade_root, price_table)
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.parent / f".{destination.name}.tmp-{uuid.uuid4()}"
    temporary.mkdir()
    try:
        aggregate = temporary / "aggregate.json"
        summary = temporary / "summary.md"
        aggregate.write_bytes(_pretty_json_bytes(report))
        summary.write_text(_markdown(report), encoding="utf-8")
        temporary.rename(destination)
    except Exception:
        _remove_tree(temporary)
        raise
    return destination / "aggregate.json", destination / "summary.md"


def _aggregate_configuration(
    identifier,
    configuration,
    records,
    grades_by_id,
    pairwise,
    all_records,
    baseline_id,
    price_table,
    issues,
):
    grades = [
        grades_by_id[record["cellID"]]
        for record in records
        if record.get("cellID") in grades_by_id
    ]
    response_count = len(records)
    provider_success = sum(
        record.get("generationStatus") in _PROVIDER_SUCCESS for record in records
    )
    mechanical_valid = sum(_valid_record(record) for record in records)
    severe = sum(_severe_grade(grade) for grade in grades)
    strong = sum(_strong_grade(grade) for grade in grades)
    usage = _usage_total(record.get("usage") for record in records)
    latencies = [_bounded_number(record.get("latencyMilliseconds")) for record in records]
    candidate_cost = Decimal(0)
    candidate_accounting_complete = True
    for record in records:
        if record.get("candidateAccountingComplete") is not True:
            issues.append(f"candidate accounting is incomplete for {identifier}")
            candidate_accounting_complete = False
        try:
            validate_candidate_usage(record.get("usage"))
        except ValueError:
            issues.append(f"candidate usage accounting is invalid for {identifier}")
            candidate_accounting_complete = False
            continue
        try:
            expected_cost = price_table.estimate(
                configuration.get("model"), record.get("usage", {})
            )
        except ValueError:
            issues.append(f"missing price coverage for {identifier}")
            candidate_accounting_complete = False
            continue
        candidate_cost += expected_cost
        stored_cost = _nonnegative_decimal(record.get("candidateCostUSD"))
        if (
            record.get("candidateAccountingComplete") is True
            and stored_cost != expected_cost
        ):
            issues.append(f"candidate cost accounting is invalid for {identifier}")
            candidate_accounting_complete = False
    pair_counts = _pair_counts(
        identifier,
        configuration,
        pairwise,
        all_records if configuration.get("baseline") is True else records,
        baseline_id,
    )
    categories = sorted(
        {record.get("category") for record in records if isinstance(record.get("category"), str)}
    )
    category_breakdown = {
        category: _subset_quality(
            [record for record in records if record.get("category") == category],
            grades_by_id,
        )
        for category in categories
    }
    initial = [record for record in records if record.get("stepIndex") == 1]
    follow_up = [record for record in records if record.get("stepIndex") != 1]
    return {
        "configuration": _public_configuration(configuration),
        "responseCount": response_count,
        "quality": {
            "severeErrorRate": _rate(severe, len(grades)),
            "allDimensionsAtLeast4Rate": _rate(strong, len(grades)),
            "dimensions": _dimension_stats(grades),
        },
        "reliability": {
            "providerSuccessRate": _rate(provider_success, response_count),
            "mechanicalValidityRate": _rate(mechanical_valid, response_count),
            "mechanicalFailureCategories": _failure_categories(records),
            "providerFailureBreakdown": _provider_failure_breakdown(records),
        },
        "pairwise": pair_counts,
        "breakdowns": {
            "category": category_breakdown,
            "turnKind": {
                "initial": _subset_quality(initial, grades_by_id),
                "followUp": _subset_quality(follow_up, grades_by_id),
            },
        },
        "usage": usage,
        "latencyMilliseconds": _distribution(latencies),
        "operations": {
            "attemptCount": sum(_bounded_int(record.get("attemptCount")) for record in records),
            "retryCount": sum(
                max(0, _bounded_int(record.get("attemptCount")) - 1)
                for record in records
            ),
        },
        "candidateCostUSD": {
            "accountingComplete": candidate_accounting_complete,
            "total": (
                _decimal_string(candidate_cost)
                if candidate_accounting_complete
                else None
            ),
            "perResponse": (
                _decimal_string(
                    candidate_cost / response_count
                    if response_count
                    else Decimal(0)
                )
                if candidate_accounting_complete
                else None
            ),
        },
        "completeSequenceCostsUSD": _sequence_costs(
            records, configuration, price_table, issues
        ),
        "trialEligible": False,
        "trialReasons": [],
        "promotionEligible": False,
        "promotionReasons": [],
    }


def _dimension_stats(grades):
    result = {}
    for dimension in RUBRIC_DIMENSIONS:
        values = [
            grade.get("scores", {}).get(dimension)
            for grade in grades
            if isinstance(grade.get("scores"), dict)
            and isinstance(grade["scores"].get(dimension), int)
        ]
        distribution = {
            str(score): values.count(score)
            for score in range(1, 6)
            if values.count(score)
        }
        result[dimension] = {
            "mean": round(sum(values) / len(values), 6) if values else 0.0,
            "distribution": distribution,
        }
    return result


def _subset_quality(records, grades_by_id):
    grades = [
        grades_by_id[record["cellID"]]
        for record in records
        if record.get("cellID") in grades_by_id
    ]
    return {
        "responseCount": len(records),
        "severeErrorRate": _rate(sum(_severe_grade(grade) for grade in grades), len(grades)),
        "strongResponseRate": _rate(sum(_strong_grade(grade) for grade in grades), len(grades)),
    }


def _pair_counts(identifier, configuration, pairwise, records, baseline_id):
    pair_rows = defaultdict(list)
    for grade in pairwise:
        pair_id = grade.get("pairID") if isinstance(grade, Mapping) else None
        if isinstance(pair_id, str):
            pair_rows[pair_id].append(grade)
    if configuration.get("baseline") is True:
        expected = {
            f"{candidate_id}|{record.get('caseID')}|r{record.get('repetition')}|vs|{identifier}"
            for candidate_id in {
                record.get("configurationID")
                for record in records
                if isinstance(record.get("configurationID"), str)
                and record.get("configurationID") != identifier
            }
            for record in records
            if record.get("configurationID") == candidate_id
        }
        outcomes = []
        for pair_id in expected:
            rows = pair_rows.get(pair_id, [])
            if len(rows) != 1:
                continue
            grade = rows[0]
            outcome = grade.get("outcome")
            if outcome == "candidateWin":
                outcomes.append("loss")
            elif outcome == "candidateLoss":
                outcomes.append("win")
            elif outcome in ("tie", "unusableTie"):
                outcomes.append("tie")
    else:
        expected = _candidate_pair_ids(identifier, records, baseline_id)
        outcomes = []
        for pair_id in expected:
            rows = pair_rows.get(pair_id, [])
            if len(rows) != 1:
                continue
            grade = rows[0]
            outcome = grade.get("outcome")
            if outcome == "candidateWin":
                outcomes.append("win")
            elif outcome == "candidateLoss":
                outcomes.append("loss")
            elif outcome in ("tie", "unusableTie"):
                outcomes.append("tie")
    return {
        "wins": outcomes.count("win"),
        "losses": outcomes.count("loss"),
        "ties": outcomes.count("tie"),
    }


def _candidate_pair_ids(identifier, records, baseline_id):
    expected = set()
    if not isinstance(baseline_id, str) or not baseline_id:
        return expected
    for record in records:
        if not isinstance(record, Mapping):
            continue
        configuration_id = record.get("configurationID")
        if configuration_id is not None and configuration_id != identifier:
            continue
        case_id = record.get("caseID")
        repetition = record.get("repetition")
        if (
            not isinstance(case_id, str)
            or not case_id
            or isinstance(repetition, bool)
            or not isinstance(repetition, int)
            or repetition <= 0
        ):
            continue
        cell_id = record.get("cellID")
        if cell_id is not None and cell_id != f"{identifier}|{case_id}|r{repetition}":
            continue
        expected.add(f"{identifier}|{case_id}|r{repetition}|vs|{baseline_id}")
    return expected


def _sequence_costs(records, configuration, price_table, issues):
    groups = defaultdict(list)
    for record in records:
        if record.get("stepIndex") in (1, 2, 3):
            groups[(record.get("groupID"), record.get("repetition"))].append(record)
    output = []
    for (group_id, repetition), group in sorted(groups.items()):
        if len(group) != 3 or {record.get("stepIndex") for record in group} != {1, 2, 3}:
            continue
        total = Decimal(0)
        try:
            for record in group:
                if record.get("candidateAccountingComplete") is not True:
                    raise ValueError("Candidate accounting is incomplete")
                validate_candidate_usage(record.get("usage"))
        except ValueError:
            continue
        try:
            for record in group:
                total += price_table.estimate(
                    configuration.get("model"), record.get("usage", {})
                )
        except ValueError:
            issues.append(f"missing sequence price coverage for {configuration.get('id')}")
            continue
        output.append(
            {
                "groupID": group_id,
                "repetition": repetition,
                "costUSD": _decimal_string(total),
            }
        )
    return output


def _confidence_intervals(records, grades_by_id, baseline_id, configurations):
    result = {
        "draws": _BOOTSTRAP_DRAWS,
        "seed": _BOOTSTRAP_SEED,
        "comparisons": {},
    }
    if baseline_id is None:
        return result
    for identifier, configuration in configurations.items():
        if identifier == baseline_id or configuration.get("baseline") is True:
            continue
        pairs = _paired_groups(records, grades_by_id, baseline_id, identifier)
        if not pairs:
            continue
        randomizer = random.Random(
            _BOOTSTRAP_SEED + int.from_bytes(hashlib.sha256(identifier.encode()).digest()[:4], "big")
        )
        strong_deltas = []
        severe_deltas = []
        for _draw in range(_BOOTSTRAP_DRAWS):
            sample = [pairs[randomizer.randrange(len(pairs))] for _ in pairs]
            strong_deltas.append(
                sum(value[0] for value in sample) / len(sample)
            )
            severe_deltas.append(
                sum(value[1] for value in sample) / len(sample)
            )
        result["comparisons"][identifier] = {
            "baselineID": baseline_id,
            "groupCount": len(pairs),
            "strongResponseRateDelta95CI": _percentile_interval(strong_deltas),
            "severeErrorRateDelta95CI": _percentile_interval(severe_deltas),
        }
    return result


def _paired_groups(records, grades_by_id, baseline_id, candidate_id):
    grouped = defaultdict(lambda: {baseline_id: [], candidate_id: []})
    for record in records:
        identifier = record.get("configurationID")
        if identifier not in (baseline_id, candidate_id):
            continue
        key = (record.get("groupID"), record.get("repetition"))
        grade = grades_by_id.get(record.get("cellID"))
        if grade is not None:
            grouped[key][identifier].append(grade)
    output = []
    for values in grouped.values():
        baseline = values[baseline_id]
        candidate = values[candidate_id]
        if not baseline or not candidate:
            continue
        candidate_strong = sum(_strong_grade(value) for value in candidate) / len(candidate)
        baseline_strong = sum(_strong_grade(value) for value in baseline) / len(baseline)
        candidate_severe = sum(_severe_grade(value) for value in candidate) / len(candidate)
        baseline_severe = sum(_severe_grade(value) for value in baseline) / len(baseline)
        output.append((candidate_strong - baseline_strong, candidate_severe - baseline_severe))
    return output


def _pareto_frontier(aggregates):
    frontier = []
    for identifier, value in aggregates.items():
        dominated = False
        metrics = _pareto_metrics(value)
        for other_id, other in aggregates.items():
            if identifier == other_id:
                continue
            other_metrics = _pareto_metrics(other)
            no_worse = (
                other_metrics[0] >= metrics[0]
                and other_metrics[1] <= metrics[1]
                and other_metrics[2] <= metrics[2]
                and other_metrics[3] <= metrics[3]
            )
            strictly_better = (
                other_metrics[0] > metrics[0]
                or other_metrics[1] < metrics[1]
                or other_metrics[2] < metrics[2]
                or other_metrics[3] < metrics[3]
            )
            if no_worse and strictly_better:
                dominated = True
                break
        if not dominated:
            frontier.append(identifier)
    return sorted(frontier)


def _pareto_metrics(value):
    cost = value["candidateCostUSD"]["total"]
    return (
        value["quality"]["allDimensionsAtLeast4Rate"],
        value["quality"]["severeErrorRate"],
        value["latencyMilliseconds"]["p90"],
        Decimal(cost) if cost is not None else Decimal("Infinity"),
    )


def _apply_promotion_eligibility(aggregates, baseline_id, issues, evidence):
    if baseline_id is None or baseline_id not in aggregates:
        return
    baseline = aggregates[baseline_id]
    baseline["trialReasons"] = ["Production baseline is the comparison reference."]
    baseline["promotionReasons"] = ["Production baseline is the comparison reference."]
    for identifier, candidate in aggregates.items():
        if identifier == baseline_id:
            continue
        gate_reasons = []
        candidate_failures = set(candidate["reliability"]["mechanicalFailureCategories"])
        baseline_failures = set(baseline["reliability"]["mechanicalFailureCategories"])
        if candidate_failures - baseline_failures:
            gate_reasons.append("Introduces a new mechanical failure category.")
        if candidate["quality"]["severeErrorRate"] > baseline["quality"]["severeErrorRate"]:
            gate_reasons.append("Severe-error rate is higher than production.")
        if candidate["pairwise"]["wins"] <= candidate["pairwise"]["losses"]:
            gate_reasons.append("Pairwise wins do not exceed losses.")
        if candidate["quality"]["allDimensionsAtLeast4Rate"] <= baseline["quality"]["allDimensionsAtLeast4Rate"]:
            gate_reasons.append("Strong-response rate does not improve on production.")
        if issues:
            gate_reasons.append("Artifact integrity is incomplete.")

        trial_reasons = list(gate_reasons)
        if not evidence["trialEligible"]:
            trial_reasons.append(
                "Complete development or holdout comparison evidence is required for trial."
            )
        candidate["trialReasons"] = trial_reasons or [
            "Eligible to advance from comparison evidence."
        ]
        candidate["trialEligible"] = not trial_reasons

        promotion_reasons = list(gate_reasons)
        if not evidence["promotionEvidenceEligible"]:
            promotion_reasons.append(
                "Complete holdout comparison evidence is required for promotion."
            )
        candidate["promotionReasons"] = promotion_reasons or [
            "Eligible to replace the production baseline."
        ]
        candidate["promotionEligible"] = not promotion_reasons


def _recommendation(aggregates, baseline_id):
    eligible = [
        (identifier, value)
        for identifier, value in aggregates.items()
        if value.get("promotionEligible") is True
    ]
    if eligible:
        identifier, _value = min(
            eligible,
            key=lambda item: (
                -item[1]["quality"]["allDimensionsAtLeast4Rate"],
                item[1]["quality"]["severeErrorRate"],
                -(item[1]["pairwise"]["wins"] - item[1]["pairwise"]["losses"]),
                item[1]["latencyMilliseconds"]["p90"],
                _candidate_cost_sort_value(item[1]),
                item[0],
            ),
        )
        return {"decision": "promoteChallenger", "configurationID": identifier}
    if baseline_id is not None:
        return {"decision": "keepBaseline", "configurationID": baseline_id}
    return {"decision": "noPromotionRecommendation", "configurationID": None}


def _candidate_cost_sort_value(value):
    cost = value["candidateCostUSD"]["total"]
    return Decimal(cost) if cost is not None else Decimal("Infinity")


def _judge_overhead(calibration, absolute, pairwise):
    metrics = _empty_metrics()
    if calibration is not None:
        _add_metrics(metrics, calibration.get("judgeMetrics"))
    for grade in absolute:
        _add_metrics(metrics, grade.get("judgeMetrics"))
    for grade in pairwise:
        _add_metrics(metrics, grade.get("judgeMetrics"))
    return metrics


def _validate_qualification_binding(qualification, manifest, issues):
    if qualification.get("status") != "accepted":
        issues.append("judge qualification was not accepted")
    bindings = qualification.get("bindings")
    if (
        not isinstance(bindings, Mapping)
        or set(bindings) != _QUALIFICATION_BINDING_KEYS
        or any(not _valid_sha256(bindings.get(key)) for key in _QUALIFICATION_BINDING_KEYS)
        or any(
            not _valid_sha256(manifest.get(key))
            for key in _MANIFEST_QUALIFICATION_BINDING_KEYS
        )
    ):
        issues.append("judge qualification bindings are invalid")
    elif any(
        bindings[key] != manifest[key]
        for key in _MANIFEST_QUALIFICATION_BINDING_KEYS
    ):
        issues.append("judge qualification bindings do not match grade manifest")
    criteria = qualification.get("criteria")
    passes = qualification.get("passes")
    if (
        not isinstance(criteria, Mapping)
        or not isinstance(criteria.get("repetitions"), int)
        or not isinstance(passes, list)
        or len(passes) != criteria.get("repetitions")
    ):
        issues.append("judge qualification pass inventory is invalid")
    try:
        created = datetime.fromisoformat(
            qualification["createdAt"].replace("Z", "+00:00")
        )
        expires = datetime.fromisoformat(
            qualification["expiresAt"].replace("Z", "+00:00")
        )
        graded = datetime.fromisoformat(manifest["gradedAt"].replace("Z", "+00:00"))
        if not created <= graded < expires:
            raise ValueError
    except (AttributeError, KeyError, TypeError, ValueError):
        issues.append("judge qualification grading time is invalid")


def _qualification_summary(qualification, grade_manifest):
    if qualification is None:
        return None
    criteria = qualification.get("criteria")
    criteria = criteria if isinstance(criteria, Mapping) else {}
    age_days = None
    try:
        created = datetime.fromisoformat(
            qualification["createdAt"].replace("Z", "+00:00")
        )
        graded = datetime.fromisoformat(
            grade_manifest["gradedAt"].replace("Z", "+00:00")
        )
        age_days = round((graded - created).total_seconds() / 86_400, 6)
    except (AttributeError, KeyError, TypeError, ValueError):
        pass
    return {
        "id": qualification.get("referenceSetID"),
        "createdAt": qualification.get("createdAt"),
        "expiresAt": qualification.get("expiresAt"),
        "ageDaysAtGrading": age_days,
        "repetitions": criteria.get("repetitions"),
        "minimumSevereAgreement": qualification.get("minimumSevereAgreement"),
        "minimumDimensionAgreement": qualification.get(
            "minimumDimensionAgreement"
        ),
        "minimumPairwiseAgreement": qualification.get("minimumPairwiseAgreement"),
        "metrics": qualification.get("qualificationMetrics"),
    }


def _empty_metrics():
    return {
        "accountingComplete": True,
        "callCount": 0,
        "usage": {key: 0 for key in _USAGE_KEYS},
        "latencyMilliseconds": {"total": 0.0},
        "estimatedCostUSD": "0",
    }


def _add_metrics(total, value):
    if not isinstance(value, Mapping):
        total["accountingComplete"] = False
        total["estimatedCostUSD"] = None
        return
    call_count = _bounded_int(value.get("callCount"))
    total["callCount"] += call_count
    usage = value.get("usage") if isinstance(value.get("usage"), Mapping) else {}
    for key in _USAGE_KEYS:
        total["usage"][key] += _bounded_int(usage.get(key))
    total["latencyMilliseconds"]["total"] += _bounded_number(
        value.get("latencyMilliseconds")
    )
    raw_cost = value.get("estimatedCostUSD")
    cost = _nonnegative_decimal(raw_cost)
    cost_valid = "estimatedCostUSD" in value and (
        raw_cost is None or cost is not None
    )
    accounting_complete = (
        value.get("accountingComplete") is True
        and _valid_bounded_int(value.get("callCount"))
        and isinstance(value.get("usage"), Mapping)
        and all(_valid_bounded_int(usage.get(key)) for key in _USAGE_KEYS)
        and _valid_bounded_number(value.get("latencyMilliseconds"))
        and cost_valid
    )
    if not accounting_complete:
        total["accountingComplete"] = False
    if not total["accountingComplete"]:
        total["estimatedCostUSD"] = None
    elif cost is None:
        total["estimatedCostUSD"] = None
    elif total["estimatedCostUSD"] is not None:
        total["estimatedCostUSD"] = _decimal_string(
            Decimal(total["estimatedCostUSD"]) + cost
        )


def _judge_cost_text(metrics):
    if not isinstance(metrics, Mapping):
        return "cost unavailable"
    if metrics.get("accountingComplete", True) is not True:
        return "cost unknown (accounting incomplete)"
    cost = metrics.get("estimatedCostUSD")
    return "cost not estimated" if cost is None else f"${cost} estimated"


def _worst_examples(run_root, records_by_id, grades_by_id):
    ranked = []
    for cell_id, grade in grades_by_id.items():
        record = records_by_id.get(cell_id, {})
        if not _valid_record(record) or grade.get("disposition") != "judged":
            continue
        scores = grade.get("scores") if isinstance(grade.get("scores"), dict) else {}
        mean = sum(scores.values()) / len(scores) if scores else 0
        severe = _severe_grade(grade)
        transcript = Path(run_root) / "transcripts" / (
            f"{record.get('configurationID')}--{record.get('caseID')}--r{record.get('repetition')}.md"
        )
        ranked.append(
            (
                0 if severe else 1,
                mean,
                cell_id,
                {
                    "cellID": cell_id,
                    "severeError": severe,
                    "meanDimensionScore": round(mean, 6),
                    "evidence": grade.get("evidence", []),
                    "transcriptPath": str(transcript),
                },
            )
        )
    ranked.sort(key=lambda value: value[:3])
    return [value[3] for value in ranked[:10]]


def _mechanical_failures(records):
    failures = []
    for record in records:
        if _valid_record(record):
            continue
        validation = record.get("mechanicalValidation")
        categories = (
            validation.get("categories", [])
            if isinstance(validation, Mapping)
            else []
        )
        failures.append(
            {
                "cellID": record.get("cellID"),
                "generationStatus": record.get("generationStatus"),
                "providerHTTPStatus": _http_status(record.get("providerHTTPStatus")),
                "categories": [
                    value for value in categories if isinstance(value, str)
                ],
            }
        )
    return failures


def _experiment_changes(configurations, baseline_id):
    if baseline_id is None or baseline_id not in configurations:
        return {}
    baseline = configurations[baseline_id]
    ignored = frozenset(("id", "baseline", "systemPrompt"))
    result = {}
    for identifier, candidate in configurations.items():
        if identifier == baseline_id:
            continue
        changed = {}
        for key in sorted((set(baseline) | set(candidate)) - ignored):
            if baseline.get(key) != candidate.get(key):
                changed[key] = {
                    "baseline": baseline.get(key),
                    "candidate": candidate.get(key),
                }
        result[identifier] = changed
    return result


def _public_configuration(configuration):
    return {
        key: value
        for key, value in configuration.items()
        if key != "systemPrompt"
    }


def _validate_configuration_policies(configurations, price_table, issues):
    pricing_versions = {
        value.get("pricingVersion") for value in configurations.values()
    }
    if pricing_versions != {price_table.version}:
        issues.append("candidate pricing version does not match report pricing")
    for identifier, configuration in configurations.items():
        if (
            configuration.get("conversationReuse") is True
            and configuration.get("store") is not True
        ):
            issues.append(
                f"conversation reuse without response storage for {identifier}"
            )


def _execution_policies(configurations):
    keys = (
        "initialReasoningEffort",
        "tacticalFollowUpReasoningEffort",
        "simpleFollowUpReasoningEffort",
        "conversationReuse",
        "store",
    )
    return {
        identifier: {key: configuration.get(key) for key in keys}
        for identifier, configuration in configurations.items()
    }


def _run_evidence(manifest, records, configurations, issues):
    mode = manifest.get("mode")
    diagnostic_subset = manifest.get("diagnosticSubset") is True
    include_holdout = manifest.get("includeHoldout") is True
    if diagnostic_subset:
        classification = "diagnosticSubset"
    elif mode == "comparison" and include_holdout:
        classification = "holdoutComparison"
    elif mode == "comparison":
        classification = "developmentComparison"
    else:
        classification = "quickDevelopment"

    complete_matrix = _complete_matrix(
        mode,
        include_holdout,
        diagnostic_subset,
        records,
        configurations,
    )
    if not diagnostic_subset and not complete_matrix:
        issues.append("candidate comparison matrix is incomplete")
    trial_eligible = (
        mode == "comparison" and not diagnostic_subset and complete_matrix
    )
    promotion_evidence_eligible = trial_eligible and include_holdout
    expected_manifest_evidence = {
        "classification": classification,
        "trialEligible": trial_eligible,
        "promotionEvidenceEligible": promotion_evidence_eligible,
    }
    if manifest.get("evidence") != expected_manifest_evidence:
        issues.append("candidate run evidence label does not match its matrix")
    return {
        "classification": classification,
        "includesHoldout": include_holdout,
        "diagnosticSubset": diagnostic_subset,
        "completeMatrix": complete_matrix,
        "trialEligible": trial_eligible,
        "promotionEvidenceEligible": promotion_evidence_eligible,
    }


def _complete_matrix(mode, include_holdout, diagnostic_subset, records, configurations):
    if diagnostic_subset or mode not in ("quick", "comparison"):
        return False
    repetitions = 1 if mode == "quick" else 3
    expected_split_counts = {"development": 56}
    if include_holdout:
        expected_split_counts["holdout"] = 14
    expected_case_count = sum(expected_split_counts.values())
    expected_record_count = expected_case_count * repetitions
    configuration_ids = set(configurations)
    if not configuration_ids or any(
        record.get("configurationID") not in configuration_ids for record in records
    ):
        return False

    common_cases = None
    for identifier in configurations:
        selected = [
            record
            for record in records
            if record.get("configurationID") == identifier
        ]
        if len(selected) != expected_record_count:
            return False
        cells = {
            (record.get("caseID"), record.get("repetition"))
            for record in selected
        }
        if len(cells) != expected_record_count:
            return False
        case_splits = {}
        repetition_cases = defaultdict(set)
        for record in selected:
            case_id = record.get("caseID")
            split = record.get("split")
            repetition = record.get("repetition")
            if (
                not isinstance(case_id, str)
                or split not in expected_split_counts
                or repetition not in range(1, repetitions + 1)
                or record.get("cellID")
                != f"{identifier}|{case_id}|r{repetition}"
            ):
                return False
            if case_id in case_splits and case_splits[case_id] != split:
                return False
            case_splits[case_id] = split
            repetition_cases[repetition].add(case_id)
        actual_split_counts = {
            split: sum(value == split for value in case_splits.values())
            for split in expected_split_counts
        }
        if actual_split_counts != expected_split_counts:
            return False
        case_ids = set(case_splits)
        if any(
            repetition_cases[repetition] != case_ids
            for repetition in range(1, repetitions + 1)
        ):
            return False
        comparable_cases = frozenset(case_splits.items())
        if common_cases is None:
            common_cases = comparable_cases
        elif common_cases != comparable_cases:
            return False
    return True


def _expected_pairs(records, configurations):
    baselines = [identifier for identifier, value in configurations.items() if value.get("baseline") is True]
    candidates = [identifier for identifier, value in configurations.items() if value.get("baseline") is False]
    if len(baselines) != 1 or not candidates:
        return set()
    baseline = baselines[0]
    baseline_cells = [record for record in records if record.get("configurationID") == baseline]
    return {
        f"{candidate}|{record.get('caseID')}|r{record.get('repetition')}|vs|{baseline}"
        for candidate in candidates
        for record in baseline_cells
    }


def _configurations(manifest, issues):
    raw = manifest.get("configurations")
    if not isinstance(raw, list):
        issues.append("candidate configurations are invalid")
        return {}
    output = {}
    for value in raw:
        if not isinstance(value, dict) or not isinstance(value.get("id"), str):
            issues.append("candidate configuration entry is invalid")
            continue
        if value["id"] in output:
            issues.append("candidate configuration IDs are duplicated")
            continue
        output[value["id"]] = value
    return output


def _baseline_id(configurations, issues, *, comparison):
    baselines = [identifier for identifier, value in configurations.items() if value.get("baseline") is True]
    if comparison and len(baselines) != 1:
        issues.append("comparison baseline is not unique")
        return None
    return baselines[0] if len(baselines) == 1 else None


def _unique_ids(values, key, label, issues):
    output = []
    for value in values:
        identifier = value.get(key) if isinstance(value, dict) else None
        if not isinstance(identifier, str) or not identifier:
            issues.append(f"{label} ID is invalid")
            continue
        output.append(identifier)
    if len(set(output)) != len(output):
        issues.append(f"{label} IDs are duplicated")
    return output


def _failure_categories(records):
    categories = set()
    for record in records:
        validation = record.get("mechanicalValidation")
        if not isinstance(validation, Mapping) or validation.get("valid") is True:
            continue
        raw = validation.get("categories")
        if isinstance(raw, list):
            categories.update(value for value in raw if isinstance(value, str))
    return sorted(categories)


def _provider_failure_breakdown(records):
    counts = defaultdict(int)
    for record in records:
        category = record.get("generationStatus")
        if (
            category in _PROVIDER_SUCCESS
            or not isinstance(category, str)
            or _bounded_int(record.get("attemptCount")) == 0
        ):
            continue
        counts[(category, _http_status(record.get("providerHTTPStatus")))] += 1
    return [
        {"category": category, "httpStatus": http_status, "count": count}
        for (category, http_status), count in sorted(
            counts.items(), key=lambda value: (value[0][0], value[0][1] or 0)
        )
    ]


def _http_status(value):
    if isinstance(value, bool) or not isinstance(value, int):
        return None
    return value if 100 <= value <= 599 else None


def _usage_total(usages):
    total = {key: 0 for key in _USAGE_KEYS}
    for usage in usages:
        if not isinstance(usage, Mapping):
            continue
        for key in _USAGE_KEYS:
            total[key] += _bounded_int(usage.get(key))
    return total


def _distribution(values):
    values = sorted(value for value in values if value >= 0)
    return {
        "count": len(values),
        "total": round(sum(values), 6),
        "p50": _nearest_rank(values, 0.50),
        "p90": _nearest_rank(values, 0.90),
    }


def _nearest_rank(values, percentile):
    if not values:
        return 0.0
    index = max(0, math.ceil(percentile * len(values)) - 1)
    return round(values[index], 6)


def _percentile_interval(values):
    values = sorted(values)
    if not values:
        return [0.0, 0.0]
    low = values[max(0, math.ceil(0.025 * len(values)) - 1)]
    high = values[max(0, math.ceil(0.975 * len(values)) - 1)]
    return [round(low, 6), round(high, 6)]


def _strong_grade(grade):
    scores = grade.get("scores") if isinstance(grade, Mapping) else None
    return bool(
        isinstance(scores, Mapping)
        and all(isinstance(scores.get(key), int) and scores[key] >= 4 for key in RUBRIC_DIMENSIONS)
        and not _severe_grade(grade)
    )


def _severe_grade(grade):
    flags = grade.get("flags") if isinstance(grade, Mapping) else None
    return bool(isinstance(flags, Mapping) and flags.get("severeError") is True)


def _valid_record(record):
    validation = record.get("mechanicalValidation") if isinstance(record, Mapping) else None
    return bool(isinstance(validation, Mapping) and validation.get("valid") is True)


def _rate(numerator, denominator):
    return round(numerator / denominator, 6) if denominator else 0.0


def _bounded_int(value):
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        return 0
    return min(value, 1_000_000_000)


def _valid_bounded_int(value):
    return (
        not isinstance(value, bool)
        and isinstance(value, int)
        and 0 <= value <= 1_000_000_000
    )


def _bounded_number(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return 0.0
    value = float(value)
    return value if math.isfinite(value) and 0 <= value <= 86_400_000 else 0.0


def _valid_bounded_number(value):
    return (
        not isinstance(value, bool)
        and isinstance(value, (int, float))
        and math.isfinite(float(value))
        and 0 <= float(value) <= 86_400_000
    )


def _nonnegative_decimal(value):
    try:
        result = Decimal(value) if isinstance(value, str) else None
        if result is not None:
            result.quantize(Decimal("0.000000000001"))
    except Exception:
        return None
    return result if result is not None and result.is_finite() and result >= 0 else None


def _valid_sha256(value):
    return isinstance(value, str) and _SHA256.fullmatch(value) is not None


def _decimal_string(value):
    return format(value.quantize(Decimal("0.000000000001")), "f")


def _read_object(path, label):
    _data, value = _read_object_bytes(path, label)
    return value


def _read_object_bytes(path, label):
    try:
        data = path.read_bytes()
        value = json.loads(data.decode("utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ValueError(f"Cannot read {label}") from error
    if not isinstance(value, dict):
        raise ValueError(f"{label} must be an object")
    return data, value


def _read_jsonl(path, label):
    try:
        data = path.read_bytes()
        values = [json.loads(line) for line in data.decode("utf-8").splitlines()]
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ValueError(f"Cannot read {label}") from error
    if any(not isinstance(value, dict) for value in values):
        raise ValueError(f"{label} must contain objects")
    return data, values


def _check_hash(issues, message, expected, data):
    if expected != _sha256(data):
        issues.append(message)


def _markdown(report):
    recommendation = report["recommendation"]
    if recommendation["decision"] == "promoteChallenger":
        decision_text = (
            f"Promote **{recommendation['configurationID']}** over the production baseline."
        )
    elif recommendation["decision"] == "keepBaseline":
        decision_text = (
            f"Keep the production baseline **{recommendation['configurationID']}**."
        )
    else:
        decision_text = "No promotion recommendation is available from this run."
    lines = [
        "# Coaching quality benchmark",
        "",
        "## Decision",
        "",
        decision_text,
        "",
        (
            f"Evidence: {report['evidence']['classification']}; "
            f"complete matrix={str(report['evidence']['completeMatrix']).lower()}; "
            f"includes holdout={str(report['evidence']['includesHoldout']).lower()}."
        ),
        "",
        "## Experiment changes",
        "",
    ]
    if report["experimentChanges"]:
        for identifier, changes in report["experimentChanges"].items():
            lines.append(f"- **{identifier}**: {', '.join(changes) if changes else 'no material changes'}")
    else:
        lines.append("- No candidate changes were available.")
    lines.extend(["", "## Execution policy", ""])
    for identifier, policy in report["executionPolicies"].items():
        lines.append(
            f"- **{identifier}**: initial {policy['initialReasoningEffort']}; "
            f"tactical follow-up {policy['tacticalFollowUpReasoningEffort']}; "
            f"simple follow-up {policy['simpleFollowUpReasoningEffort']}; "
            f"conversation reuse={str(policy['conversationReuse']).lower()}; "
            f"store={str(policy['store']).lower()}."
        )
    lines.extend(["", "## Quality and reliability", ""])
    for identifier, value in report["configurations"].items():
        line = (
            f"- **{identifier}**: strong {value['quality']['allDimensionsAtLeast4Rate']:.1%}; "
            f"severe {value['quality']['severeErrorRate']:.1%}; "
            f"mechanically valid {value['reliability']['mechanicalValidityRate']:.1%}; "
            f"p90 {value['latencyMilliseconds']['p90']:.0f} ms."
        )
        failures = value["reliability"]["providerFailureBreakdown"]
        if failures:
            details = ", ".join(
                f"{failure['category']}"
                + (
                    f" (HTTP {failure['httpStatus']})"
                    if failure["httpStatus"] is not None
                    else ""
                )
                + f": {failure['count']}"
                for failure in failures
            )
            line += f" Provider failures: {details}."
        lines.append(line)
    lines.extend(["", "## Eligibility gates", ""])
    for identifier, value in report["configurations"].items():
        reasons = "; ".join(value["promotionReasons"])
        lines.append(
            f"- **{identifier}**: trial eligible="
            f"{str(value['trialEligible']).lower()}; promotion eligible="
            f"{str(value['promotionEligible']).lower()}. {reasons}"
        )
    lines.extend(["", "## Candidate cost", ""])
    for identifier, value in report["configurations"].items():
        cost = value["candidateCostUSD"]
        cost_text = (
            f"${cost['total']}"
            if cost["accountingComplete"] and cost["total"] is not None
            else "unknown (accounting incomplete)"
        )
        lines.append(f"- **{identifier}**: {cost_text}")
    qualification = report["judgeQualification"]
    if qualification is not None:
        age = qualification["ageDaysAtGrading"]
        age_text = f"{age:.1f} days" if age is not None else "unknown"
        lines.extend(
            [
                "",
                "## Judge qualification",
                "",
                (
                    f"{qualification['repetitions']} passes; minimum severe agreement "
                    f"{qualification['minimumSevereAgreement']:.1%}; minimum dimension agreement "
                    f"{qualification['minimumDimensionAgreement']:.1%}; minimum pairwise agreement "
                    f"{qualification['minimumPairwiseAgreement']:.1%}."
                ),
                (
                    f"Created {qualification['createdAt']}; expires "
                    f"{qualification['expiresAt']}; age at grading "
                    f"{age_text}. Qualification "
                    f"{_judge_cost_text(qualification['metrics'])}."
                ),
            ]
        )
    lines.extend(
        [
            "",
            "## Judge overhead",
            "",
            f"{report['judgeOverhead']['callCount']} calls; {_judge_cost_text(report['judgeOverhead'])}.",
            "",
            "## Pareto frontier",
            "",
            ", ".join(report["paretoFrontier"]) or "None",
            "",
            "## Confidence intervals",
            "",
            f"Paired bootstrap: {report['confidenceIntervals']['draws']} draws, seed {report['confidenceIntervals']['seed']}.",
            "",
            "## Mechanical failures",
            "",
        ]
    )
    if report["mechanicalFailures"]:
        for failure in report["mechanicalFailures"]:
            http_status = failure["providerHTTPStatus"]
            http_detail = f"; HTTP {http_status}" if http_status is not None else ""
            lines.append(
                f"- **{failure['cellID']}**: {failure['generationStatus']} "
                f"({', '.join(failure['categories']) or 'unclassified'}{http_detail})"
            )
    else:
        lines.append("None.")
    lines.extend(
        [
            "",
            "## Worst-case examples",
            "",
        ]
    )
    for example in report["worstExamples"]:
        lines.append(
            f"- [{example['cellID']}]({example['transcriptPath']}): "
            f"mean {example['meanDimensionScore']:.2f}; severe={str(example['severeError']).lower()}"
        )
    if report["integrityIssues"]:
        lines.extend(["", "## Integrity issues", ""])
        lines.extend(f"- {issue}" for issue in report["integrityIssues"])
    return "\n".join(lines) + "\n"


def _ordered_unique(values):
    return list(dict.fromkeys(values))


def _pretty_json_bytes(value):
    return (json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode("utf-8")


def _sha256(data):
    return hashlib.sha256(data).hexdigest()


def _remove_tree(path):
    if not path.exists():
        return
    for child in path.iterdir():
        if child.is_dir():
            _remove_tree(child)
        else:
            child.unlink()
    path.rmdir()
