import argparse
import contextlib
import hashlib
import io
import json
import os
import sys
import tempfile
import unittest
from unittest import mock
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

import run_eval
import example_validation
import render_review
import summarize_eval
import validate_turn
from Tools.CoachingEval.tests.test_validate_turn import valid_request, valid_turn


def response(content, *, reasoning="private reasoning", prompt_tokens=21, output_tokens=9):
    return {
        "choices": [{"message": {"content": content, "reasoning_content": reasoning}}],
        "usage": {"prompt_tokens": prompt_tokens, "completion_tokens": output_tokens},
        "timings": {"prompt_ms": 15.5, "predicted_ms": 35.25},
    }


class ScriptedClient:
    def __init__(self, responses):
        self.responses = list(responses)
        self.calls = []

    def complete(self, **arguments):
        self.calls.append(arguments)
        result = self.responses.pop(0)
        if isinstance(result, Exception):
            raise result
        return result


class FailingClient:
    def __init__(self, error):
        self.error = error
        self.calls = []

    def complete(self, **arguments):
        self.calls.append(arguments)
        raise self.error


class CompactScriptedClient:
    def __init__(self, responses, *, prompt="RENDERED PROMPT", token_counts=(4000,)):
        self.responses = list(responses)
        self.prompt = prompt
        self.token_counts = list(token_counts)
        self.render_calls = []
        self.token_calls = []
        self.completion_calls = []

    def render_prompt(self, **arguments):
        self.render_calls.append(arguments)
        return self.prompt

    def token_count(self, prompt, **arguments):
        self.token_calls.append((prompt, arguments))
        return self.token_counts.pop(0)

    def complete_rendered(self, **arguments):
        self.completion_calls.append(arguments)
        result = self.responses.pop(0)
        if isinstance(result, Exception):
            raise result
        return result


