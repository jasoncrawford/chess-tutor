import email.message
import json
import socket
import sys
import threading
import unittest
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

import openai_responses
from http_security import SameOriginAuthorizationRedirectHandler


SYSTEM_PROMPT = "  Teach this turn.\nKeep the spacing exactly. \u265f  "
USER_PROMPT = "# Position\n\nBlack moved a knight.\n"
SCHEMA = {
    "type": "object",
    "properties": {
        "message": {"type": "string"},
        "actions": {
            "type": "array",
            "items": {"type": "string", "enum": ["play_move", "try_again"]},
        },
        "focus": {"type": "array", "items": {"type": "object"}},
    },
    "required": ["message", "actions", "focus"],
    "additionalProperties": False,
}
OUTPUT_TEXT = '{"message":"What could your knight attack?","actions":[],"focus":[]}'


def completed_response(*, content=None, status="completed", message_status="completed"):
    if content is None:
        content = [
            {
                "type": "output_text",
                "text": OUTPUT_TEXT,
                "annotations": [],
                "logprobs": [],
            }
        ]
    return {
        "id": "resp_123",
        "object": "response",
        "status": status,
        "model": "gpt-5.6-sol-2026-08-01",
        "error": None,
        "incomplete_details": None,
        "output": [
            {
                "id": "rs_123",
                "type": "reasoning",
                "summary": [{"type": "summary_text", "text": "PRIVATE REASONING"}],
                "encrypted_content": "PRIVATE ENCRYPTED TRACE",
            },
            {
                "id": "msg_123",
                "type": "message",
                "status": message_status,
                "role": "assistant",
                "content": content,
            },
        ],
        "usage": {
            "input_tokens": 641,
            "input_tokens_details": {"cached_tokens": 0},
            "output_tokens": 79,
            "output_tokens_details": {"reasoning_tokens": 61},
            "total_tokens": 720,
        },
    }


class FakeResponsesServer:
    def __init__(self, *, response_body=None, status=200, raw_body=None):
        self.requests = []
        self.response_body = completed_response() if response_body is None else response_body
        self.status = status
        self.raw_body = raw_body
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                length = int(self.headers.get("Content-Length", "0"))
                body = self.rfile.read(length)
                owner.requests.append(
                    {
                        "path": self.path,
                        "headers": dict(self.headers.items()),
                        "body": json.loads(body),
                    }
                )
                if owner.raw_body is None:
                    response = json.dumps(owner.response_body).encode("utf-8")
                else:
                    response = owner.raw_body
                self.send_response(owner.status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(response)))
                self.end_headers()
                self.wfile.write(response)

            def log_message(self, _format, *_args):
                return

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    @property
    def base_url(self):
        host, port = self.server.server_address
        return f"http://{host}:{port}"

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, _error_type, _error, _traceback):
        self.server.shutdown()
        self.thread.join(timeout=2)
        self.server.server_close()


def complete(client):
    return client.complete(
        system_prompt=SYSTEM_PROMPT,
        user_prompt=USER_PROMPT,
        schema=SCHEMA,
        model="gpt-5.6-sol",
        reasoning_effort="high",
        maximum_output_tokens=256,
        timeout=2,
    )


