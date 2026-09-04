"""Deterministic benchmark aggregation and concise tradeoff reports."""

import hashlib
import json
import math
import os
import random
import uuid
from collections import defaultdict
from decimal import Decimal
from pathlib import Path
from typing import Any, Mapping, Sequence

from Tools.CoachingEval.benchmark.grader import RUBRIC_DIMENSIONS


_BOOTSTRAP_DRAWS = 10_000
_BOOTSTRAP_SEED = 20260901
_PROVIDER_SUCCESS = frozenset(("completed", "invalid"))
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
    calibration = _read_object(grade_root / "calibration.json", "judge calibration")
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
    calibration_bytes = _pretty_json_bytes(calibration)
    _check_hash(
        issues,
        "calibration hash mismatch",
        grade_manifest.get("calibrationSHA256"),
        calibration_bytes,
    )
    if grade_manifest.get("sourceRunRecordsSHA256") != run_manifest.get(
        "recordsSHA256"
    ):
        issues.append("grade source run hash mismatch")
    if grade_manifest.get("corpusSHA256") != run_manifest.get("corpusSHA256"):
        issues.append("grade corpus hash mismatch")
    if calibration.get("passed") is not True:
        issues.append("judge calibration did not pass")
    if run_manifest.get("diagnosticSubset") is True:
        issues.append("diagnostic subset is not promotion eligible")

    configurations = _configurations(run_manifest, issues)
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
            price_table,
            issues,
        )

    baseline_id = _baseline_id(configurations, issues)
    confidence = _confidence_intervals(
        records, grades_by_id, baseline_id, configurations
    )
    frontier = _pareto_frontier(aggregates)
    _apply_promotion_eligibility(
        aggregates,
        baseline_id,
        issues,
    )
    global_eligible = not issues and any(
        value.get("promotionEligible") is True for value in aggregates.values()
    )
    judge_overhead = _judge_overhead(calibration, absolute, pairwise)

    return {
        "schemaVersion": "coaching-quality-report.v1",
        "source": {
            "candidateRecordsSHA256": _sha256(records_bytes),
            "absoluteGradesSHA256": _sha256(absolute_bytes),
            "pairwiseGradesSHA256": _sha256(pairwise_bytes),
            "corpusSHA256": run_manifest.get("corpusSHA256"),
            "priceTableSHA256": price_table.sha256,
        },
        "mode": run_manifest.get("mode"),
        "experimentChanges": _experiment_changes(configurations, baseline_id),
        "configurations": aggregates,
        "confidenceIntervals": confidence,
        "paretoFrontier": frontier,
        "judgeOverhead": judge_overhead,
        "promotionEligible": global_eligible,
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
    for record in records:
        try:
            candidate_cost += price_table.estimate(
                configuration.get("model"), record.get("usage", {})
            )
        except ValueError:
            issues.append(f"missing price coverage for {identifier}")
    pair_counts = _pair_counts(identifier, configuration, pairwise)
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
            "total": _decimal_string(candidate_cost),
            "perResponse": _decimal_string(
                candidate_cost / response_count if response_count else Decimal(0)
            ),
        },
        "completeSequenceCostsUSD": _sequence_costs(
            records, configuration, price_table, issues
        ),
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


def _pair_counts(identifier, configuration, pairwise):
    if configuration.get("baseline") is True:
        outcomes = []
        for grade in pairwise:
            outcome = grade.get("outcome")
            if outcome == "candidateWin":
                outcomes.append("loss")
            elif outcome == "candidateLoss":
                outcomes.append("win")
            elif outcome in ("tie", "unusableTie"):
                outcomes.append("tie")
    else:
        prefix = f"{identifier}|"
        outcomes = []
        for grade in pairwise:
            if not str(grade.get("pairID", "")).startswith(prefix):
                continue
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
    return (
        value["quality"]["allDimensionsAtLeast4Rate"],
        value["quality"]["severeErrorRate"],
        value["latencyMilliseconds"]["p90"],
        Decimal(value["candidateCostUSD"]["total"]),
    )