class RunEvalTests(unittest.TestCase):
    def runner(self, client, *, context_tokens=8192, evaluator_prompt_version="tutor-v1"):
        example_turn = valid_turn()
        example_turn["requestID"] = "example-request"
        return run_eval.EvaluationRunner(
            client=client,
            model_id="test-model",
            model_artifact_sha256="f" * 64,
            llama_cpp_version="b10516",
            system_prompt="Exact tutor prompt",
            examples=[
                {
                    "sourceCaseID": "visible-example",
                    "requestExcerpt": {"requestID": "example-request"},
                    "turn": example_turn,
                }
            ],
            schema={"type": "object", "additionalProperties": False},
            context_tokens=context_tokens,
            maximum_output_tokens=256,
            temperature=0.2,
            top_p=0.9,
            evaluator_prompt_version=evaluator_prompt_version,
        )

    def case(self, request=None):
        return {
            "id": "case-1",
            "split": "visible",
            "request": request or valid_request(),
            "oracle": {
                "successCriteria": ["One useful current step.", "The instruction is answerable."],
                "severeFailureCriteria": ["The turn invents a board fact."],
            },
        }

    def compact_case(self):
        request = valid_request()
        bindings = [
            {"alias": "action-close-help", "stableID": "action:closeHelp", "category": "action"},
            {"alias": "task-select-piece", "stableID": "task:selectBoardPiece", "category": "boardTask"},
            {"alias": "piece-white-king-d4", "stableID": "piece:white:king:d4", "category": "piece"},
            {"alias": "fact-position", "stableID": "fact:position", "category": "tacticalFact"},
        ]
        markdown = (
            "# Chess coaching context\n\n"
            "- Schema: `model-coaching-context.v1`\n"
            "- Prompt: `tutor-v3`\n"
            "- Request: `request-1`\n\n"
            "## Available response references\n\n"
            "- `action-close-help` — Close help\n"
            "- `task-select-piece` — Select a piece\n"
            "- `piece-white-king-d4` — White king on d4\n"
            "- `fact-position` — Position fact\n"
        )
        result = self.case(request)
        result["compactContext"] = {
            "schemaVersion": "model-coaching-context.v1",
            "promptVersion": "tutor-v3",
            "requestID": request["requestID"],
            "positionRevision": request["positionRevision"],
            "markdown": markdown,
            "referenceBindings": bindings,
            "omissions": [],
        }
        return result

    def alias_turn(self):
        turn = valid_turn()
        turn.update(
            {
                "actionReferences": ["action-close-help"],
                "boardTaskReference": "task-select-piece",
                "boardFocusReferences": ["piece-white-king-d4"],
                "relationshipReferences": [],
                "supportingEvidenceReferences": ["fact-position"],
            }
        )
        return turn

    def compact_runner(self, client):
        examples = json.loads((TOOLS_DIR / "prompts" / "examples-v3.json").read_text())
        return run_eval.EvaluationRunner(
            client=client,
            model_id="test-model",
            model_artifact_sha256="f" * 64,
            llama_cpp_version="b10516",
            system_prompt="Exact tutor-v3 prompt",
            examples=examples,
            schema=json.loads((TOOLS_DIR / "coaching-turn.schema.json").read_text()),
            context_tokens=8192,
            maximum_output_tokens=256,
            temperature=0.2,
            top_p=0.9,
            evaluator_prompt_version="tutor-v3",
        )

    def test_tutor_v3_refuses_4001_token_prompt_without_generation_or_repair(self):
        client = CompactScriptedClient([], token_counts=[4001])

        record = self.compact_runner(client).evaluate_case(
            self.compact_case(), mode="off", seed=1103
        )

        self.assertEqual("compilerBudgetExceeded", record["generationStatus"])
        self.assertEqual(4001, record["renderedPromptTokens"])
        self.assertFalse(record["generationAttempted"])
        self.assertEqual([], client.completion_calls)
        self.assertFalse(record["repairAttempted"])
        self.assertEqual(1, len(client.render_calls))
        self.assertEqual(1, len(client.token_calls))

    def test_tutor_v3_at_4000_tokens_restores_aliases_and_validates_stable_turn(self):
        alias_turn = self.alias_turn()
        client = CompactScriptedClient(
            [response("<think>private</think>\n" + json.dumps(alias_turn))],
            token_counts=[4000],
        )

        record = self.compact_runner(client).evaluate_case(
            self.compact_case(), mode="bounded", seed=2207
        )

        self.assertEqual("generated", record["generationStatus"])
        self.assertTrue(record["generationAttempted"])
        self.assertEqual(4000, record["renderedPromptTokens"])
        self.assertEqual(alias_turn, record["aliasTurn"])
        self.assertEqual(valid_turn(), record["stableTurn"])
        self.assertEqual(valid_turn(), record["parsedTurn"])
        self.assertEqual([], record["aliasRestorationErrors"])
        self.assertTrue(record["firstAttemptValidation"]["valid"])
        self.assertEqual(
            self.compact_case()["compactContext"]["markdown"],
            client.render_calls[0]["user_content"],
        )
        self.assertEqual(client.prompt, client.completion_calls[0]["prompt"])
        grammar = client.completion_calls[0]["grammar"]
        self.assertIn("action-close-help", grammar)
        self.assertIn("fact-position", grammar)
        self.assertNotIn("action:closeHelp", grammar)
        self.assertNotIn("private", json.dumps(record))
        self.assertEqual(64, len(record["aliasTurnSHA256"]))
        self.assertEqual(64, len(record["stableTurnSHA256"]))
        self.assertGreater(record["aliasTurnUTF8Bytes"], 0)
        self.assertGreater(record["stableTurnUTF8Bytes"], 0)

    def test_tutor_v3_refuses_repair_when_repaired_prompt_exceeds_budget(self):
        client = CompactScriptedClient(
            [response("not json")],
            token_counts=[4000, 4001],
        )

        record = self.compact_runner(client).evaluate_case(
            self.compact_case(), mode="off", seed=1103
        )

        self.assertEqual("repairBudgetExceeded", record["generationStatus"])
        self.assertTrue(record["repairAttempted"])
        self.assertEqual(4001, record["repairRenderedPromptTokens"])
        self.assertEqual(1, len(client.completion_calls))
        self.assertEqual(2, len(client.render_calls))
        self.assertEqual(2, len(client.token_calls))
        self.assertEqual(
            ["transport.repairBudgetExceeded"], record["repairValidation"]["errors"]
        )

    def test_tutor_v3_unknown_alias_fails_closed_without_semantic_repair(self):
        alias_turn = self.alias_turn()
        alias_turn["boardFocusReferences"] = ["piece-not-listed"]
        client = CompactScriptedClient(
            [response(json.dumps(alias_turn))],
            token_counts=[1000],
        )

        record = self.compact_runner(client).evaluate_case(
            self.compact_case(), mode="off", seed=1103
        )

        self.assertFalse(record["firstAttemptValidation"]["valid"])
        self.assertEqual(
            ["alias.unknown:boardFocusReferences:piece-not-listed"],
            record["aliasRestorationErrors"],
        )
        self.assertIsNone(record["stableTurn"])
        self.assertIsNone(record["parsedTurn"])
        self.assertFalse(record["repairAttempted"])
        self.assertEqual(1, len(client.completion_calls))

    def test_write_run_atomically_persists_transcript_and_bounded_record(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "visible-fixed"
            record = {
                "caseID": "case-1",
                "mode": "off",
                "seed": 1103,
                "_transcriptMarkdown": "# Coaching evaluation transcript\n",
            }

            run_eval._write_run(output, [record], {"modelID": "test-model"})

            self.assertTrue(output.is_dir())
            transcript = output / "transcripts" / "case-1--off--1103.md"
            self.assertEqual("# Coaching evaluation transcript\n", transcript.read_text())
            persisted = json.loads((output / "records.jsonl").read_text())
            self.assertNotIn("_transcriptMarkdown", persisted)
            self.assertEqual("transcripts/case-1--off--1103.md", persisted["transcriptPath"])
            self.assertEqual(
                hashlib.sha256(transcript.read_bytes()).hexdigest(),
                persisted["transcriptSHA256"],
            )
            self.assertNotIn("RENDERED PROMPT", json.dumps(persisted))
            with self.assertRaisesRegex(ValueError, "Refusing to overwrite"):
                run_eval._write_run(output, [record], {"modelID": "test-model"})
            self.assertEqual([], list(root.glob(".*.tmp-*")))

    def test_records_final_content_validation_tokens_timings_and_reproducibility_fields(self):
        turn = valid_turn()
        raw = json.dumps(turn)
        client = ScriptedClient([response(f"<think>secret trace</think>\n{raw}")])
        record = self.runner(client).evaluate_case(self.case(), mode="off", seed=1103)

        self.assertEqual(raw, record["rawFinalContent"])
        self.assertEqual(raw, record["firstAttemptRawFinalContent"])
        self.assertIsNone(record["repairRawFinalContent"])
        self.assertEqual(turn, record["parsedTurn"])
        self.assertEqual({"valid": True, "errors": []}, record["firstAttemptValidation"])
        self.assertIsNone(record["repairValidation"])
        self.assertFalse(record["repairAttempted"])
        self.assertEqual(21, record["promptTokens"])
        self.assertEqual(9, record["outputTokens"])
        self.assertEqual(15.5, record["promptMilliseconds"])
        self.assertEqual(35.25, record["generationMilliseconds"])
        self.assertEqual(1103, record["seed"])
        self.assertEqual("f" * 64, record["modelArtifactSHA256"])
        self.assertEqual("b10516", record["llamaCppVersion"])
        self.assertEqual("visible", record["caseSplit"])
        self.assertEqual([], record["errors"])
        self.assertNotIn("reasoning", json.dumps(record).lower())

        call = client.calls[0]
        self.assertEqual("Exact tutor prompt", call["system_prompt"])
        self.assertEqual(valid_request(), call["request"])
        self.assertEqual(1103, call["seed"])
        self.assertEqual(256, call["maximum_output_tokens"])
        self.assertFalse(call["enable_thinking"])
        self.assertEqual(
            ["user", "assistant"],
            [message["role"] for message in call["extra_messages"]],
        )
        self.assertEqual(
            {"promptVersion": "tutor-v1", "requestID": "example-request"},
            json.loads(call["extra_messages"][0]["content"]),
        )
        self.assertEqual(
            {"requestID": "example-request"},
            {"requestID": json.loads(call["extra_messages"][1]["content"])["requestID"]},
        )

    def test_selected_prompt_version_is_the_only_effective_request_mutation(self):
        frozen_request = valid_request()
        frozen_case = self.case(frozen_request)
        client = ScriptedClient([response(json.dumps(valid_turn()))])
        captured_validation_requests = []
        real_validate_turn = validate_turn.validate_turn

        def validate_with_capture(turn, request):
            captured_validation_requests.append(request)
            return real_validate_turn(turn, request)

        with mock.patch.object(run_eval.validate_turn, "validate_turn", validate_with_capture):
            record = self.runner(
                client,
                evaluator_prompt_version="tutor-v2",
            ).evaluate_case(frozen_case, mode="off", seed=1103)

        effective_request = client.calls[0]["request"]
        self.assertEqual("tutor-v1", frozen_request["promptVersion"])
        self.assertEqual("tutor-v2", effective_request["promptVersion"])
        self.assertEqual(frozen_request["requestID"], effective_request["requestID"])
        self.assertEqual(
            {key: value for key, value in frozen_request.items() if key != "promptVersion"},
            {key: value for key, value in effective_request.items() if key != "promptVersion"},
        )
        self.assertEqual(effective_request, record["evaluationCase"]["request"])
        self.assertEqual("tutor-v2", record["promptVersion"])
        self.assertEqual("tutor-v2", record["evaluatorPromptVersion"])
        self.assertEqual(
            [{"field": "promptVersion", "frozen": "tutor-v1", "effective": "tutor-v2"}],
            record["requestMutations"],
        )
        frozen_bytes = run_eval.canonical_json(frozen_request).encode("utf-8")
        effective_bytes = run_eval.canonical_json(effective_request).encode("utf-8")
        self.assertEqual(hashlib.sha256(frozen_bytes).hexdigest(), record["frozenRequestSHA256"])
        self.assertEqual(
            hashlib.sha256(effective_bytes).hexdigest(),
            record["effectiveRequestSHA256"],
        )
        self.assertEqual(record["effectiveRequestSHA256"], record["requestSHA256"])
        self.assertEqual("tutor-v2", captured_validation_requests[0]["promptVersion"])
        self.assertEqual(
            "tutor-v2",
            json.loads(client.calls[0]["extra_messages"][0]["content"])["promptVersion"],
        )

    def test_every_assistant_example_serializes_in_exact_grammar_order(self):
        examples = json.loads((TOOLS_DIR / "prompts" / "examples-v2.json").read_text())
        expected_required = [
            "schemaVersion",
            "requestID",
            "teachingIntent",
            "primaryMessage",
            "actionReferences",
            "boardFocusReferences",
            "relationshipReferences",
            "supportingEvidenceReferences",
        ]
        expected_optional = ["instruction", "responseToLatestAction", "boardTaskReference"]

        messages = run_eval._example_messages(examples, prompt_version="tutor-v2")

        self.assertEqual([], example_validation.validate_examples(
            examples,
            json.loads((TOOLS_DIR / "fixtures" / "example-contracts-v1.json").read_text()),
        ))
        for index, example in enumerate(examples):
            with self.subTest(sourceCaseID=example["sourceCaseID"]):
                user_request = json.loads(messages[index * 2]["content"])
                serialized = messages[index * 2 + 1]["content"]
                pairs = json.loads(serialized, object_pairs_hook=lambda value: value)
                self.assertEqual("tutor-v2", user_request["promptVersion"])
                self.assertTrue(serialized.startswith('{"schemaVersion":'))
                self.assertEqual(
                    expected_required
                    + [key for key in expected_optional if key in example["turn"]],
                    [key for key, _value in pairs],
                )
                self.assertEqual(example["turn"], dict(pairs))
                synthetic_request = example_validation._synthetic_request(example)
                self.assertEqual(
                    [],
                    validate_turn.validate_turn(dict(pairs), synthetic_request),
                )

    def test_tutor_v3_example_messages_send_exact_markdown_and_alias_turn(self):
        turn = valid_turn()
        turn["requestID"] = "corpus:example"
        turn["actionReferences"] = ["action-close-help"]
        turn["boardTaskReference"] = "task-move-piece"
        turn["boardFocusReferences"] = ["piece-white-king-d4"]
        turn["supportingEvidenceReferences"] = ["fact-no-immediate-danger"]
        markdown = (
            "# Chess coaching context\n\n"
            "- Request: `corpus:example`\n\n"
            "## Available response references\n\n"
            "- action-close-help — Close help\n"
            "- task-move-piece — Move piece\n"
            "- piece-white-king-d4 — White king on d4\n"
            "- fact-no-immediate-danger — No immediate danger"
        )
        example = {
            "sourceCaseID": "example",
            "contextMarkdown": markdown,
            "turn": turn,
        }

        messages = run_eval._example_messages([example], prompt_version="tutor-v3")

        self.assertEqual(markdown, messages[0]["content"])
        self.assertEqual(turn, json.loads(messages[1]["content"]))
        self.assertEqual([], example_validation.validate_examples(
            [example],
            [{
                "sourceCaseID": "example",
                "permittedTeachingIntents": [turn["teachingIntent"]],
                "requiredActionReferences": ["action:closeHelp"],
                "forbiddenActionReferences": [],
                "prohibitedPhrases": [],
            }],
        ))

    def test_tutor_v3_examples_preserve_visible_scenarios_with_exact_alias_contracts(self):
        examples = json.loads((TOOLS_DIR / "prompts" / "examples-v3.json").read_text())
        contracts = json.loads(
            (TOOLS_DIR / "fixtures" / "example-contracts-v1.json").read_text()
        )
        v2_source_ids = [
            example["sourceCaseID"]
            for example in json.loads(
                (TOOLS_DIR / "prompts" / "examples-v2.json").read_text()
            )
        ]

        messages = run_eval._example_messages(examples, prompt_version="tutor-v3")

        self.assertEqual(v2_source_ids, [example["sourceCaseID"] for example in examples])
        self.assertEqual([], example_validation.validate_examples(examples, contracts))
        for index, example in enumerate(examples):
            with self.subTest(sourceCaseID=example["sourceCaseID"]):
                self.assertEqual(
                    {"sourceCaseID", "contextMarkdown", "turn"},
                    set(example),
                )
                self.assertEqual(example["contextMarkdown"], messages[index * 2]["content"])
                self.assertIn("model-coaching-context.v1", example["contextMarkdown"])
                self.assertIn("tutor-v3", example["contextMarkdown"])
                self.assertEqual(
                    example["turn"],
                    json.loads(messages[index * 2 + 1]["content"]),
                )
                for field in (
                    "actionReferences",
                    "boardFocusReferences",
                    "relationshipReferences",
                    "supportingEvidenceReferences",
                ):
                    self.assertTrue(all(":" not in value for value in example["turn"][field]))
                board_task = example["turn"].get("boardTaskReference")
                self.assertTrue(board_task is None or ":" not in board_task)

    def test_repairs_parse_or_shape_failure_once_and_records_both_attempts(self):
        repaired = valid_turn()
        client = ScriptedClient([response("not json"), response(json.dumps(repaired), prompt_tokens=5, output_tokens=3)])
        record = self.runner(client).evaluate_case(self.case(), mode="bounded", seed=2207)

        self.assertEqual(2, len(client.calls))
        self.assertTrue(record["repairAttempted"])
        self.assertFalse(record["firstAttemptValidation"]["valid"])
        self.assertTrue(record["repairValidation"]["valid"])
        self.assertEqual("not json", record["firstAttemptRawFinalContent"])
        self.assertEqual(json.dumps(repaired), record["repairRawFinalContent"])
        self.assertEqual(repaired, record["parsedTurn"])
        self.assertEqual(26, record["promptTokens"])
        self.assertEqual(12, record["outputTokens"])
        self.assertTrue(client.calls[0]["enable_thinking"])

    def test_unclosed_thinking_trace_is_never_persisted_even_when_repair_fails(self):
        private = "<think>private unfinished trace"
        client = ScriptedClient([response(private), response(private)])
        record = self.runner(client).evaluate_case(self.case(), mode="bounded", seed=2207)

        self.assertEqual("", record["rawFinalContent"])
        self.assertNotIn("private", json.dumps(record))
        self.assertFalse(record["repairValidation"]["valid"])

    def test_discards_repeated_prefixed_case_variant_and_embedded_thinking_blocks(self):
        raw = json.dumps(valid_turn())
        traced = (
            "provider prefix\n<THINK>first private trace</THINK>\n"
            "<think data-kind=\"reasoning\">second private trace</think>\n"
            + raw
            + "<ThInK>embedded private trace</tHiNk>"
        )
        client = ScriptedClient([response(traced, reasoning="provider private trace")])

        record = self.runner(client).evaluate_case(self.case(), mode="bounded", seed=2207)

        self.assertEqual(raw, record["rawFinalContent"])
        self.assertTrue(record["firstAttemptValidation"]["valid"])
        serialized = json.dumps(record).lower()
        self.assertNotIn("private trace", serialized)
        self.assertNotIn("<think", serialized)
        self.assertNotIn("reasoning_content", serialized)

    def test_fails_closed_when_any_thinking_trace_marker_remains(self):
        raw = json.dumps(valid_turn())
        for traced in (
            "<think>unfinished " + raw,
            raw + " </THINK>",
            "prefix < think>spaced marker " + raw,
        ):
            with self.subTest(traced=traced[:20]):
                client = ScriptedClient([response(traced), response(traced)])
                record = self.runner(client).evaluate_case(self.case(), mode="bounded", seed=2207)

                self.assertEqual("", record["rawFinalContent"])
                self.assertNotIn("unfinished", json.dumps(record))
                self.assertNotIn("spaced marker", json.dumps(record))

    def test_repair_transport_failure_keeps_first_attempt_validation_separate(self):
        client = ScriptedClient(
            [response("not json"), run_eval.llama_server.LlamaServerError("repair endpoint failed")]
        )
        record = self.runner(client).evaluate_case(self.case(), mode="off", seed=1103)

        self.assertTrue(record["repairAttempted"])
        self.assertEqual("parse.invalidJSON", record["firstAttemptValidation"]["errors"][0].split(":")[0])
        self.assertEqual(["transport.generationError"], record["repairValidation"]["errors"])
        self.assertEqual("generationError", record["errors"][0]["kind"])

    def test_provider_error_text_cannot_persist_thinking_trace_content(self):
        client = FailingClient(
            run_eval.llama_server.LlamaServerError(
                "endpoint failed <THINK>private provider error reasoning</THINK>"
            )
        )

        record = self.runner(client).evaluate_case(self.case(), mode="bounded", seed=2207)

        serialized = json.dumps(record).lower()
        self.assertNotIn("private provider error reasoning", serialized)
        self.assertNotIn("<think", serialized)
        self.assertEqual("Provider generation failed.", record["errors"][0]["message"])

    def test_provider_error_persistence_fails_closed_for_nested_reasoning_json(self):
        client = FailingClient(
            run_eval.llama_server.LlamaServerError(
                json.dumps(
                    {
                        "error": {
                            "ReAsOnInG_CoNtEnT": "PRIVATE NESTED REASONING",
                            "details": {
                                "reasoningContent": "PRIVATE CAMEL REASONING",
                                "trace": "<THINK>PRIVATE TRACE</THINK>",
                            },
                        },
                        "message": "secret provider body",
                    }
                ),
                http_status=422,
            )
        )

        record = self.runner(client).evaluate_case(self.case(), mode="bounded", seed=2207)

        self.assertEqual("generationError", record["errors"][0]["kind"])
        self.assertEqual("Provider request failed with HTTP 422.", record["errors"][0]["message"])
        serialized = json.dumps(record).lower()
        for forbidden in (
            "private",
            "reasoning_content",
            "reasoningcontent",
            "<think",
            "secret provider body",
        ):
            self.assertNotIn(forbidden, serialized)

    def test_does_not_repair_mechanically_valid_shape_with_bad_identity_or_pedagogy(self):
        wrong_identity = valid_turn()
        wrong_identity["requestID"] = "wrong"
        client = ScriptedClient([response(json.dumps(wrong_identity))])
        case = self.case()
        case["oracle"]["severeFailureCriteria"] = ["This output is pedagogically poor."]
        record = self.runner(client).evaluate_case(case, mode="off", seed=3301)

        self.assertEqual(1, len(client.calls))
        self.assertFalse(record["repairAttempted"])
        self.assertIn("requestIDMismatch", record["firstAttemptValidation"]["errors"])

    def test_oversized_request_is_hashed_recorded_and_sent_without_compaction(self):
        request = valid_request()
        request["currentTurnCoachingHistory"] = [
            {"sequence": 1, "kind": "learnerEvent", "summary": "x" * 200, "referencedIDs": []}
        ]
        client = ScriptedClient([response(json.dumps(valid_turn()))])
        record = self.runner(client, context_tokens=10).evaluate_case(self.case(request), mode="off", seed=1103)
        exact = json.dumps(request, sort_keys=True, separators=(",", ":")).encode("utf-8")

        self.assertEqual(request, client.calls[0]["request"])
        self.assertEqual(len(exact), record["requestUTF8Bytes"])
        self.assertEqual(hashlib.sha256(exact).hexdigest(), record["requestSHA256"])
        self.assertGreater(record["promptEnvelopeUTF8Bytes"], record["requestUTF8Bytes"])
        self.assertEqual(64, len(record["promptEnvelopeSHA256"]))
        self.assertFalse(record["requestCompacted"])
        self.assertEqual("likelyContextOverflow", record["preflight"]["status"])
        self.assertEqual(10, record["preflight"]["contextTokens"])

    def test_server_context_rejection_is_explicit_and_never_repaired(self):
        client = FailingClient(run_eval.llama_server.LlamaServerError("prompt exceeds context size"))
        record = self.runner(client).evaluate_case(self.case(), mode="off", seed=1103)

        self.assertEqual(1, len(client.calls))
        self.assertFalse(record["repairAttempted"])
        self.assertEqual("contextOverflow", record["errors"][0]["kind"])
        self.assertEqual("contextOverflow", record["preflight"]["serverOutcome"])
        self.assertEqual(["transport.contextOverflow"], record["firstAttemptValidation"]["errors"])

    def test_reference_configuration_reads_only_the_three_approved_environment_keys(self):
        environment = {
            "COACHING_EVAL_REFERENCE_URL": "https://example.test/v1",
            "COACHING_EVAL_REFERENCE_MODEL": "reference-model",
            "COACHING_EVAL_REFERENCE_API_KEY": "secret",
            "OPENAI_API_KEY": "must-not-be-read",
            "HF_TOKEN": "must-not-be-read",
        }
        config = run_eval.ReferenceConfiguration.from_environment(environment)
        self.assertEqual("https://example.test/v1", config.url)
        self.assertEqual("reference-model", config.model)
        self.assertEqual("secret", config.api_key)
        self.assertEqual(
            {
                "COACHING_EVAL_REFERENCE_URL",
                "COACHING_EVAL_REFERENCE_MODEL",
                "COACHING_EVAL_REFERENCE_API_KEY",
            },
            set(config.consumed_environment_keys),
        )

    def test_versioned_examples_cover_required_visible_scenarios_only(self):
        examples = json.loads((TOOLS_DIR / "prompts" / "examples-v1.json").read_text())
        scenarios = {example["scenario"] for example in examples}
        self.assertEqual(
            {
                "first-move opening",
                "endangered piece",
                "no-safe-capture followed by a staged move",
                "benign opponent activity",
                "replacement move",
                "check resolution",
                "mate-in-one",
                "quiet move with no named purpose",
            },
            scenarios,
        )
        hidden_ids = {
            "t1OutsidePawnMove", "t3WrongAttacker", "t4LowerPriorityPawn", "t5ProtectedAbsence",
            "t7UnsafeCapture", "t9Completed", "t10Completed", "t11IncorrectLooksSafe",
            "t11BenignCaptureLooksSafe", "t12WrongChecker", "t12UnsupportedSafeMove",
        }
        serialized = json.dumps(examples, sort_keys=True)
        self.assertTrue(hidden_ids.isdisjoint(example["sourceCaseID"] for example in examples))
        self.assertTrue(all(identifier not in serialized for identifier in hidden_ids))

    def test_every_prompt_example_satisfies_its_visible_semantic_contract(self):
        examples = json.loads((TOOLS_DIR / "prompts" / "examples-v1.json").read_text())
        contracts = json.loads(
            (TOOLS_DIR / "fixtures" / "example-contracts-v1.json").read_text()
        )

        self.assertEqual([], example_validation.validate_examples(examples, contracts))

    def test_prompt_examples_keep_feedback_separate_from_the_current_instruction(self):
        examples = {
            example["sourceCaseID"]: example
            for example in json.loads((TOOLS_DIR / "prompts" / "examples-v1.json").read_text())
        }

        self.assertEqual([], examples["t1Entry"]["turn"]["actionReferences"])
        staged = examples["t7NoSafeCapture"]["turn"]
        self.assertIsNone(staged["responseToLatestAction"])
        self.assertNotIn("you moved", staged["primaryMessage"].lower())
        benign = examples["t11BenignCaptureTap"]["turn"]
        self.assertEqual("Yes. That bishop could take the pawn.", benign["responseToLatestAction"])
        self.assertNotIn("Yes.", benign["primaryMessage"])
        self.assertIn("safe", benign["primaryMessage"].lower())
        replacement = examples["t11Safe"]["turn"]
        self.assertEqual(
            "You switched to bringing out your knight.",
            replacement["responseToLatestAction"],
        )
        self.assertNotIn("switched", replacement["primaryMessage"].lower())
        block = examples["t12Block"]["turn"]
        self.assertEqual(
            "Your bishop blocks the rook's check.",
            block["responseToLatestAction"],
        )
        self.assertNotIn("blocks", block["primaryMessage"].lower())

    def test_local_candidate_modes_are_limited_to_the_manifest(self):
        candidate = {"thinkingModes": ["off"]}
        self.assertEqual(["off"], run_eval._selected_modes(candidate, None))
        self.assertEqual(["off"], run_eval._selected_modes(candidate, "off"))
        with self.assertRaisesRegex(ValueError, "does not support thinking mode bounded"):
            run_eval._selected_modes(candidate, "bounded")

    def test_case_list_requires_exact_visible_ids(self):
        expected = [
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
        ]
        cases = [
            {"id": identifier, "split": "visible"}
            for identifier in reversed(expected)
        ]
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "pilot.json"

            def write(case_ids):
                path.write_text(
                    json.dumps(
                        {
                            "schemaVersion": "coaching-eval-pilot.v1",
                            "id": "compact-markdown-v1",
                            "caseIDs": case_ids,
                        }
                    )
                )

            write(expected)
            selected = run_eval._select_case_list(cases, path, split="visible")
            self.assertEqual(expected, [item["id"] for item in selected])

            write(expected[:-1])
            with self.assertRaisesRegex(ValueError, "exact fixed pilot IDs"):
                run_eval._select_case_list(cases, path, split="visible")

            write(expected[:-1] + [expected[-2]])
            with self.assertRaisesRegex(ValueError, "duplicate"):
                run_eval._select_case_list(cases, path, split="visible")

            write(expected[:1] + ["hiddenCase"] + expected[2:])
            with self.assertRaisesRegex(ValueError, "exact fixed pilot IDs"):
                run_eval._select_case_list(
                    cases + [{"id": "hiddenCase", "split": "hidden"}],
                    path,
                    split="visible",
                )

            write(list(reversed(expected)))
            with self.assertRaisesRegex(ValueError, "exact fixed pilot IDs"):
                run_eval._select_case_list(cases, path, split="visible")

    def test_prompt_bundle_selects_immutable_versioned_files_without_runner_edits(self):
        with tempfile.TemporaryDirectory() as temporary:
            prompt_root = Path(temporary)
            (prompt_root / "tutor-v2.md").write_text("Tutor prompt v2")
            (prompt_root / "examples-v2.json").write_text("[]")

            bundle = run_eval._load_prompt_bundle("tutor-v2", prompt_root)

            self.assertEqual("tutor-v2", bundle.version)
            self.assertEqual("Tutor prompt v2", bundle.system_prompt)
            self.assertEqual([], bundle.examples)
            self.assertEqual(64, len(bundle.prompt_sha256))
            self.assertEqual(64, len(bundle.examples_sha256))
            with self.assertRaisesRegex(ValueError, "immutable tutor-v<number>"):
                run_eval._load_prompt_bundle("latest", prompt_root)

    def test_fake_model_requires_explicit_opt_in_and_uses_real_http_run_path(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            corpus = root / "visible.jsonl"
            corpus.write_text(json.dumps(self.case()) + "\n")
            arguments = argparse.Namespace(
                provider="local",
                model="fake-test-model",
                split="visible",
                case="case-1",
                repetitions=1,
                mode="off",
                corpus=str(corpus),
                prompt_version="tutor-v1",
            )
            old_root = run_eval.ARTIFACT_ROOT
            old_opt_in = os.environ.pop("COACHING_EVAL_ALLOW_FAKE", None)
            try:
                run_eval.ARTIFACT_ROOT = root / "artifacts"
                arguments.repetitions = 0
                with self.assertRaisesRegex(ValueError, "1 through 3"):
                    run_eval._execute(arguments)
                arguments.repetitions = 1
                with self.assertRaisesRegex(ValueError, "COACHING_EVAL_ALLOW_FAKE=1"):
                    run_eval._execute(arguments)
                os.environ["COACHING_EVAL_ALLOW_FAKE"] = "1"
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(0, run_eval._execute(arguments))
            finally:
                run_eval.ARTIFACT_ROOT = old_root
                if old_opt_in is None:
                    os.environ.pop("COACHING_EVAL_ALLOW_FAKE", None)
                else:
                    os.environ["COACHING_EVAL_ALLOW_FAKE"] = old_opt_in

            manifests = list((root / "artifacts" / "runs" / "fake-test-model").rglob("run-manifest.json"))
            self.assertEqual(1, len(manifests))
            manifest = json.loads(manifests[0].read_text())
            self.assertEqual(
                "llama.cpp-apply-template-native-completion",
                manifest["transport"],
            )
            self.assertEqual("tutor-v1", manifest["promptVersion"])
            self.assertEqual("fake-test-only", manifest["runtimeProvenance"]["kind"])
            for field in (
                "corpusSHA256",
                "promptSHA256",
                "examplesSHA256",
                "schemaSHA256",
                "runtimeSHA256",
            ):
                self.assertEqual(64, len(manifest[field]))
            record_path = manifests[0].with_name("records.jsonl")
            record = json.loads(record_path.read_text())
            self.assertEqual("tutor-v1", record["evaluatorPromptVersion"])
            self.assertEqual("fake-test-only", record["runtimeProvenance"]["kind"])
            self.assertTrue(record["firstAttemptValidation"]["valid"])
            self.assertNotIn("test-only trace", json.dumps(record))

            review = root / "artifacts" / "review"
            render_review.render_review(
                [manifests[0].parent],
                review,
                review_seed=20260828,
            )
            summarize_eval.summarize(review)
            for output in review.iterdir():
                if output.is_file():
                    persisted = output.read_text(encoding="utf-8").lower()
                    self.assertNotIn("test-only trace", persisted, output.name)
                    self.assertNotIn("reasoning_content", persisted, output.name)
                    self.assertNotIn("<think", persisted, output.name)

    def test_fake_tutor_v3_e2e_persists_readable_hash_bound_transcript(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            corpus = root / "visible.jsonl"
            corpus.write_text(json.dumps(self.compact_case()) + "\n")
            arguments = argparse.Namespace(
                provider="local",
                model="fake-test-model",
                split="visible",
                case="case-1",
                repetitions=1,
                mode="off",
                corpus=str(corpus),
                prompt_version="tutor-v3",
            )
            old_root = run_eval.ARTIFACT_ROOT
            old_opt_in = os.environ.get("COACHING_EVAL_ALLOW_FAKE")
            try:
                run_eval.ARTIFACT_ROOT = root / "artifacts"
                os.environ["COACHING_EVAL_ALLOW_FAKE"] = "1"
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(0, run_eval._execute(arguments))
            finally:
                run_eval.ARTIFACT_ROOT = old_root
                if old_opt_in is None:
                    os.environ.pop("COACHING_EVAL_ALLOW_FAKE", None)
                else:
                    os.environ["COACHING_EVAL_ALLOW_FAKE"] = old_opt_in

            manifest_path = next((root / "artifacts" / "runs").rglob("run-manifest.json"))
            record = json.loads(manifest_path.with_name("records.jsonl").read_text())
            manifest = json.loads(manifest_path.read_text())
            self.assertEqual(
                "llama.cpp-apply-template-tokenize-native-completion",
                manifest["transport"],
            )
            self.assertEqual(4000, manifest["compilerPromptBudgetTokens"])
            transcript_path = manifest_path.parent / record["transcriptPath"]
            transcript = transcript_path.read_text()
            self.assertTrue(record["firstAttemptValidation"]["valid"])
            self.assertEqual("generated", record["generationStatus"])
            self.assertEqual(2000, record["renderedPromptTokens"])
            self.assertEqual(
                hashlib.sha256(transcript_path.read_bytes()).hexdigest(),
                record["transcriptSHA256"],
            )
            self.assertIn(self.compact_case()["compactContext"]["markdown"], transcript)
            self.assertIn("## Exact rendered prompt", transcript)
            self.assertNotIn("renderedPrompt", record)
            self.assertNotIn("test-only trace", json.dumps(record).lower())
            self.assertNotIn("test-only trace", transcript.lower())

    def test_fake_http_error_e2e_never_persists_provider_body_or_trace(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            corpus = root / "visible.jsonl"
            corpus.write_text(json.dumps(self.case()) + "\n")
            arguments = argparse.Namespace(
                provider="local",
                model="fake-test-model",
                split="visible",
                case="case-1",
                repetitions=1,
                mode="off",
                corpus=str(corpus),
                prompt_version="tutor-v1",
            )
            old_root = run_eval.ARTIFACT_ROOT
            old_opt_in = os.environ.get("COACHING_EVAL_ALLOW_FAKE")
            old_fake_error = os.environ.get("COACHING_EVAL_FAKE_HTTP_ERROR")
            try:
                run_eval.ARTIFACT_ROOT = root / "artifacts"
                os.environ["COACHING_EVAL_ALLOW_FAKE"] = "1"
                os.environ["COACHING_EVAL_FAKE_HTTP_ERROR"] = "reasoning"
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(0, run_eval._execute(arguments))
            finally:
                run_eval.ARTIFACT_ROOT = old_root
                if old_opt_in is None:
                    os.environ.pop("COACHING_EVAL_ALLOW_FAKE", None)
                else:
                    os.environ["COACHING_EVAL_ALLOW_FAKE"] = old_opt_in
                if old_fake_error is None:
                    os.environ.pop("COACHING_EVAL_FAKE_HTTP_ERROR", None)
                else:
                    os.environ["COACHING_EVAL_FAKE_HTTP_ERROR"] = old_fake_error

            manifests = list((root / "artifacts" / "runs").rglob("run-manifest.json"))
            self.assertEqual(1, len(manifests))
            record = json.loads(manifests[0].with_name("records.jsonl").read_text())
            self.assertEqual("generationError", record["errors"][0]["kind"])
            self.assertEqual(
                "Provider request failed with HTTP 422.",
                record["errors"][0]["message"],
            )

            review = root / "artifacts" / "review"
            render_review.render_review(
                [manifests[0].parent],
                review,
                review_seed=20260828,
            )
            summarize_eval.summarize(review)
            forbidden = (
                "private nested reasoning",
                "private camel reasoning",
                "private trace",
                "reasoning_content",
                "reasoningcontent",
                "<think",
                "secret provider body",
            )
            for output in (root / "artifacts").rglob("*"):
                if not output.is_file():
                    continue
                persisted = output.read_text(encoding="utf-8").lower()
                for marker in forbidden:
                    self.assertNotIn(marker, persisted, str(output))


class CompactEvaluationRunnerTests(unittest.TestCase):
    def test_tutor_v4_uses_zero_shot_compact_markdown_with_the_compiler_budget(self):
        fixture = RunEvalTests()
        bundle = run_eval._load_prompt_bundle("tutor-v4")
        client = CompactScriptedClient(
            [response(json.dumps(fixture.alias_turn()))], token_counts=[4000]
        )
        runner = run_eval.EvaluationRunner(
            client=client,
            model_id="test-model",
            model_artifact_sha256="f" * 64,
            llama_cpp_version="b10516",
            system_prompt=bundle.system_prompt,
            examples=bundle.examples,
            schema=json.loads((TOOLS_DIR / "coaching-turn.schema.json").read_text()),
            context_tokens=8192,
            maximum_output_tokens=256,
            temperature=0.2,
            top_p=0.9,
            evaluator_prompt_version="tutor-v4",
        )

        record = runner.evaluate_case(fixture.compact_case(), mode="off", seed=1103)

        self.assertTrue(run_eval._uses_compact_context("tutor-v4"))
        self.assertEqual([], bundle.examples)
        self.assertEqual(
            fixture.compact_case()["compactContext"]["markdown"],
            client.render_calls[0]["user_content"],
        )
        self.assertEqual([], client.render_calls[0]["extra_messages"])
        self.assertEqual(4000, record["renderedPromptTokens"])
        self.assertEqual("generated", record["generationStatus"])


class RunEvalConfigurationTests(unittest.TestCase):
    def test_tutor_v4_bundle_is_zero_shot_and_older_prompt_files_are_immutable(self):
        bundle = run_eval._load_prompt_bundle("tutor-v4")

        self.assertEqual([], bundle.examples)
        self.assertLess(len(bundle.system_prompt.encode("utf-8")), 2600)
        self.assertIn("latest learner action", bundle.system_prompt.lower())
        self.assertIn("one coherent", bundle.system_prompt.lower())
        self.assertEqual(
            {
                "tutor-v1.md": "e3b988d525b6b985cf87f2ba20d43d11918ae11399345ed403c77fb88c3a613a",
                "examples-v1.json": "a685f71686f49bde1e092cda103ea07bcac56804c54cd4518af22ac8f29f7239",
                "tutor-v2.md": "787101c311ce7a851c1e553858b84b98bb6fc4d71cc8d7f7c7e40c6da38ffd5d",
                "examples-v2.json": "a685f71686f49bde1e092cda103ea07bcac56804c54cd4518af22ac8f29f7239",
                "tutor-v3.md": "d1c6b0dfc1698015e3ebbdd49d59f6544d84159ecb7752cbc1a454e0562409a8",
                "examples-v3.json": "f2b8b9cde3ecc17c4828d07754b8685b40e02320d9f48cca515041dd17c3fc0b",
            },
            {
                path.name: run_eval._file_sha256(path)
                for path in sorted((TOOLS_DIR / "prompts").glob("*v[1-3].*"))
            },
        )

    def test_tutor_v4_records_compact_transport_and_4000_token_gate(self):
        fixture = RunEvalTests()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            corpus = root / "visible.jsonl"
            corpus.write_text(json.dumps(fixture.compact_case()) + "\n")
            arguments = argparse.Namespace(
                provider="local",
                model="fake-test-model",
                split="visible",
                case="case-1",
                repetitions=1,
                mode="off",
                corpus=str(corpus),
                prompt_version="tutor-v4",
            )
            old_root = run_eval.ARTIFACT_ROOT
            old_opt_in = os.environ.get("COACHING_EVAL_ALLOW_FAKE")
            try:
                run_eval.ARTIFACT_ROOT = root / "artifacts"
                os.environ["COACHING_EVAL_ALLOW_FAKE"] = "1"
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(0, run_eval._execute(arguments))
            finally:
                run_eval.ARTIFACT_ROOT = old_root
                if old_opt_in is None:
                    os.environ.pop("COACHING_EVAL_ALLOW_FAKE", None)
                else:
                    os.environ["COACHING_EVAL_ALLOW_FAKE"] = old_opt_in

            manifest_path = next((root / "artifacts" / "runs").rglob("run-manifest.json"))
            manifest = json.loads(manifest_path.read_text())
            self.assertEqual("tutor-v4", manifest["promptVersion"])
            self.assertEqual(
                "llama.cpp-apply-template-tokenize-native-completion",
                manifest["transport"],
            )
            self.assertEqual(4000, manifest["compilerPromptBudgetTokens"])


if __name__ == "__main__":
    unittest.main()
