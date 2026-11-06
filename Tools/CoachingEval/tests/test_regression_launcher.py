import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts/run_coaching_regressions.sh"


class RegressionLauncherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "commands"
        self.env = dict(os.environ, PATH=str(self.bin) + ":/usr/bin:/bin",
                        CHESS_TUTOR_REGRESSION_ARTIFACT_ROOT=str(self.root / "artifacts"),
                        CHESS_TUTOR_REGRESSION_TIMESTAMP="test", COMMAND_LOG=str(self.log))
        self.fake("git", 'if [ "$1" = status ]; then echo -n "${FAKE_DIRTY:-}"; else echo abc123; fi')
        self.fake("security", 'echo sk-test-never-print')
        self.fake("xcodebuild", 'echo "export:$*:$COACHING_QUALITY_BENCHMARK_OUTPUT_DIR:$COACHING_PLAYTHROUGH_BENCHMARK_OUTPUT_DIR:$COACHING_QUALITY_BENCHMARK_SOURCE_SHA" >> "$COMMAND_LOG"\nexit "${EXPORT_FAILURE:-0}"')
        self.fake("eval-python", 'echo "evaluate:$*:key-${OPENAI_API_KEY:+present}" >> "$COMMAND_LOG"')
        self.env["CHESS_TUTOR_EVAL_PYTHON"] = str(self.bin / "eval-python")

    def fake(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/bash\n" + body + "\n")
        path.chmod(0o755)

    def run_script(self, *args):
        return subprocess.run(["bash", str(SCRIPT), *args], cwd=ROOT, env=self.env,
                              capture_output=True, text=True, timeout=10)

    def test_exports_both_suites_then_runs_bounded_current_config_without_exposing_key(self):
        result = self.run_script("--max-cost", "4")
        self.assertEqual(0, result.returncode, result.stderr)
        commands = self.log.read_text()
        self.assertIn("name=ChessTutor Coaching Smoke", commands)
        self.assertIn("CoachingPlaythroughBenchmarkTests/testOptInExport", commands)
        self.assertIn("CoachingQualityBenchmarkCorpusTests/testOptInExport", commands)
        self.assertIn("CoachingExperienceBenchmarkTests/testOptInExport", commands)
        self.assertIn("--experience", commands)
        self.assertIn("--max-cost 4", commands)
        self.assertIn("--regressions", commands)
        self.assertIn("key-present", commands)
        self.assertNotIn("sk-test-never-print", commands + result.stdout + result.stderr)
        self.assertNotEqual(0, self.run_script().returncode)

    def test_dirty_source_or_failed_export_never_starts_paid_work(self):
        self.env["FAKE_DIRTY"] = " M file"
        result = self.run_script()
        self.assertNotEqual(0, result.returncode)
        self.assertFalse(self.log.exists())
        self.env.pop("FAKE_DIRTY")
        self.env["EXPORT_FAILURE"] = "7"
        result = self.run_script()
        self.assertNotEqual(0, result.returncode)
        self.assertNotIn("evaluate:", self.log.read_text())
