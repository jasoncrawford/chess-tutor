import io
import json
import logging
import unittest

from CoachingServer.http_app import create_application
from CoachingServer.service import HostedCoachingServiceError


class FakeService:
    def __init__(self, response=None, error=None):
        self.requests = []
        self.response = response or {
            "schemaVersion": "hosted-coaching-turn.v1",
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
    status = None
    headers = None

    def start_response(value, response_headers):
        nonlocal status, headers
        status = value
        headers = dict(response_headers)

    environ = {
        "REQUEST_METHOD": method,
        "PATH_INFO": path,
        "CONTENT_LENGTH": str(len(body)),
        "CONTENT_TYPE": content_type,
        "wsgi.input": io.BytesIO(body),
    }
    if token is not None:
        environ["HTTP_AUTHORIZATION"] = f"Bearer {token}"
    payload = b"".join(app(environ, start_response))
    return status, headers, json.loads(payload)


class HostedCoachingHTTPApplicationTests(unittest.TestCase):
    def test_logs_http_lifecycle_with_matching_trace_and_total_elapsed_time(self):
        service = FakeService()
        clock = iter((5.0, 5.25))
        app = create_application(
            service=service,
            access_token="prototype-token",
            clock=lambda: next(clock),
            trace_id_factory=lambda: "trace-http",
        )
        encoded = json.dumps({"schemaVersion": "request.v1"}).encode("utf-8")

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
        self.assertEqual(
            [
                "event=http_request_started trace_id=trace-http",
                (
                    "event=http_request_completed trace_id=trace-http "
                    "elapsed_ms=250.0 outcome=success status=200"
                ),
            ],
            [record.getMessage() for record in captured.records],
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
