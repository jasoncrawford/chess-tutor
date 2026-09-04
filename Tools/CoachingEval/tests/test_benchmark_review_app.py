import hashlib
import json
import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

from Tools.CoachingEval.benchmark import review_app


ROOT = Path(__file__).resolve().parents[3]
REFERENCE_PATH = ROOT / "Tools/CoachingEval/benchmark/judge-reference-v2.json"
LAUNCHER_PATH = ROOT / "scripts/review_judge_references.sh"
CORE_TEST_PATH = ROOT / "Tools/CoachingEval/tests/test_benchmark_review_core.js"
EXPECTED_REFERENCE_SHA = (
    "3b0bb2ba35df5261967c1af4a0970fec67fd31dcc9f5616ab5c262af9f7c016d"
)


class JudgeReferenceReviewViewModelTests(unittest.TestCase):
    def setUp(self):
        self.reference = review_app.load_reference_set()
        self.model = review_app.build_review_view_model(self.reference)

    def test_builds_deterministic_exact_review_inventory(self):
        repeated = review_app.build_review_view_model(self.reference)

        self.assertEqual(
            json.dumps(self.model, ensure_ascii=False, separators=(",", ":")),
            json.dumps(repeated, ensure_ascii=False, separators=(",", ":")),
        )
        self.assertEqual("judge-reference-review-view.v1", self.model["schemaVersion"])
        self.assertEqual(EXPECTED_REFERENCE_SHA, self.model["reference"]["sha256"])
        self.assertEqual("pending", self.model["reference"]["reviewStatus"])
        self.assertEqual(30, len(self.model["cases"]))
        self.assertEqual(20, sum(case["kind"] == "absolute" for case in self.model["cases"]))
        self.assertEqual(10, sum(case["kind"] == "pairwise" for case in self.model["cases"]))
        self.assertEqual(
            [f"ref-{index:02d}" for index in range(1, 21)]
            + [f"pair-{index:02d}" for index in range(1, 11)],
            [case["id"] for case in self.model["cases"]],
        )

    def test_exposes_only_the_bounded_human_review_fields(self):
        absolute = self.model["cases"][0]
        pairwise = self.model["cases"][20]

        self.assertEqual(
            {
                "id",
                "index",
                "kind",
                "source",
                "position",
                "brief",
                "technical",
                "candidate",
                "proposed",
            },
            set(absolute),
        )
        self.assertEqual(
            {
                "id",
                "index",
                "kind",
                "source",
                "position",
                "brief",
                "technical",
                "responses",
                "proposed",
            },
            set(pairwise),
        )
        self.assertEqual(
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            absolute["position"]["fen"],
        )
        self.assertEqual("helpOpened", absolute["position"]["latestInteraction"]["kind"])
        self.assertEqual(
            "Which knight could you bring toward the middle, where it may have more choices?",
            absolute["candidate"]["message"],
        )
        self.assertEqual("responseOne", pairwise["proposed"]["preference"])
        self.assertNotIn("request", absolute["source"])
        self.assertNotIn("credential", json.dumps(self.model).lower())
        self.assertNotIn("provider", json.dumps(self.model).lower())

    def test_binds_browser_review_storage_to_the_exact_reference_sha(self):
        self.assertEqual(
            "chess-tutor:judge-reference-review:" + EXPECTED_REFERENCE_SHA,
            self.model["reviewStorageKey"],
        )

    def test_keeps_complete_reference_provenance_available_for_audit(self):
        reference = self.model["reference"]

        self.assertEqual("29d24c8bc081fe17431d0e88ab5a0e085c3f1b20", reference["sourceGitSHA"])
        self.assertEqual(64, len(reference["sourceCasesSHA256"]))
        self.assertEqual(64, len(reference["sourceManifestSHA256"]))


