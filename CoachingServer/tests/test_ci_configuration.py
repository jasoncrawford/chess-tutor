import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "tests.yml"


class PullRequestCIConfigurationTests(unittest.TestCase):
    def test_workflow_runs_the_approved_read_only_test_contract(self):
        self.assertTrue(WORKFLOW.is_file(), f"missing workflow: {WORKFLOW}")
        source = WORKFLOW.read_text(encoding="utf-8")

        self.assertRegex(source, r"(?m)^on:\n  pull_request:\n  workflow_dispatch:$")
        self.assertRegex(source, r"(?m)^permissions:\n  contents: read$")
        self.assertRegex(
            source,
            r"(?m)^concurrency:\n"
            r"  group: pull-request-tests-\$\{\{ github\.event\.pull_request\.number \|\| github\.ref \}\}\n"
            r"  cancel-in-progress: true$",
        )

        self.assertRegex(
            source,
            r"(?ms)^  python:\n"
            r"    name: Python\n"
            r"    runs-on: ubuntu-24\.04\n"
            r"    timeout-minutes: 10\n.*?"
            r"uses: actions/checkout@v6.*?"
            r"uses: actions/setup-python@v6\n"
            r"        with:\n"
            r"          python-version: '3\.12'.*?"
            r"python -m pip install -r requirements\.txt.*?"
            r"python -m unittest discover -s CoachingServer/tests -v.*?"
            r"python -m unittest discover -s Tools/CoachingEval/tests -v.*?"
            r"uses: actions/upload-artifact@v7\n"
            r"        if: failure\(\)\n"
            r"        with:\n"
            r"          name: python-test-output\n"
            r"          path: python-test-output\.txt$",
        )
        self.assertRegex(
            source,
            r"(?ms)^  ipad:\n"
            r"    name: iPad\n"
            r"    runs-on: macos-26\n"
            r"    timeout-minutes: 20\n"
            r"    env:\n"
            r"      DEVELOPER_DIR: /Applications/Xcode_26\.6\.app/Contents/Developer\n.*?"
            r"uses: actions/checkout@v6.*?"
            r"xcodebuild test -project ChessTutor\.xcodeproj -scheme ChessTutor "
            r"-destination 'platform=iOS Simulator,name=iPad \(A16\)' "
            r"-resultBundlePath ChessTutor\.xcresult.*?"
            r"uses: actions/upload-artifact@v7\n"
            r"        if: failure\(\)\n"
            r"        with:\n"
            r"          name: ChessTutor\.xcresult\n"
            r"          path: ChessTutor\.xcresult$",
        )


if __name__ == "__main__":
    unittest.main()
