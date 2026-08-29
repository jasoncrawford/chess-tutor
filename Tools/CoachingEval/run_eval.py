#!/usr/bin/env python3
"""Run reproducible coaching-turn evaluations through an OpenAI-compatible endpoint."""

import argparse
import copy
import dataclasses
import datetime
import hashlib
import json
import os
import re
import shutil
import sys
import tempfile
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import llama_server
import coaching_grammar
import compact_context
import model_store
import render_transcript
import runtime_provenance as provenance
import validate_turn


TOOLS_DIR = Path(__file__).resolve().parent
REPOSITORY_ROOT = TOOLS_DIR.parents[1]
ARTIFACT_ROOT = REPOSITORY_ROOT / ".coaching-eval"
THINKING_BLOCK = re.compile(
    r"<\s*think\b[^>]*>.*?<\s*/\s*think\s*>", re.IGNORECASE | re.DOTALL
)
THINKING_MARKER = re.compile(r"<\s*/?\s*think\b", re.IGNORECASE)
TURN_REQUIRED_PROPERTY_ORDER = (
    "schemaVersion",
    "requestID",
    "teachingIntent",
    "primaryMessage",
    "actionReferences",
    "boardFocusReferences",
    "relationshipReferences",
    "supportingEvidenceReferences",
)
TURN_OPTIONAL_PROPERTY_ORDER = (
    "instruction",
    "responseToLatestAction",
    "boardTaskReference",
)
COMPACT_MARKDOWN_PILOT_CASE_IDS = (
    "t1Entry",
    "t3Entry",
    "t7NoSafeCapture",
    "t1PreferredKnight",
    "t11UnsafeBishopFound",
    "t11Safe",
    "t11BenignCaptureTap",
    "t12Block",
    "t9Hint",
    "t12UnsupportedEntry",
)
COMPACT_CONTEXT_PROMPT_VERSIONS = frozenset(("tutor-v3", "tutor-v4"))


def _uses_compact_context(prompt_version):
    return prompt_version in COMPACT_CONTEXT_PROMPT_VERSIONS


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


@dataclasses.dataclass(frozen=True)
class PromptBundle:
    version: str
    system_prompt: str
    examples: list
    prompt_path: Path
    examples_path: Path
    prompt_sha256: str
    examples_sha256: str


