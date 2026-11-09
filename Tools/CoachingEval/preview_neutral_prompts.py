#!/usr/bin/env python3
"""Build an immutable, tokenizer-only packet of neutral coaching prompts."""

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path

import llama_server
import runtime_provenance


TOOLS_DIR = Path(__file__).resolve().parent
REPOSITORY_ROOT = TOOLS_DIR.parents[1]
PROMPT_VERSION = "tutor-v5"
TOKENIZER_MODEL_ID = "qwen3-1.7b-q4_k_m"
BUDGET_TOKENS = 2500
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
LEGACY_HIDDEN_IDS = (
    "t1OutsidePawnMove",
    "t3WrongAttacker",
    "t7UnsafeCapture",
    "t12WrongChecker",
)
CONCLUSION_BEARING_PHRASES = (
    "best",
    "useful",
    "important",
    "purpose",
    "needs help",
    "looks safe",
    "what to teach",
    "selected move ideas",
    "danger scan",
    "safe captures",
)


def _sha256(data):
    return hashlib.sha256(data).hexdigest()


def _file_sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _canonical_json(value):
    return json.dumps(
        value, indent=2, sort_keys=True, ensure_ascii=False
    ).encode("utf-8") + b"\n"


def _swift_canonical_json(value):
    encoded = json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    )
    return encoded.replace("/", "\\/").encode("utf-8")


def _load_json(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError) as error:
        raise ValueError(f"Cannot read JSON from {path}") from error


def _reject_forbidden_fields(value):
    if isinstance(value, dict):
        for key, child in value.items():
            lowered = str(key).lower()
            if "response" in lowered or "output" in lowered:
                raise ValueError("Neutral prompt source contains response/output data")
            if "trace" in lowered:
                raise ValueError("Neutral prompt source contains trace data")
            _reject_forbidden_fields(child)
    elif isinstance(value, list):
        for child in value:
            _reject_forbidden_fields(child)


def _validate_no_hidden_identifiers(value):
    serialized = json.dumps(value, sort_keys=True, ensure_ascii=False)
    if "hidden" in serialized.lower():
        raise ValueError("Neutral prompt source contains a hidden identifier")
    for identifier in LEGACY_HIDDEN_IDS:
        if identifier in serialized:
            raise ValueError("Neutral prompt source contains a hidden identifier")


def _expected_source_files(records):
    files = {
        Path("examples.jsonl"),
        Path("preview-manifest.json"),
        Path("system-prompt.md"),
    }
    files.update(Path("user-prompts") / record["fileName"] for record in records)
    return files


