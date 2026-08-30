#!/usr/bin/env python3
"""Run the one immutable, trace-free tutor-v6 SmolLM3 pilot."""

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
from dataclasses import dataclass
from pathlib import Path

import chess_native_response
import llama_server
import preview_chess_native_prompts
import runtime_provenance


TOOLS_DIR = Path(__file__).resolve().parent
REPOSITORY_ROOT = TOOLS_DIR.parents[1]
ARTIFACT_ROOT = REPOSITORY_ROOT / ".coaching-eval"

@dataclass(frozen=True)
class ModelCandidate:
    identifier: str
    display_name: str
    filename: str
    artifact_sha256: str
    artifact_bytes: int
    manifest_sha256: str
    resolved_revision: str


SMOLLM3_CANDIDATE = ModelCandidate(
    identifier="smollm3-3b-q4_k_m",
    display_name="SmolLM3 3B",
    filename="SmolLM3-Q4_K_M.gguf",
    artifact_sha256=(
        "8334b850b7bd46238c16b0c550df2138f0889bf433809008cc17a8b05761863e"
    ),
    artifact_bytes=1915305312,
    manifest_sha256=(
        "3037744008c5c6c656294b7998c78727dde2adfcf89bd186dee85116ef4c8bcf"
    ),
    resolved_revision="4965cb60b150737b68a0408c36aeefb65078f894",
)
QWEN3_1_7B_CANDIDATE = ModelCandidate(
    identifier="qwen3-1.7b-q4_k_m",
    display_name="Qwen3 1.7B",
    filename="Qwen3-1.7B-Q4_K_M.gguf",
    artifact_sha256=(
        "d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5"
    ),
    artifact_bytes=1282439264,
    manifest_sha256=(
        "41861a9d9ce876085d78994a2c099e0b7c8dce0d024a747d938c20e87ce6bb73"
    ),
    resolved_revision="daeb8e2d528a760970442092f6bf1e55c3b659eb",
)
MODEL_CANDIDATES = {
    candidate.identifier: candidate
    for candidate in (SMOLLM3_CANDIDATE, QWEN3_1_7B_CANDIDATE)
}

MODEL_ID = SMOLLM3_CANDIDATE.identifier
PROMPT_VERSION = "tutor-v6"
MODE = "bounded"
SEED = 1103
MAXIMUM_OUTPUT_TOKENS = 512
TEMPERATURE = 0.2
TOP_P = 0.95
PROMPT_BUDGET_TOKENS = 2500
CONTEXT_TOKENS = 8192
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
MODEL_ARTIFACT_SHA256 = SMOLLM3_CANDIDATE.artifact_sha256
MODEL_ARTIFACT_BYTES = SMOLLM3_CANDIDATE.artifact_bytes
MODEL_MANIFEST_SHA256 = SMOLLM3_CANDIDATE.manifest_sha256
MODEL_RESOLVED_REVISION = SMOLLM3_CANDIDATE.resolved_revision
RUNTIME_SOURCE_TAG = "b10516"
RUNTIME_SOURCE_COMMIT = "b95502ba9aa0eb73a2f4fc8878d7fbe6a847a0b9"
RUNTIME_BINARY_SHA256 = (
    "fa65f946a434fcb34de87520ab76a3f2d576f97ad9f5a81b3a6e4201daff137e"
)
RUNTIME_MANIFEST_SHA256 = (
    "27a5ebb2a0e3beee2c407e58173f1397ec183970cb721f0a5bf8be871340205b"
)

