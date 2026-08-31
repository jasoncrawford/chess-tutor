import json
import socket
import unittest
from pathlib import Path

from CoachingServer.service import HostedCoachingService, HostedCoachingServiceError


ROOT = Path(__file__).resolve().parents[2]
FIXTURE = json.loads(
    (ROOT / "Tools/CoachingEval/fixtures/chess-native-context-v1.json").read_text(
        encoding="utf-8"
    )
)
SYSTEM_PROMPT = (
    ROOT / "Tools/CoachingEval/prompts/tutor-v6.md"
).read_text(encoding="utf-8")


class RecordingProvider:
    def __init__(self, response=None, error=None):
        self.calls = []
        self.response = response or {
            "id": "provider-private-id",
            "model": "gpt-5.6-sol-2026-08-01",
            "status": "completed",
            "output_text": (
                '{"message":"Where could this knight help in the center?",'
                '"actions":["hint"],'
                '"focus":[{"type":"square","square":"b1"}]}'
            ),
            "usage": {
                "input_tokens": 500,
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
    def test_logs_provider_lifecycle_with_trace_and_elapsed_time(self):
        provider = RecordingProvider()
        clock = iter((10.0, 10.123))
        service = HostedCoachingService(
            provider=provider,
            system_prompt=SYSTEM_PROMPT,
            clock=lambda: next(clock),
        )

        with self.assertLogs("ChessTutor.CoachingServer", level="INFO") as captured:
            service.complete(FIXTURE["request"], trace_id="trace-1")

        self.assertEqual(
            [
                "event=request_compiled trace_id=trace-1",
                (
                    "event=provider_request_started trace_id=trace-1 "
                    "model=gpt-5.6-sol reasoning_effort=high timeout_seconds=30"
                ),
                (
                    "event=provider_request_completed trace_id=trace-1 "
                    "elapsed_ms=123.0 outcome=completed"
                ),
                "event=provider_response_validated trace_id=trace-1",
            ],
            [record.getMessage() for record in captured.records],
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
                service.complete(FIXTURE["request"], trace_id="trace-2")

        messages = [record.getMessage() for record in captured.records]
        self.assertEqual(
            [
                "event=request_compiled trace_id=trace-2",
                (
                    "event=provider_request_started trace_id=trace-2 "
                    "model=gpt-5.6-sol reasoning_effort=high timeout_seconds=30"
                ),
                (
                    "event=provider_request_failed trace_id=trace-2 "
                    "elapsed_ms=30500.0 outcome=timeout"
                ),
            ],
            messages,
        )
        self.assertNotIn("private timeout detail", "\n".join(messages))

    def test_calls_provider_once_with_server_owned_prompt_settings_and_schema(self):
        provider = RecordingProvider()
        clock = iter((10.0, 10.123))
        service = HostedCoachingService(
            provider=provider,
            system_prompt=SYSTEM_PROMPT,
            clock=lambda: next(clock),
        )

        response = service.complete(FIXTURE["request"])

        self.assertEqual(1, len(provider.calls))
        call = provider.calls[0]
        self.assertEqual("gpt-5.6-sol", call["model"])
        self.assertEqual("high", call["reasoning_effort"])
        self.assertEqual(2048, call["maximum_output_tokens"])
        self.assertEqual(30.0, call["timeout"])
        self.assertEqual(SYSTEM_PROMPT, call["system_prompt"])
        self.assertEqual(FIXTURE["expectedMarkdown"], call["user_prompt"])
        self.assertFalse(call["schema"]["additionalProperties"])
        self.assertEqual(
            {
                "schemaVersion": "hosted-coaching-turn.v1",
                "requestID": "shared-selected-knight",
                "positionRevision": 0,
                "promptVersion": "tutor-v6",
                "turn": {
                    "message": "Where could this knight help in the center?",
                    "actions": ["hint"],
                    "focus": [{"type": "square", "square": "b1"}],
                },
                "metrics": {
                    "inputTokens": 500,
                    "outputTokens": 80,
                    "reasoningTokens": 50,
                    "totalTokens": 580,
                    "latencyMilliseconds": 123.0,
                },
            },
            response,
        )
        serialized = json.dumps(response)
        self.assertNotIn("provider-private-id", serialized)
        self.assertNotIn("gpt-5.6-sol-2026", serialized)

    def test_rejects_invalid_request_before_provider_call(self):
        provider = RecordingProvider()
        service = HostedCoachingService(provider=provider, system_prompt=SYSTEM_PROMPT)
        request = dict(FIXTURE["request"], authoredAdvice="Play the knight.")

        with self.assertRaises(HostedCoachingServiceError) as raised:
            service.complete(request)

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
            service.complete(FIXTURE["request"])

        self.assertEqual("invalidProviderResponse", raised.exception.code)
        self.assertNotIn("PRIVATE", str(raised.exception))

    def test_redacts_provider_exceptions(self):
        provider = RecordingProvider(error=RuntimeError("secret provider body"))
        service = HostedCoachingService(provider=provider, system_prompt=SYSTEM_PROMPT)

        with self.assertRaises(HostedCoachingServiceError) as raised:
            service.complete(FIXTURE["request"])

        self.assertEqual("providerUnavailable", raised.exception.code)
        self.assertNotIn("secret", str(raised.exception))

    def test_preserves_provider_timeout_as_a_stable_timeout_failure(self):
        provider = RecordingProvider(error=socket.timeout("private timeout detail"))
        service = HostedCoachingService(provider=provider, system_prompt=SYSTEM_PROMPT)

        with self.assertRaises(HostedCoachingServiceError) as raised:
            service.complete(FIXTURE["request"])

        self.assertEqual("providerTimeout", raised.exception.code)
        self.assertNotIn("private", str(raised.exception))

    def test_maps_provider_gateway_timeout_to_the_same_stable_timeout_failure(self):
        error = RuntimeError("private provider body")
        error.category = "httpError"
        error.http_status = 504
        provider = RecordingProvider(error=error)
        service = HostedCoachingService(provider=provider, system_prompt=SYSTEM_PROMPT)

        with self.assertRaises(HostedCoachingServiceError) as raised:
            service.complete(FIXTURE["request"])

        self.assertEqual("providerTimeout", raised.exception.code)
        self.assertNotIn("private", str(raised.exception))


if __name__ == "__main__":
    unittest.main()
