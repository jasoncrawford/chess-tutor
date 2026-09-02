import io
import json
import os
import signal
import subprocess
import tempfile
import time
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from Tools.CoachingEval.benchmark import cli


ROOT = Path(__file__).resolve().parents[3]
LAUNCHER = ROOT / "scripts/run_coaching_quality_benchmark.sh"


class BenchmarkCLITests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.secret = "sk-test-private-benchmark-key"

    def tearDown(self):
        self.temporary.cleanup()

    def test_run_loads_exact_candidates_and_keeps_key_out_of_output(self):
        candidates = []
        clients = []

        def load_candidate(path, _root):
            value = SimpleNamespace(identifier=Path(path).stem)
            candidates.append(value)
            return value

        class Client:
            def __init__(self, *, api_key):
                self.api_key = api_key
                clients.append(self)

        def run_candidates(**arguments):
            self.assertEqual(candidates, list(arguments["configurations"]))
            for configuration in candidates:
                self.assertIsInstance(arguments["provider_factory"](configuration), Client)
            self.assertTrue(arguments["include_holdout"])
            return {"summary": {"recordCount": 12, "validCount": 11, "failedCount": 1}}

        output = io.StringIO()
        with (
            mock.patch.dict(os.environ, {"PRIVATE_BENCHMARK_KEY": self.secret}, clear=True),
            mock.patch.object(cli, "load_corpus", return_value=SimpleNamespace()),
            mock.patch.object(cli, "load_candidate", side_effect=load_candidate),
            mock.patch.object(cli, "load_prices", return_value=SimpleNamespace()),
            mock.patch.object(cli, "run_candidates", side_effect=run_candidates),
            mock.patch.object(cli, "OpenAIResponsesClient", Client),
            redirect_stdout(output),
        ):
            status = cli.main(
                [
                    "run",
                    "--corpus", str(self.root / "corpus"),
                    "--mode", "comparison",
                    "--candidate", "baseline.json",
                    "--candidate", "candidate.json",
                    "--pricing", "prices.json",
                    "--output", str(self.root / "run"),
                    "--api-key-env", "PRIVATE_BENCHMARK_KEY",
                    "--include-holdout",
                ]
            )
        result = json.loads(output.getvalue())
        self.assertEqual(0, status)
        self.assertEqual(["baseline", "candidate"], result["configurationIDs"])
        self.assertEqual(12, result["recordCount"])
        self.assertEqual([self.secret, self.secret], [client.api_key for client in clients])
        self.assertNotIn(self.secret, output.getvalue())

    def test_grade_and_report_print_only_bounded_summaries(self):
        output = io.StringIO()
        grade_destination = self.root / "grades"
        report_destination = self.root / "report"
        client_values = []

        class Client:
            def __init__(self, *, api_key):
                client_values.append(api_key)

        with (
            mock.patch.dict(os.environ, {"JUDGE_SECRET": self.secret}, clear=True),
            mock.patch.object(cli, "load_corpus", return_value=SimpleNamespace()),
            mock.patch.object(cli, "load_judge", return_value=SimpleNamespace(identifier="judge-v1")),
            mock.patch.object(cli, "load_prices", return_value=SimpleNamespace()),
            mock.patch.object(cli, "grade_run", return_value=grade_destination) as grade,
            mock.patch.object(cli, "OpenAIResponsesClient", Client),
            redirect_stdout(output),
        ):
            status = cli.main(
                [
                    "grade", "--run", "run", "--corpus", "corpus",
                    "--judge", "judge.json", "--pricing", "prices.json",
                    "--output", str(grade_destination), "--api-key-env", "JUDGE_SECRET",
                ]
            )
        self.assertEqual(0, status)
        self.assertEqual([self.secret], client_values)
        self.assertEqual(1, grade.call_count)
        grade_summary = json.loads(output.getvalue())
        self.assertEqual("judge-v1", grade_summary["judgeID"])
        self.assertNotIn(self.secret, output.getvalue())

        output = io.StringIO()
        aggregate_path = report_destination / "aggregate.json"
        summary_path = report_destination / "summary.md"
        with (
            mock.patch.object(cli, "load_prices", return_value=SimpleNamespace()),
            mock.patch.object(cli, "write_report", return_value=(aggregate_path, summary_path)),
            redirect_stdout(output),
        ):
            status = cli.main(
                [
                    "report", "--run", "run", "--grades", "grades",
                    "--pricing", "prices.json", "--output", str(report_destination),
                ]
            )
        self.assertEqual(0, status)
        report_summary = json.loads(output.getvalue())
        self.assertEqual(str(summary_path), report_summary["summary"])
        self.assertNotIn(self.secret, output.getvalue())

    def test_missing_named_credential_fails_before_provider_work(self):
        stdout = io.StringIO()
        stderr = io.StringIO()
        with (
            mock.patch.dict(os.environ, {}, clear=True),
            mock.patch.object(cli, "run_candidates") as run,
            redirect_stdout(stdout),
            redirect_stderr(stderr),
        ):
            status = cli.main(
                [
                    "run", "--corpus", "corpus", "--mode", "quick",
                    "--candidate", "baseline.json", "--pricing", "prices.json",
                    "--output", "output", "--api-key-env", "MISSING_KEY",
                ]
            )
        self.assertEqual(1, status)
        self.assertFalse(run.called)
        failure = json.loads(stderr.getvalue())
        self.assertEqual("missingCredential", failure["category"])


class BenchmarkLauncherTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "commands.log"
        self.artifacts = self.root / "artifacts"
        self.env = os.environ.copy()
        self.env.update(
            {
                "PATH": f"{self.bin}:/usr/bin:/bin:/usr/sbin:/sbin",
                "FAKE_COMMAND_LOG": str(self.log),
                "CHESS_TUTOR_BENCHMARK_ARTIFACT_ROOT": str(self.artifacts),
                "CHESS_TUTOR_BENCHMARK_TIMESTAMP": "20260901T120000Z",
            }
        )
        self.write_fake("security", "printf '%s\\n' 'sk-private-launcher-key'")
        self.write_fake("git", "printf '%s\\n' 'source-sha'")
        self.write_fake(
            "xcodebuild",
            """
            printf 'xcodebuild %s\n' "$*" >> "$FAKE_COMMAND_LOG"
            mkdir -p "$COACHING_QUALITY_BENCHMARK_OUTPUT_DIR"
            printf '{}\n' > "$COACHING_QUALITY_BENCHMARK_OUTPUT_DIR/benchmark-manifest.json"
            printf '{}\n' > "$COACHING_QUALITY_BENCHMARK_OUTPUT_DIR/cases.jsonl"
            """,
        )
        self.write_fake(
            "python3",
            """
            key_state=missing
            [ -n "${OPENAI_API_KEY:-}" ] && key_state=set
            printf 'python key=%s %s\n' "$key_state" "$*" >> "$FAKE_COMMAND_LOG"
            destination=''
            previous=''
            for value in "$@"; do
              if [ "$previous" = '--output' ]; then destination="$value"; fi
              previous="$value"
            done
            [ -n "$destination" ] && mkdir -p "$destination"
            printf '%s\n' '{"status":"completed"}'
            """,
        )

    def tearDown(self):
        self.temporary.cleanup()

    def test_one_command_exports_runs_grades_and_reports_without_leaking_key(self):
        result = subprocess.run(
            [str(LAUNCHER), "comparison", "candidate.json"],
            cwd=ROOT,
            env=self.env,
            capture_output=True,
            text=True,
            timeout=20,
        )
        combined = result.stdout + result.stderr
        commands = self.log.read_text()
        self.assertEqual(0, result.returncode, combined)
        self.assertEqual(1, commands.count("xcodebuild"))
        self.assertEqual(1, commands.count("benchmark.cli run"))
        self.assertEqual(1, commands.count("benchmark.cli grade"))
        self.assertEqual(1, commands.count("benchmark.cli report"))
        self.assertIn("production-v1.json", commands)
        self.assertIn("candidate.json", commands)
        self.assertNotIn("sk-private-launcher-key", combined)
        self.assertNotIn("sk-private-launcher-key", commands)
        self.assertTrue((self.artifacts / "runs/20260901T120000Z/report").is_dir())

    def test_missing_key_is_actionable_and_interrupt_cleans_partial_artifacts(self):
        self.write_fake("security", "exit 44")
        result = subprocess.run(
            [str(LAUNCHER), "quick"],
            cwd=ROOT,
            env=self.env,
            capture_output=True,
            text=True,
            timeout=10,
        )
        self.assertNotEqual(0, result.returncode)
        self.assertIn("ChessTutor-CoachingEval-OpenAI", result.stderr)
        self.assertFalse(self.log.exists())

        self.write_fake("security", "printf '%s\\n' 'sk-private-launcher-key'")
        self.write_fake(
            "xcodebuild",
            """
            printf '%s\n' xcodebuild >> "$FAKE_COMMAND_LOG"
            trap 'exit 130' INT TERM
            sleep 20
            """,
        )
        process = subprocess.Popen(
            [str(LAUNCHER), "quick"],
            cwd=ROOT,
            env=self.env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )
        for _ in range(100):
            if self.log.exists() and "xcodebuild" in self.log.read_text():
                break
            time.sleep(0.02)
        os.killpg(process.pid, signal.SIGINT)
        process.communicate(timeout=5)
        self.assertFalse((self.artifacts / "corpus/source-sha-20260901T120000Z").exists())
        self.assertFalse((self.artifacts / "runs/20260901T120000Z").exists())

    def write_fake(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/bash\nset -euo pipefail\n" + body.strip() + "\n")
        path.chmod(0o755)


if __name__ == "__main__":
    unittest.main()