_PROVENANCE_FIELDS = frozenset(
    (
        "modelID",
        "modelArtifactSHA256",
        "modelArtifactBytes",
        "modelArtifactManifestSHA256",
        "modelResolvedRevision",
        "runtimeSourceTag",
        "runtimeSourceCommit",
        "runtimeBinarySHA256",
        "runtimeManifestSHA256",
        "runtimeVersion",
        "serverCommand",
        "pilotCommand",
    )
)
_TRACE_MARKER = re.compile(r"<\s*/?\s*think\b", re.IGNORECASE)
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
        raise ValueError("Chess-native pilot requires the exact frozen source manifest")

    manifest = _load_json(manifest_path)
    if manifest.get("exampleIDs") != list(EXAMPLE_IDS):
        raise ValueError("Chess-native pilot requires the exact eight source IDs in order")
    if manifest.get("examplesJSONLSHA256") != EXAMPLES_JSONL_SHA256:
        raise ValueError("Frozen source manifest has an unexpected audit inventory hash")
    if _file_sha256(source_dir / "examples.jsonl") != EXAMPLES_JSONL_SHA256:
        raise ValueError("Frozen source audit inventory hash does not match")

    source = preview_chess_native_prompts._load_and_validate_source(
        source_dir, system_prompt_path
    )
    if source["systemPromptSHA256"] != SYSTEM_PROMPT_SHA256:
        raise ValueError("Chess-native pilot requires the exact tutor-v6 system prompt")
    if tuple(prompt["id"] for prompt in source["prompts"]) != EXAMPLE_IDS:
        raise ValueError("Chess-native pilot requires the exact eight source IDs in order")
    return source


def _validate_command(value, *, field):
    if (
        not isinstance(value, list)
        or not value
        or len(value) > 64
        or any(not isinstance(item, str) or not item or len(item) > 4096 for item in value)
    ):
        raise ValueError(f"Pilot provenance has an invalid {field}")


def _default_candidate():
    return ModelCandidate(
        identifier=MODEL_ID,
        display_name=SMOLLM3_CANDIDATE.display_name,
        filename=SMOLLM3_CANDIDATE.filename,
        artifact_sha256=MODEL_ARTIFACT_SHA256,
        artifact_bytes=MODEL_ARTIFACT_BYTES,
        manifest_sha256=MODEL_MANIFEST_SHA256,
        resolved_revision=MODEL_RESOLVED_REVISION,
    )


def _validate_provenance(provenance, *, candidate=None):
    candidate = candidate or _default_candidate()
    if not isinstance(provenance, dict) or set(provenance) != _PROVENANCE_FIELDS:
        raise ValueError("Pilot provenance must contain only the exact bounded fields")
    expected = {
        "modelID": candidate.identifier,
        "modelArtifactSHA256": candidate.artifact_sha256,
        "modelArtifactBytes": candidate.artifact_bytes,
        "modelArtifactManifestSHA256": candidate.manifest_sha256,
        "modelResolvedRevision": candidate.resolved_revision,
        "runtimeSourceTag": RUNTIME_SOURCE_TAG,
        "runtimeSourceCommit": RUNTIME_SOURCE_COMMIT,
        "runtimeBinarySHA256": RUNTIME_BINARY_SHA256,
        "runtimeManifestSHA256": RUNTIME_MANIFEST_SHA256,
    }
    for field, value in expected.items():
        if provenance.get(field) != value:
            raise ValueError(f"Pilot provenance does not match pinned {field}")
    runtime_version = provenance.get("runtimeVersion")
    if (
        not isinstance(runtime_version, str)
        or len(runtime_version) > 1024
        or "build 10516" not in runtime_version
        or "b95502ba9a" not in runtime_version
    ):
        raise ValueError("Pilot provenance does not match the pinned runtime version")
    _validate_command(provenance.get("serverCommand"), field="serverCommand")
    _validate_command(provenance.get("pilotCommand"), field="pilotCommand")
    return dict(provenance)


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


def _response_metrics(response, *, latency_milliseconds):
    usage = response.get("usage") if isinstance(response, dict) else None
    timings = response.get("timings") if isinstance(response, dict) else None
    usage = usage if isinstance(usage, dict) else {}
    timings = timings if isinstance(timings, dict) else {}
    return {
        "promptTokens": _bounded_int(usage.get("prompt_tokens")),
        "outputTokens": _bounded_int(usage.get("completion_tokens")),
        "promptMilliseconds": _bounded_float(timings.get("prompt_ms")),
        "generationMilliseconds": _bounded_float(
            timings.get("predicted_ms", timings.get("generation_ms"))
        ),
        "latencyMilliseconds": _bounded_float(latency_milliseconds),
    }


