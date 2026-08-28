#!/usr/bin/env python3
"""Render model outputs into deterministic blinded human-review artifacts."""

import argparse
import csv
import json
import random
import sys
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parent
RUBRIC_COLUMNS = [
    "factualCorrectness",
    "oneCoherentStep",
    "responsiveToLatestAction",
    "answerability",
    "childClarity",
    "pedagogicalUsefulness",
    "unnecessaryInterrogation",
    "mixedStages",
    "severeError",
    "notes",
]
POSITIVE_COLUMNS = RUBRIC_COLUMNS[:6]
NEGATIVE_COLUMNS = RUBRIC_COLUMNS[6:9]


def _records(run_roots):
    records = []
    for root in run_roots:
        paths = sorted(Path(root).rglob("records.jsonl"))
        if not paths:
            raise ValueError(f"No records.jsonl found under {root}")
        for path in paths:
            for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                if line:
                    records.append((path, line_number, json.loads(line)))
    return records


def render_review(run_roots, output, *, review_seed):
    output = Path(output)
    targets = [
        output / "review-packet.jsonl",
        output / "review-key.json",
        output / "rubric.csv",
    ]
    if any(path.exists() for path in targets):
        raise ValueError(f"Refusing to overwrite existing review artifacts in {output}")
    output.mkdir(parents=True, exist_ok=True)

    source_records = _records(run_roots)
    random.Random(review_seed).shuffle(source_records)
    packet = []
    key_entries = {}
    rubric_rows = []
    for index, (path, line_number, record) in enumerate(source_records, 1):
        review_id = f"review-{index:05d}"
        evaluation_case = record["evaluationCase"]
        request = evaluation_case["request"]
        oracle = evaluation_case["oracle"]
        packet.append(
            {
                "reviewID": review_id,
                "position": request["currentPosition"],
                "fullGameHistory": request["fullGameHistory"],
                "latestAction": request["currentInteraction"]["latestEvent"],
                "currentInteraction": request["currentInteraction"],
                "candidateTurn": record.get("parsedTurn"),
                "successCriteria": oracle["successCriteria"],
                "severeFailureCriteria": oracle["severeFailureCriteria"],
            }
        )
        key_entries[review_id] = {
            "modelID": record["modelID"],
            "caseID": record["caseID"],
            "caseSplit": record["caseSplit"],
            "mode": record["mode"],
            "seed": record["seed"],
            "recordsPath": str(path.resolve()),
            "recordsLine": line_number,
        }
        row = {"reviewID": review_id}
        if record["modelID"] == "fake-test-model":
            row.update({column: "3" for column in POSITIVE_COLUMNS})
            row.update({column: "0" for column in NEGATIVE_COLUMNS})
            row["notes"] = "test-only synthetic rubric row"
        else:
            row.update({column: "" for column in RUBRIC_COLUMNS})
        rubric_rows.append(row)

    with targets[0].open("w", encoding="utf-8") as destination:
        for entry in packet:
            destination.write(json.dumps(entry, sort_keys=True, separators=(",", ":")) + "\n")
    targets[1].write_text(
        json.dumps({"reviewSeed": review_seed, "entries": key_entries}, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    with targets[2].open("w", encoding="utf-8", newline="") as destination:
        writer = csv.DictWriter(
            destination,
            fieldnames=["reviewID"] + RUBRIC_COLUMNS,
            lineterminator="\n",
        )
        writer.writeheader()
        writer.writerows(rubric_rows)
    return targets


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="append", required=True, type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--review-seed", type=int)
    arguments = parser.parse_args(argv)
    if arguments.output is None:
        if len(arguments.run) != 1:
            parser.error("--output is required when combining multiple runs")
        arguments.output = arguments.run[0]
    if arguments.review_seed is None:
        runtime = json.loads((TOOLS_DIR / "runtime.json").read_text(encoding="utf-8"))
        arguments.review_seed = runtime["evaluation"]["reviewSeed"]
    try:
        render_review(arguments.run, arguments.output, review_seed=arguments.review_seed)
        print(arguments.output)
        return 0
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
