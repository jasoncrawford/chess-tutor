#!/usr/bin/env python3
"""Run and blind the frozen twelve-case hosted coaching comparison."""

import argparse
import csv
import hashlib
import io
import json
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

import chess_native_response
import preview_chess_native_prompts
import run_hosted_chess_native_pilot as hosted_pilot


CONFIGURATIONS = (
    {"id": "sol-high", "model": "gpt-5.6-sol", "reasoningEffort": "high"},
    {"id": "luna-high", "model": "gpt-5.6-luna", "reasoningEffort": "high"},
)
MAXIMUM_OUTPUT_TOKENS = 2048
PROMPT_VERSION = "tutor-v6"
RUBRIC_FIELDS = (
    "reviewID",
    "factualCorrectness",
    "currentStage",
    "singlePurpose",
    "discoveryCoaching",
    "childLanguage",
    "uiAlignment",
    "severe",
    "notes",
)
_SHA256 = re.compile(r"[0-9a-f]{64}\Z")


def _sha256(data):
    return hashlib.sha256(data).hexdigest()


def _file_sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _canonical_json_bytes(value):
    return (
        json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    ).encode("utf-8")


def _jsonl_bytes(values):
    return b"".join(
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        .encode("utf-8")
        + b"\n"
        for value in values
    )


def _validated_hash(value, name):
    if not isinstance(value, str) or _SHA256.fullmatch(value) is None:
        raise ValueError(f"{name} must be a lowercase SHA-256")
    return value


def _load_source(
    *,
    source_dir,
    system_prompt_path,
    case_ids,
    expected_source_manifest_sha256,
    expected_examples_jsonl_sha256,
):
    case_ids = tuple(case_ids)
    source_dir = Path(source_dir)
    expected_source_manifest_sha256 = _validated_hash(
        expected_source_manifest_sha256, "Expected source manifest hash"
    )
    expected_examples_jsonl_sha256 = _validated_hash(
        expected_examples_jsonl_sha256, "Expected examples JSONL hash"
    )
    manifest_path = source_dir / "preview-manifest.json"
    examples_path = source_dir / "examples.jsonl"
    if _file_sha256(manifest_path) != expected_source_manifest_sha256:
        raise ValueError("Hosted comparison source manifest hash does not match")
    if _file_sha256(examples_path) != expected_examples_jsonl_sha256:
        raise ValueError("Hosted comparison examples JSONL hash does not match")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("examplesJSONLSHA256") != expected_examples_jsonl_sha256:
        raise ValueError("Hosted comparison source manifest has a different audit hash")
    source = preview_chess_native_prompts._load_and_validate_source(
        source_dir, system_prompt_path, example_ids=case_ids
    )
    if tuple(prompt["id"] for prompt in source["prompts"]) != case_ids:
        raise ValueError("Hosted comparison source order does not match requested cases")
    return source


def _preflight(source):
    cells = []
    for prompt in source["prompts"]:
        contract = chess_native_response.ChessNativeResponseContract.from_markdown(
            prompt["userPrompt"]
        )
        schema = contract.json_schema()
        json.dumps(schema, sort_keys=True)
        cells.append((prompt, contract, schema))
    return cells