def _load_and_validate_source(source_dir, system_prompt_path):
    source_dir = Path(source_dir)
    system_prompt_path = Path(system_prompt_path)
    if not source_dir.is_dir():
        raise ValueError(f"Swift prompt export is missing: {source_dir}")
    if not system_prompt_path.is_file():
        raise ValueError(f"System prompt is missing: {system_prompt_path}")

    manifest_path = source_dir / "preview-manifest.json"
    jsonl_path = source_dir / "examples.jsonl"
    exported_system_path = source_dir / "system-prompt.md"
    source_manifest = _load_json(manifest_path)
    _reject_forbidden_fields(source_manifest)
    _validate_no_hidden_identifiers(source_manifest)

    system_bytes = system_prompt_path.read_bytes()
    if exported_system_path.read_bytes() != system_bytes:
        raise ValueError("Exported system prompt differs from exact tutor-v5.md")
    system_sha = _sha256(system_bytes)
    if source_manifest.get("systemPromptSHA256") != system_sha:
        raise ValueError("Swift manifest system prompt hash does not match exact tutor-v5.md")
    if source_manifest.get("schemaVersion") != "model-coaching-neutral-preview-manifest.v1":
        raise ValueError("Swift prompt export has an unsupported manifest schema")
    if source_manifest.get("promptVersion") != PROMPT_VERSION:
        raise ValueError(f"Swift prompt export must use exact {PROMPT_VERSION}")
    if source_manifest.get("exampleIDs") != list(EXAMPLE_IDS):
        raise ValueError("Swift prompt export does not have the exact eight-case order")

    jsonl_bytes = jsonl_path.read_bytes()
    lines = jsonl_bytes.splitlines()
    if len(lines) != len(EXAMPLE_IDS) or any(not line for line in lines):
        raise ValueError("Swift prompt export must contain exactly eight JSONL records")
    try:
        records = [json.loads(line.decode("utf-8")) for line in lines]
    except (UnicodeError, ValueError) as error:
        raise ValueError("Swift prompt export contains malformed JSONL") from error
    _reject_forbidden_fields(records)
    _validate_no_hidden_identifiers(records)

    record_ids = [record.get("id") for record in records]
    if record_ids != list(EXAMPLE_IDS):
        raise ValueError("Swift prompt export does not have the exact eight-case order")
    if len(record_ids) != len(set(record_ids)):
        raise ValueError("Swift prompt export contains duplicate prompt IDs")
    if any(record.get("visibility") != "visible" for record in records):
        raise ValueError("Swift prompt export may contain only visible examples")
    if source_manifest.get("examplesJSONLSHA256") != _sha256(jsonl_bytes):
        raise ValueError("Swift prompt export JSONL hash does not match its manifest")

    manifest_examples = source_manifest.get("examples")
    if not isinstance(manifest_examples, list) or len(manifest_examples) != len(records):
        raise ValueError("Swift prompt manifest must bind all eight examples")
    for identifier, record, manifest_example in zip(
        EXAMPLE_IDS, records, manifest_examples
    ):
        file_name = f"{identifier}.md"
        if record.get("fileName") != file_name:
            raise ValueError(f"Prompt {identifier} has an unexpected file name")
        if manifest_example != {
            "fileName": file_name,
            "id": identifier,
            "requestSHA256": record.get("requestSHA256"),
            "userPromptSHA256": record.get("userPromptSHA256"),
        }:
            raise ValueError(f"Swift manifest does not bind prompt {identifier}")

        request = record.get("request")
        compilation = record.get("compilation")
        if not isinstance(request, dict) or not isinstance(compilation, dict):
            raise ValueError(f"Prompt {identifier} lacks request or compilation data")
        if request.get("requestID") != identifier:
            raise ValueError(f"Prompt {identifier} request ID does not match")
        if compilation.get("requestID") != identifier:
            raise ValueError(f"Prompt {identifier} compilation ID does not match")
        if compilation.get("promptVersion") != PROMPT_VERSION:
            raise ValueError(f"Prompt {identifier} compilation has the wrong prompt version")
        request_sha = _sha256(_swift_canonical_json(request))
        if record.get("requestSHA256") != request_sha:
            raise ValueError(f"Prompt {identifier} request hash does not match")

        markdown = compilation.get("markdown")
        if not isinstance(markdown, str) or not markdown:
            raise ValueError(f"Prompt {identifier} has no compiled Markdown")
        user_bytes = markdown.encode("utf-8")
        user_sha = _sha256(user_bytes)
        if record.get("userPromptSHA256") != user_sha:
            raise ValueError(f"Prompt {identifier} Markdown hash does not match")
        user_path = source_dir / "user-prompts" / file_name
        if user_path.read_bytes() != user_bytes:
            raise ValueError(f"Prompt {identifier} Markdown differs from its exported file")
        lowered = markdown.lower()
        found = [phrase for phrase in CONCLUSION_BEARING_PHRASES if phrase in lowered]
        if found:
            raise ValueError(
                f"Prompt {identifier} contains conclusion-bearing language: {found[0]}"
            )

    actual_files = {
        path.relative_to(source_dir)
        for path in source_dir.rglob("*")
        if path.is_file()
    }
    if actual_files != _expected_source_files(records):
        raise ValueError("Swift prompt export contains undeclared or missing files")

    return {
        "sourceManifest": source_manifest,
        "sourceManifestBytes": manifest_path.read_bytes(),
        "examplesJSONLBytes": jsonl_bytes,
        "records": records,
        "systemPrompt": system_bytes.decode("utf-8"),
        "systemPromptSHA256": system_sha,
    }


