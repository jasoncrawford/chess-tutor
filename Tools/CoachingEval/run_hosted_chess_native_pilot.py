#!/usr/bin/env python3
"""Run the frozen tutor-v6 packet once against a hosted flagship model."""

import argparse
import hashlib
import json
import math
import os
import re
import shutil
import sys
import tempfile
import time
from pathlib import Path

import chess_native_response
import preview_chess_native_prompts


TOOLS_DIR = Path(__file__).resolve().parent
REPOSITORY_ROOT = TOOLS_DIR.parents[1]
ARTIFACT_ROOT = REPOSITORY_ROOT / ".coaching-eval"

MODEL = "gpt-5.6-sol"
REASONING_EFFORT = "high"
OPENAI_BASE_URL = "https://api.openai.com"
PROMPT_VERSION = "tutor-v6"
MAXIMUM_OUTPUT_TOKENS = 2048
EXAMPLE_IDS = (
    "01-quiet-help",
    "02-attacked-piece",
    "03-selected-piece",
    "04-replaced-tentative-move",
    "05-tactical-reply",
    "06-inspected-reply",
    "07-answering-check",
    "08-long-history",
)
SOURCE_MANIFEST_SHA256 = (
    "80eb1b8f5b57ea9fc04609909922ed1377e4dd702feb0e178a070aba4d3e15c7"
)
EXAMPLES_JSONL_SHA256 = (
    "8d9d28d904d060da791747083222c74a3ae29c87ec594792916f1dced757c75f"
)
SYSTEM_PROMPT_SHA256 = (
    "0f434c5a7b4889442fc74f5846037d96a2332e479809e68790ee6dcebc1a6051"
)

_TRACE_MARKER = re.compile(r"<\s*/?\s*think\b|reasoning_content", re.IGNORECASE)
_MAX_METRIC_TOKENS = 1_000_000
_MAX_METRIC_MILLISECONDS = 86_400_000.0


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


def _load_json(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError) as error:
        raise ValueError(f"Cannot read JSON from {path}") from error


def _load_frozen_source(source_dir, system_prompt_path):
    source_dir = Path(source_dir)
    manifest_path = source_dir / "preview-manifest.json"
    if _file_sha256(manifest_path) != SOURCE_MANIFEST_SHA256:
        raise ValueError("Hosted pilot requires the exact frozen source manifest")
    manifest = _load_json(manifest_path)
    if manifest.get("exampleIDs") != list(EXAMPLE_IDS):
        raise ValueError("Hosted pilot requires the exact eight source IDs in order")
    if manifest.get("examplesJSONLSHA256") != EXAMPLES_JSONL_SHA256:
        raise ValueError("Frozen source manifest has an unexpected audit inventory hash")
    if _file_sha256(source_dir / "examples.jsonl") != EXAMPLES_JSONL_SHA256:
        raise ValueError("Frozen source audit inventory hash does not match")

    source = preview_chess_native_prompts._load_and_validate_source(
        source_dir, system_prompt_path
    )
    if source["systemPromptSHA256"] != SYSTEM_PROMPT_SHA256:
        raise ValueError("Hosted pilot requires the exact tutor-v6 system prompt")
    if tuple(prompt["id"] for prompt in source["prompts"]) != EXAMPLE_IDS:
        raise ValueError("Hosted pilot requires the exact eight source IDs in order")
    return source


def _response_schema(contract):
    square_focus = {
        "type": "object",
        "properties": {
            "type": {"type": "string", "enum": ["square"]},
            "square": {"type": "string", "pattern": "^[a-h][1-8]$"},
        },
        "required": ["type", "square"],
        "additionalProperties": False,
    }
    focus_variants = [square_focus]
    for origin, destination in contract.allowable_moves:
        focus_variants.append(
            {
                "type": "object",
                "properties": {
                    "type": {"type": "string", "enum": ["move"]},
                    "from": {"type": "string", "enum": [origin]},
                    "to": {"type": "string", "enum": [destination]},
                },
                "required": ["type", "from", "to"],
                "additionalProperties": False,
            }
        )
    return {
        "type": "object",
        "properties": {
            "message": {"type": "string", "minLength": 1, "maxLength": 256},
            "actions": {
                "type": "array",
                "items": {"type": "string", "enum": list(contract.actions)},
                "maxItems": 3,
            },
            "focus": {
                "type": "array",
                "items": {"anyOf": focus_variants},
                "maxItems": 4,
            },
        },
        "required": ["message", "actions", "focus"],
        "additionalProperties": False,
    }


def _bounded_int(value):
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        return 0
    return min(value, _MAX_METRIC_TOKENS)


def _bounded_float(value):
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        return 0.0
    value = float(value)
    if not math.isfinite(value) or value < 0:
        return 0.0
    return min(value, _MAX_METRIC_MILLISECONDS)