def run_broad_comparison(
    *,
    source_dir,
    system_prompt_path,
    destination,
    client,
    case_ids,
    expected_source_manifest_sha256,
    expected_examples_jsonl_sha256,
    timeout=120,
    review_seed=None,
):
    destination = Path(destination)
    if os.path.lexists(destination):
        raise ValueError(f"Refusing to overwrite existing comparison: {destination}")
    source = _load_source(
        source_dir=source_dir,
        system_prompt_path=system_prompt_path,
        case_ids=case_ids,
        expected_source_manifest_sha256=expected_source_manifest_sha256,
        expected_examples_jsonl_sha256=expected_examples_jsonl_sha256,
    )
    cells = _preflight(source)
    records = []
    for configuration in CONFIGURATIONS:
        for prompt, _contract, _schema in cells:
            record = hosted_pilot._complete_prompt(
                prompt,
                source,
                client,
                timeout,
                model=configuration["model"],
                reasoning_effort=configuration["reasoningEffort"],
                maximum_output_tokens=MAXIMUM_OUTPUT_TOKENS,
            )
            record["schemaVersion"] = (
                "model-coaching-chess-native-hosted-broad-record.v1"
            )
            record["configurationID"] = configuration["id"]
            record["requestedModel"] = configuration["model"]
            record["reasoningEffort"] = configuration["reasoningEffort"]
            records.append(record)
    return _write_output(
        destination=destination,
        source_dir=Path(source_dir).resolve(),
        source=source,
        case_ids=tuple(case_ids),
        source_manifest_sha256=expected_source_manifest_sha256,
        examples_jsonl_sha256=expected_examples_jsonl_sha256,
        records=records,
        review_seed=os.urandom(32) if review_seed is None else review_seed,
    )


def _review_artifacts(source, records, manifest_records, review_seed):
    if not isinstance(review_seed, bytes) or len(review_seed) < 16:
        raise ValueError("Review seed must contain at least 16 bytes")
    record_bindings = {
        (entry["configurationID"], entry["caseID"]): entry
        for entry in manifest_records
    }
    shuffled = []
    for record in records:
        identity = f"{record['configurationID']}\0{record['caseID']}".encode("utf-8")
        order_key = hashlib.sha256(review_seed + b"\0order\0" + identity).digest()
        review_id = "review-" + hashlib.sha256(
            review_seed + b"\0id\0" + identity
        ).hexdigest()[:20]
        shuffled.append((order_key, review_id, record))
    shuffled.sort(key=lambda item: item[0])

    packet = []
    key_entries = []
    for _order, review_id, record in shuffled:
        packet.append(
            {
                "reviewID": review_id,
                "caseID": record["caseID"],
                "userPrompt": next(
                    prompt["userPrompt"]
                    for prompt in source["prompts"]
                    if prompt["id"] == record["caseID"]
                ),
                "turn": record["parsedTurn"],
                "validation": record["validation"],
            }
        )
        binding = record_bindings[(record["configurationID"], record["caseID"])]
        key_entries.append(
            {
                "reviewID": review_id,
                "configurationID": record["configurationID"],
                "requestedModel": record["requestedModel"],
                "reasoningEffort": record["reasoningEffort"],
                "caseID": record["caseID"],
                "recordPath": binding["path"],
                "recordSHA256": binding["sha256"],
            }
        )

    packet_bytes = _jsonl_bytes(packet)
    public_text = packet_bytes.decode("utf-8")
    if hosted_pilot._TRACE_MARKER.search(public_text):
        raise ValueError("Refusing to persist a public packet containing a trace marker")
    for identity in (
        "sol-high",
        "luna-high",
        "gpt-5.6-sol",
        "gpt-5.6-luna",
        "providerResponseID",
        "providerModel",
    ):
        if identity in public_text:
            raise ValueError("Refusing to persist model identity in the public packet")

    key = {
        "schemaVersion": "model-coaching-chess-native-broad-review-key.v1",
        "entries": key_entries,
    }
    rubric_text = io.StringIO(newline="")
    writer = csv.DictWriter(rubric_text, fieldnames=RUBRIC_FIELDS, lineterminator="\n")
    writer.writeheader()
    for item in packet:
        writer.writerow({field: item["reviewID"] if field == "reviewID" else "" for field in RUBRIC_FIELDS})
    return packet_bytes, _canonical_json_bytes(key), rubric_text.getvalue().encode("utf-8")


