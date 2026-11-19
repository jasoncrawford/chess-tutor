import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/install_hosted_coaching_device.py"


class DeviceSetupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        for name in ("security", "xcrun", "xcodebuild"):
            shutil.copyfile(ROOT / "CoachingServer/tests/fixtures/setup_command.py", self.directory / name)
            (self.directory / name).chmod(0o755)
        (self.directory / "keys.json").write_text(json.dumps({"ChessTutor-HostedCoaching-Family": "test-family-token"}))
        self.environment = {**os.environ, "PATH": str(self.directory) + os.pathsep + os.environ["PATH"], "SETUP_TEST_STATE": str(self.directory)}

    def run_setup(self, device="test-device-id"):
        self.assertTrue(SCRIPT.is_file(), "One-command device provisioning is required")
        return subprocess.run([sys.executable, str(SCRIPT), "--device", device], cwd=self.directory, env=self.environment, capture_output=True, text=True)

    def calls(self):
        return [json.loads(line) for line in (self.directory / "calls.jsonl").read_text().splitlines()]

    def test_installs_to_explicit_device_and_passes_secrets_only_in_launch_environment(self):
        result = self.run_setup()
        self.assertEqual(0, result.returncode, result.stderr)
        calls = self.calls()
        launch = next(call for call in calls if call["args"][:4] == ["devicectl", "device", "process", "launch"])
        self.assertEqual("test-device-id", launch["args"][launch["args"].index("--device") + 1])
        self.assertEqual("test-family-token", launch["childEnvironment"]["DEVICECTL_CHILD_CHESS_TUTOR_COACHING_ACCESS_TOKEN"])
        self.assertEqual("https://chess-tutor-coaching.vercel.app", launch["childEnvironment"]["DEVICECTL_CHILD_CHESS_TUTOR_COACHING_BASE_URL"])
        for call in calls:
            self.assertNotIn("test-family-token", json.dumps(call["args"]))
            if call != launch:
                self.assertEqual({}, call["childEnvironment"])
        self.assertNotIn("test-family-token", result.stdout + result.stderr)
        build = next(call for call in calls if call["command"] == "xcodebuild")
        self.assertIn("id=test-hardware-udid", build["args"])
        self.assertIn("Release", build["args"])

    def test_missing_device_or_secret_stops_before_build(self):
        for device, keys in [("not-the-family-device", {"ChessTutor-HostedCoaching-Family": "test-family-token"}), ("test-device-id", {})]:
            with self.subTest(device=device, has_keys=bool(keys)):
                (self.directory / "keys.json").write_text(json.dumps(keys))
                result = self.run_setup(device)
                self.assertNotEqual(0, result.returncode)
                self.assertFalse(any(call["command"] == "xcodebuild" for call in self.calls()))

    def test_install_failure_does_not_launch_or_print_sensitive_diagnostics(self):
        self.environment["SETUP_TEST_FAIL"] = "install"
        result = self.run_setup()
        self.assertNotEqual(0, result.returncode)
        self.assertNotIn("test-family-token", result.stdout + result.stderr)
        self.assertFalse(any(call["args"][:4] == ["devicectl", "device", "process", "launch"] for call in self.calls()))

    def test_simulated_and_unpaired_devices_are_not_installed(self):
        for key, value in [("SETUP_TEST_REALITY", "simulated"), ("SETUP_TEST_PAIRING", "unpaired"), ("SETUP_TEST_CONNECTION", "unavailable")]:
            with self.subTest(key=key):
                self.environment[key] = value
                result = self.run_setup()
                self.assertNotEqual(0, result.returncode)
                self.assertFalse(any(call["command"] == "xcodebuild" for call in self.calls()))
                del self.environment[key]

    def test_insecure_manifest_stops_before_any_external_command(self):
        checkout = self.directory / "checkout"
        (checkout / "scripts").mkdir(parents=True)
        (checkout / "CoachingServer").mkdir()
        for name in ("install_hosted_coaching_device.py", "deploy_coaching_server.py"):
            shutil.copyfile(ROOT / "scripts" / name, checkout / "scripts" / name)
        manifest = json.loads((ROOT / "CoachingServer/deployment.json").read_text())
        manifest["baseURL"] = "http://insecure.example"
        (checkout / "CoachingServer/deployment.json").write_text(json.dumps(manifest))
        result = subprocess.run([sys.executable, str(checkout / "scripts/install_hosted_coaching_device.py"), "--device", "test-device-id"], env=self.environment, capture_output=True, text=True)
        self.assertNotEqual(0, result.returncode)
        self.assertIn("HTTPS origin", result.stderr)
        self.assertFalse((self.directory / "calls.jsonl").exists())

