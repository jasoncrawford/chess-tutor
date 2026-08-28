import json
import sys
import tempfile
import unittest
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

import llama_server


FAKE_SERVER = r'''#!/usr/bin/env python3
import argparse
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

parser = argparse.ArgumentParser()
parser.add_argument("-m")
parser.add_argument("-c")
parser.add_argument("--host")
parser.add_argument("--port", type=int)
parser.add_argument("--skip-chat-parsing", action="store_true")
arguments = parser.parse_args()

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            body = b'{"status":"ok"}'
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_error(404)

    def do_POST(self):
        size = int(self.headers["Content-Length"])
        request = json.loads(self.rfile.read(size))
        if request.get("seed") == 996:
            body = b'provider rejected request <THINK>PRIVATE TEXT TRACE</THINK> secret payload'
            self.send_response(422)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if request.get("seed") == 997:
            body = json.dumps({
                "error": {
                    "message": "request rejected after private analysis",
                    "ReAsOnInG_CoNtEnT": "PRIVATE NESTED REASONING",
                    "details": {
                        "reasoningContent": "PRIVATE CAMEL REASONING",
                        "trace": "<THINK>PRIVATE THINK TRACE</THINK>",
                    },
                },
                "safeCode": "invalid_schema",
            }).encode("utf-8")
            self.send_response(422)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if request.get("seed") == 998:
            body = b'{"error":"prompt exceeds context size"}'
            self.send_response(400)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if request.get("seed") == 999:
            time.sleep(2)
        body = json.dumps({
            "choices": [{"message": {
                "content": json.dumps({"schemaVersion": "model-coaching-turn.v1"}),
                "reasoning_content": "private chain",
            }}],
            "usage": {"prompt_tokens": 11, "completion_tokens": 7},
            "timings": {"prompt_ms": 12.5, "predicted_ms": 44.0},
            "echo": request,
        }).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, _format, *_args):
        return

ThreadingHTTPServer((arguments.host, arguments.port), Handler).serve_forever()
'''


class LlamaServerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.executable = self.root / "fake-llama-server"
        self.executable.write_text(FAKE_SERVER)
        self.executable.chmod(0o755)
        self.model = self.root / "model.gguf"
        self.model.write_bytes(b"fake")

    def tearDown(self):
        self.temporary.cleanup()

    def test_starts_on_localhost_waits_for_health_and_sends_exact_chat_payload(self):
        server = llama_server.LlamaServer(self.executable, self.model, context_tokens=8192)
        try:
            server.start(timeout=5)
            response = server.complete(
                system_prompt="Tutor prompt",
                request={"requestID": "request-1", "positionRevision": 4},
                schema={"type": "object", "additionalProperties": False},
                seed=1103,
                maximum_output_tokens=256,
                temperature=0.2,
                top_p=0.9,
                enable_thinking=False,
                timeout=2,
            )
            payload = response["echo"]
            self.assertEqual("Tutor prompt", payload["messages"][0]["content"])
            self.assertEqual(
                {"positionRevision": 4, "requestID": "request-1"},
                json.loads(payload["messages"][-1]["content"]),
            )
            self.assertEqual(1103, payload["seed"])
            self.assertEqual(256, payload["max_tokens"])
            self.assertEqual(False, payload["chat_template_kwargs"]["enable_thinking"])
            self.assertEqual("json_schema", payload["response_format"]["type"])
            self.assertTrue(payload["response_format"]["json_schema"]["strict"])
            self.assertEqual(
                {"type": "object", "additionalProperties": False},
                payload["response_format"]["json_schema"]["schema"],
            )
            self.assertIn("--host", server.command)
            self.assertIn("--skip-chat-parsing", server.command)
            self.assertEqual("127.0.0.1", server.command[server.command.index("--host") + 1])
            self.assertEqual("8192", server.command[server.command.index("-c") + 1])
        finally:
            server.stop()
        self.assertFalse(server.is_running)

    def test_request_timeout_terminates_the_server_process_group(self):
        server = llama_server.LlamaServer(self.executable, self.model, context_tokens=8192)
        server.start(timeout=5)
        with self.assertRaises(llama_server.LlamaServerTimeout):
            server.complete(
                system_prompt="Tutor prompt",
                request={"requestID": "request-1"},
                schema={"type": "object"},
                seed=999,
                maximum_output_tokens=256,
                temperature=0.2,
                top_p=0.9,
                enable_thinking=True,
                timeout=0.05,
            )
        self.assertFalse(server.is_running)

    def test_http_error_preserves_bounded_context_overflow_classification(self):
        server = llama_server.LlamaServer(self.executable, self.model, context_tokens=8192)
        try:
            server.start(timeout=5)
            with self.assertRaises(llama_server.LlamaServerError) as raised:
                server.complete(
                    system_prompt="Tutor prompt",
                    request={"requestID": "request-1"},
                    schema={"type": "object"},
                    seed=998,
                    maximum_output_tokens=256,
                    temperature=0.2,
                    top_p=0.9,
                    enable_thinking=False,
                    timeout=2,
                )
        finally:
            server.stop()

        error = raised.exception
        self.assertEqual("contextOverflow", error.category)
        self.assertEqual(400, error.http_status)
        self.assertEqual("llama-server returned HTTP 400 (context overflow)", str(error))
        self.assertNotIn("prompt exceeds context size", str(error))

    def test_local_http_error_discards_json_and_text_provider_bodies(self):
        server = llama_server.LlamaServer(self.executable, self.model, context_tokens=8192)
        try:
            server.start(timeout=5)
            for seed in (996, 997):
                with self.subTest(seed=seed):
                    with self.assertRaises(llama_server.LlamaServerError) as raised:
                        server.complete(
                            system_prompt="Tutor prompt",
                            request={"requestID": "request-1"},
                            schema={"type": "object"},
                            seed=seed,
                            maximum_output_tokens=256,
                            temperature=0.2,
                            top_p=0.9,
                            enable_thinking=False,
                            timeout=2,
                        )
                    error = raised.exception
                    self.assertEqual("generationError", error.category)
                    self.assertEqual(422, error.http_status)
                    self.assertEqual("llama-server returned HTTP 422", str(error))
                    serialized = str(error).lower()
                    for forbidden in (
                        "private",
                        "reasoning",
                        "reasoning_content",
                        "reasoningcontent",
                        "<think",
                        "secret",
                        "invalid_schema",
                    ):
                        self.assertNotIn(forbidden, serialized)
        finally:
            server.stop()

    def test_reference_credentials_require_https_but_local_unauthenticated_http_is_allowed(self):
        with self.assertRaisesRegex(ValueError, "credentials require an HTTPS endpoint"):
            llama_server.OpenAIChatClient(
                "http://provider.example/v1",
                api_key="developer-secret",
                model="reference-model",
            )

        client = llama_server.OpenAIChatClient("http://127.0.0.1:8080", api_key=None)
        self.assertEqual("http://127.0.0.1:8080/v1/chat/completions", client.url)

    def test_reference_payload_omits_llama_cpp_only_chat_template_arguments(self):
        server = llama_server.LlamaServer(self.executable, self.model, context_tokens=8192)
        try:
            server.start(timeout=5)
            client = llama_server.OpenAIChatClient(server.base_url, model="reference-model")
            response = client.complete(
                system_prompt="Tutor prompt",
                request={"requestID": "request-1"},
                schema={"type": "object"},
                seed=1103,
                maximum_output_tokens=256,
                temperature=0.2,
                top_p=0.9,
                enable_thinking=False,
                timeout=2,
            )
        finally:
            server.stop()

        self.assertNotIn("chat_template_kwargs", response["echo"])
        self.assertEqual("reference-model", response["echo"]["model"])

    def test_reference_http_error_discards_nested_reasoning_body(self):
        server = llama_server.LlamaServer(self.executable, self.model, context_tokens=8192)
        try:
            server.start(timeout=5)
            client = llama_server.OpenAIChatClient(server.base_url, model="reference-model")
            with self.assertRaises(llama_server.LlamaServerError) as raised:
                client.complete(
                    system_prompt="Tutor prompt",
                    request={"requestID": "request-1"},
                    schema={"type": "object"},
                    seed=997,
                    maximum_output_tokens=256,
                    temperature=0.2,
                    top_p=0.9,
                    enable_thinking=False,
                    timeout=2,
                )
        finally:
            server.stop()

        error = raised.exception
        self.assertEqual("generationError", error.category)
        self.assertEqual(422, error.http_status)
        self.assertEqual("reference endpoint returned HTTP 422", str(error))
        self.assertNotIn("reasoning", str(error).lower())
        self.assertNotIn("private", str(error).lower())


if __name__ == "__main__":
    unittest.main()
