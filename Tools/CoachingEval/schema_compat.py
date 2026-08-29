#!/usr/bin/env python3
"""Preflight the coaching schema for llama.cpp b10516 grammar conversion."""

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

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


def smoke_schema(*, schema, server, model, runtime_path, runtime_manifest):
    issues = b10516_compatibility_issues(schema)
    if issues:
        raise ValueError("Schema failed deterministic b10516 compatibility: " + ", ".join(issues))
    provenance = runtime_provenance.verify_runtime(server, runtime_path, runtime_manifest)
    runtime = json.loads(Path(runtime_path).read_text(encoding="utf-8"))
    with llama_server.LlamaServer(
        server,
        model,
        context_tokens=runtime["mac"]["contextTokens"],
    ) as client:
        for mode, enable_thinking in (("off", False), ("bounded", True)):
            response = client.complete(
                system_prompt=ADVERSARIAL_SMOKE_PROMPT,
                request=SMOKE_REQUEST,
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
            validation_issues = validate_turn.validate_turn(turn, SMOKE_REQUEST)
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
        "smoke": "pinned-server-schema-and-validator-success",
        "smokeModes": ["off", "bounded"],
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--schema",
        type=Path,
        default=TOOLS_DIR / "coaching-turn.schema.json",
    )
    parser.add_argument("--smoke-server", type=Path)
    parser.add_argument("--smoke-model", type=Path)
    parser.add_argument("--runtime", type=Path, default=TOOLS_DIR / "runtime.json")
    parser.add_argument("--runtime-manifest", type=Path)
    arguments = parser.parse_args(argv)
    schema = json.loads(arguments.schema.read_text(encoding="utf-8"))
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
