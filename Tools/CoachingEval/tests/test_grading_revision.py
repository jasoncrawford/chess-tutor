import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from Tools.CoachingEval.benchmark.grading_revision import GradingRevision


class GradingRevisionTests(unittest.TestCase):
    def test_rebinds_only_private_briefs_without_rerolling_candidate_bytes(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "original"
            source.mkdir()
            old = [{"id": "j1", "request": {"fen": "same"}, "graderBrief": {"purpose": "old"}}]
            new = [{**old[0], "graderBrief": {"purpose": "clearer"}}]
            records = b'{"cellID":"a|j1|r1","caseID":"j1","requestSHA256":"' + hashlib.sha256(json.dumps(old[0]["request"], sort_keys=True, separators=(",", ":")).encode()).hexdigest().encode() + b'"}\n'
            (source / "records.jsonl").write_bytes(records)
            manifest = dict(corpusSHA256="old", recordsSHA256=hashlib.sha256(records).hexdigest(), corpusManifestSchema="old-schema")
            (source / "run-manifest.json").write_text(json.dumps(manifest))
            GradingRevision.prepare(source, root / "regraded", old, new,
                                    original_sha="old", revised_sha="new", revised_schema="new-schema")
            self.assertEqual(records, (root / "regraded/records.jsonl").read_bytes())
            saved = json.loads((root / "regraded/run-manifest.json").read_text())
            self.assertEqual("new", saved["corpusSHA256"])
            self.assertEqual("old", saved["gradingRevision"]["originalCorpusSHA256"])
            self.assertEqual(json.dumps(manifest), (source / "run-manifest.json").read_text())
            changed = [{**new[0], "request": {"fen": "different"}}]
            with self.assertRaisesRegex(ValueError, "candidate inputs"):
                GradingRevision.prepare(source, root / "changed", old, changed,
                                        original_sha="old", revised_sha="new", revised_schema="new-schema")
            self.assertFalse((root / "changed").exists())
