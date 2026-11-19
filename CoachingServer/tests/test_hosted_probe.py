import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch
import urllib.error

from scripts.probe_hosted_coaching import HostedProbe


class HostedProbeTests(unittest.TestCase):
    def test_call_cap_is_checked_before_external_work(self):
        probe = HostedProbe()
        with patch.object(probe, "_api") as api:
            for calls in (0, 5, True):
                with self.assertRaises(ValueError):
                    probe.replay("not-read.json", calls=calls)
            api.assert_not_called()

    def test_failed_probe_removes_only_its_new_project(self):
        probe = HostedProbe()
        original = {"id": "prj_live", "accountId": probe.manifest["teamID"],
                    "targets": {"production": {"id": "dpl_live"}},
                    "ssoProtection": {"deploymentType": "all_except_custom_domains"}}
        def api_response(path, *, method="GET", body=None):
            if method == "POST":
                return {"id": "prj_temporary", "name": body["name"]}
            return {} if method == "DELETE" else original
        with patch.object(Path, "read_text", return_value=json.dumps({"position": {"fen":
                "r2q2k1/ppp5/6N1/2PP1r1p/3Q4/5p2/PPP2PP1/R4RK1 w - - 0 24"}})), \
             patch.object(probe, "_api", side_effect=api_response) as api, \
             patch.object(probe, "_replay_project", side_effect=RuntimeError("probe failed")), \
             patch.object(probe, "_emit") as emit:
            with self.assertRaisesRegex(RuntimeError, "probe failed"):
                probe.replay("recorded-request.json", calls=1)
        deletions = [call.args[0] for call in api.call_args_list if call.kwargs.get("method") == "DELETE"]
        self.assertEqual(deletions, ["/v9/projects/prj_temporary"])
        emit.assert_any_call("diagnostic_project_removed", project_id="prj_temporary",
                             production_unchanged=True, production_protection_unchanged=True)

    def test_caller_timeout_collects_logs_before_removing_deployment(self):
        probe = HostedProbe()
        health = io.BytesIO(b'{"status":"ok"}')
        health.status = 200
        health.headers = {"Content-Type": "application/json"}
        opener = Mock()
        opener.open.side_effect = [health, urllib.error.HTTPError("https://test/", 401, "", {}, io.BytesIO()),
                                   TimeoutError("caller timed out")]
        actions = []
        def api_response(path, *, method="GET", body=None):
            if method == "DELETE":
                actions.append("delete")
            return {"id": "dpl_diagnostic", "readyState": "READY"}
        def collect(*args, **kwargs):
            self.assertEqual(kwargs["calls"], 1)
            actions.append("logs")
        with patch.object(probe, "_api", side_effect=api_response), \
             patch.object(probe, "read_secret", return_value="not-a-real-key"), \
             patch.object(probe, "_emit"), patch.object(probe, "_collect_transport_logs", side_effect=collect), \
             patch("scripts.probe_hosted_coaching.urllib.request.build_opener", return_value=opener):
            with self.assertRaises(TimeoutError):
                probe._replay_project({}, 4, {"id": "prj_diagnostic", "name": "chess-tutor-diag-1234567890"}, "dpl_live")
        self.assertEqual(actions, ["logs", "delete"])
        self.assertEqual(opener.open.call_count, 3)  # health, auth rejection, one paid attempt

    def test_waits_for_final_transport_logs_before_cleanup(self):
        probe = HostedProbe()
        connected = {"event": "diagnostic_transport", "client_request_id": "one", "stage": "connected"}
        finished = {"event": "diagnostic_transport", "client_request_id": "one", "stage": "complete"}
        def response(*records):
            return {"rows": [{"logs": [{"message": json.dumps(record)} for record in records]}]}
        with patch.object(probe, "_api", side_effect=[response(connected), response(connected, finished)]) as api, \
             patch.object(probe, "_emit") as emit, patch("scripts.probe_hosted_coaching.time.sleep"):
            probe._collect_transport_logs("diagnostic-project", "game", 0, calls=1)
        self.assertEqual(api.call_count, 2)
        self.assertEqual([call.kwargs["record"]["stage"] for call in emit.call_args_list
                          if call.args == ("transport",)], ["connected", "complete"])
        self.assertTrue(all("/api/logs/request-logs?" in call.args[0] for call in api.call_args_list))

    def test_reports_missing_logs_without_starting_more_model_calls(self):
        probe = HostedProbe()
        with patch.object(probe, "_api", return_value={"rows": []}) as api, \
             patch.object(probe, "_emit") as emit, patch("scripts.probe_hosted_coaching.time.sleep"):
            probe._collect_transport_logs("diagnostic-project", "game", 0, calls=1)
        self.assertEqual(api.call_count, 15)
        emit.assert_any_call("transport_logs_incomplete", expected=1, completed=0)
        self.assertTrue(all("/api/logs/request-logs?" in call.args[0] for call in api.call_args_list))

    def test_preview_uses_longer_deadline_without_changing_source_policy(self):
        probe = HostedProbe()
        policy_path = probe.root / probe.manifest["modelConfiguration"]
        original = policy_path.read_bytes()
        with tempfile.TemporaryDirectory() as temporary:
            bundle = probe.package(Path(temporary) / "runtime")
            policy = json.loads((bundle / probe.manifest["modelConfiguration"]).read_text())
            expected = json.loads(original)
            expected["timeoutSeconds"] = 90
            self.assertEqual(policy, expected)
            self.assertEqual(policy_path.read_bytes(), original)
            self.assertEqual(json.loads((bundle / "vercel.json").read_text())["functions"]["api/index.py"]["maxDuration"], 120)
            environment = {**os.environ, "OPENAI_API_KEY": "test-not-real",
                           "CHESS_TUTOR_COACHING_ACCESS_TOKEN": "probe-token",
                           "COACHING_DIAGNOSTIC_EXPIRES_AT": str(time.time() + 60)}
            environment.update(json.loads((bundle / "vercel.json").read_text())["env"])
            source = '''
from api.index import app
client = app.test_client()
assert client.get('/health').status_code == 200
assert client.post('/v1/coaching-turn', json={}).status_code == 401
'''
            run = subprocess.run([sys.executable, "-c", source], cwd=bundle, env=environment, capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            environment["COACHING_DIAGNOSTIC_EXPIRES_AT"] = "1"
            run = subprocess.run([sys.executable, "-c", "from api.index import app; assert app.test_client().get('/health').status_code == 503"],
                                 cwd=bundle, env=environment, capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)
