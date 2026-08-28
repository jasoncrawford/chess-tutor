import hashlib
import json
import sys
import tempfile
import threading
import unittest
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

import model_store


EXPECTED_MODELS = [
    {
        "id": "qwen3-0.6b-q4_0",
        "repository": "ggml-org/Qwen3-0.6B-GGUF",
        "selector": "Q4_0",
        "filename": "Qwen3-0.6B-Q4_0.gguf",
        "license": "Apache-2.0",
        "thinkingModes": ["off", "bounded"],
    },
    {
        "id": "gemma3-1b-qat-q4_0",
        "repository": "google/gemma-3-1b-it-qat-q4_0-gguf",
        "selector": "Q4_0",
        "filename": None,
        "license": "Gemma Terms",
        "requiresToken": True,
        "thinkingModes": ["off"],
    },
    {
        "id": "qwen3-1.7b-q4_k_m",
        "repository": "ggml-org/Qwen3-1.7B-GGUF",
        "selector": "Q4_K_M",
        "filename": "Qwen3-1.7B-Q4_K_M.gguf",
        "license": "Apache-2.0",
        "thinkingModes": ["off", "bounded"],
    },
    {
        "id": "smollm3-3b-q4_k_m",
        "repository": "ggml-org/SmolLM3-3B-GGUF",
        "selector": "Q4_K_M",
        "filename": "SmolLM3-Q4_K_M.gguf",
        "license": "Apache-2.0",
        "thinkingModes": ["off", "bounded"],
    },
]


class FakeHuggingFaceHandler(BaseHTTPRequestHandler):
    artifact = b"exact pinned gguf bytes"
    requests = []

    def do_GET(self):
        type(self).requests.append((self.path, dict(self.headers)))
        if self.path == "/api/models/example/repo/revision/main":
            body = json.dumps(
                {
                    "sha": "a" * 40,
                    "siblings": [
                        {"rfilename": "README.md", "size": 12},
                        {"rfilename": "model-Q4_0.gguf", "size": len(self.artifact)},
                    ],
                }
            ).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if self.path == "/example/repo/resolve/" + "a" * 40 + "/model-Q4_0.gguf":
            self.send_response(200)
            self.send_header("Content-Length", str(len(self.artifact)))
            self.end_headers()
            self.wfile.write(self.artifact)
            return
        self.send_error(404)

    def log_message(self, _format, *_args):
        return


