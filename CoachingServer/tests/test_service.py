import copy
import json
import socket
import unittest
from pathlib import Path

from CoachingServer.service import HostedCoachingService, HostedCoachingServiceError
from CoachingServer.chess_native_compiler import compile_context


ROOT = Path(__file__).resolve().parents[2]
FIXTURE = json.loads(
    (ROOT / "Tools/CoachingEval/fixtures/chess-native-context-v1.json").read_text(
        encoding="utf-8"
    )
)
SYSTEM_PROMPT = (
    ROOT / "Tools/CoachingEval/prompts/tutor-v13.md"
).read_text(encoding="utf-8")
GAME_ID = "a1111111-1111-4111-8111-111111111111"
EPISODE_ID = "b2222222-2222-4222-8222-222222222222"


def hosted_request(
    *,
    previous_response_id=None,
    request=None,
    game_id=GAME_ID,
    episode_id=EPISODE_ID,
):
    return {
        "schemaVersion": "hosted-coaching-request.v3",
        "gameID": game_id,
        "episodeID": episode_id,
        "request": FIXTURE["request"] if request is None else request,
        "previousResponseID": previous_response_id,
    }


def decoded_events(captured):
    values = [json.loads(record.getMessage()) for record in captured.records]
    for value in values:
        assert value.pop("schema_version") == "coaching-log.v1"
        assert value.pop("timestamp").endswith("Z")
    return values


def request_with_latest_event(kind, references=()):
    request = copy.deepcopy(FIXTURE["request"])
    event = {
        "sequence": 1,
        "kind": kind,
        "referencedIDs": list(references),
    }
    request["interaction"]["latestEvent"] = event
    request["interaction"]["episodeEvents"] = [event]
    return request


class RecordingProvider:
    def __init__(self, response=None, error=None):
        self.calls = []
        self.response = response or {
            "id": "resp_provider-private-id",
            "model": "gpt-5.6-sol-2026-08-01",
            "status": "completed",
            "output_text": (
                '{"message":"Where could this knight help in the center?",'
                '"actions":["hint"],'
                '"focus":[{"type":"square","square":"b1"}],'
                '"expects":"stageMove"}'
            ),
            "usage": {
                "input_tokens": 500,
                "cached_input_tokens": 25,
                "output_tokens": 80,
                "reasoning_tokens": 50,
                "total_tokens": 580,
            },
        }
        self.error = error

    def complete(self, **kwargs):
        self.calls.append(kwargs)
        if self.error is not None:
            raise self.error
        return self.response