def _final_response_content(response):
    if not isinstance(response, dict):
        raise ValueError("Provider response has no final content")
    choices = response.get("choices")
    if not isinstance(choices, list) or not choices or not isinstance(choices[0], dict):
        raise ValueError("Provider response has no final content")
    message = choices[0].get("message")
    if not isinstance(message, dict) or not isinstance(message.get("content"), str):
        raise ValueError("Provider response has no final content")
    return message["content"]


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


def _provider_error(error):
    category = getattr(error, "category", None)
    if category == "contextOverflow":
        return {
            "kind": "contextOverflow",
            "message": "Provider request exceeded the context window.",
        }
    if isinstance(error, llama_server.LlamaServerTimeout):
        return {
            "kind": "generationError",
            "message": "Provider response timed out.",
        }
    return {
        "kind": "generationError",
        "message": "Provider generation failed.",
    }


class _PilotRunner:
    def __init__(self, *, client, provenance, timeout, candidate=None):
        if not isinstance(timeout, int) or isinstance(timeout, bool) or timeout <= 0:
            raise ValueError("Pilot timeout must be a positive integer")
        self.candidate = candidate or _default_candidate()
        self.client = client
        self.provenance = _validate_provenance(
            provenance, candidate=self.candidate
        )
        self.timeout = timeout

    def run(self, *, source, source_dir, destination):
        cells = self._preflight(source)
        over_budget = [
            cell for cell in cells if cell["renderedPromptTokens"] > PROMPT_BUDGET_TOKENS
        ]
        if over_budget:
            details = ", ".join(
                f"{cell['id']}={cell['renderedPromptTokens']}" for cell in over_budget
            )
            raise ValueError(
                f"Prompt token count exceeds the 2,500-token budget: {details}"
            )

        records = [self._complete_cell(cell, source) for cell in cells]
        return _write_output(
            destination=destination,
            source_dir=source_dir,
            source=source,
            records=records,
            provenance=self.provenance,
            candidate=self.candidate,
        )

    def _preflight(self, source):
        cells = []
        for prompt in source["prompts"]:
            contract = chess_native_response.ChessNativeResponseContract.from_markdown(
                prompt["userPrompt"]
            )
            grammar = contract.grammar(enable_thinking=True)
            rendered_prompt = self.client.render_prompt(
                system_prompt=source["systemPrompt"],
                user_content=prompt["userPrompt"],
                enable_thinking=True,
                timeout=self.timeout,
            )
            if not isinstance(rendered_prompt, str) or not rendered_prompt:
                raise ValueError(f"Template renderer returned no prompt for {prompt['id']}")
            token_count = self.client.token_count(
                rendered_prompt,
                timeout=self.timeout,
            )
            if (
                not isinstance(token_count, int)
                or isinstance(token_count, bool)
                or token_count <= 0
            ):
                raise ValueError(f"Tokenizer returned an invalid count for {prompt['id']}")
            cells.append(
                {
                    "id": prompt["id"],
                    "requestSHA256": prompt["requestSHA256"],
                    "userPrompt": prompt["userPrompt"],
                    "userPromptSHA256": prompt["userPromptSHA256"],
                    "contract": contract,
                    "grammar": grammar,
                    "renderedPrompt": rendered_prompt,
                    "renderedPromptTokens": token_count,
                }
            )
        return cells

    def _complete_cell(self, cell, source):
        rendered_bytes = cell["renderedPrompt"].encode("utf-8")
        grammar_bytes = cell["grammar"].encode("utf-8")
        record = {
            "schemaVersion": "model-coaching-chess-native-pilot-record.v1",
            "caseID": cell["id"],
            "promptVersion": PROMPT_VERSION,
            "mode": MODE,
            "seed": SEED,
            "generationStatus": "notStarted",
            "completionAttempts": 0,
            "requestSHA256": cell["requestSHA256"],
            "sourceManifestSHA256": SOURCE_MANIFEST_SHA256,
            "systemPromptSHA256": source["systemPromptSHA256"],
            "userPromptSHA256": cell["userPromptSHA256"],
            "renderedPromptSHA256": _sha256(rendered_bytes),
            "renderedPromptUTF8Bytes": len(rendered_bytes),
            "renderedPromptTokens": cell["renderedPromptTokens"],
            "grammarSHA256": _sha256(grammar_bytes),
            "grammarUTF8Bytes": len(grammar_bytes),
            "finalContent": "",
            "finalContentSHA256": _sha256(b""),
            "finalContentUTF8Bytes": 0,
            "parsedTurn": None,
            "validation": {"valid": False, "errors": ["attempt.notRun"]},
            "errors": [],
            "metrics": {
                "promptTokens": 0,
                "outputTokens": 0,
                "promptMilliseconds": 0.0,
                "generationMilliseconds": 0.0,
                "latencyMilliseconds": 0.0,
            },
            "provenance": dict(self.provenance),
        }
        response = None
        started = time.monotonic()
        try:
            record["completionAttempts"] = 1
            response = self.client.complete_rendered(
                prompt=cell["renderedPrompt"],
                grammar=cell["grammar"],
                seed=SEED,
                maximum_output_tokens=MAXIMUM_OUTPUT_TOKENS,
                temperature=TEMPERATURE,
                top_p=TOP_P,
                timeout=self.timeout,
            )
            raw_content = _final_response_content(response)
            try:
                final_content = cell["contract"].strip_thinking(
                    raw_content, enable_thinking=True
                )
            except ValueError:
                record["generationStatus"] = "invalid"
                record["validation"] = {
                    "valid": False,
                    "errors": ["response.invalidThinkingEnvelope"],
                }
                record["errors"] = [
                    {
                        "kind": "invalidResponse",
                        "message": "Response did not contain one safe bounded envelope.",
                    }
                ]
            else:
                final_bytes = final_content.encode("utf-8")
                record["finalContent"] = final_content
                record["finalContentSHA256"] = _sha256(final_bytes)
                record["finalContentUTF8Bytes"] = len(final_bytes)
                try:
                    record["parsedTurn"] = cell["contract"].parse_and_validate(
                        final_content
                    )
                except ValueError as error:
                    record["generationStatus"] = "invalid"
                    record["validation"] = {
                        "valid": False,
                        "errors": _validation_error_codes(error),
                    }
                    record["errors"] = [
                        {
                            "kind": "invalidResponse",
                            "message": "Response failed strict validation.",
                        }
                    ]
                else:
                    record["generationStatus"] = "valid"
                    record["validation"] = {"valid": True, "errors": []}
        except (llama_server.LlamaServerError, OSError, ValueError) as error:
            persisted_error = _provider_error(error)
            record["generationStatus"] = persisted_error["kind"]
            record["validation"] = {
                "valid": False,
                "errors": [f"transport.{persisted_error['kind']}"],
            }
            record["errors"] = [persisted_error]
        finally:
            record["metrics"] = _response_metrics(
                response,
                latency_milliseconds=(time.monotonic() - started) * 1000,
            )
        return record


