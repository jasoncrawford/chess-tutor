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
from CoachingServer.service import HostedCoachingServiceError


GAME_ID = "a1111111-1111-4111-8111-111111111111"
EPISODE_ID = "b2222222-2222-4222-8222-222222222222"


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
        self.response = response or {
            "schemaVersion": "hosted-coaching-turn.v3",
            "requestID": "request-1",
        }
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
    def test_environment_application_owns_v13_prompt_and_simple_follow_up_effort(self):
        fake_service = FakeService()
        with mock.patch.dict(
            os.environ,
            {
                "OPENAI_API_KEY": "private-key",
                "CHESS_TUTOR_COACHING_ACCESS_TOKEN": "private-token",
                "CHESS_TUTOR_COACHING_FOLLOWUP_REASONING_EFFORT": "none",
                "CHESS_TUTOR_COACHING_LOG_CONTENT": "1",
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
        self.assertIs(True, arguments["log_content"])
        self.assertTrue(arguments["system_prompt"].startswith("# Chess Tutor v13\n"))

    def test_environment_application_requires_exact_one_to_log_content(self):
        for configured_value in (None, "", "true", "yes", "0"):
            with self.subTest(configured_value=configured_value):
                environment = {
                    "OPENAI_API_KEY": "private-key",
                    "CHESS_TUTOR_COACHING_ACCESS_TOKEN": "private-token",
                }
                if configured_value is not None:
                    environment["CHESS_TUTOR_COACHING_LOG_CONTENT"] = configured_value
                with mock.patch.dict(os.environ, environment, clear=True), mock.patch(
                    "Tools.CoachingEval.openai_responses.OpenAIResponsesClient"
                ), mock.patch(
                    "CoachingServer.http_app.HostedCoachingService",
                    return_value=FakeService(),
                ) as service_type:
                    create_environment_application()

                self.assertIs(False, service_type.call_args.kwargs["log_content"])

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
        values = [json.loads(record.getMessage()) for record in captured.records]
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
        self.assertEqual(service.response, body)
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
