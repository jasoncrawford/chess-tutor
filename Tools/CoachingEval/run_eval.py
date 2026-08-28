#!/usr/bin/env python3
"""Run reproducible coaching-turn evaluations through an OpenAI-compatible endpoint."""

import argparse
import dataclasses
import datetime
import hashlib
import json
import os
import re
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import llama_server
import model_store
import validate_turn


TOOLS_DIR = Path(__file__).resolve().parent
REPOSITORY_ROOT = TOOLS_DIR.parents[1]
ARTIFACT_ROOT = REPOSITORY_ROOT / ".coaching-eval"


@dataclasses.dataclass(frozen=True)
class ReferenceConfiguration:
    url: str
    model: str
    api_key: str
    consumed_environment_keys: tuple

    @classmethod
    def from_environment(cls, environment=None):
        environment = os.environ if environment is None else environment
        keys = (
            "COACHING_EVAL_REFERENCE_URL",
            "COACHING_EVAL_REFERENCE_MODEL",
            "COACHING_EVAL_REFERENCE_API_KEY",
        )
        values = [environment.get(key) for key in keys]
        if not all(values):
            missing = [key for key, value in zip(keys, values) if not value]
            raise ValueError("Missing reference configuration: " + ", ".join(missing))
        return cls(values[0], values[1], values[2], keys)


