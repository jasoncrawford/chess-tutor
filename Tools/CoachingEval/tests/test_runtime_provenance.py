import hashlib
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

import runtime_provenance


PINNED_COMMIT = "b95502ba9aa0eb73a2f4fc8878d7fbe6a847a0b9"


class RuntimeProvenanceTests(unittest.TestCase):
    def make_runtime(self, root):
        path = root / "runtime.json"
        path.write_text(
            json.dumps({"llamaCppTag": "b10516", "llamaCppCommit": PINNED_COMMIT})
        )
        return path

    def make_server(self, root, *, build="10516", commit=PINNED_COMMIT):
        path = root / "llama-server"
        path.write_text(
            "#!/usr/bin/env python3\n"
            f"print('llama-server version: {build} ({commit})')\n"
        )
        path.chmod(0o755)
        return path

    def test_records_and_verifies_actual_version_output_and_binary_hash(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime = self.make_runtime(root)
            server = self.make_server(root)
            manifest = root / "runtime-manifest.json"

            recorded = runtime_provenance.record_runtime(server, runtime, manifest)
            verified = runtime_provenance.verify_runtime(server, runtime, manifest)

            expected_hash = hashlib.sha256(server.read_bytes()).hexdigest()
            self.assertEqual("b10516", recorded["sourceTag"])
            self.assertEqual(PINNED_COMMIT, recorded["sourceCommit"])
            self.assertEqual(expected_hash, recorded["binarySHA256"])
            self.assertIn("10516", recorded["versionOutput"])
            self.assertEqual(recorded, verified)
            self.assertEqual(recorded, json.loads(manifest.read_text()))

    def test_refuses_changed_binary_even_when_version_text_still_matches(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime = self.make_runtime(root)
            server = self.make_server(root)
            manifest = root / "runtime-manifest.json"
            runtime_provenance.record_runtime(server, runtime, manifest)
            server.write_text(server.read_text() + "# changed\n")
            server.chmod(0o755)

            with self.assertRaisesRegex(runtime_provenance.RuntimeProvenanceError, "hash"):
                runtime_provenance.verify_runtime(server, runtime, manifest)

    def test_refuses_version_output_that_does_not_match_the_pinned_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime = self.make_runtime(root)
            wrong_build = self.make_server(root, build="10515")
            with self.assertRaisesRegex(runtime_provenance.RuntimeProvenanceError, "b10516"):
                runtime_provenance.record_runtime(wrong_build, runtime, root / "build.json")

            wrong_commit = self.make_server(root, commit="0123456789abcdef")
            with self.assertRaisesRegex(runtime_provenance.RuntimeProvenanceError, "commit"):
                runtime_provenance.record_runtime(wrong_commit, runtime, root / "commit.json")


if __name__ == "__main__":
    unittest.main()
