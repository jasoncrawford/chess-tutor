import hashlib
import inspect
import json
import subprocess
import sys
import unittest
from dataclasses import replace
from datetime import timedelta
from pathlib import Path
from unittest import mock

from Tools.CoachingEval.benchmark.configuration import load_prices
from Tools.CoachingEval.benchmark.grader import grade_run
from Tools.CoachingEval.tests import test_benchmark_grader as fixtures


ROOT = fixtures.ROOT


class ScriptedJudge(fixtures.QueueJudge):
    def complete(self, **arguments):
        if isinstance(self.outputs[0], BaseException):
            self.calls.append(arguments)
            raise self.outputs.pop(0)
        return super().complete(**arguments)


class GradeCheckpointTests(unittest.TestCase):
    setUp = fixtures.BenchmarkGraderTests.setUp
    tearDown = fixtures.BenchmarkGraderTests.tearDown
    absolute = fixtures.BenchmarkGraderTests.absolute
    qualification_outputs = fixtures.BenchmarkGraderTests.qualification_outputs
    make_run = fixtures.BenchmarkGraderTests.make_run
    make_corpus = fixtures.BenchmarkGraderTests.make_corpus

    def arguments(self, **updates):
        self.root = self.root.resolve()
        values = dict(
            run_root=self.make_run(all_valid=True), corpus=self.make_corpus(),
            judge_configuration=self.configuration,
            destination=self.root / "grades", qualification_path=self.qualification_path,
            now=self.now, checkpoint_path=self.root / "grading-checkpoint.json",
            price_table=load_prices(ROOT / "Tools/CoachingEval/benchmark/pricing-v1.json"),
        )
        values.update(updates)
        return values

    def outputs(self):
        return [self.absolute(score=1), *[self.absolute() for _ in range(5)],
                {"winner": "tie", "evidence": ["Both fit the current step."]},
                {"winner": "A", "evidence": ["A fits the current step."]},
                {"winner": "B", "evidence": ["B fits the current step."]}]

    def interrupted(self, *, successful=7, error=None, **updates):
        arguments = self.arguments(**updates)
        client = ScriptedJudge(self.outputs()[:successful] + [
            error if error is not None else RuntimeError("sk-secret raw provider resp_private")])
        with self.assertRaises((ValueError, KeyboardInterrupt)):
            grade_run(client=client, **arguments)
        self.assertFalse(arguments["destination"].exists())
        return arguments, client

    def rewrite(self, path, mutate):
        envelope = json.loads(path.read_text())
        mutate(envelope["state"])
        envelope["sha256"] = hashlib.sha256(json.dumps(
            envelope["state"], sort_keys=True, separators=(",", ":"),
            ensure_ascii=False).encode()).hexdigest()
        path.write_text(json.dumps(envelope))

    def test_checkpoint_is_opt_in(self):
        self.assertIn("checkpoint_path", inspect.signature(grade_run).parameters)
        arguments = self.arguments()
        checkpoint = arguments.pop("checkpoint_path")
        client = ScriptedJudge(self.outputs())
        grade_run(client=client, **arguments)
        self.assertEqual(9, len(client.calls))
        self.assertFalse(checkpoint.exists())
        self.assertFalse(checkpoint.with_name(checkpoint.name + ".lock").exists())

    def test_checkpoint_does_not_change_completed_grades_or_mechanical_gates(self):
        arguments = self.arguments(run_root=self.make_run())
        outputs = [self.absolute(score=2) for _ in range(3)] + [
            {"winner": "B", "evidence": ["B fits the current step."]}]
        for checkpoint in (None, arguments["checkpoint_path"]):
            destination = self.root / ("without-checkpoint" if checkpoint is None else "with-checkpoint")
            client = ScriptedJudge(outputs)
            with mock.patch("Tools.CoachingEval.benchmark.judge_contract.time.monotonic",
                            side_effect=[value for index in range(4) for value in (index, index + .125)]):
                grade_run(client=client, **dict(arguments, checkpoint_path=checkpoint, destination=destination))
            self.assertEqual(4, len(client.calls))
        for filename in ("absolute-grades.jsonl", "pairwise-grades.jsonl", "grade-manifest.json", "qualification.json"):
            self.assertEqual((self.root / "without-checkpoint" / filename).read_bytes(),
                             (self.root / "with-checkpoint" / filename).read_bytes())

    def test_resume_preserves_absolute_pairwise_low_score_and_original_metrics(self):
        with mock.patch("Tools.CoachingEval.benchmark.judge_contract.time.monotonic",
                        side_effect=[value for index in range(8) for value in (index, index + .125)]):
            arguments, first = self.interrupted()
        client = ScriptedJudge(self.outputs()[7:])
        grade_run(client=client, **arguments)
        self.assertEqual(8, len(first.calls))
        self.assertEqual(2, len(client.calls))
        destination = arguments["destination"]
        absolute = [json.loads(line) for line in (destination / "absolute-grades.jsonl").read_text().splitlines()]
        pairs = [json.loads(line) for line in (destination / "pairwise-grades.jsonl").read_text().splitlines()]
        self.assertEqual({1}, set(absolute[0]["scores"].values()))
        self.assertEqual(125.0, absolute[0]["judgeMetrics"]["latencyMilliseconds"])
        self.assertEqual(50, absolute[0]["judgeMetrics"]["usage"]["inputTokens"])
        # Pinned $4/M input and $20/M output: 50*4/M + 20*20/M.
        self.assertEqual("0.0006", absolute[0]["judgeMetrics"]["estimatedCostUSD"])
        self.assertEqual("tie", pairs[0]["outcome"])
        self.assertEqual(125.0, pairs[0]["judgeMetrics"]["latencyMilliseconds"])
        resumed = pairs[1]["judgeMetrics"]
        self.assertEqual(2, resumed["callCount"])
        self.assertGreaterEqual(resumed["latencyMilliseconds"], 125.0)
        self.assertFalse(resumed["accountingComplete"])
        self.assertIsNone(resumed["estimatedCostUSD"])
        checkpoint = arguments["checkpoint_path"].read_text()
        self.assertNotIn("sk-secret", checkpoint)
        self.assertNotIn("raw provider", checkpoint)
        self.assertNotIn("resp_", checkpoint)
        state = json.loads(checkpoint)["state"]
        self.assertEqual(10, sum(len(cell["attempts"]) for cell in state["cells"].values()))

    def test_unresolved_inflight_is_one_unknown_attempt_and_lock_is_recoverable(self):
        arguments, _ = self.interrupted(successful=1, error=KeyboardInterrupt())
        state = json.loads(arguments["checkpoint_path"].read_text())["state"]
        self.assertIsNotNone(state["inFlight"])
        client = ScriptedJudge(self.outputs()[1:])
        grade_run(client=client, **arguments)
        absolute = [json.loads(line) for line in (arguments["destination"] / "absolute-grades.jsonl").read_text().splitlines()]
        self.assertEqual(8, len(client.calls))
        self.assertEqual(2, absolute[1]["judgeMetrics"]["callCount"])
        self.assertFalse(absolute[1]["judgeMetrics"]["accountingComplete"])
        self.assertIsNone(absolute[1]["judgeMetrics"]["estimatedCostUSD"])

    def test_known_failure_metrics_survive_validation_failure(self):
        invalid = self.absolute()
        invalid["evidence"] = ["candidate-id must not leak."]
        arguments, _ = self.interrupted(successful=0, error=ValueError())
        # Start a separate ledger for a received response rejected by validation.
        arguments["checkpoint_path"] = self.root / "validation.json"
        with self.assertRaisesRegex(ValueError, "identity"):
            grade_run(client=ScriptedJudge([invalid]), **arguments)
        client = ScriptedJudge(self.outputs())
        grade_run(client=client, **arguments)
        first = json.loads((arguments["destination"] / "absolute-grades.jsonl").read_text().splitlines()[0])
        metrics = first["judgeMetrics"]
        self.assertTrue(metrics["accountingComplete"])
        self.assertEqual(2, metrics["callCount"])
        self.assertEqual(100, metrics["usage"]["inputTokens"])
        self.assertEqual("0.0012", metrics["estimatedCostUSD"])
        self.assertNotIn("must not leak", arguments["checkpoint_path"].read_text())

    def test_malformed_provider_json_retains_bounded_failure_cost_and_usage(self):
        arguments = self.arguments()
        with self.assertRaisesRegex(ValueError, "malformed"):
            grade_run(client=fixtures.RawQueueJudge(["not json"]), **arguments)
        grade_run(client=ScriptedJudge(self.outputs()), **arguments)
        first = json.loads((arguments["destination"] / "absolute-grades.jsonl").read_text().splitlines()[0])
        self.assertEqual(2, first["judgeMetrics"]["callCount"])
        self.assertTrue(first["judgeMetrics"]["accountingComplete"])
        self.assertEqual("0.0006", first["judgeMetrics"]["estimatedCostUSD"])

    def test_every_binding_change_is_rejected_before_provider_use(self):
        arguments, _ = self.interrupted(successful=1)
        manifest_path = arguments["run_root"] / "run-manifest.json"
        original_manifest = manifest_path.read_bytes()
        record_path = arguments["run_root"] / "records.jsonl"
        original_records = record_path.read_bytes()
        original_qualification = self.qualification_path.read_bytes()
        prices = arguments["price_table"]
        cases = [
            {"judge_configuration": replace(self.configuration, review_seed=1)},
            {"judge_configuration": replace(self.configuration, system_prompt="Changed prompt")},
            {"price_table": replace(prices, sha256="0" * 64)},
            {"price_table": replace(prices, version="changed")},
            {"price_table": replace(prices, models={self.configuration.model: replace(
                prices.models[self.configuration.model], output_per_million=prices.models[self.configuration.model].output_per_million * 2)})},
            {"price_table": None},
            {"corpus": replace(arguments["corpus"], source_git_sha="different")},
            {"corpus": replace(arguments["corpus"], turns=tuple(replace(turn, request=dict(turn.request, requestID="different")) for turn in arguments["corpus"].turns))},
        ]
        for updates in cases:
            client = ScriptedJudge([])
            with self.subTest(updates=updates), self.assertRaisesRegex(ValueError, "binding"):
                grade_run(client=client, **dict(arguments, **updates))
            self.assertEqual([], client.calls)
        for name in ("manifest", "records", "qualification"):
            with self.subTest(name=name):
                if name == "manifest":
                    manifest_path.write_bytes(original_manifest + b"\n")
                elif name == "records":
                    record_path.write_bytes(original_records + b"\n")
                    value = json.loads(original_manifest)
                    value["recordsSHA256"] = hashlib.sha256(record_path.read_bytes()).hexdigest()
                    manifest_path.write_text(json.dumps(value))
                else:
                    self.qualification_path.write_bytes(original_qualification + b"\n")
                client = ScriptedJudge([])
                with self.assertRaises(ValueError):
                    grade_run(client=client, **arguments)
                self.assertEqual([], client.calls)
                manifest_path.write_bytes(original_manifest)
                record_path.write_bytes(original_records)
                self.qualification_path.write_bytes(original_qualification)

    def test_corpus_manifest_bytes_and_schema_identity_are_bound(self):
        path = self.root / "benchmark-manifest.json"
        path.write_text('{"sourceGitSHA":"source"}')
        corpus = replace(self.make_corpus(), manifest_path=path)
        arguments, _ = self.interrupted(successful=1, corpus=corpus)
        path.write_text('{"sourceGitSHA":"source"}\n')
        client = ScriptedJudge([])
        with self.assertRaisesRegex(ValueError, "binding"):
            grade_run(client=client, **arguments)
        self.assertEqual([], client.calls)
        path.write_text('{"sourceGitSHA":"source"}')
        with mock.patch("Tools.CoachingEval.benchmark.grader._absolute_schema", return_value={"type": "object"}):
            with self.assertRaisesRegex(ValueError, "binding"):
                grade_run(client=client, **arguments)
        self.assertEqual([], client.calls)

    def test_expired_qualification_is_rechecked_even_with_cached_success(self):
        arguments, _ = self.interrupted(successful=1)
        client = ScriptedJudge([])
        with self.assertRaisesRegex(ValueError, "expired"):
            grade_run(client=client, **dict(arguments, now=self.now + timedelta(days=31)))
        self.assertEqual([], client.calls)

    def test_corrupt_cached_output_metrics_and_identity_rejected_before_paid_call(self):
        arguments, _ = self.interrupted(successful=7)
        path = arguments["checkpoint_path"]
        original = path.read_bytes()
        for kind in ("json", "digest", "score", "identity", "pairwise", "metrics", "unknown-cell"):
            with self.subTest(kind=kind):
                if kind == "json":
                    path.write_text("not json")
                elif kind == "digest":
                    path.write_bytes(original.replace(b"Grounded", b"Altered!"))
                else:
                    def mutate(state):
                        cells = list(state["cells"].values())
                        absolute = next(cell for cell in cells if cell["output"] and "scores" in cell["output"])
                        if kind == "score":
                            absolute["output"]["scores"]["childClarity"] = 6
                        elif kind == "identity":
                            absolute["output"]["evidence"] = ["candidate-id is better"]
                        elif kind == "pairwise":
                            next(cell for cell in cells if cell["output"] and "winner" in cell["output"])["output"]["winner"] = "invalid"
                            # Even an earlier missing judgment must not be paid
                            # for before a later invalid cached grade is found.
                            del state["cells"][next(key for key in state["cells"] if key.startswith("absolute|"))]
                        elif kind == "metrics":
                            absolute["attempts"][0]["metrics"]["latencyMilliseconds"] = -1
                        else:
                            state["cells"]["unknown"] = absolute
                    self.rewrite(path, mutate)
                client = ScriptedJudge([])
                with self.assertRaises(ValueError):
                    grade_run(client=client, **arguments)
                self.assertEqual([], client.calls)
                path.write_bytes(original)

    def test_symlink_checkpoint_lock_and_parent_are_rejected(self):
        arguments = self.arguments()
        original = self.root / "untouched"
        original.write_text("unchanged")
        checkpoint = arguments["checkpoint_path"]
        for target in (checkpoint, checkpoint.with_name(checkpoint.name + ".lock")):
            target.symlink_to(original)
            client = ScriptedJudge([])
            with self.assertRaisesRegex(ValueError, "symlink"):
                grade_run(client=client, **arguments)
            self.assertEqual([], client.calls)
            self.assertEqual("unchanged", original.read_text())
            target.unlink()
        parent = self.root / "linked"
        parent.symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlink"):
            grade_run(client=ScriptedJudge([]), **dict(arguments, checkpoint_path=parent / "other.json"))

    def test_concurrent_process_cannot_use_same_checkpoint(self):
        arguments = self.arguments()
        checkpoint = arguments["checkpoint_path"]
        lock = checkpoint.with_name(checkpoint.name + ".lock")
        script = "import fcntl,sys; f=open(sys.argv[1], 'a'); fcntl.flock(f,fcntl.LOCK_EX); print('locked',flush=True); sys.stdin.read()"
        with subprocess.Popen([sys.executable, "-c", script, str(lock)], stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE, text=True) as process:
            self.assertEqual("locked\n", process.stdout.readline())
            client = ScriptedJudge([])
            with self.assertRaisesRegex(ValueError, "in use"):
                grade_run(client=client, **arguments)
            self.assertEqual([], client.calls)
            process.kill()  # A crashed writer cannot leave an unrecoverable lock.
            process.stdin.close()
            process.wait(timeout=5)
        grade_run(client=ScriptedJudge(self.outputs()), **arguments)

    def test_output_overwrite_and_checkpoint_inside_output_refused_before_provider_use(self):
        arguments = self.arguments()
        destination = arguments["destination"]
        destination.mkdir()
        (destination / "grade-manifest.json").write_text("existing completed run")
        client = ScriptedJudge([])
        with self.assertRaisesRegex(ValueError, "overwrite"):
            grade_run(client=client, **arguments)
        self.assertEqual([], client.calls)
        self.assertFalse(arguments["checkpoint_path"].exists())
        other = self.root / "new-grades"
        for path in (other, other / "checkpoint.json"):
            with self.assertRaisesRegex(ValueError, "output"):
                grade_run(client=client, **dict(arguments, destination=other, checkpoint_path=path))
        self.assertEqual([], client.calls)


if __name__ == "__main__":
    unittest.main()
