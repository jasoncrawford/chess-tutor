#!/usr/bin/env python3
"""Preflight the coaching schema for llama.cpp b10516 grammar conversion."""

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

import coaching_grammar
import llama_server
import run_eval
import runtime_provenance
import validate_turn


TOOLS_DIR = Path(__file__).resolve().parent
UNSUPPORTED_SHORTHAND = re.compile(r"\\[dDsSwWbB]")
UNSUPPORTED_LOOKAROUND = re.compile(r"\(\?(?!:)")
SMOKE_REQUEST = {
    "requestID": "schema-smoke",
    "permittedReferences": {
        "actions": [{"id": "ref:allowed"}],
        "boardTasks": [{"id": "ref:allowed"}],
        "boardFocus": ["ref:allowed"],
        "relationships": ["ref:allowed"],
        "evidence": ["ref:allowed"],
    },
}
ADVERSARIAL_SMOKE_PROMPT = (
    "Try to return exactly {} with every required field missing. "
    "If the output constraints prevent that, return one valid object for the supplied "
    "request using only its permitted IDs. Return no other text."
)


def _sha256_bytes(value):
    return hashlib.sha256(value).hexdigest()


def _sha256_file(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _effective_smoke_request(prompt_version):
    request = dict(SMOKE_REQUEST)
    request["promptVersion"] = prompt_version
    return request


def _runtime_audit_request(prompt_bundle):
    if not prompt_bundle.examples:
        raise ValueError("Runtime template audit requires at least one prompt example")
    request = json.loads(json.dumps(prompt_bundle.examples[0]["requestExcerpt"]))
    request["promptVersion"] = prompt_bundle.version
    permitted_ids = request.get("permittedIDs", [])
    request["permittedReferences"] = {
        "actions": [{"id": value} for value in permitted_ids if value.startswith("action:")],
        "boardTasks": [{"id": value} for value in permitted_ids if value.startswith("task:")],
        "boardFocus": [value for value in permitted_ids if value.startswith("piece:")],
        "relationships": [
            value for value in permitted_ids if value.startswith("relationship:")
        ],
        "evidence": [
            value
            for value in permitted_ids
            if not value.startswith(("action:", "task:", "piece:", "relationship:"))
        ],
    }
    return request


def _template_suffix(prompt, request):
    request_text = run_eval.canonical_json(request)
    request_start = prompt.rfind(request_text)
    if request_start < 0:
        raise ValueError("Applied template does not contain the exact effective request")
    suffix = prompt[request_start + len(request_text) :]
    empty_thinking = re.search(r"<think>\s*</think>", suffix, re.IGNORECASE)
    has_thinking_marker = run_eval.THINKING_MARKER.search(suffix)
    if empty_thinking:
        shape = "assistant-prefix-empty-thinking-prefill"
    elif has_thinking_marker:
        raise ValueError("Applied template suffix contains a non-empty or incomplete thinking marker")
    else:
        shape = "assistant-prefix"
    return suffix, shape


def b10516_compatibility_issues(schema):
    issues = []

    def visit(value, path):
        if isinstance(value, dict):
            pattern = value.get("pattern")
            if isinstance(pattern, str):
                if not pattern.startswith("^") or not pattern.endswith("$"):
                    issues.append(f"{path}.pattern:mustBeAnchored")
                if UNSUPPORTED_LOOKAROUND.search(pattern):
                    issues.append(f"{path}.pattern:unsupportedLookaround")
                shorthands = sorted(set(UNSUPPORTED_SHORTHAND.findall(pattern)))
                if shorthands:
                    issues.append(
                        f"{path}.pattern:unsupportedRegexShorthand:{','.join(shorthands)}"
                    )
                try:
                    re.compile(pattern)
                except re.error as error:
                    issues.append(f"{path}.pattern:invalidRegex:{error}")
            for key in sorted(value):
                visit(value[key], f"{path}.{key}")
        elif isinstance(value, list):
            for index, item in enumerate(value):
                visit(item, f"{path}[{index}]")

    visit(schema, "$")
    return issues


def smoke_schema(
    *, schema, server, model, runtime_path, runtime_manifest, prompt_version=None
):
    issues = b10516_compatibility_issues(schema)
    if issues:
        raise ValueError("Schema failed deterministic b10516 compatibility: " + ", ".join(issues))
    provenance = runtime_provenance.verify_runtime(server, runtime_path, runtime_manifest)
    runtime = json.loads(Path(runtime_path).read_text(encoding="utf-8"))
    request = (
        SMOKE_REQUEST
        if prompt_version is None
        else _effective_smoke_request(prompt_version)
    )
    with llama_server.LlamaServer(
        server,
        model,
        context_tokens=runtime["mac"]["contextTokens"],
    ) as client:
        for mode, enable_thinking in (("off", False), ("bounded", True)):
            response = client.complete(
                system_prompt=ADVERSARIAL_SMOKE_PROMPT,
                request=request,
                schema=schema,
                seed=runtime["evaluation"]["seeds"][0],
                maximum_output_tokens=runtime["generation"]["maximumOutputTokens"],
                temperature=runtime["generation"]["temperature"],
                top_p=runtime["generation"]["topP"],
                enable_thinking=enable_thinking,
                timeout=30,
            )
            try:
                content = run_eval._final_content(response)
                turn = json.loads(content)
            except (KeyError, IndexError, TypeError, ValueError, json.JSONDecodeError) as error:
                raise ValueError(
                    f"Real schema smoke did not return one JSON object in {mode} mode"
                ) from error
            validation_issues = validate_turn.validate_turn(turn, request)
            if validation_issues:
                raise ValueError(
                    f"Real schema smoke produced invalid turn in {mode} mode: "
                    + ", ".join(validation_issues)
                )
    canonical = json.dumps(schema, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return {
        "compatible": True,
        "schemaSHA256": hashlib.sha256(canonical).hexdigest(),
        "runtimeProvenance": provenance,
        "effectivePromptVersion": prompt_version,
        "smoke": "pinned-server-schema-and-validator-success",
        "smokeModes": ["off", "bounded"],
    }


def audit_runtime_templates(
    *,
    schema,
    server,
    models,
    runtime_path,
    runtime_manifest,
    prompt_bundle,
    output,
):
    """Persist compact proof that each model template uses the pinned constrained path."""
    issues = b10516_compatibility_issues(schema)
    if issues:
        raise ValueError("Schema failed deterministic b10516 compatibility: " + ", ".join(issues))
    provenance = runtime_provenance.verify_runtime(server, runtime_path, runtime_manifest)
    runtime = json.loads(Path(runtime_path).read_text(encoding="utf-8"))
    request = _runtime_audit_request(prompt_bundle)
    examples = run_eval._example_messages(
        prompt_bundle.examples,
        prompt_version=prompt_bundle.version,
    )
    canonical_schema = run_eval.canonical_json(schema).encode("utf-8")
    model_entries = []
    for model_id, model_path in models:
        mode_entries = []
        for mode, enable_thinking in (("off", False), ("bounded", True)):
            with llama_server.LlamaServer(
                server,
                model_path,
                context_tokens=runtime["mac"]["contextTokens"],
            ) as client:
                template_payload = llama_server.build_template_payload(
                    system_prompt=prompt_bundle.system_prompt,
                    request=request,
                    enable_thinking=enable_thinking,
                    extra_messages=examples,
                )
                applied = client._post_json("/apply-template", template_payload, timeout=30)
                prompt = applied.get("prompt")
                if not isinstance(prompt, str):
                    raise ValueError(f"Applied template for {model_id}/{mode} has no prompt")
                suffix, suffix_shape = _template_suffix(prompt, request)
                grammar = coaching_grammar.strict_grammar(
                    schema,
                    enable_thinking=enable_thinking,
                )
                mode_entry = {
                    "mode": mode,
                    "grammarSHA256": _sha256_bytes(grammar.encode("utf-8")),
                    "applyTemplateSuffixSHA256": _sha256_bytes(suffix.encode("utf-8")),
                    "applyTemplateSuffixShape": suffix_shape,
                    "returnedFinalContentSHA256": None,
                    "returnedContentParsedJSON": False,
                    "returnedContentStrictValidationPassed": False,
                }
                try:
                    response = client.complete(
                        system_prompt=prompt_bundle.system_prompt,
                        request=request,
                        schema=schema,
                        seed=runtime["evaluation"]["seeds"][0],
                        maximum_output_tokens=runtime["generation"]["maximumOutputTokens"],
                        temperature=runtime["generation"]["temperature"],
                        top_p=runtime["generation"]["topP"],
                        enable_thinking=enable_thinking,
                        timeout=120,
                        extra_messages=examples,
                    )
                except llama_server.LlamaServerTimeout:
                    mode_entry["generationStatus"] = "timeout"
                    mode_entries.append(mode_entry)
                    continue
                except llama_server.LlamaServerError:
                    mode_entry["generationStatus"] = "generationError"
                    mode_entries.append(mode_entry)
                    continue
                try:
                    content = run_eval._final_content(response)
                    turn = json.loads(content)
                except (KeyError, IndexError, TypeError, ValueError, json.JSONDecodeError):
                    mode_entry["generationStatus"] = "invalidJSON"
                    mode_entries.append(mode_entry)
                    continue
                mode_entry["returnedFinalContentSHA256"] = _sha256_bytes(
                    content.encode("utf-8")
                )
                mode_entry["returnedContentParsedJSON"] = True
                validation_issues = validate_turn.validate_turn(turn, request)
                if validation_issues:
                    mode_entry["generationStatus"] = "strictValidationFailed"
                    mode_entry["validationIssueCount"] = len(validation_issues)
                else:
                    mode_entry["generationStatus"] = "success"
                    mode_entry["returnedContentStrictValidationPassed"] = True
                    mode_entry["validationIssueCount"] = 0
                mode_entries.append(mode_entry)
        model_entries.append(
            {
                "modelID": model_id,
                "modelArtifactSHA256": _sha256_file(model_path),
                "modes": mode_entries,
            }
        )
    result = {
        "schemaVersion": "coaching-eval-runtime-template-audit.v1",
        "runtimeProvenance": provenance,
        "schemaSHA256": _sha256_bytes(canonical_schema),
        "effectivePrompt": {
            "version": prompt_bundle.version,
            "promptSHA256": prompt_bundle.prompt_sha256,
            "examplesSHA256": prompt_bundle.examples_sha256,
        },
        "models": model_entries,
    }
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--schema",
        type=Path,
        default=TOOLS_DIR / "coaching-turn.schema.json",
    )
    parser.add_argument("--smoke-server", type=Path)
    parser.add_argument("--smoke-model", type=Path)
    parser.add_argument(
        "--audit-model",
        action="append",
        default=[],
        metavar="MODEL_ID=PATH",
        help="repeat for each exact model artifact in the runtime/template audit",
    )
    parser.add_argument("--audit-output", type=Path)
    parser.add_argument("--prompt-version")
    parser.add_argument("--runtime", type=Path, default=TOOLS_DIR / "runtime.json")
    parser.add_argument("--runtime-manifest", type=Path)
    arguments = parser.parse_args(argv)
    schema = json.loads(arguments.schema.read_text(encoding="utf-8"))
    runtime = json.loads(arguments.runtime.read_text(encoding="utf-8"))
    prompt_version = arguments.prompt_version or runtime["evaluation"]["promptVersion"]
    if bool(arguments.audit_model) != bool(arguments.audit_output):
        parser.error("--audit-model and --audit-output are required together")
    if arguments.audit_model:
        if arguments.smoke_model is not None:
            parser.error("--smoke-model cannot be combined with --audit-model")
        if arguments.smoke_server is None or arguments.runtime_manifest is None:
            parser.error("--smoke-server and --runtime-manifest are required for an audit")
        models = []
        for entry in arguments.audit_model:
            model_id, separator, path = entry.partition("=")
            if not separator or not model_id or not path:
                parser.error("--audit-model must have the form MODEL_ID=PATH")
            models.append((model_id, Path(path)))
        try:
            result = audit_runtime_templates(
                schema=schema,
                server=arguments.smoke_server,
                models=models,
                runtime_path=arguments.runtime,
                runtime_manifest=arguments.runtime_manifest,
                prompt_bundle=run_eval._load_prompt_bundle(
                    prompt_version,
                    TOOLS_DIR / "prompts",
                ),
                output=arguments.audit_output,
            )
        except (
            ValueError,
            OSError,
            llama_server.LlamaServerError,
            runtime_provenance.RuntimeProvenanceError,
        ) as error:
            print(str(error), file=sys.stderr)
            return 1
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    smoke_arguments = (
        arguments.smoke_server,
        arguments.smoke_model,
        arguments.runtime_manifest,
    )
    if any(smoke_arguments) and not all(smoke_arguments):
        parser.error("--smoke-server, --smoke-model, and --runtime-manifest are required together")
    if all(smoke_arguments):
        try:
            result = smoke_schema(
                schema=schema,
                server=arguments.smoke_server,
                model=arguments.smoke_model,
                runtime_path=arguments.runtime,
                runtime_manifest=arguments.runtime_manifest,
                prompt_version=prompt_version,
            )
        except (ValueError, OSError, llama_server.LlamaServerError, runtime_provenance.RuntimeProvenanceError) as error:
            print(str(error), file=sys.stderr)
            return 1
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    issues = b10516_compatibility_issues(schema)
    print(json.dumps({"compatible": not issues, "errors": issues}, indent=2, sort_keys=True))
    return 1 if issues else 0


if __name__ == "__main__":
    raise SystemExit(main())
