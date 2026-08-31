#!/usr/bin/env python3
"""Validate blinded coaching scores and summarize each hosted configuration."""

import argparse
import csv
import hashlib
import json
import math
import os
import shutil
import statistics
import sys
import tempfile
from pathlib import Path

import run_hosted_chess_native_broad_comparison as broad_runner


DIMENSIONS = (
    "factualCorrectness",
    "currentStage",
    "singlePurpose",
    "discoveryCoaching",
    "childLanguage",
    "uiAlignment",
)
RUBRIC_FIELDS = ("reviewID",) + DIMENSIONS + ("severe", "notes")
PRICES_PER_MILLION = {
    "gpt-5.6-sol": {"input": 4.00, "output": 20.00},
    "gpt-5.6-luna": {"input": 0.20, "output": 1.20},
}


def _sha256(data):
    return hashlib.sha256(data).hexdigest()


def _file_sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _load_json(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError) as error:
        raise ValueError(f"Cannot read JSON from {path}") from error


def _load_jsonl(path):
    try:
        lines = Path(path).read_text(encoding="utf-8").splitlines()
        return [json.loads(line) for line in lines]
    except (OSError, UnicodeError, ValueError) as error:
        raise ValueError(f"Cannot read JSONL from {path}") from error


def _inside_run(run_dir, relative_path):
    if not isinstance(relative_path, str) or not relative_path:
        raise ValueError("Review key record path must stay inside run")
    root = Path(run_dir).resolve()
    candidate = (root / relative_path).resolve()
    if root not in candidate.parents or not candidate.is_file():
        raise ValueError("Review key record path must stay inside run")
    return candidate


def _load_complete_rubric(rubric_path, packet):
    try:
        with Path(rubric_path).open(encoding="utf-8", newline="") as source:
            reader = csv.DictReader(source)
            if tuple(reader.fieldnames or ()) != RUBRIC_FIELDS:
                raise ValueError("Rubric has an unexpected header")
            rows = list(reader)
    except (OSError, UnicodeError, csv.Error) as error:
        raise ValueError("Cannot read completed rubric") from error
    packet_ids = [item.get("reviewID") for item in packet]
    rubric_ids = [row.get("reviewID") for row in rows]
    if len(rows) != len(packet) or len(set(rubric_ids)) != len(rubric_ids):
        raise ValueError("Rubric must be complete with one row per review")
    if rubric_ids != packet_ids:
        raise ValueError("Rubric review order must match the blinded packet")
    for row in rows:
        for dimension in DIMENSIONS:
            if row[dimension] not in {"1", "2", "3", "4", "5"}:
                raise ValueError(
                    "Rubric must be complete with integer scores 1 through 5"
                )
        if row["severe"] not in {"true", "false"}:
            raise ValueError("Rubric severe must be true or false")
        if row["severe"] == "true" and not row["notes"].strip():
            raise ValueError("Severe rubric rows require nonempty notes")
    return rows


def _percentile_90(values):
    ordered = sorted(values)
    return ordered[max(0, math.ceil(len(ordered) * 0.9) - 1)]