def _apply_promotion_eligibility(aggregates, baseline_id, issues):
    if baseline_id is None or baseline_id not in aggregates:
        return
    baseline = aggregates[baseline_id]
    baseline["promotionReasons"] = ["Production baseline is the comparison reference."]
    for identifier, candidate in aggregates.items():
        if identifier == baseline_id:
            continue
        reasons = []
        candidate_failures = set(candidate["reliability"]["mechanicalFailureCategories"])
        baseline_failures = set(baseline["reliability"]["mechanicalFailureCategories"])
        if candidate_failures - baseline_failures:
            reasons.append("Introduces a new mechanical failure category.")
        if candidate["quality"]["severeErrorRate"] > baseline["quality"]["severeErrorRate"]:
            reasons.append("Severe-error rate is higher than production.")
        if candidate["pairwise"]["wins"] <= candidate["pairwise"]["losses"]:
            reasons.append("Pairwise wins do not exceed losses.")
        if candidate["quality"]["allDimensionsAtLeast4Rate"] <= baseline["quality"]["allDimensionsAtLeast4Rate"]:
            reasons.append("Strong-response rate does not improve on production.")
        if issues:
            reasons.append("Artifact integrity is incomplete.")
        candidate["promotionReasons"] = reasons or ["Eligible for a human app trial."]
        candidate["promotionEligible"] = not reasons


def _judge_overhead(calibration, absolute, pairwise):
    metrics = _empty_metrics()
    _add_metrics(metrics, calibration.get("judgeMetrics"))
    for grade in absolute:
        _add_metrics(metrics, grade.get("judgeMetrics"))
    for grade in pairwise:
        _add_metrics(metrics, grade.get("judgeMetrics"))
    return metrics


def _empty_metrics():
    return {
        "callCount": 0,
        "usage": {key: 0 for key in _USAGE_KEYS},
        "latencyMilliseconds": {"total": 0.0},
        "estimatedCostUSD": "0",
    }


def _add_metrics(total, value):
    if not isinstance(value, Mapping):
        return
    total["callCount"] += _bounded_int(value.get("callCount"))
    usage = value.get("usage") if isinstance(value.get("usage"), Mapping) else {}
    for key in _USAGE_KEYS:
        total["usage"][key] += _bounded_int(usage.get(key))
    total["latencyMilliseconds"]["total"] += _bounded_number(
        value.get("latencyMilliseconds")
    )
    cost = value.get("estimatedCostUSD")
    if cost is not None:
        try:
            total["estimatedCostUSD"] = _decimal_string(
                Decimal(total["estimatedCostUSD"]) + Decimal(str(cost))
            )
        except Exception:
            pass


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


def _baseline_id(configurations, issues):
    baselines = [identifier for identifier, value in configurations.items() if value.get("baseline") is True]
    if len(baselines) != 1:
        issues.append("comparison baseline is not unique")
        return None
    return baselines[0]


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


def _bounded_number(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return 0.0
    value = float(value)
    return value if math.isfinite(value) and 0 <= value <= 86_400_000 else 0.0


def _decimal_string(value):
    return format(value.quantize(Decimal("0.000000000001")), "f")


def _read_object(path, label):
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ValueError(f"Cannot read {label}") from error
    if not isinstance(value, dict):
        raise ValueError(f"{label} must be an object")
    return value


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
    lines = [
        "# Coaching quality benchmark",
        "",
        "## Decision",
        "",
        (
            "At least one candidate is eligible for a human app trial."
            if report["promotionEligible"]
            else "No candidate is currently eligible for a human app trial."
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
    lines.extend(["", "## Candidate cost", ""])
    for identifier, value in report["configurations"].items():
        lines.append(f"- **{identifier}**: ${value['candidateCostUSD']['total']}")
    lines.extend(
        [
            "",
            "## Judge overhead",
            "",
            f"{report['judgeOverhead']['callCount']} calls; ${report['judgeOverhead']['estimatedCostUSD']} estimated.",
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