def _metrics(response, latency_milliseconds):
    usage = response.get("usage") if isinstance(response, dict) else None
    usage = usage if isinstance(usage, dict) else {}
    return {
        "inputTokens": _bounded_int(usage.get("input_tokens")),
        "outputTokens": _bounded_int(usage.get("output_tokens")),
        "reasoningTokens": _bounded_int(usage.get("reasoning_tokens")),
        "totalTokens": _bounded_int(usage.get("total_tokens")),
        "latencyMilliseconds": _bounded_float(latency_milliseconds),
    }


def _validation_error_codes(error):
    message = str(error)
    if message.startswith("Duplicate JSON key"):
        return ["response.duplicateJSONKey"]
    if message == "Response is not valid JSON":
        return ["response.invalidJSON"]
    prefix = "Invalid chess-native response: "
    if message.startswith(prefix):
        codes = []
        for issue in message.removeprefix(prefix).split(", "):
            code = issue.split(":", 1)[0]
            if re.fullmatch(r"[A-Za-z][A-Za-z0-9.]*", code) and code not in codes:
                codes.append(code)
        if codes:
            return codes
    return ["response.invalid"]


def _new_record(prompt, source):
    return {
        "schemaVersion": "model-coaching-chess-native-hosted-record.v1",
        "caseID": prompt["id"],
        "promptVersion": PROMPT_VERSION,
        "generationStatus": "notStarted",
        "completionAttempts": 0,
        "requestSHA256": prompt["requestSHA256"],
        "sourceManifestSHA256": SOURCE_MANIFEST_SHA256,
        "systemPromptSHA256": source["systemPromptSHA256"],
        "userPromptSHA256": prompt["userPromptSHA256"],
        "providerResponseID": "",
        "providerModel": "",
        "finalContent": "",
        "finalContentSHA256": _sha256(b""),
        "finalContentUTF8Bytes": 0,
        "parsedTurn": None,
        "validation": {"valid": False, "errors": ["attempt.notRun"]},
        "errors": [],
        "metrics": {
            "inputTokens": 0,
            "outputTokens": 0,
            "reasoningTokens": 0,
            "totalTokens": 0,
            "latencyMilliseconds": 0.0,
        },
    }


def _complete_prompt(prompt, source, client, timeout):
    contract = chess_native_response.ChessNativeResponseContract.from_markdown(
        prompt["userPrompt"]
    )
    record = _new_record(prompt, source)
    response = None
    started = time.monotonic()
    try:
        record["completionAttempts"] = 1
        response = client.complete(
            system_prompt=source["systemPrompt"],
            user_prompt=prompt["userPrompt"],
            schema=_response_schema(contract),
            model=MODEL,
            reasoning_effort=REASONING_EFFORT,
            maximum_output_tokens=MAXIMUM_OUTPUT_TOKENS,
            timeout=timeout,
        )
        response_id = response.get("id") if isinstance(response, dict) else None
        provider_model = response.get("model") if isinstance(response, dict) else None
        content = response.get("output_text") if isinstance(response, dict) else None
        if not isinstance(response_id, str) or not response_id:
            raise ValueError("Hosted provider response has no bounded ID")
        if not isinstance(provider_model, str) or not provider_model:
            raise ValueError("Hosted provider response has no model ID")
        if not isinstance(content, str) or not content:
            raise ValueError("Hosted provider response has no final text")
        record["providerResponseID"] = response_id[:256]
        record["providerModel"] = provider_model[:256]
        if _TRACE_MARKER.search(content):
            record["generationStatus"] = "invalid"
            record["validation"] = {
                "valid": False,
                "errors": ["response.traceMarker"],
            }
            record["errors"] = [{
                "kind": "invalidResponse",
                "message": "Response contained a prohibited trace marker.",
            }]
        else:
            content_bytes = content.encode("utf-8")
            record["finalContent"] = content
            record["finalContentSHA256"] = _sha256(content_bytes)
            record["finalContentUTF8Bytes"] = len(content_bytes)
            try:
                record["parsedTurn"] = contract.parse_and_validate(content)
            except ValueError as error:
                record["generationStatus"] = "invalid"
                record["validation"] = {
                    "valid": False,
                    "errors": _validation_error_codes(error),
                }
                record["errors"] = [{
                    "kind": "invalidResponse",
                    "message": "Response failed strict validation.",
                }]
            else:
                record["generationStatus"] = "valid"
                record["validation"] = {"valid": True, "errors": []}
    except (OSError, RuntimeError, ValueError):
        record["generationStatus"] = "generationError"
        record["validation"] = {
            "valid": False,
            "errors": ["transport.generationError"],
        }
        record["errors"] = [{
            "kind": "generationError",
            "message": "Hosted provider generation failed.",
        }]
    finally:
        record["metrics"] = _metrics(
            response, (time.monotonic() - started) * 1000
        )
    return record


def run_hosted_pilot(
    *, source_dir, system_prompt_path, destination, client, timeout=120
):
    destination = Path(destination)
    if os.path.lexists(destination):
        raise ValueError(f"Refusing to overwrite existing pilot directory: {destination}")
    source = _load_frozen_source(source_dir, system_prompt_path)
    records = [
        _complete_prompt(prompt, source, client, timeout)
        for prompt in source["prompts"]
    ]
    return _write_output(
        destination=destination,
        source_dir=Path(source_dir).resolve(),
        source=source,
        records=records,
    )