def run_pilot(
    *,
    source_dir,
    system_prompt_path,
    destination,
    client,
    provenance,
    timeout=120,
    candidate=None,
):
    """Run all eight frozen cells through one injected server/client instance."""
    destination = Path(destination)
    if os.path.lexists(destination):
        raise ValueError(f"Refusing to overwrite existing pilot directory: {destination}")
    source = _load_frozen_source(source_dir, system_prompt_path)
    runner = _PilotRunner(
        client=client,
        provenance=provenance,
        timeout=timeout,
        candidate=candidate,
    )
    return runner.run(
        source=source,
        source_dir=Path(source_dir).resolve(),
        destination=destination,
    )


def _review_markdown(*, source_dir, records, candidate):
    lines = [
        f"# Chess-native {candidate.display_name} pilot review",
        "",
        "This review contains only trace-free model candidates.",
        "",
    ]
    system_path = (Path(source_dir) / "system-prompt.md").resolve().as_posix()
    for record in records:
        identifier = record["caseID"]
        user_path = (
            Path(source_dir) / "user-prompts" / f"{identifier}.md"
        ).resolve().as_posix()
        lines.extend(
            (
                f"## {identifier}",
                "",
                f"- System: [system-prompt.md]({system_path})",
                f"- User: [{identifier}.md]({user_path})",
                f"- Validation: {record['generationStatus']}",
                "",
                "### Response",
                "",
            )
        )
        content = record["finalContent"]
        if content:
            lines.extend("    " + line for line in content.splitlines())
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


