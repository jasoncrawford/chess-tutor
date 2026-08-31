import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "tests.yml"
CI_REQUIREMENTS = ROOT / "requirements-ci.txt"


PYTHON_TEST_COMMAND = """set -o pipefail
coaching_server_status=0
python -m unittest discover -s CoachingServer/tests -v 2>&1 | tee python-test-output.txt || coaching_server_status=$?
coaching_eval_status=0
python -m unittest discover -s Tools/CoachingEval/tests -v 2>&1 | tee -a python-test-output.txt || coaching_eval_status=$?
if [ \"$coaching_server_status\" -ne 0 ] || [ \"$coaching_eval_status\" -ne 0 ]; then
  exit 1
fi
"""


class PullRequestCIConfigurationTests(unittest.TestCase):
    def test_workflow_runs_the_approved_read_only_test_contract(self):
        self.assertTrue(WORKFLOW.is_file(), f"missing workflow: {WORKFLOW}")

        workflow = yaml.load(WORKFLOW.read_text(encoding="utf-8"), Loader=yaml.BaseLoader)

        self.assertEqual(
            {
                "name": "Pull Request Tests",
                "on": {"pull_request": "", "workflow_dispatch": ""},
                "permissions": {"contents": "read"},
                "concurrency": {
                    "group": "pull-request-tests-${{ github.event.pull_request.number || github.ref }}",
                    "cancel-in-progress": "true",
                },
            },
            {key: workflow[key] for key in ("name", "on", "permissions", "concurrency")},
        )

        jobs = workflow["jobs"]
        self.assertEqual({"python", "ipad"}, set(jobs))
        self.assertTrue(all("permissions" not in job for job in jobs.values()))
        self.assertEqual(
            {
                "name": "Python",
                "runs-on": "ubuntu-24.04",
                "timeout-minutes": "10",
                "steps": [
                    {"uses": "actions/checkout@v6"},
                    {
                        "uses": "actions/setup-python@v6",
                        "with": {"python-version": "3.12"},
                    },
                    {
                        "name": "Install dependencies",
                        "run": "python -m pip install -r requirements.txt -r requirements-ci.txt",
                    },
                    {"name": "Run Python tests", "run": PYTHON_TEST_COMMAND},
                    {
                        "name": "Upload Python test output",
                        "uses": "actions/upload-artifact@v7",
                        "if": "failure()",
                        "with": {
                            "name": "python-test-output",
                            "path": "python-test-output.txt",
                        },
                    },
                ],
            },
            jobs["python"],
        )
        self.assertEqual(
            {
                "name": "iPad",
                "runs-on": "macos-26",
                "timeout-minutes": "20",
                "env": {"DEVELOPER_DIR": "/Applications/Xcode_26.6.app/Contents/Developer"},
                "steps": [
                    {"uses": "actions/checkout@v6"},
                    {
                        "name": "Run iPad tests",
                        "run": "xcodebuild test -project ChessTutor.xcodeproj -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -resultBundlePath ChessTutor.xcresult",
                    },
                    {
                        "name": "Upload Xcode result bundle",
                        "uses": "actions/upload-artifact@v7",
                        "if": "failure()",
                        "with": {
                            "name": "ChessTutor.xcresult",
                            "path": "ChessTutor.xcresult",
                        },
                    },
                ],
            },
            jobs["ipad"],
        )
        self.assertTrue(CI_REQUIREMENTS.is_file(), f"missing CI requirements: {CI_REQUIREMENTS}")
        self.assertEqual("PyYAML==6.0.3\n", CI_REQUIREMENTS.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
