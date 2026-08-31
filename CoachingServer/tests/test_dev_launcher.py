import os
from pathlib import Path
import signal
import subprocess
import tempfile
import textwrap
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = REPOSITORY_ROOT / "scripts" / "run_hosted_coaching_dev.sh"


class HostedCoachingDevelopmentLauncherTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.temp_path = Path(self.temporary_directory.name)
        self.fake_bin = self.temp_path / "bin"
        self.fake_bin.mkdir()
        self.command_log = self.temp_path / "commands.log"
        self.env = os.environ.copy()
        self.env.update(
            {
                "PATH": f"{self.fake_bin}:/usr/bin:/bin:/usr/sbin:/sbin",
                "FAKE_COMMAND_LOG": str(self.command_log),
                "CHESS_TUTOR_COACHING_DEV_PORT": "18787",
                "SIMCTL_CHILD_UNRELATED_SECRET": "do-not-forward",
            }
        )
        self._install_successful_fakes()

    def tearDown(self):
        self.temporary_directory.cleanup()

    def test_launches_configured_app_without_printing_secrets_and_stops_server(self):
        process = subprocess.Popen(
            [str(LAUNCHER)],
            cwd=REPOSITORY_ROOT,
            env=self.env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )

        observed_lines = []
        assert process.stdout is not None
        for _ in range(80):
            line = process.stdout.readline()
            if line:
                observed_lines.append(line)
            if "ChessTutor is ready" in line:
                break
            if process.poll() is not None:
                break
        else:
            self.fail("launcher never reported readiness")

        process.send_signal(signal.SIGINT)
        remaining_output, _ = process.communicate(timeout=10)
        combined_output = "".join(observed_lines) + remaining_output
        command_log = self.command_log.read_text() if self.command_log.exists() else ""

        self.assertEqual(process.returncode, 130, combined_output)
        self.assertNotIn("sk-private-key", combined_output)
        self.assertNotIn("local-token-secret", combined_output)
        self.assertNotIn("sk-private-key", command_log)
        self.assertNotIn("local-token-secret", command_log)
        self.assertIn("simctl boot AA821CF0", command_log)
        self.assertIn("simctl bootstatus AA821CF0 -b", command_log)
        self.assertIn("simctl install AA821CF0", command_log)
        self.assertIn(
            "simctl launch --terminate-running-process AA821CF0 "
            "org.jasoncrawford.chesstutor base-url=set token=set extra-child=missing",
            command_log,
        )
        self.assertIn("server-start key=set token=set", command_log)
        self.assertIn("server-stopped", command_log)

    def test_reports_actionable_error_when_keychain_item_is_missing(self):
        self._write_executable(
            "security",
            """
            #!/bin/bash
            exit 44
            """,
        )

        result = subprocess.run(
            [str(LAUNCHER)],
            cwd=REPOSITORY_ROOT,
            env=self.env,
            capture_output=True,
            text=True,
            timeout=10,
        )

        combined_output = result.stdout + result.stderr
        command_log = self.command_log.read_text() if self.command_log.exists() else ""
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ChessTutor-CoachingEval-OpenAI", combined_output)
        self.assertIn("Keychain", combined_output)
        self.assertNotIn("xcodebuild", command_log)

    def test_does_not_launch_app_when_spawned_server_exits_before_health_check(self):
        self.env["FAKE_SERVER_EXITS_IMMEDIATELY"] = "1"

        result = subprocess.run(
            [str(LAUNCHER)],
            cwd=REPOSITORY_ROOT,
            env=self.env,
            capture_output=True,
            text=True,
            timeout=10,
        )

        combined_output = result.stdout + result.stderr
        command_log = self.command_log.read_text() if self.command_log.exists() else ""
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("server stopped before it became ready", combined_output)
        self.assertNotIn("xcodebuild", command_log)
        self.assertNotIn("simctl install", command_log)

    def test_does_not_accept_health_from_listener_unowned_by_spawned_server(self):
        self.env["FAKE_SERVER_FAILS_AFTER_DELAY"] = "1"

        result = subprocess.run(
            [str(LAUNCHER)],
            cwd=REPOSITORY_ROOT,
            env=self.env,
            capture_output=True,
            text=True,
            timeout=10,
        )

        command_log = self.command_log.read_text() if self.command_log.exists() else ""
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("xcodebuild", command_log)
        self.assertNotIn("simctl install", command_log)

    def test_optional_simulator_name_selects_that_device(self):
        result = subprocess.Popen(
            [str(LAUNCHER), "ChessTutor Coaching Smoke"],
            cwd=REPOSITORY_ROOT,
            env=self.env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )

        observed_lines = []
        assert result.stdout is not None
        for _ in range(80):
            line = result.stdout.readline()
            if line:
                observed_lines.append(line)
            if "ChessTutor is ready" in line or result.poll() is not None:
                break
        result.send_signal(signal.SIGINT)
        remaining_output, _ = result.communicate(timeout=10)
        combined_output = "".join(observed_lines) + remaining_output
        command_log = self.command_log.read_text() if self.command_log.exists() else ""

        self.assertEqual(result.returncode, 130, combined_output)
        self.assertIn("simctl install SMOKE123", command_log)

    def _install_successful_fakes(self):
        self._write_executable(
            "security",
            """
            #!/bin/bash
            printf '%s\n' 'sk-private-key'
            """,
        )
        self._write_executable(
            "openssl",
            """
            #!/bin/bash
            printf '%s\n' 'local-token-secret'
            """,
        )
        self._write_executable(
            "python3",
            """
            #!/bin/bash
            key_state=missing
            token_state=missing
            [ -n "${OPENAI_API_KEY:-}" ] && key_state=set
            [ -n "${CHESS_TUTOR_COACHING_ACCESS_TOKEN:-}" ] && token_state=set
            printf 'server-start key=%s token=%s\n' "$key_state" "$token_state" >> "$FAKE_COMMAND_LOG"
            [ "${FAKE_SERVER_EXITS_IMMEDIATELY:-}" = "1" ] && exit 0
            [ "${FAKE_SERVER_FAILS_AFTER_DELAY:-}" = "1" ] && sleep 2 && exit 0
            trap 'printf "%s\n" server-stopped >> "$FAKE_COMMAND_LOG"; exit 0' TERM INT
            while true; do sleep 1; done
            """,
        )
        self._write_executable(
            "lsof",
            """
            #!/bin/bash
            [ "${FAKE_SERVER_FAILS_AFTER_DELAY:-}" = "1" ] && exit 1
            printf '%s\n' '12345'
            """,
        )
        self._write_executable(
            "curl",
            """
            #!/bin/bash
            printf '%s\n' '{"status":"ok"}'
            """,
        )
        self._write_executable(
            "xcrun",
            """
            #!/bin/bash
            if [ "$*" = "simctl list devices available -j" ]; then
              printf '%s\n' '{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-5":[{"name":"iPad (A16)","udid":"AA821CF0","state":"Shutdown","isAvailable":true},{"name":"ChessTutor Coaching Smoke","udid":"SMOKE123","state":"Booted","isAvailable":true}]}}'
              exit 0
            fi
            if [ "${1:-}" = "simctl" ] && [ "${2:-}" = "launch" ]; then
              base_state=missing
              token_state=missing
              extra_child_state=missing
              [ -n "${SIMCTL_CHILD_CHESS_TUTOR_COACHING_BASE_URL:-}" ] && base_state=set
              [ -n "${SIMCTL_CHILD_CHESS_TUTOR_COACHING_ACCESS_TOKEN:-}" ] && token_state=set
              [ -n "${SIMCTL_CHILD_UNRELATED_SECRET:-}" ] && extra_child_state=present
              printf '%s base-url=%s token=%s extra-child=%s\n' "$*" "$base_state" "$token_state" "$extra_child_state" >> "$FAKE_COMMAND_LOG"
              printf '%s\n' 'org.jasoncrawford.chesstutor: 12345'
              exit 0
            fi
            printf '%s\n' "$*" >> "$FAKE_COMMAND_LOG"
            """,
        )
        self._write_executable(
            "xcodebuild",
            """
            #!/bin/bash
            printf 'xcodebuild %s\n' "$*" >> "$FAKE_COMMAND_LOG"
            derived_data=''
            previous=''
            for argument in "$@"; do
              if [ "$previous" = "-derivedDataPath" ]; then
                derived_data="$argument"
                break
              fi
              previous="$argument"
            done
            mkdir -p "$derived_data/Build/Products/Debug-iphonesimulator/ChessTutor.app"
            """,
        )
        self._write_executable(
            "open",
            """
            #!/bin/bash
            printf 'open %s\n' "$*" >> "$FAKE_COMMAND_LOG"
            """,
        )

    def _write_executable(self, name, body):
        path = self.fake_bin / name
        path.write_text(textwrap.dedent(body).lstrip())
        path.chmod(0o755)


if __name__ == "__main__":
    unittest.main()