def _review_markdown(source_dir, records):
    lines = [
        "# Chess-native hosted-model pilot review",
        "",
        "This review contains only final trace-free candidates.",
        "",
    ]
    system_path = (Path(source_dir) / "system-prompt.md").resolve().as_posix()
    for record in records:
        identifier = record["caseID"]
        user_path = (
            Path(source_dir) / "user-prompts" / f"{identifier}.md"
        ).resolve().as_posix()
        lines.extend((
            f"## {identifier}",
            "",
            f"- System: [system-prompt.md]({system_path})",
            f"- User: [{identifier}.md]({user_path})",
            f"- Validation: {record['generationStatus']}",
            "",
            "### Response",
            "",
        ))
        if record["finalContent"]:
            lines.extend("    " + line for line in record["finalContent"].splitlines())
        else:
            lines.append("_No safe final content was persisted._")
        lines.append("")
    return "\n".join(lines)


def _write_fsynced(path, content):
    mode = "wb" if isinstance(content, bytes) else "w"
    arguments = {} if mode == "wb" else {"encoding": "utf-8"}
    with Path(path).open(mode, **arguments) as destination:
        destination.write(content)
        destination.flush()
        os.fsync(destination.fileno())


def _fsync_directory(path):
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _write_output(*, destination, source_dir, source, records):
    destination = Path(destination)
    if os.path.lexists(destination):
        raise ValueError(f"Refusing to overwrite existing pilot directory: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(
        tempfile.mkdtemp(prefix=f".{destination.name}.tmp-", dir=str(destination.parent))
    )
    try:
        records_dir = temporary / "records"
        records_dir.mkdir()
        manifest_records = []
        for record in records:
            record_bytes = _canonical_json_bytes(record)
            relative_path = Path("records") / f"{record['caseID']}.json"
            _write_fsynced(temporary / relative_path, record_bytes)
            manifest_records.append({
                "caseID": record["caseID"],
                "path": relative_path.as_posix(),
                "sha256": _sha256(record_bytes),
            })
        _fsync_directory(records_dir)

        review = _review_markdown(source_dir, records)
        if _TRACE_MARKER.search(review):
            raise ValueError("Refusing to persist a review containing a trace marker")
        review_bytes = review.encode("utf-8")
        _write_fsynced(temporary / "review.md", review_bytes)

        valid_count = sum(record["validation"]["valid"] for record in records)
        provider_error_count = sum(
            record["generationStatus"] == "generationError" for record in records
        )
        manifest = {
            "schemaVersion": "model-coaching-chess-native-hosted-pilot.v1",
            "promptVersion": PROMPT_VERSION,
            "exampleIDs": list(EXAMPLE_IDS),
            "sourceDirectory": str(Path(source_dir).resolve()),
            "sourceManifestSHA256": SOURCE_MANIFEST_SHA256,
            "examplesJSONLSHA256": EXAMPLES_JSONL_SHA256,
            "systemPromptSHA256": source["systemPromptSHA256"],
            "provider": {
                "api": "openai-responses-v1",
                "model": MODEL,
                "reasoningEffort": REASONING_EFFORT,
                "maximumOutputTokens": MAXIMUM_OUTPUT_TOKENS,
            },
            "records": manifest_records,
            "review": {"path": "review.md", "sha256": _sha256(review_bytes)},
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
        manifest_bytes = _canonical_json_bytes(manifest)
        if _TRACE_MARKER.search(manifest_bytes.decode("utf-8")):
            raise ValueError("Refusing to persist a manifest containing a trace marker")
        _write_fsynced(temporary / "run-manifest.json", manifest_bytes)
        _fsync_directory(temporary)
        if os.path.lexists(destination):
            raise ValueError(f"Refusing to overwrite existing pilot directory: {destination}")
        os.rename(temporary, destination)
        _fsync_directory(destination.parent)
        return manifest
    except Exception:
        shutil.rmtree(temporary, ignore_errors=True)
        raise


def _api_key_from_environment(environment):
    value = environment.get("OPENAI_API_KEY") if isinstance(environment, dict) else None
    if not isinstance(value, str) or not value or value.strip() != value:
        raise ValueError(
            "OPENAI_API_KEY is not configured; set it locally without committing it"
        )
    return value


def _execute(arguments):
    import openai_responses

    client = openai_responses.OpenAIResponsesClient(
        OPENAI_BASE_URL,
        api_key=_api_key_from_environment(dict(os.environ)),
    )
    manifest = run_hosted_pilot(
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
        default=ARTIFACT_ROOT / "chess-native-prompt-preview" / "swift-export-v2",
    )
    parser.add_argument(
        "--system-prompt",
        type=Path,
        default=TOOLS_DIR / "prompts" / "tutor-v6.md",
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
