import http.client
import json
import logging
import os
import threading
import time
import unittest
from unittest import mock

from flask import Flask
from werkzeug.serving import make_server

from CoachingServer.http_app import create_application, create_environment_application
from CoachingServer.service import HostedCoachingCompletion, HostedCoachingServiceError


GAME_ID = "a1111111-1111-4111-8111-111111111111"
EPISODE_ID = "b2222222-2222-4222-8222-222222222222"
SAFE_DIAGNOSTICS = {
    "request": {
        "kind": "initial",
        "request_id": "request-1",
        "prompt_version": "tutor-v13",
        "position_revision": 2,
        "fen": "4k3/8/8/8/8/8/8/1N2K3 w - - 0 1",
        "moves": ["e4", "e5"],
        "side_to_move": "white",
        "status": "ongoing",
        "latest_interaction": None,
        "selected_piece": None,
        "selected_square": None,
        "staged_move": None,
    },
    "response": {
        "message": "Which piece could help in the center?",
        "actions": ["hint"],
        "focus": [],
        "expects": "stageMove",
    },
    "provider": {
        "model": "gpt-5.6-sol",
        "reasoning_effort": "high",
        "input_tokens": 100,
        "cached_input_tokens": 0,
        "output_tokens": 25,
        "reasoning_tokens": 10,
        "total_tokens": 125,
        "latency_ms": 200.0,
    },
}


def correlated_request():
    return {
        "schemaVersion": "hosted-coaching-request.v3",
        "gameID": GAME_ID,
        "episodeID": EPISODE_ID,
        "request": {},
        "previousResponseID": None,
    }


class FakeService:
    def __init__(self, response=None, error=None):
        self.requests = []
        public_response = response or {
            "schemaVersion": "hosted-coaching-turn.v3",
            "requestID": "request-1",
        }
        self.response = HostedCoachingCompletion(
            response=public_response,
            diagnostics=SAFE_DIAGNOSTICS,
        )
        self.error = error
        self.trace_ids = []

    def complete(self, request, *, trace_id="direct"):
        self.requests.append(request)
        self.trace_ids.append(trace_id)
        if self.error is not None:
            raise self.error
        return self.response


class RecordingHandler(logging.Handler):
    def __init__(self):
        super().__init__()
        self.messages = []

    def emit(self, record):
        self.messages.append(record.getMessage())


def invoke(app, method, path, *, token=None, body=b"", content_type="application/json"):
    headers = {}
    if token is not None:
        headers["Authorization"] = f"Bearer {token}"
    with app.test_client() as client:
        response = client.open(
            path,
            method=method,
            data=body,
            content_type=content_type,
            headers=headers,
        )
    value = json.loads(response.data) if response.data else None
    return response.status, dict(response.headers), value