def summarize(run_dir, *, rubric_path=None):
    run_dir = Path(run_dir).resolve()
    manifest_path = run_dir / "run-manifest.json"
    packet_path = run_dir / "review" / "review-packet.jsonl"
    key_path = run_dir / "review" / "review-key.json"
    rubric_path = Path(rubric_path or (run_dir / "review" / "rubric.csv"))
    manifest = _load_json(manifest_path)
    packet = _load_jsonl(packet_path)
    rubric = _load_complete_rubric(rubric_path, packet)

    key = _load_json(key_path)
    entries = key.get("entries") if isinstance(key, dict) else None
    if not isinstance(entries, list) or len(entries) != len(packet):
        raise ValueError("Review key must map every blinded row exactly once")
    packet_ids = [item["reviewID"] for item in packet]
    key_ids = [item.get("reviewID") for item in entries]
    if len(set(key_ids)) != len(key_ids) or set(key_ids) != set(packet_ids):
        raise ValueError("Review key must map every blinded row exactly once")
    packet_by_id = {item["reviewID"]: item for item in packet}
    rubric_by_id = {item["reviewID"]: item for item in rubric}
    manifest_bindings = {
        (entry["configurationID"], entry["caseID"]): entry
        for entry in manifest.get("records", [])
    }

    joined = []
    for entry in entries:
        record_path = _inside_run(run_dir, entry.get("recordPath"))
        actual_hash = _file_sha256(record_path)
        if actual_hash != entry.get("recordSHA256"):
            raise ValueError("Review key record hash does not match")
        binding = manifest_bindings.get(
            (entry.get("configurationID"), entry.get("caseID"))
        )
        if (
            not isinstance(binding, dict)
            or binding.get("path") != entry.get("recordPath")
            or binding.get("sha256") != actual_hash
        ):
            raise ValueError("Review key record does not match run manifest")
        record = _load_json(record_path)
        if (
            record.get("configurationID") != entry.get("configurationID")
            or record.get("caseID") != entry.get("caseID")
            or record.get("requestedModel") != entry.get("requestedModel")
            or record.get("reasoningEffort") != entry.get("reasoningEffort")
        ):
            raise ValueError("Review key identity does not match its private record")
        review_id = entry["reviewID"]
        joined.append(
            {
                "entry": entry,
                "record": record,
                "packet": packet_by_id[review_id],
                "rubric": rubric_by_id[review_id],
            }
        )

    configurations = []
    for configuration in manifest.get("configurations", []):
        identifier = configuration["id"]
        cells = [
            cell for cell in joined if cell["entry"]["configurationID"] == identifier
        ]
        if not cells:
            raise ValueError(f"No reviewed records for configuration {identifier}")
        model = configuration["model"]
        if model not in PRICES_PER_MILLION:
            raise ValueError(f"No frozen price for model {model}")
        input_tokens = sum(cell["record"]["metrics"]["inputTokens"] for cell in cells)
        output_tokens = sum(cell["record"]["metrics"]["outputTokens"] for cell in cells)
        reasoning_tokens = sum(
            cell["record"]["metrics"]["reasoningTokens"] for cell in cells
        )
        latencies = [cell["record"]["metrics"]["latencyMilliseconds"] for cell in cells]
        dimension_means = {
            dimension: round(
                statistics.fmean(int(cell["rubric"][dimension]) for cell in cells),
                3,
            )
            for dimension in DIMENSIONS
        }
        prices = PRICES_PER_MILLION[model]
        estimated_cost = (
            input_tokens * prices["input"] + output_tokens * prices["output"]
        ) / 1_000_000
        example_cells = sorted(
            cells,
            key=lambda cell: (
                cell["rubric"]["severe"] != "true",
                cell["entry"]["caseID"],
            ),
        )[:3]
        configurations.append(
            {
                "configurationID": identifier,
                "model": model,
                "reasoningEffort": configuration["reasoningEffort"],
                "total": len(cells),
                "strictValid": sum(
                    cell["record"]["validation"]["valid"] for cell in cells
                ),
                "severe": sum(
                    cell["rubric"]["severe"] == "true" for cell in cells
                ),
                "dimensionMeans": dimension_means,
                "latencyMedianMilliseconds": round(statistics.median(latencies), 3),
                "latencyP90Milliseconds": round(_percentile_90(latencies), 3),
                "inputTokens": input_tokens,
                "outputTokens": output_tokens,
                "reasoningTokens": reasoning_tokens,
                "estimatedCostUSD": round(estimated_cost, 8),
                "reviewExamples": [
                    {
                        "reviewID": cell["entry"]["reviewID"],
                        "caseID": cell["entry"]["caseID"],
                        "scores": {
                            dimension: int(cell["rubric"][dimension])
                            for dimension in DIMENSIONS
                        },
                        "severe": cell["rubric"]["severe"] == "true",
                        "notes": cell["rubric"]["notes"],
                        "turn": cell["packet"]["turn"],
                    }
                    for cell in example_cells
                ],
            }
        )

    return {
        "schemaVersion": "model-coaching-chess-native-broad-summary.v1",
        "recordCount": len(joined),
        "reviewCount": len(rubric),
        "sourceManifestSHA256": manifest["sourceManifestSHA256"],
        "examplesJSONLSHA256": manifest["examplesJSONLSHA256"],
        "runManifestSHA256": _file_sha256(manifest_path),
        "reviewPacketSHA256": _file_sha256(packet_path),
        "reviewKeySHA256": _file_sha256(key_path),
        "rubricSHA256": _file_sha256(rubric_path),
        "configurations": configurations,
    }


def _markdown(summary):
    lines = [
        "# Broader hosted chess-coaching comparison",
        "",
        "Results are reported by dimension; no combined score or automatic ranking is calculated.",
        "",
    ]
    for configuration in summary["configurations"]:
        lines.extend(
            (
                f"## {configuration['configurationID']}",
                "",
                f"- Model: `{configuration['model']}`",
                f"- Strict valid: {configuration['strictValid']}/{configuration['total']}",
                f"- Severe: {configuration['severe']}/{configuration['total']}",
                f"- Estimated cost: ${configuration['estimatedCostUSD']:.6f}",
                f"- Latency median / p90: {configuration['latencyMedianMilliseconds']:.0f} / {configuration['latencyP90Milliseconds']:.0f} ms",
                "",
                "| Dimension | Mean |",
                "|---|---:|",
            )
        )
        for dimension in DIMENSIONS:
            lines.append(
                f"| {dimension} | {configuration['dimensionMeans'][dimension]:.3f} |"
            )
        lines.append("")
    return "\n".join(lines)


def write_summary(run_dir, *, rubric_path=None, destination):
    destination = Path(destination)
    if os.path.lexists(destination):
        raise ValueError(f"Refusing to overwrite existing summary: {destination}")
    summary = summarize(run_dir, rubric_path=rubric_path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(
        tempfile.mkdtemp(prefix=f".{destination.name}.tmp-", dir=str(destination.parent))
    )
    try:
        broad_runner.hosted_pilot._write_fsynced(
            temporary / "comparison-summary.json",
            broad_runner._canonical_json_bytes(summary),
        )
        broad_runner.hosted_pilot._write_fsynced(
            temporary / "comparison-summary.md", _markdown(summary)
        )
        broad_runner.hosted_pilot._fsync_directory(temporary)
        if os.path.lexists(destination):
            raise ValueError(f"Refusing to overwrite existing summary: {destination}")
        os.rename(temporary, destination)
        broad_runner.hosted_pilot._fsync_directory(destination.parent)
        return summary
    except Exception:
        shutil.rmtree(temporary, ignore_errors=True)
        raise


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", required=True, type=Path)
    parser.add_argument("--rubric", type=Path)
    parser.add_argument("--destination", required=True, type=Path)
    arguments = parser.parse_args(argv)
    try:
        summary = write_summary(
            arguments.run,
            rubric_path=arguments.rubric,
            destination=arguments.destination,
        )
    except (OSError, RuntimeError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1
    print(json.dumps({"recordCount": summary["recordCount"]}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