def _logical_transcript(identifier, system_prompt, user_prompt):
    return (
        f"# Neutral coaching prompt: {identifier}\n\n"
        "## System message\n\n"
        f"{system_prompt}\n"
        "## User message\n\n"
        f"{user_prompt}"
        + ("" if user_prompt.endswith("\n") else "\n")
    ).encode("utf-8")


def _validate_tokenizer_provenance(provenance):
    if not isinstance(provenance, dict):
        raise ValueError("Tokenizer provenance must be a JSON object")
    _reject_forbidden_fields(provenance)
    if provenance.get("modelID") != TOKENIZER_MODEL_ID:
        raise ValueError(f"Prompt preview requires pinned {TOKENIZER_MODEL_ID}")


def build_preview(
    *,
    source_dir,
    system_prompt_path,
    destination,
    client,
    tokenizer_provenance,
    timeout=30,
):
    """Render, tokenize, and persist eight logical prompts without inference."""
    destination = Path(destination)
    if os.path.lexists(destination):
        raise ValueError(f"Refusing to overwrite existing prompt preview: {destination}")
    if not isinstance(timeout, int) or isinstance(timeout, bool) or timeout <= 0:
        raise ValueError("Tokenizer timeout must be a positive integer")
    _validate_tokenizer_provenance(tokenizer_provenance)
    source = _load_and_validate_source(source_dir, system_prompt_path)

    prompt_cells = []
    transcript_files = {}
    token_counts = []
    for record in source["records"]:
        identifier = record["id"]
        user_prompt = record["compilation"]["markdown"]
        rendered_prompt = client.render_prompt(
            system_prompt=source["systemPrompt"],
            user_content=user_prompt,
            enable_thinking=False,
            timeout=timeout,
        )
        if not isinstance(rendered_prompt, str) or not rendered_prompt:
            raise ValueError(f"Template renderer returned no prompt for {identifier}")
        token_count = client.token_count(rendered_prompt, timeout=timeout)
        if (
            not isinstance(token_count, int)
            or isinstance(token_count, bool)
            or token_count <= 0
        ):
            raise ValueError(f"Tokenizer returned an invalid count for {identifier}")
        if token_count > BUDGET_TOKENS:
            raise ValueError(
                f"Prompt {identifier} uses {token_count:,} tokens, above the 2,500-token budget"
            )

        user_bytes = user_prompt.encode("utf-8")
        rendered_bytes = rendered_prompt.encode("utf-8")
        transcript_bytes = _logical_transcript(
            identifier, source["systemPrompt"], user_prompt
        )
        transcript_name = f"prompts/{identifier}.md"
        transcript_files[transcript_name] = transcript_bytes
        token_counts.append(token_count)
        prompt_cells.append(
            {
                "id": identifier,
                "requestID": record["request"]["requestID"],
                "requestSHA256": record["requestSHA256"],
                "systemPromptSHA256": source["systemPromptSHA256"],
                "userPromptSHA256": record["userPromptSHA256"],
                "userPromptUTF8Bytes": len(user_bytes),
                "userPromptWords": len(user_prompt.split()),
                "renderedPromptSHA256": _sha256(rendered_bytes),
                "renderedPromptUTF8Bytes": len(rendered_bytes),
                "renderedPromptTokens": token_count,
                "transcriptFileName": transcript_name,
                "transcriptSHA256": _sha256(transcript_bytes),
                "transcriptUTF8Bytes": len(transcript_bytes),
            }
        )

    manifest = {
        "schemaVersion": "model-coaching-neutral-human-preview.v1",
        "promptVersion": PROMPT_VERSION,
        "budgetTokens": BUDGET_TOKENS,
        "templateThinkingMode": "off",
        "exampleIDs": list(EXAMPLE_IDS),
        "systemPromptSHA256": source["systemPromptSHA256"],
        "examplesJSONLSHA256": _sha256(source["examplesJSONLBytes"]),
        "sourceManifestSHA256": _sha256(source["sourceManifestBytes"]),
        "tokenizerProvenance": dict(tokenizer_provenance),
        "prompts": prompt_cells,
        "summary": {
            "promptCount": len(prompt_cells),
            "minimumTokens": min(token_counts),
            "maximumTokens": max(token_counts),
        },
    }
    _reject_forbidden_fields(manifest)
    _validate_no_hidden_identifiers(manifest)

    destination.mkdir(parents=True, exist_ok=False)
    (destination / "prompts").mkdir()
    for relative_name, contents in sorted(transcript_files.items()):
        with (destination / relative_name).open("xb") as artifact:
            artifact.write(contents)
    with (destination / "preview-manifest.json").open("xb") as artifact:
        artifact.write(_canonical_json(manifest))
    return manifest