def canonical_json(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def _final_content(provider_response):
    choices = provider_response.get("choices", [])
    if not choices or not isinstance(choices[0], dict):
        raise ValueError("provider response has no choice")
    message = choices[0].get("message", {})
    content = message.get("content")
    if not isinstance(content, str):
        raise ValueError("provider response has no final string content")
    stripped = content.lstrip()
    if stripped.startswith("<think>"):
        closing = stripped.find("</think>")
        if closing < 0:
            return ""
        return stripped[closing + len("</think>"):].lstrip()
    return content


def _validation(raw_content, request):
    try:
        parsed = json.loads(raw_content)
    except (TypeError, ValueError) as error:
        return None, {"valid": False, "errors": [f"parse.invalidJSON:{error}"]}, True
    issues = validate_turn.validate_turn(parsed, request)
    return parsed, {"valid": not issues, "errors": issues}, any(
        issue.startswith("shape.") for issue in issues
    )


def _response_metrics(response):
    usage = response.get("usage", {})
    timings = response.get("timings", {})
    return {
        "promptTokens": int(usage.get("prompt_tokens", 0) or 0),
        "outputTokens": int(usage.get("completion_tokens", 0) or 0),
        "promptMilliseconds": float(timings.get("prompt_ms", 0.0) or 0.0),
        "generationMilliseconds": float(
            timings.get("predicted_ms", timings.get("generation_ms", 0.0)) or 0.0
        ),
    }


def _example_messages(examples):
    messages = []
    for example in examples:
        messages.append(
            {"role": "user", "content": canonical_json(example["requestExcerpt"])}
        )
        messages.append(
            {"role": "assistant", "content": canonical_json(example["turn"])}
        )
    return messages


class EvaluationRunner:
    def __init__(
        self,
        *,
        client,
        model_id,
        model_artifact_sha256,
        llama_cpp_version,
        system_prompt,
        examples,
        schema,
        context_tokens,
        maximum_output_tokens,
        temperature,
        top_p,
        request_timeout=120,
    ):
        self.client = client
        self.model_id = model_id
        self.model_artifact_sha256 = model_artifact_sha256
        self.llama_cpp_version = llama_cpp_version
        self.system_prompt = system_prompt
        self.examples = examples
        self.schema = schema
        self.context_tokens = context_tokens
        self.maximum_output_tokens = maximum_output_tokens
        self.temperature = temperature
        self.top_p = top_p
        self.request_timeout = request_timeout

    def evaluate_case(self, evaluation_case, *, mode, seed):
        request = evaluation_case["request"]
        request_bytes = canonical_json(request).encode("utf-8")
        example_messages = _example_messages(self.examples)
        prompt_payload = llama_server.build_chat_payload(
            system_prompt=self.system_prompt,
            request=request,
            schema=self.schema,
            seed=seed,
            maximum_output_tokens=self.maximum_output_tokens,
            temperature=self.temperature,
            top_p=self.top_p,
            enable_thinking=mode == "bounded",
            extra_messages=example_messages,
        )
        prompt_bytes = canonical_json(prompt_payload["messages"]).encode("utf-8")
        likely_overflow = len(prompt_bytes) > self.context_tokens * 4
        record = {
            "caseID": evaluation_case["id"],
            "caseSplit": evaluation_case["split"],
            "evaluationCase": evaluation_case,
            "modelID": self.model_id,
            "mode": mode,
            "seed": seed,
            "requestID": request.get("requestID"),
            "positionRevision": request.get("positionRevision"),
            "modelArtifactSHA256": self.model_artifact_sha256,
            "llamaCppVersion": self.llama_cpp_version,
            "promptVersion": request.get("promptVersion"),
            "requestUTF8Bytes": len(request_bytes),
            "requestSHA256": hashlib.sha256(request_bytes).hexdigest(),
            "requestCompacted": False,
            "promptEnvelopeUTF8Bytes": len(prompt_bytes),
            "promptEnvelopeSHA256": hashlib.sha256(prompt_bytes).hexdigest(),
            "preflight": {
                "status": "likelyContextOverflow" if likely_overflow else "withinByteHeuristic",
                "contextTokens": self.context_tokens,
                "heuristicUTF8BytesPerToken": 4,
            },
            "rawFinalContent": None,
            "firstAttemptRawFinalContent": None,
            "repairRawFinalContent": None,
            "parsedTurn": None,
            "firstAttemptValidation": {"valid": False, "errors": ["attempt.notRun"]},
            "repairAttempted": False,
            "repairValidation": None,
            "promptTokens": 0,
            "outputTokens": 0,
            "promptMilliseconds": 0.0,
            "generationMilliseconds": 0.0,
            "latencyMilliseconds": 0.0,
            "errors": [],
        }
        common = {
            "system_prompt": self.system_prompt,
            "request": request,
            "schema": self.schema,
            "seed": seed,
            "maximum_output_tokens": self.maximum_output_tokens,
            "temperature": self.temperature,
            "top_p": self.top_p,
            "enable_thinking": mode == "bounded",
            "timeout": self.request_timeout,
            "extra_messages": example_messages,
        }
        started = time.monotonic()
        try:
            first_response = self.client.complete(**common)
            first_content = _final_content(first_response)
            record["firstAttemptRawFinalContent"] = first_content
            record["rawFinalContent"] = first_content
            parsed, validation, repairable = _validation(first_content, request)
            record["parsedTurn"] = parsed
            record["firstAttemptValidation"] = validation
            self._add_metrics(record, first_response)

            if repairable:
                record["repairAttempted"] = True
                repair_messages = [
                    {"role": "assistant", "content": first_content},
                    {
                        "role": "user",
                        "content": (
                            "Return one corrected JSON object only. Fix parsing or schema shape. "
                            "Use the same request and only its permitted identifiers."
                        ),
                    },
                ]
                repaired_response = self.client.complete(**common, after_messages=repair_messages)
                repaired_content = _final_content(repaired_response)
                record["repairRawFinalContent"] = repaired_content
                repaired, repair_validation, _ = _validation(repaired_content, request)
                record["rawFinalContent"] = repaired_content
                record["parsedTurn"] = repaired
                record["repairValidation"] = repair_validation
                self._add_metrics(record, repaired_response)
        except (llama_server.LlamaServerError, OSError, ValueError) as error:
            message = str(error)
            category = "contextOverflow" if re.search(r"context|token.*(limit|exceed|size)", message, re.I) else "generationError"
            record["errors"].append({"kind": category, "message": message})
            record["preflight"]["serverOutcome"] = category
            transport_validation = {
                "valid": False,
                "errors": [f"transport.{category}"],
            }
            if record["repairAttempted"]:
                record["repairValidation"] = transport_validation
            else:
                record["firstAttemptValidation"] = transport_validation
        finally:
            record["latencyMilliseconds"] = (time.monotonic() - started) * 1000
        return record

    @staticmethod
    def _add_metrics(record, response):
        metrics = _response_metrics(response)
        for key, value in metrics.items():
            record[key] += value


def _load_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def _file_sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _load_cases(path, case_id=None):
    cases = [json.loads(line) for line in Path(path).read_text(encoding="utf-8").splitlines() if line]
    if case_id is not None:
        cases = [case for case in cases if case["id"] == case_id]
        if not cases:
            raise ValueError(f"Case {case_id} is absent from {path}")
    return cases


def _run_output_directory(base, split):
    timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    output = base / f"{split}-{timestamp}"
    output.mkdir(parents=True, exist_ok=False)
    return output


def _write_run(output, records, manifest):
    records_path = output / "records.jsonl"
    with records_path.open("w", encoding="utf-8") as destination:
        for record in records:
            destination.write(canonical_json(record) + "\n")
    manifest = dict(manifest)
    manifest["recordCount"] = len(records)
    manifest["recordsSHA256"] = hashlib.sha256(records_path.read_bytes()).hexdigest()
    (output / "run-manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def _fake_turn_for(request):
    permitted = request["permittedReferences"]
    evidence = permitted.get("evidence", [])
    if not evidence:
        raise ValueError("fake model requires at least one permitted evidence ID")
    board_tasks = permitted.get("boardTasks", [])
    board_focus = permitted.get("boardFocus", [])
    return {
        "schemaVersion": "model-coaching-turn.v1",
        "requestID": request["requestID"],
        "teachingIntent": "other",
        "primaryMessage": "Choose one move and look at the board.",
        "instruction": "Use the board to show your choice.",
        "responseToLatestAction": None,
        "actionReferences": [],
        "boardTaskReference": board_tasks[0]["id"] if board_tasks else None,
        "boardFocusReferences": board_focus[:1],
        "relationshipReferences": [],
        "supportingEvidenceReferences": evidence[:1],
    }


def _fake_server(argv):
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("-m")
    parser.add_argument("-c")
    parser.add_argument("--host")
    parser.add_argument("--port", type=int)
    arguments = parser.parse_args(argv)

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != "/health":
                self.send_error(404)
                return
            body = b'{"status":"ok"}'
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self):
            size = int(self.headers["Content-Length"])
            payload = json.loads(self.rfile.read(size))
            request = None
            for message in reversed(payload.get("messages", [])):
                if message.get("role") != "user":
                    continue
                try:
                    candidate = json.loads(message.get("content", ""))
                except ValueError:
                    continue
                if isinstance(candidate, dict) and "requestID" in candidate:
                    request = candidate
                    break
            if request is None:
                self.send_error(400, "missing request JSON")
                return
            content = "<think>test-only trace</think>\n" + canonical_json(_fake_turn_for(request))
            body = json.dumps(
                {
                    "choices": [{"message": {"content": content, "reasoning_content": "discard me"}}],
                    "usage": {
                        "prompt_tokens": max(1, size // 4),
                        "completion_tokens": max(1, len(content) // 4),
                    },
                    "timings": {"prompt_ms": 1.25, "predicted_ms": 2.5},
                }
            ).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, _format, *_arguments):
            return

    ThreadingHTTPServer((arguments.host, arguments.port), Handler).serve_forever()


def _candidate(identifier):
    for candidate in model_store.load_models():
        if candidate["id"] == identifier:
            return candidate
    raise ValueError(f"Unknown local model: {identifier}")


def _selected_modes(candidate, requested_mode):
    supported = candidate["thinkingModes"]
    if requested_mode is None:
        return supported
    if requested_mode not in supported:
        raise ValueError(f"Model does not support thinking mode {requested_mode}")
    return [requested_mode]


def _runner(client, model_id, artifact_hash, version):
    runtime = _load_json(TOOLS_DIR / "runtime.json")
    return EvaluationRunner(
        client=client,
        model_id=model_id,
        model_artifact_sha256=artifact_hash,
        llama_cpp_version=version,
        system_prompt=(TOOLS_DIR / "prompts" / "tutor-v1.md").read_text(encoding="utf-8"),
        examples=_load_json(TOOLS_DIR / "prompts" / "examples-v1.json"),
        schema=_load_json(TOOLS_DIR / "coaching-turn.schema.json"),
        context_tokens=runtime["mac"]["contextTokens"],
        maximum_output_tokens=runtime["generation"]["maximumOutputTokens"],
        temperature=runtime["generation"]["temperature"],
        top_p=runtime["generation"]["topP"],
    )


def _execute(arguments):
    runtime = _load_json(TOOLS_DIR / "runtime.json")
    corpus_path = Path(arguments.corpus or ARTIFACT_ROOT / "corpus" / "v1" / f"{arguments.split}.jsonl")
    cases = _load_cases(corpus_path, arguments.case)
    repetitions = (
        runtime["evaluation"]["repetitions"]
        if arguments.repetitions is None
        else arguments.repetitions
    )
    seeds = runtime["evaluation"]["seeds"]
    if repetitions < 1:
        raise ValueError(f"Repetitions must be from 1 through {len(seeds)}")
    if repetitions > len(seeds):
        raise ValueError(f"At most {len(seeds)} pinned repetitions are available")

    server = None
    if arguments.provider == "local":
        if arguments.model == "fake-test-model":
            if os.environ.get("COACHING_EVAL_ALLOW_FAKE") != "1":
                raise ValueError("fake-test-model requires COACHING_EVAL_ALLOW_FAKE=1")
            environment = dict(os.environ)
            environment["COACHING_EVAL_INTERNAL_FAKE_SERVER"] = "1"
            server = llama_server.LlamaServer(
                Path(__file__),
                TOOLS_DIR / "runtime.json",
                context_tokens=runtime["mac"]["contextTokens"],
                command_prefix=[sys.executable],
                environment=environment,
            )
            artifact_hash = hashlib.sha256(b"fake-test-model").hexdigest()
            version = runtime["llamaCppTag"] + "-fake"
            modes = [arguments.mode or "off"]
        else:
            candidate = _candidate(arguments.model)
            store = model_store.ModelStore()
            if not store.verify(candidate):
                raise ValueError(f"Model is missing or failed verification: {arguments.model}")
            artifact_manifest = _load_json(
                model_store.DEFAULT_STORE_ROOT / candidate["id"] / "artifact-manifest.json"
            )
            artifact_path = model_store.DEFAULT_STORE_ROOT / candidate["id"] / artifact_manifest["filename"]
            executable = ARTIFACT_ROOT / "runtime" / runtime["llamaCppTag"] / "bin" / "llama-server"
            if not executable.is_file():
                raise ValueError(f"Pinned llama-server is missing: {executable}")
            server = llama_server.LlamaServer(
                executable,
                artifact_path,
                context_tokens=runtime["mac"]["contextTokens"],
            )
            artifact_hash = artifact_manifest["sha256"]
            version = runtime["llamaCppTag"]
            modes = _selected_modes(candidate, arguments.mode)
        client = server
        model_id = arguments.model
    else:
        reference = ReferenceConfiguration.from_environment()
        client = llama_server.OpenAIChatClient(
            reference.url, api_key=reference.api_key, model=reference.model
        )
        model_id = "reference-" + re.sub(r"[^A-Za-z0-9._-]+", "-", reference.model)
        artifact_hash = "online-reference"
        version = "online-reference"
        modes = [arguments.mode or "off"]

    runner = _runner(client, model_id, artifact_hash, version)
    records = []
    try:
        if server is not None:
            server.start()
        for mode in modes:
            for evaluation_case in cases:
                for seed in seeds[:repetitions]:
                    if server is not None and not server.is_running:
                        server.start()
                    records.append(runner.evaluate_case(evaluation_case, mode=mode, seed=seed))
    finally:
        if server is not None:
            server.stop()

    base = ARTIFACT_ROOT / "runs" / model_id
    output = _run_output_directory(base, arguments.split)
    manifest = {
        "modelID": model_id,
        "provider": arguments.provider,
        "transport": "openai-compatible-http",
        "split": arguments.split,
        "corpusPath": str(corpus_path.resolve()),
        "corpusSHA256": _file_sha256(corpus_path),
        "promptVersion": "tutor-v1",
        "promptSHA256": _file_sha256(TOOLS_DIR / "prompts" / "tutor-v1.md"),
        "examplesSHA256": _file_sha256(TOOLS_DIR / "prompts" / "examples-v1.json"),
        "schemaVersion": "model-coaching-turn.v1",
        "schemaSHA256": _file_sha256(TOOLS_DIR / "coaching-turn.schema.json"),
        "runtimeSHA256": _file_sha256(TOOLS_DIR / "runtime.json"),
        "modelArtifactSHA256": artifact_hash,
        "llamaCppVersion": version,
        "contextTokens": runtime["mac"]["contextTokens"],
        "maximumOutputTokens": runtime["generation"]["maximumOutputTokens"],
        "temperature": runtime["generation"]["temperature"],
        "topP": runtime["generation"]["topP"],
        "modes": modes,
        "seeds": seeds[:repetitions],
    }
    _write_run(output, records, manifest)
    print(output)
    return 0


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if os.environ.get("COACHING_EVAL_INTERNAL_FAKE_SERVER") == "1" and "--port" in argv:
        _fake_server(argv)
        return 0
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="provider", required=True)
    local = subparsers.add_parser("local")
    local.add_argument("--model", required=True)
    reference = subparsers.add_parser("reference")
    for subparser in (local, reference):
        subparser.add_argument("--split", choices=("visible", "hidden"), required=True)
        subparser.add_argument("--case")
        subparser.add_argument("--repetitions", type=int)
        subparser.add_argument("--mode", choices=("off", "bounded"))
        subparser.add_argument("--corpus")
    arguments = parser.parse_args(argv)
    try:
        return _execute(arguments)
    except (ValueError, OSError, model_store.ModelStoreError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
