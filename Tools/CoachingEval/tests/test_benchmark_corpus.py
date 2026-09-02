import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from Tools.CoachingEval.benchmark.corpus import load_corpus


def _jsonl(values):
    return b"".join(
        json.dumps(value, sort_keys=True, separators=(",", ":")).encode() + b"\n"
        for value in values
    )


class BenchmarkCorpusTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        independent = [
            (f"d-{index:02}", "development" if index <= 32 else "holdout")
            for index in range(1, 41)
        ]
        sequences = [
            (f"s-{index:02}", "development" if index <= 8 else "holdout")
            for index in range(1, 11)
        ]
        self.cases = [self._case(identifier, identifier, 1, split) for identifier, split in independent]
        for identifier, split in sequences:
            self.cases.extend(
                self._case(f"{identifier}-{step:02}", identifier, step, split)
                for step in range(1, 4)
            )
        self.write()

    def tearDown(self):
        self.temporary.cleanup()

    def _case(self, identifier, group, step, split):
        return {
            "schemaVersion": "coaching-quality-benchmark-case.v1",
            "id": identifier,
            "groupID": group,
            "stepIndex": step,
            "split": split,
            "category": "quiet" if step == 1 else "interaction",
            "request": {"schemaVersion": "model-coaching-neutral-request.v1", "requestID": f"benchmark:{identifier}"},
            "graderBrief": {
                "verifiedFacts": ["Side to move: white."],
                "coachingPurpose": "Coach one useful step.",
                "acceptableAlternatives": ["Any accurate response."],
                "successCriteria": ["Accurate and answerable."],
                "severeFailureCriteria": ["Invents checkmate."],
            },
            "sourceTraceID": None,
        }

    def write(self):
        cases_bytes = _jsonl(self.cases)
        (self.root / "cases.jsonl").write_bytes(cases_bytes)
        groups = {}
        for case in self.cases:
            groups.setdefault(case["groupID"], []).append(case)
        manifest = {
            "schemaVersion": "coaching-quality-benchmark-manifest.v1",
            "sourceGitSHA": "abc123",
            "independentGroupCount": sum(len(turns) == 1 for turns in groups.values()),
            "sequenceGroupCount": sum(len(turns) == 3 for turns in groups.values()),
            "turnCount": len(self.cases),
            "developmentTurnCount": sum(case["split"] == "development" for case in self.cases),
            "holdoutTurnCount": sum(case["split"] == "holdout" for case in self.cases),
            "turnIDs": [case["id"] for case in self.cases],
            "casesSHA256": hashlib.sha256(cases_bytes).hexdigest(),
        }
        (self.root / "benchmark-manifest.json").write_text(
            json.dumps(manifest, sort_keys=True), encoding="utf-8"
        )

    def test_loads_exact_inventory_and_hides_holdout_by_default(self):
        corpus = load_corpus(self.root)

        self.assertEqual(70, len(corpus.turns))
        self.assertEqual(56, len(corpus.select(include_holdout=False)))
        self.assertEqual(70, len(corpus.select(include_holdout=True)))
        self.assertEqual("abc123", corpus.source_git_sha)
        self.assertEqual(64, len(corpus.sha256))

    def test_accepts_swift_omission_of_nil_source_trace_id(self):
        for case in self.cases:
            case.pop("sourceTraceID")
        self.write()

        corpus = load_corpus(self.root)

        self.assertTrue(all(turn.source_trace_id is None for turn in corpus.turns))

    def test_rejects_hash_duplicate_count_split_category_and_missing_brief(self):
        original = json.loads(json.dumps(self.cases))
        mutations = (
            lambda: self.cases.__setitem__(1, dict(self.cases[1], id=self.cases[0]["id"])),
            lambda: self.cases.pop(),
            lambda: self.cases[0].__setitem__("split", "secret"),
            lambda: self.cases[0].__setitem__("category", "opening"),
            lambda: self.cases[0].pop("graderBrief"),
            lambda: self.cases[0].__setitem__("unexpected", True),
        )
        for mutate in mutations:
            with self.subTest(mutate=mutate):
                self.cases = json.loads(json.dumps(original))
                mutate()
                self.write()
                with self.assertRaises(ValueError):
                    load_corpus(self.root)

        self.cases = original
        self.write()
        (self.root / "cases.jsonl").write_bytes((self.root / "cases.jsonl").read_bytes() + b" ")
        with self.assertRaisesRegex(ValueError, "hash"):
            load_corpus(self.root)

    def test_rejects_partial_or_reordered_sequences(self):
        sequence = [case for case in self.cases if case["groupID"] == "s-01"]
        sequence[1]["stepIndex"] = 3
        self.write()
        with self.assertRaises(ValueError):
            load_corpus(self.root)


if __name__ == "__main__":
    unittest.main()
