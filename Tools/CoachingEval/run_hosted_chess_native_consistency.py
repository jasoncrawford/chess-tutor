#!/usr/bin/env python3
"""Repeat the frozen tutor-v6 hard cases against the hosted flagship model."""

import argparse
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path

import run_hosted_chess_native_pilot as hosted_pilot


HARD_CASE_IDS = (
    "02-attacked-piece",
    "05-tactical-reply",
    "06-inspected-reply",
    "07-answering-check",
)
SAMPLE_INDICES = (2, 3)


def run_hosted_consistency(
    *, source_dir, system_prompt_path, destination, client, timeout=120
):
    destination = Path(destination)
    if os.path.lexists(destination):
        raise ValueError(
            f"Refusing to overwrite existing consistency directory: {destination}"
        )
    source = hosted_pilot._load_frozen_source(source_dir, system_prompt_path)
    prompts = {prompt["id"]: prompt for prompt in source["prompts"]}
    records = []
    for sample_index in SAMPLE_INDICES:
        for identifier in HARD_CASE_IDS:
            record = hosted_pilot._complete_prompt(
                prompts[identifier], source, client, timeout
            )
            record["schemaVersion"] = (
                "model-coaching-chess-native-hosted-consistency-record.v1"
            )
            record["sampleIndex"] = sample_index
            records.append(record)
    return _write_output(
        destination=destination,
        source_dir=Path(source_dir).resolve(),
        source=source,
        records=records,
    )


def _review_markdown(source_dir, records):
    lines = [
        "# Chess-native hosted-model consistency review",
        "",
        "This review contains only final trace-free candidates.",
        "",
    ]
    system_path = (Path(source_dir) / "system-prompt.md").resolve().as_posix()
    for record in records:
        identifier = record["caseID"]
        sample_index = record["sampleIndex"]
        user_path = (
            Path(source_dir) / "user-prompts" / f"{identifier}.md"
        ).resolve().as_posix()
        lines.extend(
            (
                f"## {identifier} — sample {sample_index}",
                "",
                f"- System: [system-prompt.md]({system_path})",
                f"- User: [{identifier}.md]({user_path})",
                f"- Validation: {record['generationStatus']}",
                "",
                "### Response",
                "",
            )
        )
        if record["finalContent"]:
            lines.extend(
                "    " + line for line in record["finalContent"].splitlines()
            )
        else:
            lines.append("_No safe final content was persisted._")
        lines.append("")
    return "\n".join(lines)


def _write_output(*, destination, source_dir, source, records):
    destination = Path(destination)
    if os.path.lexists(destination):
        raise ValueError(
            f"Refusing to overwrite existing consistency directory: {destination}"
        )
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(
        tempfile.mkdtemp(prefix=f".{destination.name}.tmp-", dir=str(destination.parent))
    )
    try:
        records_dir = temporary / "records"
        records_dir.mkdir()
        manifest_records = []
        for record in records:
            record_bytes = hosted_pilot._canonical_json_bytes(record)
            stem = f"{record['caseID']}-sample-{record['sampleIndex']}"
            relative_path = Path("records") / f"{stem}.json"
            hosted_pilot._write_fsynced(temporary / relative_path, record_bytes)
            manifest_records.append(
                {
                    "caseID": record["caseID"],
                    "sampleIndex": record["sampleIndex"],
                    "path": relative_path.as_posix(),
                    "sha256": hosted_pilot._sha256(record_bytes),
                }
            )
        hosted_pilot._fsync_directory(records_dir)

        review = _review_markdown(source_dir, records)
        if hosted_pilot._TRACE_MARKER.search(review):
            raise ValueError("Refusing to persist a review containing a trace marker")
        review_bytes = review.encode("utf-8")
        hosted_pilot._write_fsynced(temporary / "review.md", review_bytes)

        valid_count = sum(record["validation"]["valid"] for record in records)
        provider_error_count = sum(
            record["generationStatus"] == "generationError" for record in records
        )
        manifest = {
            "schemaVersion": "model-coaching-chess-native-hosted-consistency.v1",
            "promptVersion": hosted_pilot.PROMPT_VERSION,
            "caseIDs": list(HARD_CASE_IDS),
            "sampleIndices": list(SAMPLE_INDICES),
            "sourceDirectory": str(Path(source_dir).resolve()),
            "sourceManifestSHA256": hosted_pilot.SOURCE_MANIFEST_SHA256,
            "examplesJSONLSHA256": hosted_pilot.EXAMPLES_JSONL_SHA256,
            "systemPromptSHA256": source["systemPromptSHA256"],
            "provider": {
                "api": "openai-responses-v1",
                "model": hosted_pilot.MODEL,
                "reasoningEffort": hosted_pilot.REASONING_EFFORT,
                "maximumOutputTokens": hosted_pilot.MAXIMUM_OUTPUT_TOKENS,
            },
            "records": manifest_records,
            "review": {
                "path": "review.md",
                "sha256": hosted_pilot._sha256(review_bytes),
            },
            "summary": {
                "recordCount": len(records),
                "completionAttempts": sum(
                    record["completionAttempts"] for record in records
                ),
                "validCount": valid_count,
                "invalidCount": len(records) - valid_count,
                "providerErrorCount": provider_error_count,
            },
        }
        manifest_bytes = hosted_pilot._canonical_json_bytes(manifest)
        if hosted_pilot._TRACE_MARKER.search(manifest_bytes.decode("utf-8")):
            raise ValueError("Refusing to persist a manifest containing a trace marker")
        hosted_pilot._write_fsynced(
            temporary / "run-manifest.json", manifest_bytes
        )
        hosted_pilot._fsync_directory(temporary)
        if os.path.lexists(destination):
            raise ValueError(
                f"Refusing to overwrite existing consistency directory: {destination}"
            )
        os.rename(temporary, destination)
        hosted_pilot._fsync_directory(destination.parent)
        return manifest
    except Exception:
        shutil.rmtree(temporary, ignore_errors=True)
        raise


def _execute(arguments):
    import openai_responses

    client = openai_responses.OpenAIResponsesClient(
        hosted_pilot.OPENAI_BASE_URL,
        api_key=hosted_pilot._api_key_from_environment(dict(os.environ)),
    )
    manifest = run_hosted_consistency(
        source_dir=arguments.source,
        system_prompt_path=arguments.system_prompt,
        destination=arguments.destination,
        client=client,
        timeout=arguments.timeout,
    )
    print(json.dumps(manifest["summary"], sort_keys=True))
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        type=Path,
        default=(
            hosted_pilot.ARTIFACT_ROOT
            / "chess-native-prompt-preview"
            / "swift-export-v2"
        ),
    )
    parser.add_argument(
        "--system-prompt",
        type=Path,
        default=hosted_pilot.TOOLS_DIR / "prompts" / "tutor-v6.md",
    )
    parser.add_argument("--destination", required=True, type=Path)
    parser.add_argument("--timeout", type=int, default=120)
    arguments = parser.parse_args(argv)
    try:
        return _execute(arguments)
    except (OSError, RuntimeError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
