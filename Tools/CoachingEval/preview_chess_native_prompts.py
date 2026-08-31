#!/usr/bin/env python3
"""Build an immutable, tokenizer-only packet of chess-native coaching prompts."""

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path

import llama_server
import runtime_provenance


TOOLS_DIR = Path(__file__).resolve().parent
PROMPT_VERSION = "tutor-v6"
TOKENIZER_MODEL_ID = "qwen3-1.7b-q4_k_m"
BUDGET_TOKENS = 2500
PREFERRED_MINIMUM_TOKENS = 500
PREFERRED_MAXIMUM_TOKENS = 1500
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
MODEL_FACING_SYSTEM_ROLE = "modelFacingSystemMessage"
MODEL_FACING_USER_ROLE = "modelFacingUserMessage"
AUDIT_ONLY_ROLE = "auditOnly"
PERMITTED_ENDPOINTS = ("/health", "/apply-template", "/tokenize")
ALIAS_PATTERN = re.compile(r"\b(?:relationship|move|piece|action)-[0-9]+\b")
HIDDEN_IDENTIFIER_PATTERN = re.compile(
    r"hidden|t[0-9]+(?:OutsidePawnMove|WrongAttacker|UnsafeCapture|WrongChecker)",
    re.IGNORECASE,
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


def _load_json(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError) as error:
        raise ValueError(f"Cannot read JSON from {path}") from error


def _reject_forbidden_fields(value):
    if isinstance(value, dict):
        for key, child in value.items():
            lowered = str(key).lower()
            if "response" in lowered or "assistant" in lowered:
                raise ValueError("Prompt preview metadata contains response/assistant data")
            if "trace" in lowered or "hidden" in lowered:
                raise ValueError("Prompt preview metadata contains trace/hidden data")
            _reject_forbidden_fields(child)
    elif isinstance(value, list):
        for child in value:
            _reject_forbidden_fields(child)


def _validate_model_facing_text(text, *, source):
    alias = ALIAS_PATTERN.search(text)
    if alias is not None:
        raise ValueError(f"{source} contains numbered alias {alias.group(0)}")
    hidden_identifier = HIDDEN_IDENTIFIER_PATTERN.search(text)
    if hidden_identifier is not None:
        raise ValueError(f"{source} contains a hidden identifier")


def _validated_relative_path(raw_path):
    if not isinstance(raw_path, str) or not raw_path:
        raise ValueError("Swift prompt manifest declares an invalid path")
    path = Path(raw_path)
    if path.is_absolute() or raw_path != path.as_posix() or ".." in path.parts:
        raise ValueError("Swift prompt manifest declares an unsafe path")
    return path


def _expected_declared_files(example_ids=EXAMPLE_IDS):
    return [
        {"path": "examples.jsonl", "role": AUDIT_ONLY_ROLE},
        {"path": "preview-manifest.json", "role": AUDIT_ONLY_ROLE},
        {"path": "system-prompt.md", "role": MODEL_FACING_SYSTEM_ROLE},
    ] + [
        {
            "path": f"user-prompts/{identifier}.md",
            "role": MODEL_FACING_USER_ROLE,
        }
        for identifier in example_ids
    ]


def _load_and_validate_source(
    source_dir, system_prompt_path, *, example_ids=EXAMPLE_IDS
):
    example_ids = tuple(example_ids)
    if (
        not example_ids
        or any(not isinstance(identifier, str) or not identifier for identifier in example_ids)
        or len(example_ids) != len(set(example_ids))
    ):
        raise ValueError("Prompt preview requires unique visible IDs")
    source_dir = Path(source_dir)
    system_prompt_path = Path(system_prompt_path)
    if not source_dir.is_dir():
        raise ValueError(f"Swift prompt export is missing: {source_dir}")
    if not system_prompt_path.is_file():
        raise ValueError(f"System prompt is missing: {system_prompt_path}")

    manifest_path = source_dir / "preview-manifest.json"
    source_manifest_bytes = manifest_path.read_bytes()
    source_manifest = _load_json(manifest_path)
    _reject_forbidden_fields(source_manifest)
    if source_manifest.get("schemaVersion") != (
        "model-coaching-chess-native-preview-manifest.v2"
    ):
        raise ValueError("Swift prompt export has an unsupported manifest schema")
    if source_manifest.get("promptVersion") != PROMPT_VERSION:
        raise ValueError(f"Swift prompt export must use exact {PROMPT_VERSION}")
    if source_manifest.get("exampleIDs") != list(example_ids):
        raise ValueError("Swift prompt export does not have the exact requested case order")

    declared_files = source_manifest.get("declaredFiles")
    if declared_files != _expected_declared_files(example_ids):
        raise ValueError(
            "Swift prompt export roles must identify the exact model-facing files"
        )
    declared_paths = [_validated_relative_path(item["path"]) for item in declared_files]
    if len(declared_paths) != len(set(declared_paths)):
        raise ValueError("Swift prompt export declares duplicate files")
    actual_files = {
        path.relative_to(source_dir)
        for path in source_dir.rglob("*")
        if path.is_file()
    }
    if actual_files != set(declared_paths):
        raise ValueError("Swift prompt export contains undeclared or missing files")

    system_declarations = [
        item for item in declared_files if item["role"] == MODEL_FACING_SYSTEM_ROLE
    ]
    user_declarations = [
        item for item in declared_files if item["role"] == MODEL_FACING_USER_ROLE
    ]
    if len(system_declarations) != 1 or len(user_declarations) != len(example_ids):
        raise ValueError("Swift prompt export has invalid model-facing roles")

    system_bytes = system_prompt_path.read_bytes()
    exported_system_path = source_dir / system_declarations[0]["path"]
    if exported_system_path.read_bytes() != system_bytes:
        raise ValueError("Exported system prompt differs from exact tutor-v6.md")
    system_sha = _sha256(system_bytes)
    if source_manifest.get("systemPromptSHA256") != system_sha:
        raise ValueError("Swift manifest system prompt hash does not match exact tutor-v6.md")
    try:
        system_prompt = system_bytes.decode("utf-8")
    except UnicodeError as error:
        raise ValueError("System prompt is not valid UTF-8") from error
    _validate_model_facing_text(system_prompt, source="System prompt")

    manifest_examples = source_manifest.get("examples")
    if not isinstance(manifest_examples, list) or len(manifest_examples) != len(
        example_ids
    ):
        raise ValueError("Swift prompt manifest must bind every requested example")

    prompts = []
    for identifier, declaration, example in zip(
        example_ids, user_declarations, manifest_examples
    ):
        file_name = f"{identifier}.md"
        if set(example) != {
            "fileName",
            "id",
            "requestSHA256",
            "systemPromptSHA256",
            "userPromptSHA256",
        }:
            raise ValueError(f"Swift manifest has invalid fields for prompt {identifier}")
        if example.get("id") != identifier or example.get("fileName") != file_name:
            raise ValueError(f"Swift manifest does not bind prompt {identifier}")
        if declaration["path"] != f"user-prompts/{file_name}":
            raise ValueError(f"Swift manifest role order does not bind prompt {identifier}")
        if example.get("systemPromptSHA256") != system_sha:
            raise ValueError(f"Prompt {identifier} system prompt hash does not match")
        for field in ("requestSHA256", "userPromptSHA256"):
            if not re.fullmatch(r"[0-9a-f]{64}", str(example.get(field, ""))):
                raise ValueError(f"Prompt {identifier} has an invalid {field}")

        user_bytes = (source_dir / declaration["path"]).read_bytes()
        if _sha256(user_bytes) != example["userPromptSHA256"]:
            raise ValueError(f"Prompt {identifier} user prompt hash does not match")
        try:
            user_prompt = user_bytes.decode("utf-8")
        except UnicodeError as error:
            raise ValueError(f"Prompt {identifier} is not valid UTF-8") from error
        if not user_prompt:
            raise ValueError(f"Prompt {identifier} is empty")
        _validate_model_facing_text(user_prompt, source=f"Prompt {identifier}")
        prompts.append(
            {
                "id": identifier,
                "requestSHA256": example["requestSHA256"],
                "userPrompt": user_prompt,
                "userPromptSHA256": example["userPromptSHA256"],
            }
        )

    return {
        "sourceManifestBytes": source_manifest_bytes,
        "systemPrompt": system_prompt,
        "systemPromptSHA256": system_sha,
        "prompts": prompts,
    }


def _logical_transcript(identifier, system_prompt, user_prompt):
    return (
        f"# Chess-native coaching prompt: {identifier}\n\n"
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
    example_ids=EXAMPLE_IDS,
):
    """Render, tokenize, and persist exact logical prompts without inference."""
    destination = Path(destination)
    if os.path.lexists(destination):
        raise ValueError(f"Refusing to overwrite existing prompt preview: {destination}")
    if not isinstance(timeout, int) or isinstance(timeout, bool) or timeout <= 0:
        raise ValueError("Tokenizer timeout must be a positive integer")
    _validate_tokenizer_provenance(tokenizer_provenance)
    example_ids = tuple(example_ids)
    source = _load_and_validate_source(
        source_dir, system_prompt_path, example_ids=example_ids
    )

    prompt_cells = []
    transcript_files = {}
    token_counts = []
    for source_prompt in source["prompts"]:
        identifier = source_prompt["id"]
        user_prompt = source_prompt["userPrompt"]
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
                f"Prompt {identifier} uses {token_count:,} tokens, above the "
                "2,500-token budget"
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
                "requestSHA256": source_prompt["requestSHA256"],
                "systemPromptSHA256": source["systemPromptSHA256"],
                "userPromptSHA256": source_prompt["userPromptSHA256"],
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

    preferred_ids = [
        cell["id"]
        for cell in prompt_cells
        if PREFERRED_MINIMUM_TOKENS
        <= cell["renderedPromptTokens"]
        <= PREFERRED_MAXIMUM_TOKENS
    ]
    manifest = {
        "schemaVersion": "model-coaching-chess-native-human-preview.v1",
        "promptVersion": PROMPT_VERSION,
        "budgetTokens": BUDGET_TOKENS,
        "preferredTokenRange": {
            "minimumTokens": PREFERRED_MINIMUM_TOKENS,
            "maximumTokens": PREFERRED_MAXIMUM_TOKENS,
        },
        "templateThinkingMode": "off",
        "consumedSourceRoles": [
            MODEL_FACING_SYSTEM_ROLE,
            MODEL_FACING_USER_ROLE,
        ],
        "permittedServerEndpoints": list(PERMITTED_ENDPOINTS),
        "exampleIDs": list(example_ids),
        "systemPromptSHA256": source["systemPromptSHA256"],
        "sourceManifestSHA256": _sha256(source["sourceManifestBytes"]),
        "tokenizerProvenance": dict(tokenizer_provenance),
        "prompts": prompt_cells,
        "summary": {
            "promptCount": len(prompt_cells),
            "minimumTokens": min(token_counts),
            "maximumTokens": max(token_counts),
            "preferredRangePromptCount": len(preferred_ids),
            "preferredRangePromptIDs": preferred_ids,
        },
    }
    _reject_forbidden_fields(manifest)

    destination.mkdir(parents=True, exist_ok=False)
    (destination / "prompts").mkdir()
    for relative_name, contents in sorted(transcript_files.items()):
        with (destination / relative_name).open("xb") as artifact:
            artifact.write(contents)
    with (destination / "preview-manifest.json").open("xb") as artifact:
        artifact.write(_canonical_json(manifest))
    return manifest


class _TokenizerOnlyClient:
    """Expose only the two server operations permitted by this command."""

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
        "--system-prompt", type=Path, default=TOOLS_DIR / "prompts" / "tutor-v6.md"
    )
    parser.add_argument("--server", required=True, type=Path)
    parser.add_argument("--runtime-manifest", required=True, type=Path)
    parser.add_argument("--model", required=True, type=Path)
    parser.add_argument("--model-manifest", required=True, type=Path)
    parser.add_argument("--destination", required=True, type=Path)
    parser.add_argument("--timeout", type=int, default=30)
    parser.add_argument("--example-id", action="append", dest="example_ids")
    arguments = parser.parse_args(argv)
    example_ids = tuple(arguments.example_ids or EXAMPLE_IDS)

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
        provenance["serverCommand"] = list(server.command)
        provenance["previewCommand"] = [
            sys.executable,
            str(Path(__file__).resolve()),
        ] + list(sys.argv[1:] if argv is None else argv)
        manifest = build_preview(
            source_dir=arguments.source,
            system_prompt_path=arguments.system_prompt,
            destination=arguments.destination,
            client=_TokenizerOnlyClient(server),
            tokenizer_provenance=provenance,
            timeout=arguments.timeout,
            example_ids=example_ids,
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
