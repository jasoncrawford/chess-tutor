#!/usr/bin/env python3
"""Render and tokenize the fixed compact coaching pilot without inference."""

import argparse
import hashlib
import json
import math
import os
import statistics
import sys
import tempfile
from pathlib import Path

import llama_server
import run_eval
import runtime_provenance


TOOLS_DIR = Path(__file__).resolve().parent
PROMPT_VERSION = "tutor-v4"
BUDGET_TOKENS = 4000
PREFERRED_TARGET_TOKENS = 3000
MODES = (("off", False), ("bounded", True))
PILOT_CASE_COUNT = 10
MODEL_COUNT = 3


def _file_sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _canonical_manifest_bytes(manifest):
    return (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode("utf-8")


def _write_immutable_manifest(output, manifest):
    """Persist one finished manifest without exposing a partial destination file."""
    output = Path(output)
    if output.exists():
        raise ValueError(f"Refusing to overwrite existing preflight manifest: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{output.name}.", suffix=".tmp", dir=output.parent
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as destination:
            destination.write(_canonical_manifest_bytes(manifest))
            destination.flush()
            os.fsync(destination.fileno())
        try:
            os.link(temporary, output)
        except FileExistsError as error:
            raise ValueError(
                f"Refusing to overwrite existing preflight manifest: {output}"
            ) from error
        try:
            directory_descriptor = os.open(str(output.parent), os.O_RDONLY)
        except OSError:
            directory_descriptor = None
        if directory_descriptor is not None:
            try:
                os.fsync(directory_descriptor)
            finally:
                os.close(directory_descriptor)
    finally:
        if temporary.exists():
            temporary.unlink()


def _validated_models(models):
    models = [(identifier, Path(path)) for identifier, path in models]
    identifiers = [identifier for identifier, _path in models]
    if len(models) != MODEL_COUNT:
        raise ValueError(f"Preflight requires exactly three models, not {len(models)}")
    if any(not isinstance(identifier, str) or not identifier for identifier in identifiers):
        raise ValueError("Preflight model IDs must be nonempty strings")
    if len(identifiers) != len(set(identifiers)):
        raise ValueError("Preflight refuses duplicate model IDs because they create duplicate cells")
    if len({path.resolve() for _identifier, path in models}) != len(models):
        raise ValueError("Preflight refuses duplicate model artifacts")
    missing = [str(path) for _identifier, path in models if not path.is_file()]
    if missing:
        raise ValueError("Preflight model artifacts are missing: " + ", ".join(missing))
    return models


def _pilot_cases(corpus, pilot):
    cases = run_eval._load_cases(corpus)
    selected = run_eval._select_case_list(cases, pilot, split="visible")
    if len(selected) != PILOT_CASE_COUNT:
        raise ValueError(f"Preflight requires exactly {PILOT_CASE_COUNT} pilot cases")
    return selected


def _compact_markdown(evaluation_case):
    compact_context = evaluation_case.get("compactContext")
    if not isinstance(compact_context, dict):
        raise ValueError(f"Pilot case {evaluation_case.get('id')} has no compact context")
    markdown = compact_context.get("markdown")
    if not isinstance(markdown, str):
        raise ValueError(f"Pilot case {evaluation_case.get('id')} has no compact Markdown")
    return markdown


def _validate_complete_matrix(cells, models, cases):
    expected = [
        (model_id, mode, case["id"])
        for model_id, _model_path in models
        for mode, _enable_thinking in MODES
        for case in cases
    ]
    actual = [(cell["modelID"], cell["mode"], cell["caseID"]) for cell in cells]
    if len(cells) != MODEL_COUNT * len(MODES) * PILOT_CASE_COUNT:
        raise ValueError("Preflight produced an incomplete 60-cell matrix")
    if len(actual) != len(set(actual)):
        raise ValueError("Preflight produced duplicate model/mode/case cells")
    if actual != expected:
        raise ValueError("Preflight matrix does not match the fixed model/mode/pilot order")


def _summary(cells):
    tokens = sorted(cell["renderedPromptTokens"] for cell in cells)
    if not tokens:
        raise ValueError("Preflight cannot summarize an empty matrix")
    return {
        "cellCount": len(cells),
        "overBudgetCount": sum(token > BUDGET_TOKENS for token in tokens),
        "abovePreferredTargetCount": sum(
            token > PREFERRED_TARGET_TOKENS for token in tokens
        ),
        "minimumTokens": tokens[0],
        "medianTokens": statistics.median(tokens),
        "p90Tokens": tokens[math.ceil(len(tokens) * 0.9) - 1],
        "maximumTokens": tokens[-1],
    }


def preflight(
    *,
    server,
    models,
    runtime_path=TOOLS_DIR / "runtime.json",
    runtime_manifest,
    corpus,
    pilot,
    output,
    prompt_version=PROMPT_VERSION,
    timeout=30,
    server_factory=llama_server.LlamaServer,
):
    """Write the complete exact-token preflight manifest and return its value.

    This deliberately calls only llama.cpp's apply-template and tokenize endpoints.
    The fixed matrix is intentionally small and serial: three supplied model artifacts,
    both supported thinking modes, and the immutable ten-case visible pilot.
    """
    if prompt_version != PROMPT_VERSION:
        raise ValueError(f"Preflight requires immutable {PROMPT_VERSION}")
    output = Path(output)
    if output.exists():
        raise ValueError(f"Refusing to overwrite existing preflight manifest: {output}")
    if timeout <= 0:
        raise ValueError("Preflight timeout must be positive")

    models = _validated_models(models)
    runtime_path = Path(runtime_path)
    corpus = Path(corpus)
    pilot = Path(pilot)
    prompt_bundle = run_eval._load_prompt_bundle(prompt_version)
    if not run_eval._uses_compact_context(prompt_bundle.version):
        raise ValueError("Preflight requires a compact-context prompt bundle")
    cases = _pilot_cases(corpus, pilot)
    examples = run_eval._example_messages(
        prompt_bundle.examples, prompt_version=prompt_bundle.version
    )
    runtime = run_eval._load_json(runtime_path)
    context_tokens = runtime["mac"]["contextTokens"]
    runtime_record = runtime_provenance.verify_runtime(
        server, runtime_path, runtime_manifest
    )
    runtime_sha256 = _file_sha256(runtime_path)
    corpus_sha256 = _file_sha256(corpus)
    pilot_sha256 = _file_sha256(pilot)
    model_records = [
        {
            "modelID": identifier,
            "modelPath": str(path.resolve()),
            "modelArtifactSHA256": _file_sha256(path),
            "modes": [mode for mode, _enable_thinking in MODES],
        }
        for identifier, path in models
    ]

    cells = []
    model_hashes = {
        record["modelID"]: record["modelArtifactSHA256"] for record in model_records
    }
    for model_id, model_path in models:
        client = server_factory(server, model_path, context_tokens=context_tokens)
        try:
            client.start()
            for mode, enable_thinking in MODES:
                for evaluation_case in cases:
                    markdown = _compact_markdown(evaluation_case)
                    rendered_prompt = client.render_prompt(
                        system_prompt=prompt_bundle.system_prompt,
                        user_content=markdown,
                        enable_thinking=enable_thinking,
                        timeout=timeout,
                        extra_messages=examples,
                    )
                    if not isinstance(rendered_prompt, str):
                        raise ValueError(
                            f"Template renderer returned a non-string prompt for {model_id}/{mode}"
                        )
                    rendered_bytes = rendered_prompt.encode("utf-8")
                    token_count = client.token_count(rendered_prompt, timeout=timeout)
                    if not isinstance(token_count, int) or token_count < 0:
                        raise ValueError(
                            f"Tokenizer returned an invalid token count for {model_id}/{mode}"
                        )
                    request = evaluation_case.get("request", {})
                    cells.append(
                        {
                            "modelID": model_id,
                            "modelArtifactSHA256": model_hashes[model_id],
                            "mode": mode,
                            "caseID": evaluation_case["id"],
                            "caseSplit": evaluation_case["split"],
                            "requestID": request.get("requestID"),
                            "positionRevision": request.get("positionRevision"),
                            "promptVersion": prompt_bundle.version,
                            "promptSHA256": prompt_bundle.prompt_sha256,
                            "examplesSHA256": prompt_bundle.examples_sha256,
                            "exampleCount": len(prompt_bundle.examples),
                            "corpusSHA256": corpus_sha256,
                            "pilotSHA256": pilot_sha256,
                            "runtimeSHA256": runtime_sha256,
                            "runtimeProvenance": runtime_record,
                            "compactContextUTF8Bytes": len(markdown.encode("utf-8")),
                            "compactContextSHA256": hashlib.sha256(
                                markdown.encode("utf-8")
                            ).hexdigest(),
                            "renderedPromptUTF8Bytes": len(rendered_bytes),
                            "renderedPromptSHA256": hashlib.sha256(rendered_bytes).hexdigest(),
                            "renderedPromptTokens": token_count,
                            "budgetStatus": (
                                "overBudget"
                                if token_count > BUDGET_TOKENS
                                else "withinBudget"
                            ),
                            "abovePreferredTarget": token_count > PREFERRED_TARGET_TOKENS,
                        }
                    )
        finally:
            client.stop()

    _validate_complete_matrix(cells, models, cases)
    manifest = {
        "schemaVersion": "coaching-prompt-preflight.v1",
        "promptVersion": prompt_bundle.version,
        "budgetTokens": BUDGET_TOKENS,
        "preferredTargetTokens": PREFERRED_TARGET_TOKENS,
        "promptSHA256": prompt_bundle.prompt_sha256,
        "examplesSHA256": prompt_bundle.examples_sha256,
        "exampleCount": len(prompt_bundle.examples),
        "corpusPath": str(corpus.resolve()),
        "corpusSHA256": corpus_sha256,
        "pilotPath": str(pilot.resolve()),
        "pilotSHA256": pilot_sha256,
        "runtimePath": str(runtime_path.resolve()),
        "runtimeSHA256": runtime_sha256,
        "runtimeProvenance": runtime_record,
        "models": model_records,
        "cells": cells,
        "summary": _summary(cells),
    }
    _write_immutable_manifest(output, manifest)
    return manifest


def _model_argument(value):
    identifier, separator, path = value.partition("=")
    if not separator or not identifier or not path:
        raise argparse.ArgumentTypeError("--model must be MODEL_ID=GGUF_PATH")
    return identifier, Path(path)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", required=True, type=Path)
    parser.add_argument("--runtime", type=Path, default=TOOLS_DIR / "runtime.json")
    parser.add_argument("--runtime-manifest", required=True, type=Path)
    parser.add_argument("--corpus", required=True, type=Path)
    parser.add_argument("--pilot", "--case-list", dest="pilot", required=True, type=Path)
    parser.add_argument("--model", action="append", required=True, type=_model_argument)
    parser.add_argument("--prompt-version", default=PROMPT_VERSION)
    parser.add_argument("--timeout", type=int, default=30)
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args(argv)
    try:
        manifest = preflight(
            server=arguments.server,
            models=arguments.model,
            runtime_path=arguments.runtime,
            runtime_manifest=arguments.runtime_manifest,
            corpus=arguments.corpus,
            pilot=arguments.pilot,
            output=arguments.output,
            prompt_version=arguments.prompt_version,
            timeout=arguments.timeout,
        )
    except (
        ValueError,
        OSError,
        llama_server.LlamaServerError,
        runtime_provenance.RuntimeProvenanceError,
    ) as error:
        print(str(error), file=sys.stderr)
        return 1
    print(arguments.output)
    return 1 if manifest["summary"]["overBudgetCount"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