def _write_output(
    *,
    destination,
    source_dir,
    source,
    case_ids,
    source_manifest_sha256,
    examples_jsonl_sha256,
    records,
    review_seed,
):
    destination = Path(destination)
    if os.path.lexists(destination):
        raise ValueError(f"Refusing to overwrite existing comparison: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(
        tempfile.mkdtemp(prefix=f".{destination.name}.tmp-", dir=str(destination.parent))
    )
    try:
        records_dir = temporary / "records"
        review_dir = temporary / "review"
        records_dir.mkdir()
        review_dir.mkdir()
        manifest_records = []
        for record in records:
            record_bytes = _canonical_json_bytes(record)
            relative = Path("records") / (
                f"{record['configurationID']}--{record['caseID']}.json"
            )
            hosted_pilot._write_fsynced(temporary / relative, record_bytes)
            manifest_records.append(
                {
                    "configurationID": record["configurationID"],
                    "caseID": record["caseID"],
                    "path": relative.as_posix(),
                    "sha256": _sha256(record_bytes),
                }
            )
        hosted_pilot._fsync_directory(records_dir)

        packet_bytes, key_bytes, rubric_bytes = _review_artifacts(
            source, records, manifest_records, review_seed
        )
        review_files = {
            "review-packet.jsonl": packet_bytes,
            "review-key.json": key_bytes,
            "rubric.csv": rubric_bytes,
        }
        for name, data in review_files.items():
            hosted_pilot._write_fsynced(review_dir / name, data)
        hosted_pilot._fsync_directory(review_dir)

        valid_count = sum(record["validation"]["valid"] for record in records)
        manifest = {
            "schemaVersion": "model-coaching-chess-native-hosted-broad.v1",
            "promptVersion": PROMPT_VERSION,
            "caseIDs": list(case_ids),
            "configurations": [dict(value) for value in CONFIGURATIONS],
            "sourceDirectory": str(source_dir),
            "sourceManifestSHA256": source_manifest_sha256,
            "examplesJSONLSHA256": examples_jsonl_sha256,
            "systemPromptSHA256": source["systemPromptSHA256"],
            "provider": {
                "api": "openai-responses-v1",
                "maximumOutputTokens": MAXIMUM_OUTPUT_TOKENS,
                "store": False,
                "retries": 0,
                "repairs": 0,
            },
            "records": manifest_records,
            "review": {
                name: {"path": f"review/{name}", "sha256": _sha256(data)}
                for name, data in review_files.items()
            },
            "summary": {
                "recordCount": len(records),
                "completionAttempts": sum(
                    record["completionAttempts"] for record in records
                ),
                "validCount": valid_count,
                "invalidCount": len(records) - valid_count,
                "providerErrorCount": sum(
                    record["generationStatus"] == "generationError"
                    for record in records
                ),
            },
        }
        manifest_bytes = _canonical_json_bytes(manifest)
        hosted_pilot._write_fsynced(temporary / "run-manifest.json", manifest_bytes)
        hosted_pilot._fsync_directory(temporary)
        if os.path.lexists(destination):
            raise ValueError(f"Refusing to overwrite existing comparison: {destination}")
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
    manifest = run_broad_comparison(
        source_dir=arguments.source,
        system_prompt_path=arguments.system_prompt,
        destination=arguments.destination,
        client=client,
        case_ids=tuple(arguments.case_ids),
        expected_source_manifest_sha256=arguments.source_manifest_sha256,
        expected_examples_jsonl_sha256=arguments.examples_jsonl_sha256,
        timeout=arguments.timeout,
    )
    print(json.dumps(manifest["summary"], sort_keys=True))
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument(
        "--system-prompt",
        type=Path,
        default=hosted_pilot.TOOLS_DIR / "prompts" / "tutor-v6.md",
    )
    parser.add_argument("--destination", required=True, type=Path)
    parser.add_argument("--source-manifest-sha256", required=True)
    parser.add_argument("--examples-jsonl-sha256", required=True)
    parser.add_argument("--case-id", action="append", dest="case_ids", required=True)
    parser.add_argument("--timeout", type=int, default=120)
    arguments = parser.parse_args(argv)
    try:
        return _execute(arguments)
    except (OSError, RuntimeError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