class _TokenizerOnlyClient:
    """Narrow the server object to the two operations this command permits."""

    def __init__(self, server):
        self._server = server

    def render_prompt(self, **arguments):
        return self._server.render_prompt(**arguments)

    def token_count(self, prompt, **arguments):
        return self._server.token_count(prompt, **arguments)


def _pinned_provenance(model_path, model_manifest_path, server, runtime_manifest):
    model_path = Path(model_path)
    model_manifest = _load_json(model_manifest_path)
    if model_manifest.get("modelID") != TOKENIZER_MODEL_ID:
        raise ValueError(f"Model manifest must identify {TOKENIZER_MODEL_ID}")
    if model_manifest.get("filename") != model_path.name:
        raise ValueError("Model path does not match its artifact manifest")
    if model_manifest.get("bytes") != model_path.stat().st_size:
        raise ValueError("Model byte count does not match its artifact manifest")
    model_sha = _file_sha256(model_path)
    if model_manifest.get("sha256") != model_sha:
        raise ValueError("Model hash does not match its artifact manifest")

    runtime = runtime_provenance.verify_runtime(
        server, TOOLS_DIR / "runtime.json", runtime_manifest
    )
    return {
        "modelID": TOKENIZER_MODEL_ID,
        "modelArtifactSHA256": model_sha,
        "modelArtifactBytes": model_path.stat().st_size,
        "modelResolvedRevision": model_manifest.get("resolvedRevision"),
        "runtimeSourceTag": runtime["sourceTag"],
        "runtimeSourceCommit": runtime["sourceCommit"],
        "runtimeBinarySHA256": runtime["binarySHA256"],
        "runtimeVersion": runtime["versionOutput"],
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument(
        "--system-prompt", type=Path, default=TOOLS_DIR / "prompts" / "tutor-v5.md"
    )
    parser.add_argument("--server", required=True, type=Path)
    parser.add_argument("--runtime-manifest", required=True, type=Path)
    parser.add_argument("--model", required=True, type=Path)
    parser.add_argument("--model-manifest", required=True, type=Path)
    parser.add_argument("--destination", required=True, type=Path)
    parser.add_argument("--timeout", type=int, default=30)
    arguments = parser.parse_args(argv)

    server = None
    try:
        provenance = _pinned_provenance(
            arguments.model,
            arguments.model_manifest,
            arguments.server,
            arguments.runtime_manifest,
        )
        runtime = _load_json(TOOLS_DIR / "runtime.json")
        server = llama_server.LlamaServer(
            arguments.server,
            arguments.model,
            context_tokens=runtime["mac"]["contextTokens"],
        )
        server.start(timeout=arguments.timeout)
        manifest = build_preview(
            source_dir=arguments.source,
            system_prompt_path=arguments.system_prompt,
            destination=arguments.destination,
            client=_TokenizerOnlyClient(server),
            tokenizer_provenance=provenance,
            timeout=arguments.timeout,
        )
    except (
        ValueError,
        OSError,
        KeyError,
        llama_server.LlamaServerError,
        runtime_provenance.RuntimeProvenanceError,
    ) as error:
        print(str(error), file=sys.stderr)
        return 1
    finally:
        if server is not None:
            server.stop()

    print(json.dumps(manifest["summary"], sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
