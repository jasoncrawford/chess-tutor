import argparse
import contextlib
import hashlib
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

import run_eval
import example_validation
import render_review
import summarize_eval
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


class RunEvalTests(unittest.TestCase):
    def runner(self, client, *, context_tokens=8192):
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
                    "turn": {"requestID": "example-request"},
                }
            ],
            schema={"type": "object", "additionalProperties": False},
            context_tokens=context_tokens,
            maximum_output_tokens=256,
            temperature=0.2,
            top_p=0.9,
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
            {"requestID": "example-request"},
            json.loads(call["extra_messages"][0]["content"]),
        )
        self.assertEqual(
            {"requestID": "example-request"},
            json.loads(call["extra_messages"][1]["content"]),
        )

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
        self.assertIn("endpoint failed", record["errors"][0]["message"])

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
            self.assertEqual("openai-compatible-http", manifest["transport"])
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
                [root / "artifacts" / "runs" / "fake-test-model"],
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


if __name__ == "__main__":
    unittest.main()