def canonical_json(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def _without_thinking_traces(text, *, discard_prefix_before_json=False):
    had_block = THINKING_BLOCK.search(text) is not None
    text = THINKING_BLOCK.sub("", text)
    if THINKING_MARKER.search(text):
        return ""
    text = text.strip()
    if had_block and discard_prefix_before_json:
        json_start = text.find("{")
        if json_start >= 0:
            text = text[json_start:]
    return text


def _final_content(provider_response):
    choices = provider_response.get("choices", [])
    if not choices or not isinstance(choices[0], dict):
        raise ValueError("provider response has no choice")
    message = choices[0].get("message", {})
    content = message.get("content")
    if not isinstance(content, str):
        raise ValueError("provider response has no final string content")
    return _without_thinking_traces(content, discard_prefix_before_json=True)


def _persistable_provider_error(error):
    """Return a bounded classification and message without retaining provider text."""
    category = getattr(error, "category", None)
    inferred_context_overflow = llama_server.CONTEXT_OVERFLOW_BODY.search(str(error))
    if inferred_context_overflow:
        category = "contextOverflow"
    elif category not in llama_server.ERROR_CATEGORIES:
        category = "generationError"
    if category == "contextOverflow":
        return category, "Provider request exceeded the context window."
    status = getattr(error, "http_status", None)
    if isinstance(status, int):
        return category, f"Provider request failed with HTTP {status}."
    if isinstance(error, llama_server.LlamaServerTimeout):
        return category, "Provider response timed out."
    return category, "Provider generation failed."


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


def _effective_request(frozen_request, prompt_version):
    effective = copy.deepcopy(frozen_request)
    frozen_version = effective.get("promptVersion")
    effective["promptVersion"] = prompt_version
    mutations = []
    if frozen_version != prompt_version:
        mutations.append(
            {
                "field": "promptVersion",
                "frozen": frozen_version,
                "effective": prompt_version,
            }
        )
    return effective, mutations


def _serialize_assistant_turn(turn):
    permitted = set(TURN_REQUIRED_PROPERTY_ORDER + TURN_OPTIONAL_PROPERTY_ORDER)
    missing = [key for key in TURN_REQUIRED_PROPERTY_ORDER if key not in turn]
    unknown = sorted(set(turn) - permitted)
    if missing or unknown:
        raise ValueError(
            f"Assistant example does not match coaching turn shape; missing={missing}, unknown={unknown}"
        )
    ordered = {key: turn[key] for key in TURN_REQUIRED_PROPERTY_ORDER}
    ordered.update(
        (key, turn[key]) for key in TURN_OPTIONAL_PROPERTY_ORDER if key in turn
    )
    return json.dumps(ordered, ensure_ascii=False, separators=(",", ":"))


def _example_messages(examples, *, prompt_version):
    messages = []
    for example in examples:
        if _uses_compact_context(prompt_version):
            user_content = example["contextMarkdown"]
        else:
            effective_excerpt, _mutations = _effective_request(
                example["requestExcerpt"], prompt_version
            )
            user_content = canonical_json(effective_excerpt)
        messages.append(
            {"role": "user", "content": user_content}
        )
        messages.append(
            {"role": "assistant", "content": _serialize_assistant_turn(example["turn"])}
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
        evaluator_prompt_version="test-prompt",
        runtime_provenance_record=None,
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
        self.evaluator_prompt_version = evaluator_prompt_version
        self.runtime_provenance_record = dict(runtime_provenance_record or {})

    def evaluate_case(self, evaluation_case, *, mode, seed):
        if _uses_compact_context(self.evaluator_prompt_version):
            return self._evaluate_compact_case(evaluation_case, mode=mode, seed=seed)
        return self._evaluate_legacy_case(evaluation_case, mode=mode, seed=seed)

    def _evaluate_legacy_case(self, evaluation_case, *, mode, seed):
        frozen_request = evaluation_case["request"]
        request, request_mutations = _effective_request(
            frozen_request, self.evaluator_prompt_version
        )
        effective_evaluation_case = copy.deepcopy(evaluation_case)
        effective_evaluation_case["request"] = request
        frozen_request_bytes = canonical_json(frozen_request).encode("utf-8")
        request_bytes = canonical_json(request).encode("utf-8")
        example_messages = _example_messages(
            self.examples,
            prompt_version=self.evaluator_prompt_version,
        )
        prompt_payload = llama_server.build_template_payload(
            system_prompt=self.system_prompt,
            request=request,
            enable_thinking=mode == "bounded",
            extra_messages=example_messages,
        )
        prompt_bytes = canonical_json(prompt_payload).encode("utf-8")
        likely_overflow = len(prompt_bytes) > self.context_tokens * 4
        record = {
            "caseID": evaluation_case["id"],
            "caseSplit": evaluation_case["split"],
            "evaluationCase": effective_evaluation_case,
            "modelID": self.model_id,
            "mode": mode,
            "seed": seed,
            "requestID": request.get("requestID"),
            "positionRevision": request.get("positionRevision"),
            "modelArtifactSHA256": self.model_artifact_sha256,
            "llamaCppVersion": self.llama_cpp_version,
            "runtimeProvenance": self.runtime_provenance_record,
            "evaluatorPromptVersion": self.evaluator_prompt_version,
            "promptVersion": request.get("promptVersion"),
            "requestUTF8Bytes": len(request_bytes),
            "requestSHA256": hashlib.sha256(request_bytes).hexdigest(),
            "frozenRequestSHA256": hashlib.sha256(frozen_request_bytes).hexdigest(),
            "effectiveRequestSHA256": hashlib.sha256(request_bytes).hexdigest(),
            "requestMutations": request_mutations,
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
            category, message = _persistable_provider_error(error)
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

    def _evaluate_compact_case(self, evaluation_case, *, mode, seed):
        frozen_request = evaluation_case["request"]
        request, request_mutations = _effective_request(
            frozen_request, self.evaluator_prompt_version
        )
        effective_evaluation_case = copy.deepcopy(evaluation_case)
        effective_evaluation_case["request"] = request
        compilation = evaluation_case.get("compactContext", {})
        markdown = compilation.get("markdown", "")
        frozen_request_bytes = canonical_json(frozen_request).encode("utf-8")
        request_bytes = canonical_json(request).encode("utf-8")
        markdown_bytes = markdown.encode("utf-8") if isinstance(markdown, str) else b""
        example_messages = _example_messages(
            self.examples,
            prompt_version=self.evaluator_prompt_version,
        )
        record = {
            "caseID": evaluation_case["id"],
            "caseSplit": evaluation_case["split"],
            "evaluationCase": effective_evaluation_case,
            "modelID": self.model_id,
            "mode": mode,
            "seed": seed,
            "requestID": request.get("requestID"),
            "positionRevision": request.get("positionRevision"),
            "modelArtifactSHA256": self.model_artifact_sha256,
            "llamaCppVersion": self.llama_cpp_version,
            "runtimeProvenance": self.runtime_provenance_record,
            "evaluatorPromptVersion": self.evaluator_prompt_version,
            "promptVersion": request.get("promptVersion"),
            "requestUTF8Bytes": len(request_bytes),
            "requestSHA256": hashlib.sha256(request_bytes).hexdigest(),
            "frozenRequestSHA256": hashlib.sha256(frozen_request_bytes).hexdigest(),
            "effectiveRequestSHA256": hashlib.sha256(request_bytes).hexdigest(),
            "requestMutations": request_mutations,
            "requestCompacted": False,
            "modelInputFormat": "compactMarkdown",
            "modelInputMarkdownUTF8Bytes": len(markdown_bytes),
            "modelInputMarkdownSHA256": hashlib.sha256(markdown_bytes).hexdigest(),
            "renderedPromptUTF8Bytes": 0,
            "renderedPromptSHA256": None,
            "renderedPromptTokens": 0,
            "grammarUTF8Bytes": 0,
            "grammarSHA256": None,
            "generationStatus": "notStarted",
            "generationAttempted": False,
            "rawFinalContent": None,
            "firstAttemptRawFinalContent": None,
            "repairRawFinalContent": None,
            "aliasTurn": None,
            "aliasTurnUTF8Bytes": 0,
            "aliasTurnSHA256": None,
            "stableTurn": None,
            "stableTurnUTF8Bytes": 0,
            "stableTurnSHA256": None,
            "parsedTurn": None,
            "aliasRestorationErrors": [],
            "firstAttemptValidation": {"valid": False, "errors": ["attempt.notRun"]},
            "repairAttempted": False,
            "repairValidation": None,
            "repairRenderedPromptTokens": None,
            "repairRenderedPromptUTF8Bytes": None,
            "repairRenderedPromptSHA256": None,
            "promptTokens": 0,
            "outputTokens": 0,
            "promptMilliseconds": 0.0,
            "generationMilliseconds": 0.0,
            "latencyMilliseconds": 0.0,
            "errors": [],
        }
        started = time.monotonic()
        rendered_prompt = ""
        repair_rendered_prompt = None
        compilation_issues = compact_context.validate_compilation(evaluation_case)
        if compilation_issues:
            record["generationStatus"] = "compilerValidationFailed"
            record["firstAttemptValidation"] = {
                "valid": False,
                "errors": compilation_issues,
            }
            record["errors"].append(
                {
                    "kind": "compilerValidationFailed",
                    "message": "Compact context failed deterministic validation.",
                }
            )
            return self._finish_compact_record(record, rendered_prompt, started)

        aliases = compact_context.permitted_aliases(compilation)
        try:
            rendered_prompt = self.client.render_prompt(
                system_prompt=self.system_prompt,
                user_content=markdown,
                enable_thinking=mode == "bounded",
                timeout=self.request_timeout,
                extra_messages=example_messages,
            )
            self._record_rendered_prompt(record, rendered_prompt)
            record["renderedPromptTokens"] = self.client.token_count(
                rendered_prompt,
                timeout=self.request_timeout,
            )
            if record["renderedPromptTokens"] > 4000:
                record["generationStatus"] = "compilerBudgetExceeded"
                record["firstAttemptValidation"] = {
                    "valid": False,
                    "errors": ["transport.compilerBudgetExceeded"],
                }
                return self._finish_compact_record(record, rendered_prompt, started)

            grammar = coaching_grammar.strict_grammar(
                self.schema,
                enable_thinking=mode == "bounded",
                request_id=request["requestID"],
                permitted_aliases=aliases,
            )
            grammar_bytes = grammar.encode("utf-8")
            record["grammarUTF8Bytes"] = len(grammar_bytes)
            record["grammarSHA256"] = hashlib.sha256(grammar_bytes).hexdigest()
            record["generationAttempted"] = True
            record["generationStatus"] = "generated"
            first_response = self.client.complete_rendered(
                prompt=rendered_prompt,
                grammar=grammar,
                seed=seed,
                maximum_output_tokens=self.maximum_output_tokens,
                temperature=self.temperature,
                top_p=self.top_p,
                timeout=self.request_timeout,
            )
            first_content = _final_content(first_response)
            record["firstAttemptRawFinalContent"] = first_content
            record["rawFinalContent"] = first_content
            repairable = self._record_compact_turn(
                record,
                first_content,
                request,
                compilation,
                validation_field="firstAttemptValidation",
            )
            self._add_metrics(record, first_response)

            if repairable:
                record["repairAttempted"] = True
                repair_messages = [
                    {"role": "assistant", "content": first_content},
                    {
                        "role": "user",
                        "content": (
                            "Return one corrected JSON object only. Fix parsing or schema shape. "
                            "Use only aliases listed in this coaching context."
                        ),
                    },
                ]
                repair_prompt = self.client.render_prompt(
                    system_prompt=self.system_prompt,
                    user_content=markdown,
                    enable_thinking=mode == "bounded",
                    timeout=self.request_timeout,
                    extra_messages=example_messages,
                    after_messages=repair_messages,
                )
                repair_rendered_prompt = repair_prompt
                repair_bytes = repair_prompt.encode("utf-8")
                record["repairRenderedPromptUTF8Bytes"] = len(repair_bytes)
                record["repairRenderedPromptSHA256"] = hashlib.sha256(repair_bytes).hexdigest()
                repair_tokens = self.client.token_count(
                    repair_prompt,
                    timeout=self.request_timeout,
                )
                record["repairRenderedPromptTokens"] = repair_tokens
                if repair_tokens > 4000:
                    record["generationStatus"] = "repairBudgetExceeded"
                    record["repairValidation"] = {
                        "valid": False,
                        "errors": ["transport.repairBudgetExceeded"],
                    }
                else:
                    repaired_response = self.client.complete_rendered(
                        prompt=repair_prompt,
                        grammar=grammar,
                        seed=seed,
                        maximum_output_tokens=self.maximum_output_tokens,
                        temperature=self.temperature,
                        top_p=self.top_p,
                        timeout=self.request_timeout,
                    )
                    repaired_content = _final_content(repaired_response)
                    record["repairRawFinalContent"] = repaired_content
                    record["rawFinalContent"] = repaired_content
                    self._record_compact_turn(
                        record,
                        repaired_content,
                        request,
                        compilation,
                        validation_field="repairValidation",
                    )
                    self._add_metrics(record, repaired_response)
        except (llama_server.LlamaServerError, OSError, ValueError) as error:
            category, message = _persistable_provider_error(error)
            record["generationStatus"] = category
            record["errors"].append({"kind": category, "message": message})
            transport_validation = {
                "valid": False,
                "errors": [f"transport.{category}"],
            }
            if record["repairAttempted"]:
                record["repairValidation"] = transport_validation
            else:
                record["firstAttemptValidation"] = transport_validation
        return self._finish_compact_record(
            record, rendered_prompt, started, repair_rendered_prompt
        )

    @staticmethod
    def _record_rendered_prompt(record, prompt):
        prompt_bytes = prompt.encode("utf-8")
        record["renderedPromptUTF8Bytes"] = len(prompt_bytes)
        record["renderedPromptSHA256"] = hashlib.sha256(prompt_bytes).hexdigest()

    @staticmethod
    def _record_compact_turn(record, content, request, compilation, *, validation_field):
        record["aliasTurnUTF8Bytes"] = 0
        record["aliasTurnSHA256"] = None
        record["stableTurnUTF8Bytes"] = 0
        record["stableTurnSHA256"] = None
        try:
            alias_turn = json.loads(content)
        except (TypeError, ValueError) as error:
            record["aliasTurn"] = None
            record["stableTurn"] = None
            record["parsedTurn"] = None
            record[validation_field] = {
                "valid": False,
                "errors": [f"parse.invalidJSON:{error}"],
            }
            return True
        if not isinstance(alias_turn, dict):
            record["aliasTurn"] = alias_turn
            record["stableTurn"] = None
            record["parsedTurn"] = None
            record[validation_field] = {
                "valid": False,
                "errors": ["shape.rootMustBeObject"],
            }
            return True
        alias_bytes = canonical_json(alias_turn).encode("utf-8")
        record["aliasTurnUTF8Bytes"] = len(alias_bytes)
        record["aliasTurnSHA256"] = hashlib.sha256(alias_bytes).hexdigest()
        stable_turn, alias_issues = compact_context.restore_stable_turn(
            alias_turn, compilation
        )
        stable_issues = validate_turn.validate_turn(stable_turn, request)
        issues = sorted(set(alias_issues + stable_issues))
        record["aliasTurn"] = alias_turn
        record["stableTurn"] = stable_turn if not alias_issues else None
        record["parsedTurn"] = stable_turn if not alias_issues else None
        if not alias_issues:
            stable_bytes = canonical_json(stable_turn).encode("utf-8")
            record["stableTurnUTF8Bytes"] = len(stable_bytes)
            record["stableTurnSHA256"] = hashlib.sha256(stable_bytes).hexdigest()
        else:
            record["stableTurnUTF8Bytes"] = 0
            record["stableTurnSHA256"] = None
        record["aliasRestorationErrors"] = alias_issues
        record[validation_field] = {"valid": not issues, "errors": issues}
        return any(issue.startswith("shape.") for issue in issues)

    @staticmethod
    def _finish_compact_record(
        record, rendered_prompt, started, repair_rendered_prompt=None
    ):
        record["latencyMilliseconds"] = (time.monotonic() - started) * 1000
        record["_transcriptMarkdown"] = render_transcript.render_transcript(
            record,
            rendered_prompt=rendered_prompt,
            repair_rendered_prompt=repair_rendered_prompt,
            environment={},
        )
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


def _load_prompt_bundle(version, prompt_root=None):
    if re.fullmatch(r"tutor-v[1-9][0-9]*", version or "") is None:
        raise ValueError("Prompt version must be an immutable tutor-v<number> identifier")
    prompt_root = Path(prompt_root or TOOLS_DIR / "prompts")
    suffix = version.removeprefix("tutor-")
    prompt_path = prompt_root / f"{version}.md"
    examples_path = prompt_root / f"examples-{suffix}.json"
    if not prompt_path.is_file() or not examples_path.is_file():
        raise ValueError(f"Prompt bundle {version} is incomplete under {prompt_root}")
    return PromptBundle(
        version=version,
        system_prompt=prompt_path.read_text(encoding="utf-8"),
        examples=_load_json(examples_path),
        prompt_path=prompt_path,
        examples_path=examples_path,
        prompt_sha256=_file_sha256(prompt_path),
        examples_sha256=_file_sha256(examples_path),
    )


def _load_cases(path, case_id=None):
    cases = [json.loads(line) for line in Path(path).read_text(encoding="utf-8").splitlines() if line]
    if case_id is not None:
        cases = [case for case in cases if case["id"] == case_id]
        if not cases:
            raise ValueError(f"Case {case_id} is absent from {path}")
    return cases


def _select_case_list(cases, path, *, split):
    manifest = _load_json(path)
    case_ids = manifest.get("caseIDs")
    if not isinstance(case_ids, list) or len(case_ids) != len(set(case_ids)):
        raise ValueError("Pilot case list contains a duplicate or invalid case ID")
    if (
        manifest.get("schemaVersion") != "coaching-eval-pilot.v1"
        or manifest.get("id") != "compact-markdown-v1"
        or tuple(case_ids) != COMPACT_MARKDOWN_PILOT_CASE_IDS
    ):
        raise ValueError("Pilot case list must contain the exact fixed pilot IDs in order")
    if split != "visible":
        raise ValueError("Pilot case list may be used only with the visible split")
    by_id = {}
    for case in cases:
        identifier = case.get("id")
        if identifier in by_id:
            raise ValueError(f"Corpus contains duplicate case ID: {identifier}")
        by_id[identifier] = case
    missing = [identifier for identifier in case_ids if identifier not in by_id]
    if missing:
        raise ValueError(f"Pilot case list is missing corpus cases: {missing}")
    selected = [by_id[identifier] for identifier in case_ids]
    hidden = [case["id"] for case in selected if case.get("split") != "visible"]
    if hidden:
        raise ValueError(f"Pilot case list contains hidden or mislabeled cases: {hidden}")
    return selected


def _run_output_directory(base, split):
    timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    return base / f"{split}-{timestamp}"


def _write_run(output, records, manifest):
    output = Path(output)
    if output.exists():
        raise ValueError(f"Refusing to overwrite existing run directory: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(
        tempfile.mkdtemp(prefix=f".{output.name}.tmp-", dir=str(output.parent))
    )
    try:
        transcript_root = temporary / "transcripts"
        persisted_records = []
        transcript_names = set()
        for source_record in records:
            record = dict(source_record)
            transcript = record.pop("_transcriptMarkdown", None)
            if transcript is not None:
                components = (record.get("caseID"), record.get("mode"), record.get("seed"))
                if not all(
                    isinstance(value, (str, int))
                    and re.fullmatch(r"[A-Za-z0-9._-]+", str(value))
                    for value in components
                ):
                    raise ValueError(f"Unsafe transcript identity: {components}")
                name = "--".join(str(value) for value in components) + ".md"
                if name in transcript_names:
                    raise ValueError(f"Duplicate transcript identity: {name}")
                transcript_names.add(name)
                transcript_root.mkdir(exist_ok=True)
                transcript_path = transcript_root / name
                _write_fsynced(transcript_path, transcript)
                relative = transcript_path.relative_to(temporary)
                record["transcriptPath"] = str(relative)
                record["transcriptSHA256"] = hashlib.sha256(
                    transcript_path.read_bytes()
                ).hexdigest()
            persisted_records.append(record)

        records_path = temporary / "records.jsonl"
        _write_fsynced(
            records_path,
            "".join(canonical_json(record) + "\n" for record in persisted_records),
        )
        manifest = dict(manifest)
        manifest["recordCount"] = len(persisted_records)
        manifest["recordsSHA256"] = hashlib.sha256(records_path.read_bytes()).hexdigest()
        _write_fsynced(
            temporary / "run-manifest.json",
            json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        )
        directory_descriptor = os.open(temporary, os.O_RDONLY)
        try:
            os.fsync(directory_descriptor)
        finally:
            os.close(directory_descriptor)
        os.replace(temporary, output)
        parent_descriptor = os.open(output.parent, os.O_RDONLY)
        try:
            os.fsync(parent_descriptor)
        finally:
            os.close(parent_descriptor)
    except Exception:
        shutil.rmtree(temporary, ignore_errors=True)
        raise


def _write_fsynced(path, content):
    with Path(path).open("w", encoding="utf-8") as destination:
        destination.write(content)
        destination.flush()
        os.fsync(destination.fileno())


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


def _fake_alias_turn_for(markdown):
    request_match = re.search(r"^- Request: `([^`]+)`$", markdown, re.MULTILINE)
    aliases = sorted(set(re.findall(r"\b(?:fact|move|reply)-[a-z0-9-]+\b", markdown)))
    if request_match is None or not aliases:
        raise ValueError("fake model requires a compact request ID and evidence alias")
    return {
        "schemaVersion": "model-coaching-turn.v1",
        "requestID": request_match.group(1),
        "teachingIntent": "other",
        "primaryMessage": "Choose one move and look at the board.",
        "actionReferences": [],
        "boardFocusReferences": [],
        "relationshipReferences": [],
        "supportingEvidenceReferences": [aliases[0]],
        "instruction": "Use the board to show your choice.",
        "responseToLatestAction": None,
        "boardTaskReference": None,
    }


def _fake_server(argv):
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("-m")
    parser.add_argument("-c")
    parser.add_argument("--host")
    parser.add_argument("--port", type=int)
    arguments = parser.parse_args(argv)
    state = {"templatePayload": None}

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
            if self.path == "/apply-template":
                state["templatePayload"] = payload
                prompt = "".join(
                    "<|im_start|>{role}\n{content}<|im_end|>\n".format(**message)
                    for message in payload["messages"]
                ) + "<|im_start|>assistant\n"
                body = json.dumps({"prompt": prompt}).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            if self.path == "/tokenize":
                body = json.dumps({"count": 2000}).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            if os.environ.get("COACHING_EVAL_FAKE_HTTP_ERROR") == "reasoning":
                body = json.dumps(
                    {
                        "error": {
                            "message": "secret provider body",
                            "ReAsOnInG_CoNtEnT": "PRIVATE NESTED REASONING",
                            "details": {
                                "reasoningContent": "PRIVATE CAMEL REASONING",
                                "trace": "<THINK>PRIVATE TRACE</THINK>",
                            },
                        }
                    }
                ).encode("utf-8")
                self.send_response(422)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            template_payload = state.get("templatePayload") or {}
            request = None
            for message in reversed(template_payload.get("messages", [])):
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
                messages = template_payload.get("messages", [])
                markdown = messages[-1].get("content", "") if messages else ""
                try:
                    turn = _fake_alias_turn_for(markdown)
                except ValueError:
                    self.send_error(400, "missing request JSON or compact Markdown")
                    return
            else:
                turn = _fake_turn_for(request)
            content = "<think>test-only trace</think>\n" + canonical_json(turn)
            body = json.dumps(
                {
                    "content": content,
                    "stop_type": "eos",
                    "timings": {
                        "prompt_n": max(1, size // 4),
                        "predicted_n": max(1, len(content) // 4),
                        "prompt_ms": 1.25,
                        "predicted_ms": 2.5,
                    },
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


def _runner(client, model_id, artifact_hash, version, prompt_bundle, runtime_record):
    runtime = _load_json(TOOLS_DIR / "runtime.json")
    return EvaluationRunner(
        client=client,
        model_id=model_id,
        model_artifact_sha256=artifact_hash,
        llama_cpp_version=version,
        system_prompt=prompt_bundle.system_prompt,
        examples=prompt_bundle.examples,
        schema=_load_json(TOOLS_DIR / "coaching-turn.schema.json"),
        context_tokens=runtime["mac"]["contextTokens"],
        maximum_output_tokens=runtime["generation"]["maximumOutputTokens"],
        temperature=runtime["generation"]["temperature"],
        top_p=runtime["generation"]["topP"],
        evaluator_prompt_version=prompt_bundle.version,
        runtime_provenance_record=runtime_record,
    )


def _execute(arguments):
    runtime = _load_json(TOOLS_DIR / "runtime.json")
    prompt_bundle = _load_prompt_bundle(
        getattr(arguments, "prompt_version", None) or runtime["evaluation"]["promptVersion"]
    )
    corpus_path = Path(arguments.corpus or ARTIFACT_ROOT / "corpus" / "v1" / f"{arguments.split}.jsonl")
    case_list = getattr(arguments, "case_list", None)
    if case_list is not None and getattr(arguments, "case", None) is not None:
        raise ValueError("Use only one of --case or --case-list")
    cases = _load_cases(corpus_path, None if case_list is not None else arguments.case)
    if case_list is not None:
        cases = _select_case_list(cases, case_list, split=arguments.split)
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
            runtime_record = {
                "kind": "fake-test-only",
                "sourceTag": version,
                "binarySHA256": _file_sha256(__file__),
            }
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
            runtime_record = provenance.verify_runtime(
                executable,
                TOOLS_DIR / "runtime.json",
                executable.parents[1] / "runtime-manifest.json",
            )
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
        runtime_record = {"kind": "online-reference"}
        modes = [arguments.mode or "off"]

    runner = _runner(client, model_id, artifact_hash, version, prompt_bundle, runtime_record)
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
        "transport": (
            (
                "llama.cpp-apply-template-tokenize-native-completion"
                if _uses_compact_context(prompt_bundle.version)
                else "llama.cpp-apply-template-native-completion"
            )
            if arguments.provider == "local"
            else "openai-compatible-http"
        ),
        "split": arguments.split,
        "corpusPath": str(corpus_path.resolve()),
        "corpusSHA256": _file_sha256(corpus_path),
        "promptVersion": prompt_bundle.version,
        "promptPath": str(prompt_bundle.prompt_path.resolve()),
        "promptSHA256": prompt_bundle.prompt_sha256,
        "examplesPath": str(prompt_bundle.examples_path.resolve()),
        "examplesSHA256": prompt_bundle.examples_sha256,
        "schemaVersion": "model-coaching-turn.v1",
        "schemaSHA256": _file_sha256(TOOLS_DIR / "coaching-turn.schema.json"),
        "runtimeSHA256": _file_sha256(TOOLS_DIR / "runtime.json"),
        "modelArtifactSHA256": artifact_hash,
        "llamaCppVersion": version,
        "runtimeProvenance": runtime_record,
        "contextTokens": runtime["mac"]["contextTokens"],
        "compilerPromptBudgetTokens": (
            4000 if _uses_compact_context(prompt_bundle.version) else None
        ),
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
        subparser.add_argument("--case-list")
        subparser.add_argument("--repetitions", type=int)
        subparser.add_argument("--mode", choices=("off", "bounded"))
        subparser.add_argument("--corpus")
        subparser.add_argument("--prompt-version")
    arguments = parser.parse_args(argv)
    try:
        return _execute(arguments)
    except (
        ValueError,
        OSError,
        model_store.ModelStoreError,
        provenance.RuntimeProvenanceError,
    ) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