def _write_output(
    *, destination, source_dir, source, records, provenance, candidate=None
):
    candidate = candidate or _default_candidate()
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
            manifest_records.append(
                {
                    "caseID": record["caseID"],
                    "path": relative_path.as_posix(),
                    "sha256": _sha256(record_bytes),
                }
            )
        _fsync_directory(records_dir)

        review = _review_markdown(
            source_dir=source_dir, records=records, candidate=candidate
        )
        if _TRACE_MARKER.search(review):
            raise ValueError("Refusing to persist a review containing a thinking trace")
        review_bytes = review.encode("utf-8")
        _write_fsynced(temporary / "review.md", review_bytes)

        valid_count = sum(record["validation"]["valid"] for record in records)
        manifest = {
            "schemaVersion": "model-coaching-chess-native-pilot.v1",
            "promptVersion": PROMPT_VERSION,
            "exampleIDs": list(EXAMPLE_IDS),
            "sourceDirectory": str(Path(source_dir).resolve()),
            "sourceManifestSHA256": SOURCE_MANIFEST_SHA256,
            "examplesJSONLSHA256": EXAMPLES_JSONL_SHA256,
            "systemPromptSHA256": source["systemPromptSHA256"],
            "settings": {
                "mode": MODE,
                "seed": SEED,
                "maximumOutputTokens": MAXIMUM_OUTPUT_TOKENS,
                "temperature": TEMPERATURE,
                "topP": TOP_P,
                "promptBudgetTokens": PROMPT_BUDGET_TOKENS,
            },
            "provenance": dict(provenance),
            "records": manifest_records,
            "review": {
                "path": "review.md",
                "sha256": _sha256(review_bytes),
            },
            "summary": {
                "recordCount": len(records),
                "completionAttempts": sum(
                    record["completionAttempts"] for record in records
                ),
                "validCount": valid_count,
                "invalidCount": len(records) - valid_count,
                "providerErrorCount": sum(
                    record["generationStatus"]
                    in {"generationError", "contextOverflow"}
                    for record in records
                ),
            },
        }
        manifest_bytes = _canonical_json_bytes(manifest)
        if _TRACE_MARKER.search(manifest_bytes.decode("utf-8")):
            raise ValueError("Refusing to persist a manifest containing a thinking trace")
        _write_fsynced(temporary / "run-manifest.json", manifest_bytes)
        _fsync_directory(temporary)

        if os.path.lexists(destination):
            raise ValueError(
                f"Refusing to overwrite existing pilot directory: {destination}"
            )
        os.rename(temporary, destination)
        _fsync_directory(destination.parent)
        return manifest
    except Exception:
        shutil.rmtree(temporary, ignore_errors=True)
        raise


def _pinned_provenance(
    *,
    model_path,
    model_manifest_path,
    server_path,
    runtime_manifest_path,
    candidate=None,
):
    candidate = candidate or _default_candidate()
    model_path = Path(model_path)
    model_manifest_path = Path(model_manifest_path)
    server_path = Path(server_path)
    runtime_manifest_path = Path(runtime_manifest_path)

    artifact_error = (
        f"{candidate.display_name} artifact manifest does not match the frozen pilot"
    )
    if _file_sha256(model_manifest_path) != candidate.manifest_sha256:
        raise ValueError(artifact_error)
    model_manifest = _load_json(model_manifest_path)
    if (
        model_manifest.get("modelID") != candidate.identifier
        or model_manifest.get("filename") != candidate.filename
        or model_path.name != candidate.filename
        or model_manifest.get("bytes") != candidate.artifact_bytes
        or model_manifest.get("sha256") != candidate.artifact_sha256
        or model_manifest.get("resolvedRevision") != candidate.resolved_revision
    ):
        raise ValueError(artifact_error)
    if model_path.stat().st_size != candidate.artifact_bytes:
        raise ValueError(
            f"{candidate.display_name} artifact byte count does not match the frozen pilot"
        )
    if _file_sha256(model_path) != candidate.artifact_sha256:
        raise ValueError(
            f"{candidate.display_name} artifact hash does not match the frozen pilot"
        )

    if _file_sha256(runtime_manifest_path) != RUNTIME_MANIFEST_SHA256:
        raise ValueError("Runtime manifest does not match the frozen pilot")
    runtime = runtime_provenance.verify_runtime(
        server_path,
        TOOLS_DIR / "runtime.json",
        runtime_manifest_path,
    )
    if (
        runtime.get("sourceTag") != RUNTIME_SOURCE_TAG
        or runtime.get("sourceCommit") != RUNTIME_SOURCE_COMMIT
        or runtime.get("binarySHA256") != RUNTIME_BINARY_SHA256
    ):
        raise ValueError("Runtime provenance does not match the frozen pilot")
    return {
        "modelID": candidate.identifier,
        "modelArtifactSHA256": candidate.artifact_sha256,
        "modelArtifactBytes": candidate.artifact_bytes,
        "modelArtifactManifestSHA256": candidate.manifest_sha256,
        "modelResolvedRevision": candidate.resolved_revision,
        "runtimeSourceTag": runtime["sourceTag"],
        "runtimeSourceCommit": runtime["sourceCommit"],
        "runtimeBinarySHA256": runtime["binarySHA256"],
        "runtimeManifestSHA256": RUNTIME_MANIFEST_SHA256,
        "runtimeVersion": runtime["versionOutput"],
    }