class HostedCoachingServiceTests(unittest.TestCase):
    def test_opt_in_content_trace_contains_client_request_and_server_response(self):
        provider = RecordingProvider()
        clock = iter((10.0, 10.123))
        request = json.loads(json.dumps(FIXTURE["request"]))
        request["positionRevision"] = 1
        request["position"] = {
            "fen": "4k3/8/8/8/4P3/8/8/1N2K3 b - - 0 1",
            "sideToMove": "black",
            "status": "ongoing",
        }
        request["gameHistory"] = [
            {"ply": 1, "canonicalMove": "e2e4", "displayNotation": "e4"}
        ]
        service = HostedCoachingService(
            provider=provider,
            system_prompt=SYSTEM_PROMPT,
            log_content=True,
            clock=lambda: next(clock),
        )

        with self.assertLogs("ChessTutor.CoachingServer", level="INFO") as captured:
            service.complete(
                hosted_request(request=request),
                trace_id="trace-content",
            )

        messages = [record.getMessage() for record in captured.records]
        content_messages = [
            message
            for message in messages
            if message.startswith("event=coaching_trace ")
        ]
        self.assertEqual(1, len(content_messages))
        content = content_messages[0]
        expected_trace = {
            "kind": "initial",
            "reasoning": "high",
            "revision": 1,
            "position": {
                "fen": "4k3/8/8/8/4P3/8/8/1N2K3 b - - 0 1",
                "moves": ["e4"],
                "side": "black",
                "status": "ongoing",
            },
            "interaction": {
                "selected": "piece:white:knight:b1",
                "selectedSquare": "b1",
                "staged": None,
                "events": [
                    {
                        "sequence": 1,
                        "kind": "pieceSelected",
                        "references": ["piece:white:knight:b1"],
                    }
                ],
            },
            "advice": {
                "message": "Where could this knight help in the center?",
                "actions": ["hint"],
                "focus": [{"type": "square", "square": "b1"}],
                "expects": "stageMove",
            },
            "latencyMs": 123.0,
        }
        self.assertEqual(
            "event=coaching_trace trace_id=trace-content data="
            + json.dumps(expected_trace, ensure_ascii=False, separators=(",", ":")),
            content,
        )
        self.assertNotIn("# Chess Tutor v13", content)
        self.assertNotIn("# Chess coaching context", content)
        self.assertNotIn('"pieces":', content)
        self.assertNotIn('"legalMoves":', content)
        self.assertNotIn('"occupiedSquareRelationships":', content)
        self.assertNotIn('"tentativeReplies":', content)
        self.assertNotIn('"capabilities":', content)
        self.assertNotIn("resp_provider-private-id", content)
        self.assertNotIn("gpt-5.6-sol-2026", content)

    def test_invalid_provider_output_never_appears_in_content_trace(self):
        provider = RecordingProvider(
            response={
                "id": "resp_invalid-private-id",
                "status": "completed",
                "output_text": (
                    '{"message":"PRIVATE RAW PROVIDER OUTPUT",'
                    '"actions":["unavailable"],"focus":[],'
                    '"expects":"findEndangeredPiece"}'
                ),
                "usage": {},
            }
        )
        service = HostedCoachingService(
            provider=provider,
            system_prompt=SYSTEM_PROMPT,
            log_content=True,
        )

        with self.assertLogs("ChessTutor.CoachingServer", level="INFO") as captured:
            with self.assertRaises(HostedCoachingServiceError):
                service.complete(hosted_request(), trace_id="trace-invalid")

        joined = "\n".join(record.getMessage() for record in captured.records)
        self.assertNotIn("event=coaching_trace", joined)
        self.assertNotIn("PRIVATE RAW PROVIDER OUTPUT", joined)
        failure = next(
            value
            for value in decoded_events(captured)
            if value["event"] == "provider_response_failed"
        )
        self.assertEqual(["unavailableAction"], failure["reasons"])
        self.assertNotIn("resp_invalid-private-id", joined)

    def test_rejects_provider_turn_without_a_meaningful_next_interaction(self):
        provider = RecordingProvider(
            response={
                "id": "resp_inert-turn",
                "status": "completed",
                "output_text": (
                    '{"message":"That pawn is safe.",'
                    '"actions":[],"focus":[],"expects":"none"}'
                ),
                "usage": {},
            }
        )
        service = HostedCoachingService(provider=provider, system_prompt=SYSTEM_PROMPT)

        with self.assertRaises(HostedCoachingServiceError) as captured:
            service.complete(hosted_request())

        self.assertEqual("invalidProviderResponse", captured.exception.code)

    def test_invalid_json_logs_a_safe_reason_without_provider_content(self):
        provider = RecordingProvider(
            response={
                "id": "resp_invalid-json",
                "status": "completed",
                "output_text": "PRIVATE not-json body",
                "usage": {},
            }
        )
        service = HostedCoachingService(provider=provider, system_prompt=SYSTEM_PROMPT)

        with self.assertLogs("ChessTutor.CoachingServer", level="INFO") as captured:
            with self.assertRaises(HostedCoachingServiceError):
                service.complete(hosted_request(), trace_id="trace-invalid-json")

        joined = "\n".join(record.getMessage() for record in captured.records)
        failure = next(
            value
            for value in decoded_events(captured)
            if value["event"] == "provider_response_failed"
        )
        self.assertEqual(["invalidJSON"], failure["reasons"])
        self.assertNotIn("PRIVATE not-json body", joined)

    def test_overlong_provider_message_logs_specific_safe_reason(self):
        private_message = "PRIVATE" + ("x" * 251)
        provider = RecordingProvider(
            response={
                "id": "resp_overlong-message",
                "status": "completed",
                "output_text": json.dumps(
                    {
                        "message": private_message,
                        "actions": [],
                        "focus": [],
                        "expects": "findEndangeredPiece",
                    },
                    separators=(",", ":"),
                ),
                "usage": {},
            }
        )
        service = HostedCoachingService(provider=provider, system_prompt=SYSTEM_PROMPT)

        with self.assertLogs("ChessTutor.CoachingServer", level="INFO") as captured:
            with self.assertRaises(HostedCoachingServiceError):
                service.complete(hosted_request(), trace_id="trace-overlong")

        joined = "\n".join(record.getMessage() for record in captured.records)
        failure = next(
            value
            for value in decoded_events(captured)
            if value["event"] == "provider_response_failed"
        )
        self.assertEqual(["messageTooLong"], failure["reasons"])
        self.assertNotIn(private_message, joined)

    def test_follow_up_content_trace_excludes_continuation_identifiers(self):
        service = HostedCoachingService(
            provider=RecordingProvider(),
            system_prompt=SYSTEM_PROMPT,
            log_content=True,
        )

        with self.assertLogs("ChessTutor.CoachingServer", level="INFO") as captured:
            service.complete(
                hosted_request(previous_response_id="resp_previous-private-id"),
                trace_id="trace-follow-up",
            )

        content = next(
            record.getMessage()
            for record in captured.records
            if record.getMessage().startswith("event=coaching_trace ")
        )
        self.assertIn('"kind":"follow_up"', content)
        self.assertNotIn("resp_previous-private-id", content)
        self.assertNotIn("resp_provider-private-id", content)

    def test_content_trace_configuration_requires_a_boolean(self):
        with self.assertRaisesRegex(ValueError, "log_content must be a boolean"):
            HostedCoachingService(
                provider=RecordingProvider(),
                system_prompt=SYSTEM_PROMPT,
                log_content="1",
            )

    def test_logs_provider_lifecycle_with_trace_and_elapsed_time(self):
        provider = RecordingProvider()
        clock = iter((10.0, 10.123))
        service = HostedCoachingService(
            provider=provider,
            system_prompt=SYSTEM_PROMPT,
            clock=lambda: next(clock),
        )

        with self.assertLogs("ChessTutor.CoachingServer", level="INFO") as captured:
            service.complete(hosted_request(), trace_id="trace-1")

        self.assertEqual(
            [
                {
                    "level": "info",
                    "event": "request_compiled",
                    "trace_id": "trace-1",
                    "game_id": GAME_ID,
                    "episode_id": EPISODE_ID,
                    "request_kind": "initial",
                },
                {
                    "level": "info",
                    "event": "provider_request_started",
                    "trace_id": "trace-1",
                    "game_id": GAME_ID,
                    "episode_id": EPISODE_ID,
                    "request_kind": "initial",
                    "model": "gpt-5.6-sol",
                    "reasoning_effort": "high",
                    "timeout_seconds": 30.0,
                },
                {
                    "level": "info",
                    "event": "provider_request_completed",
                    "trace_id": "trace-1",
                    "game_id": GAME_ID,
                    "episode_id": EPISODE_ID,
                    "elapsed_ms": 123.0,
                    "outcome": "completed",
                    "input_tokens": 500,
                    "cached_input_tokens": 25,
                    "output_tokens": 80,
                    "reasoning_tokens": 50,
                },
                {
                    "level": "info",
                    "event": "provider_response_validated",
                    "trace_id": "trace-1",
                    "game_id": GAME_ID,
                    "episode_id": EPISODE_ID,
                },
            ],
            decoded_events(captured),
        )

    def test_logs_timeout_category_without_private_exception_text(self):
        provider = RecordingProvider(error=socket.timeout("private timeout detail"))
        clock = iter((20.0, 50.5))
        service = HostedCoachingService(
            provider=provider,
            system_prompt=SYSTEM_PROMPT,
            clock=lambda: next(clock),
        )

        with self.assertLogs("ChessTutor.CoachingServer", level="INFO") as captured:
            with self.assertRaises(HostedCoachingServiceError):
                service.complete(hosted_request(), trace_id="trace-2")

        self.assertEqual(
            [
                {
                    "level": "info",
                    "event": "request_compiled",
                    "trace_id": "trace-2",
                    "game_id": GAME_ID,
                    "episode_id": EPISODE_ID,
                    "request_kind": "initial",
                },
                {
                    "level": "info",
                    "event": "provider_request_started",
                    "trace_id": "trace-2",
                    "game_id": GAME_ID,
                    "episode_id": EPISODE_ID,
                    "request_kind": "initial",
                    "model": "gpt-5.6-sol",
                    "reasoning_effort": "high",
                    "timeout_seconds": 30.0,
                },
                {
                    "level": "warning",
                    "event": "provider_request_failed",
                    "trace_id": "trace-2",
                    "game_id": GAME_ID,
                    "episode_id": EPISODE_ID,
                    "elapsed_ms": 30500.0,
                    "outcome": "timeout",
                },
            ],
            decoded_events(captured),
        )
        self.assertNotIn(
            "private timeout detail",
            "\n".join(record.getMessage() for record in captured.records),
        )

    def test_calls_provider_once_with_server_owned_prompt_settings_and_schema(self):
        provider = RecordingProvider()
        clock = iter((10.0, 10.123))
        service = HostedCoachingService(
            provider=provider,
            system_prompt=SYSTEM_PROMPT,
            clock=lambda: next(clock),
        )

        response = service.complete(hosted_request())

        self.assertEqual(1, len(provider.calls))
        call = provider.calls[0]
        self.assertEqual("gpt-5.6-sol", call["model"])
        self.assertEqual("high", call["reasoning_effort"])
        self.assertEqual(2048, call["maximum_output_tokens"])
        self.assertEqual(30.0, call["timeout"])
        self.assertIsNone(call["previous_response_id"])
        self.assertTrue(call["store"])
        self.assertEqual(SYSTEM_PROMPT, call["system_prompt"])
        self.assertNotIn(GAME_ID, call["system_prompt"])
        self.assertNotIn(EPISODE_ID, call["system_prompt"])
        self.assertEqual(
            compile_context(FIXTURE["request"], "tutor-v13").markdown,
            call["user_prompt"],
        )
        self.assertNotIn(GAME_ID, call["user_prompt"])
        self.assertNotIn(EPISODE_ID, call["user_prompt"])
        self.assertFalse(call["schema"]["additionalProperties"])
        self.assertEqual(
            [
                "findEndangeredPiece",
                "findSafeCapture",
                "stageMove",
                "judgeMoveSafety",
                "chooseWhetherToPlay",
            ],
            call["schema"]["properties"]["expects"]["enum"],
        )
        self.assertEqual(
            {
                "schemaVersion": "hosted-coaching-turn.v3",
                "requestID": "shared-selected-knight",
                "positionRevision": 0,
                "promptVersion": "tutor-v13",
                "continuationID": "resp_provider-private-id",
                "turn": {
                    "message": "Where could this knight help in the center?",
                    "actions": ["hint"],
                    "focus": [{"type": "square", "square": "b1"}],
                    "expects": "stageMove",
                },
                "metrics": {
                    "inputTokens": 500,
                    "cachedInputTokens": 25,
                    "outputTokens": 80,
                    "reasoningTokens": 50,
                    "totalTokens": 580,
                    "latencyMilliseconds": 123.0,
                },
            },
            response,
        )
        serialized = json.dumps(response)
        self.assertNotIn("gpt-5.6-sol-2026", serialized)

    def test_simple_follow_up_uses_compact_update_previous_response_and_no_reasoning(self):
        provider = RecordingProvider()
        service = HostedCoachingService(
            provider=provider,
            system_prompt=SYSTEM_PROMPT,
        )

        response = service.complete(
            hosted_request(previous_response_id="resp_previous-123")
        )

        call = provider.calls[0]
        self.assertEqual("none", call["reasoning_effort"])
        self.assertEqual("resp_previous-123", call["previous_response_id"])
        self.assertTrue(call["store"])
        self.assertTrue(call["user_prompt"].startswith("# Chess coaching update\n"))
        self.assertNotIn("## Position", call["user_prompt"])
        self.assertEqual("resp_provider-private-id", response["continuationID"])

    def test_tactical_follow_ups_use_low_reasoning(self):
        cases = (
            ("moveStaged", ("move:b1-c3",)),
            ("moveReplaced", ("move:b1-c3",)),
            ("squareInspected", ("piece:white:knight:b1",)),
            ("actionChosen", ("action:hint",)),
        )

        for kind, references in cases:
            with self.subTest(kind=kind):
                provider = RecordingProvider()
                service = HostedCoachingService(
                    provider=provider,
                    system_prompt=SYSTEM_PROMPT,
                )
                service.complete(
                    hosted_request(
                        previous_response_id="resp_previous-123",
                        request=request_with_latest_event(kind, references),
                    )
                )
                self.assertEqual("low", provider.calls[0]["reasoning_effort"])

    def test_simple_follow_up_effort_can_be_configured_to_low_but_not_other_values(self):
        provider = RecordingProvider()
        service = HostedCoachingService(
            provider=provider,
            system_prompt=SYSTEM_PROMPT,
            follow_up_reasoning_effort="low",
        )
        service.complete(hosted_request(previous_response_id="resp_previous-123"))
        self.assertEqual("low", provider.calls[0]["reasoning_effort"])

        with self.assertRaisesRegex(ValueError, "follow-up reasoning effort"):
            HostedCoachingService(
                provider=provider,
                system_prompt=SYSTEM_PROMPT,
                follow_up_reasoning_effort="medium",
            )

    def test_rejects_invalid_request_before_provider_call(self):
        provider = RecordingProvider()
        service = HostedCoachingService(provider=provider, system_prompt=SYSTEM_PROMPT)
        request = dict(FIXTURE["request"], authoredAdvice="Play the knight.")

        with self.assertRaises(HostedCoachingServiceError) as raised:
            service.complete(hosted_request(request=request))

        self.assertEqual("invalidRequest", raised.exception.code)
        self.assertEqual([], provider.calls)

    def test_rejects_invalid_provider_output_without_returning_private_content(self):
        provider = RecordingProvider(
            response={
                "status": "completed",
                "output_text": (
                    '{"message":"PRIVATE TRACE",'
                    '"actions":["unavailable"],"focus":[]}'
                ),
                "usage": {},
            }
        )
        service = HostedCoachingService(provider=provider, system_prompt=SYSTEM_PROMPT)

        with self.assertRaises(HostedCoachingServiceError) as raised:
            service.complete(hosted_request())

        self.assertEqual("invalidProviderResponse", raised.exception.code)
        self.assertNotIn("PRIVATE", str(raised.exception))

    def test_redacts_provider_exceptions(self):
        provider = RecordingProvider(error=RuntimeError("secret provider body"))
        service = HostedCoachingService(provider=provider, system_prompt=SYSTEM_PROMPT)

        with self.assertRaises(HostedCoachingServiceError) as raised:
            service.complete(hosted_request())

        self.assertEqual("providerUnavailable", raised.exception.code)
        self.assertNotIn("secret", str(raised.exception))

    def test_preserves_provider_timeout_as_a_stable_timeout_failure(self):
        provider = RecordingProvider(error=socket.timeout("private timeout detail"))
        service = HostedCoachingService(provider=provider, system_prompt=SYSTEM_PROMPT)

        with self.assertRaises(HostedCoachingServiceError) as raised:
            service.complete(hosted_request())

        self.assertEqual("providerTimeout", raised.exception.code)
        self.assertNotIn("private", str(raised.exception))

    def test_maps_provider_gateway_timeout_to_the_same_stable_timeout_failure(self):
        error = RuntimeError("private provider body")
        error.category = "httpError"
        error.http_status = 504
        provider = RecordingProvider(error=error)
        service = HostedCoachingService(provider=provider, system_prompt=SYSTEM_PROMPT)

        with self.assertRaises(HostedCoachingServiceError) as raised:
            service.complete(hosted_request())

        self.assertEqual("providerTimeout", raised.exception.code)
        self.assertNotIn("private", str(raised.exception))

    def test_rejects_invalid_or_extra_envelope_fields_before_provider_call(self):
        provider = RecordingProvider()
        service = HostedCoachingService(provider=provider, system_prompt=SYSTEM_PROMPT)
        invalid = hosted_request(previous_response_id="not-a-response-id")
        invalid["clientReasoningEffort"] = "max"

        with self.assertRaises(HostedCoachingServiceError) as raised:
            service.complete(invalid)

        self.assertEqual("invalidRequest", raised.exception.code)
        self.assertEqual([], provider.calls)

    def test_rejects_missing_malformed_or_noncanonical_correlation_ids(self):
        invalid_requests = (
            {key: value for key, value in hosted_request().items() if key != "gameID"},
            hosted_request(game_id="not-a-uuid"),
            hosted_request(game_id=GAME_ID.upper()),
            hosted_request(episode_id="not-a-uuid"),
            hosted_request(episode_id=EPISODE_ID.upper()),
        )

        for invalid in invalid_requests:
            with self.subTest(invalid=invalid):
                provider = RecordingProvider()
                service = HostedCoachingService(
                    provider=provider,
                    system_prompt=SYSTEM_PROMPT,
                )
                with self.assertRaises(HostedCoachingServiceError) as raised:
                    service.complete(invalid)
                self.assertEqual("invalidRequest", raised.exception.code)
                self.assertEqual([], provider.calls)


if __name__ == "__main__":
    unittest.main()