class ModelStoreTests(unittest.TestCase):
    def setUp(self):
        FakeHuggingFaceHandler.requests = []
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), FakeHuggingFaceHandler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def test_committed_manifests_pin_exact_candidates_and_runtime(self):
        self.assertEqual(EXPECTED_MODELS, model_store.load_models(TOOLS_DIR / "models.json"))
        runtime = json.loads((TOOLS_DIR / "runtime.json").read_text())
        self.assertEqual("b10516", runtime["llamaCppTag"])
        self.assertEqual(8192, runtime["mac"]["contextTokens"])
        self.assertEqual(256, runtime["generation"]["maximumOutputTokens"])
        self.assertEqual(0.2, runtime["generation"]["temperature"])
        self.assertEqual(0.9, runtime["generation"]["topP"])
        self.assertEqual(3, runtime["evaluation"]["repetitions"])
        self.assertEqual([1103, 2207, 3301], runtime["evaluation"]["seeds"])

    def test_fetch_resolves_main_and_writes_verified_artifact_manifest(self):
        candidate = {
            "id": "example",
            "repository": "example/repo",
            "selector": "Q4_0",
            "filename": None,
            "license": "Test",
            "thinkingModes": ["off"],
        }
        with tempfile.TemporaryDirectory() as temporary:
            store = model_store.ModelStore(
                Path(temporary),
                api_base=f"http://127.0.0.1:{self.server.server_port}",
                download_base=f"http://127.0.0.1:{self.server.server_port}",
                environment={"HF_TOKEN": "must-not-leak"},
            )
            artifact = store.fetch(candidate)
            manifest = json.loads((artifact.parent / "artifact-manifest.json").read_text())

            self.assertEqual(FakeHuggingFaceHandler.artifact, artifact.read_bytes())
            self.assertEqual("a" * 40, manifest["resolvedRevision"])
            self.assertEqual("model-Q4_0.gguf", manifest["filename"])
            self.assertEqual(len(FakeHuggingFaceHandler.artifact), manifest["bytes"])
            self.assertEqual(
                hashlib.sha256(FakeHuggingFaceHandler.artifact).hexdigest(),
                manifest["sha256"],
            )
            self.assertTrue(all("Authorization" not in headers for _, headers in FakeHuggingFaceHandler.requests))

    def test_fetch_reuses_only_matching_size_and_checksum(self):
        candidate = {
            "id": "example",
            "repository": "example/repo",
            "selector": "Q4_0",
            "filename": None,
            "license": "Test",
            "thinkingModes": ["off"],
        }
        with tempfile.TemporaryDirectory() as temporary:
            store = model_store.ModelStore(
                Path(temporary),
                api_base=f"http://127.0.0.1:{self.server.server_port}",
                download_base=f"http://127.0.0.1:{self.server.server_port}",
                environment={},
            )
            artifact = store.fetch(candidate)
            request_count = len(FakeHuggingFaceHandler.requests)
            self.assertEqual(artifact, store.fetch(candidate))
            self.assertEqual(request_count + 1, len(FakeHuggingFaceHandler.requests))

            artifact.write_bytes(b"corrupt bytes with same-ish length")
            self.assertEqual(artifact, store.fetch(candidate))
            self.assertEqual(FakeHuggingFaceHandler.artifact, artifact.read_bytes())
            self.assertGreater(len(FakeHuggingFaceHandler.requests), request_count + 2)

    def test_verify_rejects_manifest_for_a_different_candidate(self):
        candidate = {
            "id": "example",
            "repository": "example/repo",
            "selector": "Q4_0",
            "filename": None,
            "license": "Test",
            "thinkingModes": ["off"],
        }
        with tempfile.TemporaryDirectory() as temporary:
            store = model_store.ModelStore(
                Path(temporary),
                api_base=f"http://127.0.0.1:{self.server.server_port}",
                download_base=f"http://127.0.0.1:{self.server.server_port}",
                environment={},
            )
            artifact = store.fetch(candidate)
            manifest_path = artifact.parent / "artifact-manifest.json"
            manifest = json.loads(manifest_path.read_text())
            manifest["modelID"] = "different-model"
            manifest_path.write_text(json.dumps(manifest))
            self.assertFalse(store.verify(candidate))

    def test_gated_candidate_never_substitutes_another_artifact(self):
        candidate = EXPECTED_MODELS[1]
        with tempfile.TemporaryDirectory() as temporary:
            store = model_store.ModelStore(Path(temporary), environment={})
            with self.assertRaisesRegex(model_store.ModelAccessError, "Gemma Terms.*HF_TOKEN"):
                store.fetch(candidate)

    def test_authorization_is_stripped_from_redirects_off_huggingface(self):
        handler = model_store.SafeAuthorizationRedirectHandler()
        original = urllib.request.Request(
            "https://huggingface.co/example/repo/resolve/revision/model.gguf",
            headers={"Authorization": "Bearer secret"},
        )
        redirected = handler.redirect_request(
            original,
            None,
            302,
            "Found",
            {},
            "https://cdn.example.test/model.gguf",
        )
        same_host = handler.redirect_request(
            original,
            None,
            302,
            "Found",
            {},
            "https://huggingface.co/redirected/model.gguf",
        )
        self.assertNotIn("Authorization", redirected.headers)
        self.assertEqual("Bearer secret", same_host.headers["Authorization"])


if __name__ == "__main__":
    unittest.main()