class HostedCoachingHTTPApplicationTests(unittest.TestCase):
    def test_emits_one_exact_canonical_terminal_record_on_success(self):
        clock = iter((5.0, 5.25))
        app = create_application(
            service=FakeService(),
            access_token="prototype-token",
            clock=lambda: next(clock),
            trace_id_factory=lambda: "trace-canonical",
        )

        with self.assertLogs("ChessTutor.CoachingServer", level="INFO") as captured:
            status, _, body = invoke(
                app,
                "POST",
                "/v1/coaching-turn",
                token="prototype-token",
                body=json.dumps(correlated_request()).encode("utf-8"),
            )

        events = [json.loads(record.getMessage()) for record in captured.records]
        terminal = [value for value in events if value["event"] == "coaching_turn"]
        self.assertEqual(1, len(terminal))
        value = terminal[0]
        self.assertEqual("coaching-log.v1", value.pop("schema_version"))
        self.assertTrue(value.pop("timestamp").endswith("Z"))
        self.assertEqual(
            {
                "level": "info",
                "event": "coaching_turn",
                "trace_id": "trace-canonical",
                "game_id": GAME_ID,
                "episode_id": EPISODE_ID,
                **SAFE_DIAGNOSTICS,
                "outcome": "success",
                "http_status": 200,
                "elapsed_ms": 250.0,
            },
            value,
        )
        self.assertEqual("200 OK", status)
        self.assertEqual(FakeService().response.response, body)

    def test_emits_one_terminal_record_for_each_stable_and_unexpected_failure(self):
        cases = (
            (HostedCoachingServiceError("invalidRequest"), 400, "invalidRequest", False),
            (
                HostedCoachingServiceError(
                    "invalidProviderResponse",
                    diagnostics={**SAFE_DIAGNOSTICS, "response": None},
                ),
                502,
                "invalidProviderResponse",
                True,
            ),
            (
                HostedCoachingServiceError(
                    "providerUnavailable",
                    diagnostics={**SAFE_DIAGNOSTICS, "response": None},
                ),
                503,
                "providerUnavailable",
                True,
            ),
            (
                HostedCoachingServiceError(
                    "providerTimeout",
                    diagnostics={**SAFE_DIAGNOSTICS, "response": None},
                ),
                504,
                "providerTimeout",
                True,
            ),
            (
                RuntimeError("PRIVATE EXCEPTION BODY"),
                503,
                "providerUnavailable",
                False,
            ),
        )
        for error, expected_status, expected_outcome, retains_request in cases:
            with self.subTest(outcome=expected_outcome):
                clock = iter((5.0, 5.1))
                app = create_application(
                    service=FakeService(error=error),
                    access_token="prototype-token",
                    clock=lambda: next(clock),
                    trace_id_factory=lambda: "trace-failure",
                )
                with self.assertLogs(
                    "ChessTutor.CoachingServer", level="INFO"
                ) as captured:
                    status, _, _ = invoke(
                        app,
                        "POST",
                        "/v1/coaching-turn",
                        token="prototype-token",
                        body=json.dumps(correlated_request()).encode("utf-8"),
                    )

                events = [json.loads(record.getMessage()) for record in captured.records]
                terminal = [
                    value for value in events if value["event"] == "coaching_turn"
                ]
                self.assertEqual(1, len(terminal))
                self.assertEqual(expected_outcome, terminal[0]["outcome"])
                self.assertEqual(expected_status, terminal[0]["http_status"])
                self.assertIsNone(terminal[0]["response"])
                if retains_request:
                    self.assertEqual(SAFE_DIAGNOSTICS["request"], terminal[0]["request"])
                else:
                    self.assertIsNone(terminal[0]["request"])
                self.assertNotIn("PRIVATE", json.dumps(events))

    def test_environment_application_owns_v13_prompt_and_simple_follow_up_effort(self):
        fake_service = FakeService()
        with mock.patch.dict(
            os.environ,
            {
                "OPENAI_API_KEY": "private-key",
                "CHESS_TUTOR_COACHING_ACCESS_TOKEN": "private-token",
                "CHESS_TUTOR_COACHING_FOLLOWUP_REASONING_EFFORT": "none",
            },
            clear=True,
        ), mock.patch(
            "Tools.CoachingEval.openai_responses.OpenAIResponsesClient"
        ) as client_type, mock.patch(
            "CoachingServer.http_app.HostedCoachingService",
            return_value=fake_service,
        ) as service_type:
            application = create_environment_application()

        self.assertIsInstance(application, Flask)
        client_type.assert_called_once_with(api_key="private-key")
        arguments = service_type.call_args.kwargs
        self.assertEqual("none", arguments["follow_up_reasoning_effort"])
        self.assertTrue(arguments["system_prompt"].startswith("# Chess Tutor v13\n"))

    def test_uses_flask_for_the_http_boundary(self):
        app = create_application(
            service=FakeService(),
            access_token="prototype-token",
        )

        self.assertIsInstance(app, Flask)

    def test_real_socket_request_body_is_processed_without_waiting_for_client_close(self):
        service = FakeService()
        app = create_application(service=service, access_token="prototype-token")
        server = make_server("127.0.0.1", 0, app)
        server_thread = threading.Thread(target=server.handle_request, daemon=True)
        server_thread.start()
        connection = http.client.HTTPConnection(
            "127.0.0.1",
            server.server_port,
            timeout=0.75,
        )
        encoded = json.dumps({"schemaVersion": "request.v1"}).encode("utf-8")

        started = time.monotonic()
        try:
            connection.request(
                "POST",
                "/v1/coaching-turn",
                body=encoded,
                headers={
                    "Authorization": "Bearer prototype-token",
                    "Content-Type": "application/json",
                },
            )
            response = connection.getresponse()
            response.read()
        finally:
            connection.close()
            server.server_close()
            server_thread.join(timeout=2)

        self.assertEqual(200, response.status)
        self.assertLess(time.monotonic() - started, 0.5)
        self.assertEqual([{"schemaVersion": "request.v1"}], service.requests)

    def test_logs_http_lifecycle_with_matching_trace_and_total_elapsed_time(self):
        service = FakeService()
        clock = iter((5.0, 5.25))
        app = create_application(
            service=service,
            access_token="prototype-token",
            clock=lambda: next(clock),
            trace_id_factory=lambda: "trace-http",
        )
        encoded = json.dumps(correlated_request()).encode("utf-8")

        with self.assertLogs("ChessTutor.CoachingServer", level="INFO") as captured:
            status, _, _ = invoke(
                app,
                "POST",
                "/v1/coaching-turn",
                token="prototype-token",
                body=encoded,
            )

        self.assertEqual("200 OK", status)
        self.assertEqual(["trace-http"], service.trace_ids)
        values = [
            json.loads(record.getMessage())
            for record in captured.records
            if json.loads(record.getMessage())["event"] != "coaching_turn"
        ]
        for value in values:
            self.assertEqual("coaching-log.v1", value.pop("schema_version"))
            self.assertTrue(value.pop("timestamp").endswith("Z"))
        self.assertEqual(
            [
                {
                    "level": "info",
                    "event": "http_request_started",
                    "trace_id": "trace-http",
                    "game_id": GAME_ID,
                    "episode_id": EPISODE_ID,
                },
                {
                    "level": "info",
                    "event": "http_request_completed",
                    "trace_id": "trace-http",
                    "game_id": GAME_ID,
                    "episode_id": EPISODE_ID,
                    "elapsed_ms": 250.0,
                    "outcome": "success",
                    "status": 200,
                },
            ],
            values,
        )

    def test_rejected_input_does_not_log_payload_content(self):
        service = FakeService()
        app = create_application(service=service, access_token="prototype-token")
        logger = logging.getLogger("ChessTutor.CoachingServer")
        handler = RecordingHandler()
        logger.addHandler(handler)
        logger.setLevel(logging.INFO)
        try:
            invoke(
                app,
                "POST",
                "/v1/coaching-turn",
                token="wrong-token",
                body=b'{"private":"CHILD-BOARD-SECRET"}',
            )
        finally:
            logger.removeHandler(handler)

        self.assertNotIn("CHILD-BOARD-SECRET", "\n".join(handler.messages))

    def test_health_is_public_and_does_not_call_service(self):
        service = FakeService()
        app = create_application(service=service, access_token="prototype-token")

        status, headers, body = invoke(app, "GET", "/health")

        self.assertEqual("200 OK", status)
        self.assertEqual("application/json; charset=utf-8", headers["Content-Type"])
        self.assertEqual({"status": "ok"}, body)
        self.assertEqual([], service.requests)

    def test_preserves_method_errors_without_flask_automatic_head_or_options(self):
        service = FakeService()
        app = create_application(service=service, access_token="prototype-token")

        cases = (
            ("POST", "/health", "404 Not Found", "notFound"),
            ("HEAD", "/health", "404 Not Found", None),
            ("OPTIONS", "/health", "404 Not Found", "notFound"),
            (
                "OPTIONS",
                "/v1/coaching-turn",
                "405 Method Not Allowed",
                "methodNotAllowed",
            ),
        )
        for method, path, expected_status, expected_code in cases:
            with self.subTest(method=method, path=path):
                status, _, body = invoke(app, method, path)
                self.assertEqual(expected_status, status)
                if expected_code is not None:
                    self.assertEqual({"error": {"code": expected_code}}, body)

        self.assertEqual([], service.requests)

    def test_post_requires_exact_bearer_and_forwards_json_object(self):
        service = FakeService()
        app = create_application(service=service, access_token="prototype-token")
        request = {"schemaVersion": "model-coaching-neutral-request.v1"}
        encoded = json.dumps(request).encode("utf-8")

        for token in (None, "wrong-token", "prototype-token "):
            status, _, body = invoke(
                app, "POST", "/v1/coaching-turn", token=token, body=encoded
            )
            self.assertEqual("401 Unauthorized", status)
            self.assertEqual({"error": {"code": "unauthorized"}}, body)
        status, _, body = invoke(
            app,
            "POST",
            "/v1/coaching-turn",
            token="prototype-token",
            body=encoded,
        )
        self.assertEqual("200 OK", status)
        self.assertEqual(service.response.response, body)
        self.assertEqual([request], service.requests)

    def test_rejects_bad_routes_content_type_json_shape_and_body_size(self):
        service = FakeService()
        app = create_application(service=service, access_token="prototype-token")

        cases = (
            ("GET", "/v1/coaching-turn", b"{}", "application/json", "405 Method Not Allowed", "methodNotAllowed"),
            ("POST", "/missing", b"{}", "application/json", "404 Not Found", "notFound"),
            ("POST", "/v1/coaching-turn", b"{}", "text/plain", "415 Unsupported Media Type", "unsupportedMediaType"),
            ("POST", "/v1/coaching-turn", b"{", "application/json", "400 Bad Request", "invalidJSON"),
            ("POST", "/v1/coaching-turn", b"[]", "application/json", "400 Bad Request", "invalidJSON"),
            ("POST", "/v1/coaching-turn", b"x" * (128 * 1024 + 1), "application/json", "413 Payload Too Large", "bodyTooLarge"),
        )
        for method, path, body, content_type, expected_status, expected_code in cases:
            with self.subTest(code=expected_code):
                status, _, response = invoke(
                    app,
                    method,
                    path,
                    token="prototype-token",
                    body=body,
                    content_type=content_type,
                )
                self.assertEqual(expected_status, status)
                self.assertEqual({"error": {"code": expected_code}}, response)
        self.assertEqual([], service.requests)

    def test_maps_service_failures_to_small_stable_errors(self):
        cases = (
            ("invalidRequest", "400 Bad Request"),
            ("invalidProviderResponse", "502 Bad Gateway"),
            ("providerUnavailable", "503 Service Unavailable"),
            ("providerTimeout", "504 Gateway Timeout"),
        )
        for code, expected_status in cases:
            with self.subTest(code=code):
                service = FakeService(error=HostedCoachingServiceError(code))
                app = create_application(service=service, access_token="prototype-token")
                status, _, response = invoke(
                    app,
                    "POST",
                    "/v1/coaching-turn",
                    token="prototype-token",
                    body=b"{}",
                )
                self.assertEqual(expected_status, status)
                self.assertEqual({"error": {"code": code}}, response)


if __name__ == "__main__":
    unittest.main()
