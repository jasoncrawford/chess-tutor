import hashlib
import json
import unittest

from Tools.CoachingEval.benchmark.corpus import load_corpus
from Tools.CoachingEval.benchmark.grading_revision import GradingRevision
from Tools.CoachingEval.tests import test_benchmark_corpus as fixtures


class GradingRevisionTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.BenchmarkCorpusTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.tearDown)
        self.original = self.fixture.root
        self.old = load_corpus(self.original)
        self.source = self.original / "run"
        self.source.mkdir()
        case = self.fixture.cases[0]
        request_sha = hashlib.sha256(json.dumps(case["request"], sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        self.records = (json.dumps(dict(cellID="a|d-01|r1", caseID=case["id"], requestSHA256=request_sha)) + "\n").encode()
        self.manifest = dict(corpusSHA256=self.old.sha256, recordsSHA256=hashlib.sha256(self.records).hexdigest())
        (self.source / "records.jsonl").write_bytes(self.records)
        (self.source / "run-manifest.json").write_text(json.dumps(self.manifest))
        self.revised = self.original / "revised"
        self.revised.mkdir()
        self.fixture.root = self.revised
        self.fixture.cases[0]["graderBrief"]["coachingPurpose"] = "Clearer wording; same candidate input"
        self.fixture.write()

    def test_rebinds_only_private_briefs_without_rerolling_candidate_bytes(self):
        destination = self.original / "regraded"
        GradingRevision.prepare(self.source, destination, self.original, self.revised)
        self.assertEqual(self.records, (destination / "records.jsonl").read_bytes())
        saved = json.loads((destination / "run-manifest.json").read_text())
        self.assertEqual(load_corpus(self.revised).sha256, saved["corpusSHA256"])
        self.assertEqual(self.old.sha256, saved["gradingRevision"]["originalCorpusSHA256"])
        self.assertEqual(json.dumps(self.manifest), (self.source / "run-manifest.json").read_text())

    def test_actual_target_is_checked_instead_of_trusting_separately_supplied_case_lists(self):
        self.fixture.cases[0]["request"]["requestID"] = "changed input in target corpus"
        self.fixture.write()
        with self.assertRaisesRegex(ValueError, "candidate inputs"):
            GradingRevision.prepare(self.source, self.original / "changed", self.original, self.revised)
        self.assertFalse((self.original / "changed").exists())

    def test_cannot_copy_a_run_into_itself(self):
        with self.assertRaises(ValueError):
            GradingRevision.prepare(self.source, self.source / "nested", self.original, self.revised)
