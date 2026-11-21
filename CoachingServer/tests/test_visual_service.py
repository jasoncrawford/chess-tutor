import copy
import json
import unittest

from CoachingServer.http_app import create_application
from CoachingServer.model_configuration import HostedModelConfiguration
from CoachingServer.service import HostedCoachingService
from CoachingServer.versioned_service import VersionedHostedCoachingService
from CoachingServer.tests.test_service import ROOT, RecordingProvider, hosted_request
from Tools.CoachingEval.visual_response import VisualResponseContract


class VisualServiceTests(unittest.TestCase):
    def setUp(self):
        self.fixture = json.loads((ROOT / "Tools/CoachingEval/fixtures/visual-coaching-validation-v1.json").read_text())
        self.legacy_provider = RecordingProvider()
        self.visual_provider = RecordingProvider()
        self.visual_turn = next(c["turn"] for c in self.fixture["cases"] if c["id"] == "linked-threat")
        self.visual_provider.response["output_text"] = json.dumps(self.visual_turn)
        self.legacy_config = HostedModelConfiguration.load(ROOT / "CoachingServer/configs/production-v2.json", ROOT)
        self.visual_config = HostedModelConfiguration.load(ROOT / "CoachingServer/configs/visual-v1.json", ROOT)
        service = VersionedHostedCoachingService(
            legacy=HostedCoachingService(provider=self.legacy_provider, configuration=self.legacy_config),
            visual=HostedCoachingService(provider=self.visual_provider, configuration=self.visual_config))
        self.client = create_application(service=service, access_token="test").test_client()

    def post(self, version, previous=None):
        envelope = hosted_request(request=self.fixture["requests"]["normal"], previous_response_id=previous)
        envelope["schemaVersion"] = "hosted-coaching-request." + version
        return self.client.post("/v1/coaching-turn", json=envelope, headers={"Authorization": "Bearer test"})

    def test_v3_installed_client_keeps_its_plain_text_contract(self):
        response = self.post("v3")
        self.assertEqual(200, response.status_code)
        self.assertEqual("hosted-coaching-turn.v3", response.json["schemaVersion"])
        self.assertIsInstance(response.json["turn"]["message"], str)
        self.assertEqual([], self.visual_provider.calls)

    def test_v4_receives_validated_structured_references(self):
        response = self.post("v4")
        self.assertEqual(200, response.status_code, response.json)
        self.assertEqual("hosted-coaching-turn.v4", response.json["schemaVersion"])
        self.assertEqual("tutor-v14", response.json["promptVersion"])
        self.assertEqual(self.visual_turn, response.json["turn"])
        self.assertEqual([], self.legacy_provider.calls)
        self.assertEqual(VisualResponseContract.from_request(self.fixture["requests"]["normal"]).json_schema(),
                         self.visual_provider.calls[0]["schema"])

    def test_unknown_version_never_calls_a_provider(self):
        self.assertEqual(400, self.post("v99").status_code)
        self.assertFalse(self.legacy_provider.calls or self.visual_provider.calls)

    def test_invalid_reference_is_a_bounded_provider_failure(self):
        bad = copy.deepcopy(self.visual_turn)
        bad["message"][0]["square"] = "a4"
        self.visual_provider.response["output_text"] = json.dumps(bad)
        self.assertEqual(502, self.post("v4").status_code)
        self.assertEqual(1, len(self.visual_provider.calls))

    def test_followup_retains_visual_schema_and_context(self):
        response = self.post("v4", previous="resp_previous")
        self.assertEqual(200, response.status_code)
        sent = self.visual_provider.calls[0]
        self.assertEqual("resp_previous", sent["previous_response_id"])
        self.assertIn("Displayed board references", sent["user_prompt"])
        self.assertNotIn("Allowable move focus", sent["user_prompt"])

    def test_visual_config_preserves_model_parameters(self):
        for field in ("model", "initial_reasoning_effort", "tactical_follow_up_reasoning_effort",
                      "simple_follow_up_reasoning_effort", "maximum_attempts", "timeout_seconds"):
            self.assertEqual(getattr(self.legacy_config, field), getattr(self.visual_config, field), field)