def _execute(arguments, *, argv):
    destination = Path(arguments.destination)
    if os.path.lexists(destination):
        raise ValueError(f"Refusing to overwrite existing pilot directory: {destination}")
    _load_frozen_source(arguments.source, arguments.system_prompt)
    candidate = MODEL_CANDIDATES[arguments.candidate]
    model_path = arguments.model or (
        ARTIFACT_ROOT / "models" / candidate.identifier / candidate.filename
    )
    model_manifest_path = arguments.model_manifest or (
        ARTIFACT_ROOT / "models" / candidate.identifier / "artifact-manifest.json"
    )
    provenance = _pinned_provenance(
        candidate=candidate,
        model_path=model_path,
        model_manifest_path=model_manifest_path,
        server_path=arguments.server,
        runtime_manifest_path=arguments.runtime_manifest,
    )
    server = llama_server.LlamaServer(
        arguments.server,
        model_path,
        context_tokens=CONTEXT_TOKENS,
    )
    try:
        server.start(timeout=arguments.timeout)
        provenance["serverCommand"] = list(server.command)
        provenance["pilotCommand"] = [
            sys.executable,
            str(Path(__file__).resolve()),
        ] + list(argv)
        manifest = run_pilot(
            source_dir=arguments.source,
            system_prompt_path=arguments.system_prompt,
            destination=destination,
            client=server,
            provenance=provenance,
            timeout=arguments.timeout,
            candidate=candidate,
        )
    finally:
        server.stop()
    print(json.dumps(manifest["summary"], sort_keys=True))
    return 0


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        type=Path,
        default=(
            ARTIFACT_ROOT / "chess-native-prompt-preview" / "swift-export-v2"
        ),
    )
    parser.add_argument(
        "--system-prompt",
        type=Path,
        default=TOOLS_DIR / "prompts" / "tutor-v6.md",
    )
    parser.add_argument(
        "--server",
        type=Path,
        default=ARTIFACT_ROOT / "runtime" / RUNTIME_SOURCE_TAG / "bin" / "llama-server",
    )
    parser.add_argument(
        "--runtime-manifest",
        type=Path,
        default=(
            ARTIFACT_ROOT / "runtime" / RUNTIME_SOURCE_TAG / "runtime-manifest.json"
        ),
    )
    parser.add_argument(
        "--candidate",
        choices=tuple(MODEL_CANDIDATES),
        default=MODEL_ID,
    )
    parser.add_argument(
        "--model",
        type=Path,
        default=None,
    )
    parser.add_argument(
        "--model-manifest",
        type=Path,
        default=None,
    )
    parser.add_argument("--destination", required=True, type=Path)
    parser.add_argument("--timeout", type=int, default=120)
    arguments = parser.parse_args(argv)
    try:
        return _execute(arguments, argv=argv)
    except (
        ValueError,
        OSError,
        llama_server.LlamaServerError,
        runtime_provenance.RuntimeProvenanceError,
    ) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