class OpenAIResponsesClientTests(unittest.TestCase):
    def test_posts_exact_responses_payload_and_returns_only_bounded_final_fields(self):
        with FakeResponsesServer() as server:
            client = openai_responses.OpenAIResponsesClient(server.base_url)
            result = complete(client)

        self.assertEqual(1, len(server.requests))
        request = server.requests[0]
        self.assertEqual("/v1/responses", request["path"])
        self.assertEqual(
            {
                "model": "gpt-5.6-sol",
                "input": [
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {"role": "user", "content": USER_PROMPT},
                ],
                "reasoning": {"effort": "high"},
                "max_output_tokens": 256,
                "text": {
                    "format": {
                        "type": "json_schema",
                        "name": "chess_coaching_turn",
                        "strict": True,
                        "schema": SCHEMA,
                    }
                },
                "store": False,
            },
            request["body"],
        )
        self.assertNotIn("Authorization", request["headers"])
        self.assertEqual(
            {
                "id": "resp_123",
                "model": "gpt-5.6-sol-2026-08-01",
                "status": "completed",
                "output_text": OUTPUT_TEXT,
                "usage": {
                    "input_tokens": 641,
                    "output_tokens": 79,
                    "reasoning_tokens": 61,
                    "total_tokens": 720,
                },
            },
            result,
        )
        serialized = json.dumps(result).lower()
        self.assertNotIn("reasoning_content", serialized)
        self.assertNotIn("summary", serialized)
        self.assertNotIn("private", serialized)
        self.assertNotIn("encrypted", serialized)

    def test_credentials_require_https_but_unauthenticated_local_http_is_allowed(self):
        with self.assertRaisesRegex(ValueError, "credentials require an HTTPS endpoint"):
            openai_responses.OpenAIResponsesClient(
                "http://provider.example",
                api_key="developer-secret",
            )

        client = openai_responses.OpenAIResponsesClient("http://127.0.0.1:8080")
        self.assertEqual("http://127.0.0.1:8080/v1/responses", client.url)

        with self.assertRaisesRegex(ValueError, "official OpenAI API origin"):
            openai_responses.OpenAIResponsesClient(
                "https://provider.example",
                api_key="developer-secret",
            )

    def test_client_redirect_handler_strips_authorization_across_origins(self):
        client = openai_responses.OpenAIResponsesClient(
            "https://api.openai.com",
            api_key="developer-secret",
        )
        redirect_handlers = [
            handler
            for handler in client.opener.handlers
            if isinstance(handler, SameOriginAuthorizationRedirectHandler)
        ]
        self.assertEqual(1, len(redirect_handlers))
        original = urllib.request.Request(
            "https://api.openai.com/v1/responses",
            headers={"Authorization": "Bearer developer-secret"},
        )
        redirected = redirect_handlers[0].redirect_request(
            original,
            None,
            302,
            "Found",
            email.message.Message(),
            "https://elsewhere.example/final",
        )

        self.assertIsNotNone(redirected)
        self.assertIsNone(redirected.get_header("Authorization"))

    def test_http_error_discards_provider_body_and_secret_text(self):
        private_body = (
            b'{"error":{"message":"PRIVATE REASONING",'
            b'"api_key":"developer-secret","trace":"<think>secret</think>"}}'
        )
        with FakeResponsesServer(status=422, raw_body=private_body) as server:
            client = openai_responses.OpenAIResponsesClient(server.base_url)
            with self.assertRaises(openai_responses.OpenAIResponsesError) as raised:
                complete(client)

        error = raised.exception
        self.assertEqual("httpError", error.category)
        self.assertEqual(422, error.http_status)
        self.assertEqual("OpenAI Responses API returned HTTP 422", str(error))
        lowered = str(error).lower()
        for forbidden in ("private", "reasoning", "developer-secret", "think", "trace"):
            self.assertNotIn(forbidden, lowered)

    def test_classifies_socket_timeout_without_retaining_details(self):
        client = openai_responses.OpenAIResponsesClient("http://127.0.0.1:8080")

        class TimeoutOpener:
            def open(self, _request, timeout):
                self.timeout = timeout
                raise socket.timeout("PRIVATE timeout body")

        opener = TimeoutOpener()
        client.opener = opener

        with self.assertRaises(openai_responses.OpenAIResponsesError) as raised:
            complete(client)

        self.assertEqual(2, opener.timeout)
        self.assertEqual("timeout", raised.exception.category)
        self.assertNotIn("private", str(raised.exception).lower())

    def test_malformed_success_body_is_rejected_without_echoing_it(self):
        private_body = b'{"PRIVATE_REASONING":"developer-secret"'
        with FakeResponsesServer(raw_body=private_body) as server:
            client = openai_responses.OpenAIResponsesClient(server.base_url)
            with self.assertRaises(openai_responses.OpenAIResponsesError) as raised:
                complete(client)

        self.assertEqual("invalidResponse", raised.exception.category)
        self.assertEqual("OpenAI Responses API returned an invalid response", str(raised.exception))
        self.assertNotIn("private", str(raised.exception).lower())
        self.assertNotIn("developer-secret", str(raised.exception).lower())

    def test_refuses_non_completed_response_and_message_statuses(self):
        fixtures = (
            completed_response(status="incomplete"),
            completed_response(status="failed"),
            completed_response(message_status="incomplete"),
        )
        for response_body in fixtures:
            with self.subTest(status=response_body["status"], output=response_body["output"][-1]["status"]):
                with FakeResponsesServer(response_body=response_body) as server:
                    client = openai_responses.OpenAIResponsesClient(server.base_url)
                    with self.assertRaises(openai_responses.OpenAIResponsesError) as raised:
                        complete(client)
                self.assertEqual("incompleteResponse", raised.exception.category)
                self.assertEqual(
                    "OpenAI Responses API did not return a completed response",
                    str(raised.exception),
                )

    def test_refuses_refusal_or_multiple_candidate_output_text(self):
        refusal = completed_response(
            content=[{"type": "refusal", "refusal": "PRIVATE POLICY DETAILS"}]
        )
        multiple = completed_response(
            content=[
                {"type": "output_text", "text": OUTPUT_TEXT},
                {"type": "output_text", "text": "PRIVATE SECOND CANDIDATE"},
            ]
        )
        second_message = completed_response()
        second_message["output"].append(
            {
                "id": "msg_456",
                "type": "message",
                "status": "completed",
                "role": "assistant",
                "content": [{"type": "output_text", "text": "PRIVATE SECOND CANDIDATE"}],
            }
        )
        for category, response_body in (
            ("refusal", refusal),
            ("multipleOutputTexts", multiple),
            ("multipleOutputTexts", second_message),
        ):
            with self.subTest(category=category):
                with FakeResponsesServer(response_body=response_body) as server:
                    client = openai_responses.OpenAIResponsesClient(server.base_url)
                    with self.assertRaises(openai_responses.OpenAIResponsesError) as raised:
                        complete(client)
                self.assertEqual(category, raised.exception.category)
                self.assertNotIn("private", str(raised.exception).lower())

    def test_refuses_unbounded_identifiers_output_text_and_usage(self):
        fixtures = []
        long_id = completed_response()
        long_id["id"] = "x" * 257
        fixtures.append(long_id)
        long_model = completed_response()
        long_model["model"] = "m" * 257
        fixtures.append(long_model)
        long_text = completed_response(
            content=[{"type": "output_text", "text": "x" * (64 * 1024 + 1)}]
        )
        fixtures.append(long_text)
        huge_usage = completed_response()
        huge_usage["usage"]["total_tokens"] = 1_000_000_001
        fixtures.append(huge_usage)
        huge_reasoning_usage = completed_response()
        huge_reasoning_usage["usage"]["output_tokens_details"][
            "reasoning_tokens"
        ] = 1_000_000_001
        fixtures.append(huge_reasoning_usage)
        invalid_unicode = completed_response()
        invalid_unicode["id"] = "resp_\ud800"
        fixtures.append(invalid_unicode)

        for response_body in fixtures:
            with self.subTest(response_id=len(response_body["id"])):
                with FakeResponsesServer(response_body=response_body) as server:
                    client = openai_responses.OpenAIResponsesClient(server.base_url)
                    with self.assertRaises(openai_responses.OpenAIResponsesError) as raised:
                        complete(client)
                self.assertEqual("invalidResponse", raised.exception.category)
                self.assertEqual(
                    "OpenAI Responses API returned an invalid response",
                    str(raised.exception),
                )


if __name__ == "__main__":
    unittest.main()
