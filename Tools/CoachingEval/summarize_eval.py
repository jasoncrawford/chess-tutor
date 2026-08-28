#!/usr/bin/env python3
"""Summarize mechanical and blinded human coaching-evaluation results."""

import argparse
import csv
import json
import math
import statistics
import sys
from pathlib import Path

import render_review


def _record_rows(run_root):
    rows = []
    for path in sorted(Path(run_root).rglob("records.jsonl")):
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if line:
                rows.append((str(path.resolve()), line_number, json.loads(line)))
    if not rows:
        raise ValueError(f"No evaluation records found under {run_root}")
    return rows


def _rubric_rows(run_root, key):
    rubric_path = Path(run_root) / "rubric.csv"
    if not rubric_path.is_file():
        raise ValueError(f"Missing rubric.csv under {run_root}")
    with rubric_path.open(encoding="utf-8", newline="") as source:
        rows = list(csv.DictReader(source))
    by_id = {}
    for row in rows:
        review_id = row.get("reviewID", "")
        if not review_id or review_id in by_id:
            raise ValueError(f"Missing or duplicate rubric reviewID: {review_id!r}")
        for column in render_review.RUBRIC_COLUMNS[:-1]:
            if not row.get(column, "").strip():
                raise ValueError(f"Rubric row {review_id} is incomplete at {column}")
        for column in render_review.POSITIVE_COLUMNS:
            try:
                value = int(row[column])
            except ValueError as error:
                raise ValueError(f"Rubric {column} must be an integer from 1 through 5") from error
            if value not in range(1, 6):
                raise ValueError(f"Rubric {column} must be an integer from 1 through 5")
            row[column] = value
        for column in render_review.NEGATIVE_COLUMNS:
            try:
                value = int(row[column])
            except ValueError as error:
                raise ValueError(f"Rubric {column} must be 0 or 1") from error
            if value not in (0, 1):
                raise ValueError(f"Rubric {column} must be 0 or 1")
            row[column] = value
        by_id[review_id] = row
    expected = set(key["entries"])
    if set(by_id) != expected:
        missing = sorted(expected - set(by_id))
        extra = sorted(set(by_id) - expected)
        raise ValueError(f"Rubric IDs do not match review key; missing={missing}, extra={extra}")
    return by_id


def _percentile(values, percentile):
    if not values:
        return None
    ordered = sorted(values)
    index = max(0, math.ceil(percentile * len(ordered)) - 1)
    return ordered[index]


def _rate(count, total):
    return 0.0 if total == 0 else count / total


def _aggregate(records, scores):
    total = len(records)
    first_valid = sum(bool(record.get("firstAttemptValidation", {}).get("valid")) for record in records)
    repaired = [record for record in records if record.get("repairAttempted")]
    repaired_valid = sum(
        bool((record.get("repairValidation") or {}).get("valid")) for record in repaired
    )
    displayable = sum(
        bool(record.get("firstAttemptValidation", {}).get("valid"))
        or bool((record.get("repairValidation") or {}).get("valid"))
        for record in records
    )
    latency = [float(record.get("latencyMilliseconds", 0.0)) for record in records]
    rubric_dimensions = {}
    for column in render_review.POSITIVE_COLUMNS:
        values = [score[column] for score in scores]
        rubric_dimensions[column] = {
            "mean": statistics.fmean(values) if values else None,
            "values": values,
        }
    for column in render_review.NEGATIVE_COLUMNS:
        values = [score[column] for score in scores]
        count = sum(values)
        rubric_dimensions[column] = {
            "count": count,
            "rate": _rate(count, len(values)),
            "values": values,
        }
    return {
        "recordCount": total,
        "mechanical": {
            "firstAttemptValidCount": first_valid,
            "firstAttemptValidityRate": _rate(first_valid, total),
            "repairAttemptCount": len(repaired),
            "repairedValidCount": repaired_valid,
            "repairedValidityRate": _rate(repaired_valid, len(repaired)),
            "displayableValidCount": displayable,
            "displayableValidityRate": _rate(displayable, total),
        },
        "latencyMilliseconds": {
            "p50": _percentile(latency, 0.5),
            "p90": _percentile(latency, 0.9),
        },
        "tokens": {
            "inputTotal": sum(int(record.get("promptTokens", 0)) for record in records),
            "outputTotal": sum(int(record.get("outputTokens", 0)) for record in records),
            "inputMean": statistics.fmean(int(record.get("promptTokens", 0)) for record in records),
            "outputMean": statistics.fmean(int(record.get("outputTokens", 0)) for record in records),
        },
        "rubric": {
            "completedRows": len(scores),
            "severeErrorCount": sum(score["severeError"] for score in scores),
            "dimensions": rubric_dimensions,
        },
    }


