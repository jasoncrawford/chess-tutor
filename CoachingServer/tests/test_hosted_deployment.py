"""The deployable bundle, not the full checkout, must run the real server."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import shutil


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/deploy_coaching_server.py"


class HostedDeploymentTests(unittest.TestCase):
    def test_deploy_creates_private_configuration_without_secrets_in_arguments_or_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for name in ("security", "vercel"):
                shutil.copyfile(ROOT / "CoachingServer/tests/fixtures/setup_command.py", directory / name)
                (directory / name).chmod(0o755)
            (directory / "keys.json").write_text(json.dumps({"ChessTutor-CoachingEval-OpenAI": "test-openai-key"}))
            environment = {**os.environ, "PATH": str(directory) + os.pathsep + os.environ["PATH"], "SETUP_TEST_STATE": temporary}
            result = subprocess.run([sys.executable, str(SCRIPT), "--deploy"], cwd=temporary, env=environment, capture_output=True, text=True)
            self.assertEqual(0, result.returncode, result.stderr)
            keys = json.loads((directory / "keys.json").read_text())
            self.assertGreaterEqual(len(keys["ChessTutor-HostedCoaching-Family"]), 43)
            calls = [json.loads(line) for line in (directory / "calls.jsonl").read_text().splitlines()]
            argv = json.dumps([call["args"] for call in calls])
            for secret in keys.values():
                self.assertNotIn(secret, argv)
                self.assertNotIn(secret, result.stdout + result.stderr)
            inputs = {call["args"][2]: call["input"] for call in calls if call["command"] == "vercel" and call["args"][:2] == ["env", "add"]}
            self.assertEqual("test-openai-key", inputs["OPENAI_API_KEY"])
            self.assertEqual(keys["ChessTutor-HostedCoaching-Family"], inputs["CHESS_TUTOR_COACHING_ACCESS_TOKEN"])
            self.assertIn("https://chess-tutor-coaching.vercel.app", result.stdout)

            environment["SETUP_TEST_FAIL"] = "vercel"
            result = subprocess.run([sys.executable, str(SCRIPT), "--deploy"], cwd=temporary, env=environment, capture_output=True, text=True)
            self.assertNotEqual(0, result.returncode)
            self.assertNotIn("test-openai-key", result.stdout + result.stderr)

    def test_packaged_server_boots_with_pinned_policy_and_enforces_authentication(self):
        # Catches missing runtime imports/resources and accidental inclusion of local data.
        self.assertTrue(SCRIPT.is_file(), "A reproducible deployment command is required")
        with tempfile.TemporaryDirectory() as temporary:
            bundle = Path(temporary) / "runtime"
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--package", str(bundle)],
                cwd=temporary, capture_output=True, text=True,
            )
            self.assertEqual(0, result.returncode, result.stderr)
            files = {str(path.relative_to(bundle)) for path in bundle.rglob("*") if path.is_file()}
            self.assertIn("api/index.py", files)
            self.assertNotIn(".env", files)
            self.assertFalse(any("tests/" in name or name.startswith(("ChessTutor/", ".coaching-eval/", ".git/", ".venv/")) for name in files))
            self.assertLess(sum(path.stat().st_size for path in bundle.rglob("*") if path.is_file()), 1_000_000)
            environment = {**os.environ, "OPENAI_API_KEY": "test-not-a-real-key", "CHESS_TUTOR_COACHING_ACCESS_TOKEN": "test-family-token"}
            environment.pop("PYTHONPATH", None)
            environment.update(json.loads((bundle / "vercel.json").read_text())["env"])
            probe = '''
from pathlib import Path
import os
from api.index import app
from CoachingServer.model_configuration import HostedModelConfiguration
c = HostedModelConfiguration.load(os.environ["CHESS_TUTOR_COACHING_MODEL_CONFIG"], Path.cwd())
assert c.model == "gpt-6-astra"
assert c.user_prompt_generator == "chess-native-grounded-v4"
assert c.initial_reasoning_effort == c.simple_follow_up_reasoning_effort == "low"
assert c.system_prompt_sha256 == "d15b6f422607b4325089ca1a1522e5927d5afc46313bbdccb8cd90fd8b297225"
client = app.test_client()
assert client.get("/health").json == {"status": "ok"}
assert client.post("/v1/coaching-turn", json={}).status_code == 401
assert client.post("/v1/coaching-turn", json={}, headers={"Authorization": "Bearer wrong"}).status_code == 401
assert client.post("/v1/coaching-turn", json={}, headers={"Authorization": "Bearer test-family-token"}).status_code == 400
for path in ("/.env", "/CoachingServer/http_app.py", "/vercel.json"):
    assert client.get(path).status_code == 404
'''
            result = subprocess.run([sys.executable, "-c", probe], cwd=bundle, env=environment, capture_output=True, text=True)
            self.assertEqual(0, result.returncode, result.stderr)

    def test_package_refuses_to_overwrite_an_existing_directory(self):
        self.assertTrue(SCRIPT.is_file())
        with tempfile.TemporaryDirectory() as temporary:
            result = subprocess.run([sys.executable, str(SCRIPT), "--package", temporary], capture_output=True, text=True)
            self.assertNotEqual(0, result.returncode)


if __name__ == "__main__":
    unittest.main()