class JudgeReferenceReviewHTTPTests(unittest.TestCase):
    def setUp(self):
        self.model = review_app.build_review_view_model(review_app.load_reference_set())
        self.application = review_app.create_application(self.model)
        self.client = self.application.test_client()

    def test_serves_static_shell_assets_and_separate_json_data(self):
        index = self.client.get("/")
        style = self.client.get("/review_app.css")
        core_script = self.client.get("/review_core.js")
        script = self.client.get("/review_app.js")
        data = self.client.get("/api/review")

        self.assertEqual(200, index.status_code)
        self.assertEqual(200, style.status_code)
        self.assertEqual(200, core_script.status_code)
        self.assertEqual(200, script.status_code)
        self.assertEqual(200, data.status_code)
        self.assertTrue(index.content_type.startswith("text/html"))
        self.assertTrue(style.content_type.startswith("text/css"))
        self.assertTrue(core_script.content_type.startswith("text/javascript"))
        self.assertTrue(script.content_type.startswith("text/javascript"))
        self.assertEqual("application/json", data.content_type)
        self.assertIn(b'rel="stylesheet" href="/review_app.css"', index.data)
        self.assertIn(b'src="/review_core.js"', index.data)
        self.assertIn(b'src="/review_app.js"', index.data)
        self.assertIn(b'<details class="reference-mark">', index.data)
        self.assertNotIn(self.model["cases"][0]["candidate"]["message"].encode(), index.data)
        self.assertNotIn(self.model["cases"][0]["position"]["fen"].encode(), index.data)
        self.assertEqual(self.model, data.get_json())

    def test_routes_are_read_only_local_assets_with_browser_security_headers(self):
        for path in (
            "/",
            "/review_app.css",
            "/review_core.js",
            "/review_app.js",
            "/api/review",
        ):
            with self.subTest(path=path):
                response = self.client.get(path)
                self.assertEqual("nosniff", response.headers["X-Content-Type-Options"])
                self.assertEqual("no-referrer", response.headers["Referrer-Policy"])
                self.assertIn("default-src 'self'", response.headers["Content-Security-Policy"])
        self.assertEqual(404, self.client.get("/not-a-review-route").status_code)
        self.assertEqual(405, self.client.post("/api/review", json={}).status_code)
        self.assertEqual(405, self.client.put("/", data=b"change").status_code)

    def test_serving_review_never_mutates_reference_or_calls_a_provider(self):
        before = REFERENCE_PATH.read_bytes()
        with mock.patch.object(
            Path, "write_bytes", side_effect=AssertionError("unexpected write")
        ), mock.patch.object(
            Path, "write_text", side_effect=AssertionError("unexpected write")
        ), mock.patch(
            "socket.create_connection", side_effect=AssertionError("unexpected network call")
        ):
            reference = review_app.load_reference_set()
            model = review_app.build_review_view_model(reference)
            self.assertEqual(30, len(model["cases"]))
            self.assertEqual(200, self.client.get("/api/review").status_code)
            self.assertEqual(200, self.client.get("/").status_code)
        self.assertEqual(before, REFERENCE_PATH.read_bytes())
        self.assertEqual(EXPECTED_REFERENCE_SHA, hashlib.sha256(before).hexdigest())

    def test_executes_the_dependency_free_browser_review_core(self):
        completed = subprocess.run(
            ["node", str(CORE_TEST_PATH)],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
            timeout=20,
        )

        self.assertEqual(0, completed.returncode, completed.stderr)
        self.assertIn("9 review core tests passed", completed.stdout)


class JudgeReferenceReviewLauncherTests(unittest.TestCase):
    def test_no_open_check_mode_resolves_repo_when_launched_elsewhere(self):
        completed = subprocess.run(
            [str(LAUNCHER_PATH), "--no-open", "--check"],
            cwd="/tmp",
            check=False,
            capture_output=True,
            text=True,
            timeout=20,
        )

        self.assertEqual(0, completed.returncode, completed.stderr)
        self.assertEqual(
            f"Judge reference review ready: 30 cases, SHA-256 {EXPECTED_REFERENCE_SHA}\n",
            completed.stdout,
        )

    def test_main_binds_loopback_and_no_open_suppresses_browser_side_effect(self):
        fake_application = mock.Mock()
        with mock.patch.object(
            review_app, "create_application", return_value=fake_application
        ), mock.patch("webbrowser.open") as open_browser:
            result = review_app.main(["--no-open", "--port", "4117"])

        self.assertEqual(0, result)
        open_browser.assert_not_called()
        fake_application.run.assert_called_once_with(
            host="127.0.0.1", port=4117, debug=False, use_reloader=False
        )


if __name__ == "__main__":
    unittest.main()