def summarize(run_root):
    run_root = Path(run_root)
    key_path = run_root / "review-key.json"
    if not key_path.is_file():
        raise ValueError(f"Missing review-key.json under {run_root}")
    key = json.loads(key_path.read_text(encoding="utf-8"))
    rubric = _rubric_rows(run_root, key)
    source_rows = _record_rows(run_root)
    by_pointer = {(path, line): record for path, line, record in source_rows}

    reviewed = []
    for review_id, identity in key["entries"].items():
        pointer = (identity["recordsPath"], identity["recordsLine"])
        if pointer not in by_pointer:
            raise ValueError(f"Review key points to an absent record: {pointer}")
        reviewed.append((review_id, by_pointer[pointer], rubric[review_id]))

    records = [record for _, record, _ in reviewed]
    scores = [score for _, _, score in reviewed]
    summary = _aggregate(records, scores)
    summary["reviewSeed"] = key["reviewSeed"]

    configurations = {}
    configuration_keys = sorted(
        {(record["modelID"], record["mode"], record["caseSplit"]) for record in records}
    )
    for model_id, mode, split in configuration_keys:
        selected = [
            (record, score)
            for _, record, score in reviewed
            if record["modelID"] == model_id and record["mode"] == mode and record["caseSplit"] == split
        ]
        configurations[f"{model_id}|{mode}|{split}"] = _aggregate(
            [record for record, _ in selected], [score for _, score in selected]
        )
    summary["byConfiguration"] = configurations

    examples = {}
    for review_id, record, score in reviewed:
        examples.setdefault(record["caseID"], []).append(
            {
                "reviewID": review_id,
                "modelID": record["modelID"],
                "mode": record["mode"],
                "seed": record["seed"],
                "rawFinalContent": record.get("rawFinalContent"),
                "candidateTurn": record.get("parsedTurn"),
                "rubric": {column: score[column] for column in render_review.RUBRIC_COLUMNS},
            }
        )
    summary["examplesByCase"] = {case_id: examples[case_id] for case_id in sorted(examples)}

    (run_root / "aggregate.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    (run_root / "summary.md").write_text(_markdown(summary), encoding="utf-8")
    return summary


def _markdown(summary):
    mechanical = summary["mechanical"]
    lines = [
        "# Coaching evaluation summary",
        "",
        f"Records: {summary['recordCount']}",
        f"First-attempt valid: {mechanical['firstAttemptValidCount']} ({mechanical['firstAttemptValidityRate']:.1%})",
        f"Valid after repair: {mechanical['displayableValidCount']} ({mechanical['displayableValidityRate']:.1%})",
        f"Repair attempts: {mechanical['repairAttemptCount']}; successful: {mechanical['repairedValidCount']}",
        f"Latency p50/p90: {summary['latencyMilliseconds']['p50']:.1f} / {summary['latencyMilliseconds']['p90']:.1f} ms",
        f"Input/output tokens: {summary['tokens']['inputTotal']} / {summary['tokens']['outputTotal']}",
        f"Severe errors: {summary['rubric']['severeErrorCount']}",
        "",
        "## Rubric dimensions",
        "",
    ]
    for name, result in summary["rubric"]["dimensions"].items():
        if "mean" in result:
            lines.append(f"- {name}: mean {result['mean']:.2f}")
        else:
            lines.append(f"- {name}: {result['count']} ({result['rate']:.1%})")
    lines.extend(["", "## Configurations", ""])
    for name, result in summary["byConfiguration"].items():
        lines.append(
            f"- {name}: {result['mechanical']['displayableValidCount']}/{result['recordCount']} displayable; "
            f"p50/p90 {result['latencyMilliseconds']['p50']:.1f}/{result['latencyMilliseconds']['p90']:.1f} ms"
        )
    lines.extend(["", "Raw examples remain available in aggregate.json under examplesByCase.", ""])
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", required=True, type=Path)
    arguments = parser.parse_args(argv)
    try:
        summarize(arguments.run)
        print(arguments.run / "summary.md")
        return 0
    except (OSError, ValueError, KeyError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
