import hashlib
import json
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path
from types import MappingProxyType

from Tools.CoachingEval.benchmark.configuration import load_prices
from Tools.CoachingEval.benchmark.grader import RUBRIC_DIMENSIONS, RUBRIC_FLAGS
from Tools.CoachingEval.benchmark.report import (
    _pair_counts,
    build_report,
    write_report,
)


ROOT = Path(__file__).resolve().parents[3]


class BenchmarkReportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.prices = load_prices(ROOT / "Tools/CoachingEval/benchmark/pricing-v1.json")
        self.run_root, self.grade_root = self.make_artifacts()

    def tearDown(self):
        self.temporary.cleanup()

    def test_aggregates_quality_reliability_latency_usage_cost_and_judge_overhead(self):
        report = build_report(self.run_root, self.grade_root, self.prices)
        baseline = report["configurations"]["baseline"]
        candidate = report["configurations"]["candidate"]

        self.assertEqual(4, baseline["responseCount"])
        self.assertEqual(0.75, baseline["reliability"]["providerSuccessRate"])
        self.assertEqual(0.75, baseline["reliability"]["mechanicalValidityRate"])
        self.assertEqual(
            [{"category": "httpError", "httpStatus": 502, "count": 1}],
            baseline["reliability"]["providerFailureBreakdown"],
        )
        self.assertEqual([], candidate["reliability"]["providerFailureBreakdown"])
        self.assertEqual(0.25, baseline["quality"]["severeErrorRate"])
        self.assertEqual(0.5, baseline["quality"]["allDimensionsAtLeast4Rate"])
        self.assertEqual({"1": 1, "3": 1, "4": 1, "5": 1}, baseline["quality"]["dimensions"]["chessCorrectness"]["distribution"])
        self.assertEqual(2, baseline["operations"]["retryCount"])
        self.assertEqual(10, baseline["usage"]["outputTokens"])
        self.assertEqual(2000.0, baseline["latencyMilliseconds"]["p50"])
        self.assertEqual(4000.0, baseline["latencyMilliseconds"]["p90"])
        self.assertEqual(1, len(baseline["completeSequenceCostsUSD"]))
        self.assertEqual(3, candidate["pairwise"]["wins"])
        self.assertEqual(0, candidate["pairwise"]["losses"])
        self.assertEqual(1, candidate["pairwise"]["ties"])
        self.assertEqual(1.0, candidate["breakdowns"]["category"]["quiet"]["strongResponseRate"])
        self.assertEqual(1.0, candidate["breakdowns"]["turnKind"]["initial"]["strongResponseRate"])
        self.assertGreater(float(candidate["candidateCostUSD"]["total"]), 0)
        self.assertEqual(10, report["judgeOverhead"]["callCount"])
        self.assertEqual(1000, report["judgeOverhead"]["usage"]["inputTokens"])
        self.assertEqual(120, report["judgeQualification"]["metrics"]["callCount"])
        self.assertEqual(3, report["judgeQualification"]["repetitions"])
        self.assertEqual(0.95, report["judgeQualification"]["minimumSevereAgreement"])
        self.assertEqual(0.9, report["judgeQualification"]["minimumPairwiseAgreement"])
        self.assertEqual(7.0, report["judgeQualification"]["ageDaysAtGrading"])
        self.assertFalse(candidate["trialEligible"])
        self.assertFalse(candidate["promotionEligible"])
        self.assertEqual("diagnosticSubset", report["evidence"]["classification"])
        self.assertFalse(report["evidence"]["trialEligible"])
        self.assertFalse(report["evidence"]["promotionEvidenceEligible"])
        self.assertEqual(
            {"decision": "keepBaseline", "configurationID": "baseline"},
            report["recommendation"],
        )
        self.assertIn("candidate", report["paretoFrontier"])
        self.assertNotIn("baseline", report["paretoFrontier"])
        self.assertEqual(
            ["baseline|s1-3|r1"],
            [value["cellID"] for value in report["mechanicalFailures"]],
        )
        self.assertEqual(502, report["mechanicalFailures"][0]["providerHTTPStatus"])

    def test_confidence_intervals_are_deterministic_and_manifest_failures_are_diagnostic(self):
        first = build_report(self.run_root, self.grade_root, self.prices)
        second = build_report(self.run_root, self.grade_root, self.prices)
        self.assertEqual(first["confidenceIntervals"], second["confidenceIntervals"])
        self.assertEqual(10_000, first["confidenceIntervals"]["draws"])
        self.assertEqual(20260901, first["confidenceIntervals"]["seed"])

        diagnostic_subset = build_report(self.run_root, self.grade_root, self.prices)
        self.assertFalse(diagnostic_subset["promotionEligible"])
        self.assertEqual([], diagnostic_subset["integrityIssues"])

        records_path = self.run_root / "records.jsonl"
        lines = records_path.read_text().splitlines()
        records_path.write_text("\n".join(lines[:-1]) + "\n")
        diagnostic = build_report(self.run_root, self.grade_root, self.prices)
        self.assertFalse(diagnostic["promotionEligible"])
        self.assertIn("candidate records hash mismatch", diagnostic["integrityIssues"])

    def test_writes_reproducible_json_and_markdown_without_overwrite(self):
        destination = self.root / "report"
        aggregate_path, summary_path = write_report(
            self.run_root,
            self.grade_root,
            self.prices,
            destination,
        )
        aggregate = json.loads(aggregate_path.read_text())
        summary = summary_path.read_text()
        self.assertEqual("coaching-quality-report.v2", aggregate["schemaVersion"])
        self.assertIn("# Coaching quality benchmark", summary)
        self.assertIn("Experiment changes", summary)
        self.assertIn("Quality and reliability", summary)
        self.assertIn("Candidate cost", summary)
        self.assertIn("Execution policy", summary)
        self.assertIn("Eligibility gates", summary)
        self.assertIn(
            "Complete holdout comparison evidence is required for promotion.",
            summary,
        )
        self.assertIn("Keep the production baseline", summary)
        self.assertIn("Judge overhead", summary)
        self.assertIn("Judge qualification", summary)
        self.assertIn("Pareto frontier", summary)
        self.assertIn("Mechanical failures", summary)
        self.assertIn("baseline|s1-3|r1", summary)
        self.assertIn("httpError (HTTP 502): 1", summary)
        self.assertIn("HTTP 502", summary)
        self.assertIn("transcripts/candidate--s1-3--r1.md", summary)
        with self.assertRaisesRegex(ValueError, "overwrite"):
            write_report(self.run_root, self.grade_root, self.prices, destination)

    def test_reports_unknown_judge_cost_when_accounting_is_incomplete(self):
        grades_path = self.grade_root / "absolute-grades.jsonl"
        grades = [json.loads(line) for line in grades_path.read_text().splitlines()]
        grades[0]["judgeMetrics"]["accountingComplete"] = False
        grades[0]["judgeMetrics"]["estimatedCostUSD"] = None
        grades_bytes = self.jsonl(grades)
        grades_path.write_bytes(grades_bytes)
        manifest_path = self.grade_root / "grade-manifest.json"
        manifest = json.loads(manifest_path.read_text())
        manifest["absoluteGradesSHA256"] = self.sha(grades_bytes)
        manifest_path.write_text(json.dumps(manifest))

        report = build_report(self.run_root, self.grade_root, self.prices)

        self.assertFalse(report["judgeOverhead"]["accountingComplete"])
        self.assertIsNone(report["judgeOverhead"]["estimatedCostUSD"])
        destination = self.root / "incomplete-accounting-report"
        _aggregate, summary = write_report(
            self.run_root, self.grade_root, self.prices, destination
        )
        self.assertIn("unknown (accounting incomplete)", summary.read_text())

    def test_malformed_judge_cost_is_incomplete_and_blocks_holdout_promotion(self):
        run_root, grade_root = self.make_complete_comparison(
            self.root / "malformed-judge-cost",
            include_holdout=True,
        )
        grades_path = grade_root / "absolute-grades.jsonl"
        grades = [json.loads(line) for line in grades_path.read_text().splitlines()]
        grades[0]["judgeMetrics"]["estimatedCostUSD"] = "not-a-cost"
        grade_bytes = self.jsonl(grades)
        grades_path.write_bytes(grade_bytes)
        manifest_path = grade_root / "grade-manifest.json"
        manifest = json.loads(manifest_path.read_text())
        manifest["absoluteGradesSHA256"] = self.sha(grade_bytes)
        manifest_path.write_text(json.dumps(manifest))

        report = build_report(run_root, grade_root, self.prices)

        self.assertFalse(report["judgeOverhead"]["accountingComplete"])
        self.assertIsNone(report["judgeOverhead"]["estimatedCostUSD"])
        self.assertIn("judge accounting is incomplete", report["integrityIssues"])
        self.assertFalse(report["promotionEligible"])

    def test_missing_candidate_price_is_unknown_not_zero_cost(self):
        missing_prices = replace(self.prices, models=MappingProxyType({}))

        report = build_report(self.run_root, self.grade_root, missing_prices)

        candidate_cost = report["configurations"]["candidate"]["candidateCostUSD"]
        self.assertFalse(candidate_cost["accountingComplete"])
        self.assertIsNone(candidate_cost["total"])
        self.assertIsNone(candidate_cost["perResponse"])
        self.assertIn("missing price coverage for candidate", report["integrityIssues"])

    def test_missing_candidate_accounting_is_unknown_and_ineligible(self):
        records_path = self.run_root / "records.jsonl"
        records = [json.loads(line) for line in records_path.read_text().splitlines()]
        records[4].pop("candidateAccountingComplete")
        records[4]["candidateCostUSD"] = None
        records_bytes = self.jsonl(records)
        records_path.write_bytes(records_bytes)
        run_manifest_path = self.run_root / "run-manifest.json"
        run_manifest = json.loads(run_manifest_path.read_text())
        run_manifest["recordsSHA256"] = self.sha(records_bytes)
        run_manifest_path.write_text(json.dumps(run_manifest))
        grade_manifest_path = self.grade_root / "grade-manifest.json"
        grade_manifest = json.loads(grade_manifest_path.read_text())
        grade_manifest["sourceRunRecordsSHA256"] = self.sha(records_bytes)
        grade_manifest_path.write_text(json.dumps(grade_manifest))

        report = build_report(self.run_root, self.grade_root, self.prices)

        candidate_cost = report["configurations"]["candidate"]["candidateCostUSD"]
        self.assertFalse(candidate_cost["accountingComplete"])
        self.assertIsNone(candidate_cost["total"])
        self.assertIn(
            "candidate accounting is incomplete for candidate",
            report["integrityIssues"],
        )

    def test_malformed_candidate_cost_is_unknown_and_ineligible(self):
        records_path = self.run_root / "records.jsonl"
        records = [json.loads(line) for line in records_path.read_text().splitlines()]
        records[4]["candidateCostUSD"] = "not-a-cost"
        records_bytes = self.jsonl(records)
        records_path.write_bytes(records_bytes)
        run_manifest_path = self.run_root / "run-manifest.json"
        run_manifest = json.loads(run_manifest_path.read_text())
        run_manifest["recordsSHA256"] = self.sha(records_bytes)
        run_manifest_path.write_text(json.dumps(run_manifest))
        grade_manifest_path = self.grade_root / "grade-manifest.json"
        grade_manifest = json.loads(grade_manifest_path.read_text())
        grade_manifest["sourceRunRecordsSHA256"] = self.sha(records_bytes)
        grade_manifest_path.write_text(json.dumps(grade_manifest))

        report = build_report(self.run_root, self.grade_root, self.prices)

        candidate_cost = report["configurations"]["candidate"]["candidateCostUSD"]
        self.assertFalse(candidate_cost["accountingComplete"])
        self.assertIsNone(candidate_cost["total"])
        self.assertIn(
            "candidate cost accounting is invalid for candidate",
            report["integrityIssues"],
        )

    def test_empty_usage_cannot_claim_complete_candidate_accounting(self):
        run_root, grade_root = self.make_complete_comparison(
            self.root / "empty-candidate-usage",
            include_holdout=True,
        )
        records_path = run_root / "records.jsonl"
        records = [json.loads(line) for line in records_path.read_text().splitlines()]
        candidate_records = [
            record
            for record in records
            if record["configurationID"] == "candidate"
            and record["repetition"] == 1
        ][:3]
        for step_index, record in enumerate(candidate_records, start=1):
            record["groupID"] = "candidate-sequence"
            record["stepIndex"] = step_index
        candidate_record = candidate_records[0]
        candidate_record["usage"] = {}
        candidate_record["candidateAccountingComplete"] = True
        candidate_record["candidateCostUSD"] = "0"
        records_bytes = self.jsonl(records)
        records_path.write_bytes(records_bytes)
        run_manifest_path = run_root / "run-manifest.json"
        run_manifest = json.loads(run_manifest_path.read_text())
        run_manifest["recordsSHA256"] = self.sha(records_bytes)
        run_manifest_path.write_text(json.dumps(run_manifest))
        grade_manifest_path = grade_root / "grade-manifest.json"
        grade_manifest = json.loads(grade_manifest_path.read_text())
        grade_manifest["sourceRunRecordsSHA256"] = self.sha(records_bytes)
        grade_manifest_path.write_text(json.dumps(grade_manifest))

        report = build_report(run_root, grade_root, self.prices)

        candidate = report["configurations"]["candidate"]
        self.assertFalse(candidate["candidateCostUSD"]["accountingComplete"])
        self.assertIsNone(candidate["candidateCostUSD"]["total"])
        self.assertIn(
            "candidate usage accounting is invalid for candidate",
            report["integrityIssues"],
        )
        self.assertFalse(
            any(
                value["groupID"] == "candidate-sequence"
                for value in candidate["completeSequenceCostsUSD"]
            )
        )
        self.assertFalse(report["promotionEligible"])
        self.assertEqual(
            {"decision": "keepBaseline", "configurationID": "baseline"},
            report["recommendation"],
        )

    def test_development_comparison_can_qualify_a_trial_but_not_promotion(self):
        run_root, grade_root = self.make_complete_comparison(
            self.root / "development-comparison",
            include_holdout=False,
        )

        report = build_report(run_root, grade_root, self.prices)
        candidate = report["configurations"]["candidate"]

        self.assertEqual("developmentComparison", report["evidence"]["classification"])
        self.assertTrue(report["evidence"]["completeMatrix"])
        self.assertTrue(candidate["trialEligible"])
        self.assertFalse(candidate["promotionEligible"])
        self.assertIn(
            "Complete holdout comparison evidence is required for promotion.",
            candidate["promotionReasons"],
        )
        self.assertEqual(
            {"decision": "keepBaseline", "configurationID": "baseline"},
            report["recommendation"],
        )

    def test_complete_holdout_requires_every_concrete_promotion_gate(self):
        passing_run, passing_grades = self.make_complete_comparison(
            self.root / "passing-holdout",
            include_holdout=True,
        )
        passing = build_report(passing_run, passing_grades, self.prices)
        self.assertTrue(passing["configurations"]["candidate"]["promotionEligible"])
        self.assertEqual(
            {"decision": "promoteChallenger", "configurationID": "candidate"},
            passing["recommendation"],
        )

        blocked = (
            ("newMechanicalFailure", "Introduces a new mechanical failure category."),
            ("higherSevereRate", "Severe-error rate is higher than production."),
            ("noStrongImprovement", "Strong-response rate does not improve on production."),
            ("noPairwiseAdvantage", "Pairwise wins do not exceed losses."),
        )
        for gate, reason in blocked:
            with self.subTest(gate=gate):
                run_root, grade_root = self.make_complete_comparison(
                    self.root / gate,
                    include_holdout=True,
                    blocked_gate=gate,
                )
                report = build_report(run_root, grade_root, self.prices)
                candidate = report["configurations"]["candidate"]
                self.assertFalse(candidate["promotionEligible"])
                self.assertIn(reason, candidate["promotionReasons"])
                self.assertEqual(
                    {"decision": "keepBaseline", "configurationID": "baseline"},
                    report["recommendation"],
                )

    def test_complete_holdout_requires_accepted_correctly_bound_qualification(self):
        mutations = (
            (
                "rejected",
                lambda qualification: qualification.update(status="rejected"),
                "judge qualification was not accepted",
            ),
            (
                "wrong-binding",
                lambda qualification: qualification["bindings"].update(
                    judgePromptSHA256="0" * 64
                ),
                "judge qualification bindings do not match grade manifest",
            ),
        )
        for name, mutate, issue in mutations:
            with self.subTest(name=name):
                run_root, grade_root = self.make_complete_comparison(
                    self.root / f"qualification-{name}",
                    include_holdout=True,
                )
                qualification_path = grade_root / "qualification.json"
                qualification = json.loads(qualification_path.read_text())
                mutate(qualification)
                qualification_bytes = self.pretty(qualification)
                qualification_path.write_bytes(qualification_bytes)
                manifest_path = grade_root / "grade-manifest.json"
                manifest = json.loads(manifest_path.read_text())
                manifest["qualificationSHA256"] = self.sha(qualification_bytes)
                manifest_path.write_text(json.dumps(manifest))

                report = build_report(run_root, grade_root, self.prices)

                self.assertFalse(report["promotionEligible"])
                self.assertIn(issue, report["integrityIssues"])
                self.assertEqual(
                    {"decision": "keepBaseline", "configurationID": "baseline"},
                    report["recommendation"],
                )

    def test_qualification_and_manifest_require_complete_valid_sha_bindings(self):
        mutations = (
            (
                "same-missing-binding",
                lambda qualification, manifest: (
                    qualification["bindings"].pop("judgePromptSHA256"),
                    manifest.pop("judgePromptSHA256"),
                ),
            ),
            (
                "same-malformed-binding",
                lambda qualification, manifest: (
                    qualification["bindings"].update(judgePromptSHA256="bad"),
                    manifest.update(judgePromptSHA256="bad"),
                ),
            ),
            (
                "malformed-reference-binding",
                lambda qualification, _manifest: qualification["bindings"].update(
                    referenceSetSHA256="bad"
                ),
            ),
        )
        for name, mutate in mutations:
            with self.subTest(name=name):
                run_root, grade_root = self.make_complete_comparison(
                    self.root / name,
                    include_holdout=True,
                )
                qualification_path = grade_root / "qualification.json"
                qualification = json.loads(qualification_path.read_text())
                manifest_path = grade_root / "grade-manifest.json"
                manifest = json.loads(manifest_path.read_text())
                mutate(qualification, manifest)
                qualification_bytes = self.pretty(qualification)
                qualification_path.write_bytes(qualification_bytes)
                manifest["qualificationSHA256"] = self.sha(qualification_bytes)
                manifest_path.write_text(json.dumps(manifest))

                report = build_report(run_root, grade_root, self.prices)

                self.assertFalse(report["promotionEligible"])
                self.assertIn(
                    "judge qualification bindings are invalid",
                    report["integrityIssues"],
                )
                self.assertEqual(
                    {"decision": "keepBaseline", "configurationID": "baseline"},
                    report["recommendation"],
                )

    def test_pairwise_counts_require_exact_unique_candidate_pair_ids(self):
        records = [
            {"caseID": "case-1", "repetition": 1},
            {"caseID": "case-2", "repetition": 1},
        ]
        pairwise = [
            {
                "pairID": "a|case-1|r1|vs|baseline",
                "outcome": "candidateWin",
            },
            {
                "pairID": "a|b|case-1|r1|vs|baseline",
                "outcome": "candidateWin",
            },
            {
                "pairID": "a|case-2|r1|vs|baseline",
                "outcome": "candidateLoss",
            },
            {
                "pairID": "a|case-2|r1|vs|baseline",
                "outcome": "candidateLoss",
            },
        ]

        counts = _pair_counts(
            "a",
            {"baseline": False},
            pairwise,
            records,
            "baseline",
        )

        self.assertEqual({"wins": 1, "losses": 0, "ties": 0}, counts)

    def test_incomplete_matrix_or_grading_cannot_support_eligibility(self):
        partial_parent = self.root / "partial-comparison"
        partial_parent.mkdir()
        partial_run, partial_grades = self.make_artifacts(partial_parent)
        manifest_path = partial_run / "run-manifest.json"
        manifest = json.loads(manifest_path.read_text())
        manifest.update(
            {
                "diagnosticSubset": False,
                "evidence": {
                    "classification": "developmentComparison",
                    "trialEligible": True,
                    "promotionEvidenceEligible": False,
                },
            }
        )
        manifest_path.write_text(json.dumps(manifest))
        partial = build_report(partial_run, partial_grades, self.prices)
        self.assertFalse(partial["trialEligible"])
        self.assertIn(
            "candidate comparison matrix is incomplete",
            partial["integrityIssues"],
        )

        run_root, grade_root = self.make_complete_comparison(
            self.root / "incomplete-grading",
            include_holdout=True,
        )
        grade_manifest_path = grade_root / "grade-manifest.json"
        grade_manifest = json.loads(grade_manifest_path.read_text())
        grade_manifest["status"] = "failed"
        grade_manifest_path.write_text(json.dumps(grade_manifest))
        incomplete_grading = build_report(run_root, grade_root, self.prices)
        self.assertFalse(incomplete_grading["promotionEligible"])
        self.assertIn(
            "grade run did not complete",
            incomplete_grading["integrityIssues"],
        )

        legacy_run, legacy_grades = self.make_complete_comparison(
            self.root / "legacy-holdout",
            include_holdout=True,
        )
        calibration = {
            "schemaVersion": "coaching-quality-calibration-result.v1",
            "passed": True,
            "severeAgreement": 1.0,
            "dimensionWithinOne": 1.0,
            "rowCount": 20,
            "calibrationSHA256": "d" * 64,
            "judgeMetrics": self.metrics(20),
        }
        calibration_bytes = self.pretty(calibration)
        (legacy_grades / "calibration.json").write_bytes(calibration_bytes)
        legacy_manifest_path = legacy_grades / "grade-manifest.json"
        legacy_manifest = json.loads(legacy_manifest_path.read_text())
        legacy_manifest["schemaVersion"] = "coaching-quality-grade-run.v1"
        legacy_manifest["calibrationSHA256"] = self.sha(calibration_bytes)
        for key in ("status", "gradedAt", "qualificationSHA256"):
            legacy_manifest.pop(key, None)
        legacy_manifest_path.write_text(json.dumps(legacy_manifest))

        legacy = build_report(legacy_run, legacy_grades, self.prices)

        self.assertFalse(legacy["trialEligible"])
        self.assertFalse(legacy["promotionEligible"])
        self.assertEqual(
            {"decision": "keepBaseline", "configurationID": "baseline"},
            legacy["recommendation"],
        )
        self.assertIn(
            "legacy grade artifacts are diagnostic only",
            legacy["integrityIssues"],
        )

    def test_reads_legacy_calibration_artifacts(self):
        legacy_root = self.root / "legacy"
        legacy_root.mkdir()
        run_root, grade_root = self.make_artifacts(legacy_root, legacy=True)

        report = build_report(run_root, grade_root, self.prices)

        self.assertEqual("coaching-quality-report.v2", report["schemaVersion"])
        self.assertIsNone(report["judgeQualification"])
        self.assertEqual(30, report["judgeOverhead"]["callCount"])
        self.assertEqual(
            ["legacy grade artifacts are diagnostic only"],
            report["integrityIssues"],
        )

    def make_complete_comparison(
        self,
        parent,
        *,
        include_holdout,
        blocked_gate=None,
    ):
        parent.mkdir()
        run_root, grade_root = self.make_artifacts(parent)
        run_manifest = json.loads((run_root / "run-manifest.json").read_text())
        grade_manifest = json.loads((grade_root / "grade-manifest.json").read_text())
        configurations = run_manifest["configurations"]
        case_splits = [
            (f"development-{index:02}", "development")
            for index in range(1, 57)
        ]
        if include_holdout:
            case_splits.extend(
                (f"holdout-{index:02}", "holdout")
                for index in range(1, 15)
            )

        records = []
        grades = []
        for configuration_id in ("baseline", "candidate"):
            for repetition in range(1, 4):
                for case_index, (case_id, split) in enumerate(case_splits):
                    cell_id = f"{configuration_id}|{case_id}|r{repetition}"
                    is_first_candidate = (
                        configuration_id == "candidate"
                        and repetition == 1
                        and case_index == 0
                    )
                    mechanically_valid = not (
                        blocked_gate == "newMechanicalFailure"
                        and is_first_candidate
                    )
                    categories = [] if mechanically_valid else ["invalidResponse"]
                    records.append(
                        {
                            "cellID": cell_id,
                            "configurationID": configuration_id,
                            "caseID": case_id,
                            "groupID": case_id,
                            "stepIndex": 1,
                            "split": split,
                            "category": "quiet",
                            "repetition": repetition,
                            "generationStatus": (
                                "completed" if mechanically_valid else "invalid"
                            ),
                            "providerHTTPStatus": None,
                            "mechanicalValidation": {
                                "valid": mechanically_valid,
                                "categories": categories,
                            },
                            "usage": {
                                "inputTokens": 100,
                                "cachedInputTokens": 10,
                                "outputTokens": 10,
                                "reasoningTokens": 2,
                                "totalTokens": 110,
                            },
                            "latencyMilliseconds": (
                                1000 if configuration_id == "baseline" else 900
                            ),
                            "attemptCount": 1,
                            "candidateAccountingComplete": True,
                            "candidateCostUSD": "0.000564",
                        }
                    )
                    score = 3 if configuration_id == "baseline" else 5
                    if blocked_gate == "noStrongImprovement" and configuration_id == "candidate":
                        score = 3
                    flags = {flag: False for flag in RUBRIC_FLAGS}
                    if blocked_gate == "higherSevereRate" and is_first_candidate:
                        flags["severeError"] = True
                    grades.append(
                        {
                            "schemaVersion": "coaching-quality-absolute-grade.v1",
                            "cellID": cell_id,
                            "disposition": (
                                "judged" if mechanically_valid else "unusable"
                            ),
                            "scores": {
                                dimension: score for dimension in RUBRIC_DIMENSIONS
                            },
                            "flags": flags,
                            "evidence": ["Synthetic complete-matrix evidence."],
                            "judgeMetrics": self.metrics(1),
                        }
                    )

        pairs = []
        pair_index = 0
        pair_total = len(case_splits) * 3
        for repetition in range(1, 4):
            for case_id, _split in case_splits:
                outcome = "candidateWin"
                if blocked_gate == "noPairwiseAdvantage" and pair_index >= pair_total // 2:
                    outcome = "candidateLoss"
                pairs.append(
                    {
                        "schemaVersion": "coaching-quality-pairwise-grade.v1",
                        "pairID": f"candidate|{case_id}|r{repetition}|vs|baseline",
                        "outcome": outcome,
                        "candidatePresentedAs": "A",
                        "evidence": ["Synthetic complete-matrix pair evidence."],
                        "judgeMetrics": self.metrics(1),
                    }
                )
                pair_index += 1

        records_bytes = self.jsonl(records)
        absolute_bytes = self.jsonl(grades)
        pairwise_bytes = self.jsonl(pairs)
        (run_root / "records.jsonl").write_bytes(records_bytes)
        (grade_root / "absolute-grades.jsonl").write_bytes(absolute_bytes)
        (grade_root / "pairwise-grades.jsonl").write_bytes(pairwise_bytes)
        classification = (
            "holdoutComparison" if include_holdout else "developmentComparison"
        )
        run_manifest.update(
            {
                "mode": "comparison",
                "diagnosticSubset": False,
                "includeHoldout": include_holdout,
                "evidence": {
                    "classification": classification,
                    "trialEligible": True,
                    "promotionEvidenceEligible": include_holdout,
                },
                "recordIDs": [record["cellID"] for record in records],
                "recordsSHA256": self.sha(records_bytes),
                "summary": {
                    "recordCount": len(records),
                    "validCount": sum(
                        record["mechanicalValidation"]["valid"] for record in records
                    ),
                    "failedCount": sum(
                        not record["mechanicalValidation"]["valid"] for record in records
                    ),
                },
            }
        )
        (run_root / "run-manifest.json").write_text(json.dumps(run_manifest))
        grade_manifest.update(
            {
                "sourceRunRecordsSHA256": self.sha(records_bytes),
                "absoluteGradesSHA256": self.sha(absolute_bytes),
                "pairwiseGradesSHA256": self.sha(pairwise_bytes),
                "absoluteGradeCount": len(grades),
                "pairwiseGradeCount": len(pairs),
            }
        )
        (grade_root / "grade-manifest.json").write_text(json.dumps(grade_manifest))
        return run_root, grade_root

    def make_artifacts(self, parent=None, *, legacy=False):
        parent = parent or self.root
        run_root = parent / "run"
        grade_root = parent / "grades"
        run_root.mkdir()
        grade_root.mkdir()
        configurations = [
            {
                "id": "baseline",
                "baseline": True,
                "model": "gpt-5.6-sol",
                "systemPromptSHA256": "a" * 64,
                "initialReasoningEffort": "high",
                "tacticalFollowUpReasoningEffort": "low",
                "simpleFollowUpReasoningEffort": "none",
                "conversationReuse": True,
                "store": True,
                "maximumOutputTokens": 2048,
                "userPromptGenerator": "chess-native-v13",
                "pricingVersion": self.prices.version,
            },
            {
                "id": "candidate",
                "baseline": False,
                "model": "gpt-5.6-sol",
                "systemPromptSHA256": "b" * 64,
                "initialReasoningEffort": "medium",
                "tacticalFollowUpReasoningEffort": "low",
                "simpleFollowUpReasoningEffort": "none",
                "conversationReuse": True,
                "store": True,
                "maximumOutputTokens": 1024,
                "userPromptGenerator": "chess-native-v13",
                "pricingVersion": self.prices.version,
            },
        ]
        records = []
        grades = []
        cases = (("q1", "q1", 1, "quiet"), ("s1-1", "s1", 1, "interaction"), ("s1-2", "s1", 2, "interaction"), ("s1-3", "s1", 3, "interaction"))
        baseline_scores = (4, 5, 3, 1)
        candidate_scores = (5, 5, 5, 2)
        baseline_valid = (True, True, True, False)
        candidate_valid = (True, True, True, True)
        baseline_latency = (1000, 2000, 3000, 4000)
        candidate_latency = (800, 1200, 1800, 2500)
        for configuration_id, score_values, valid_values, latencies, input_tokens in (
            ("baseline", baseline_scores, baseline_valid, baseline_latency, 100),
            ("candidate", candidate_scores, candidate_valid, candidate_latency, 25),
        ):
            for (case_id, group_id, step_index, category), score, valid, latency in zip(cases, score_values, valid_values, latencies):
                cell_id = f"{configuration_id}|{case_id}|r1"
                status = "completed" if valid else "httpError"
                output_tokens = 10 if case_id == "q1" and valid else 0
                usage = {
                    "inputTokens": input_tokens if valid else 0,
                    "cachedInputTokens": 10 if valid else 0,
                    "outputTokens": output_tokens,
                    "reasoningTokens": 2 if output_tokens else 0,
                    "totalTokens": input_tokens + output_tokens if valid else 0,
                }
                records.append(
                    {
                        "cellID": cell_id,
                        "configurationID": configuration_id,
                        "caseID": case_id,
                        "groupID": group_id,
                        "stepIndex": step_index,
                        "split": "development",
                        "category": category,
                        "repetition": 1,
                        "generationStatus": status,
                        "providerHTTPStatus": None if valid else 502,
                        "mechanicalValidation": {"valid": valid, "categories": [] if valid else ["httpError"]},
                        "usage": usage,
                        "latencyMilliseconds": latency,
                        "attemptCount": 3 if configuration_id == "baseline" and case_id == "q1" else 1,
                        "candidateAccountingComplete": True,
                        "candidateCostUSD": str(
                            self.prices.estimate("gpt-5.6-sol", usage)
                        ),
                    }
                )
                flags = {flag: False for flag in RUBRIC_FLAGS}
                flags["severeError"] = not valid or (configuration_id == "candidate" and case_id == "s1-3")
                grades.append(
                    {
                        "schemaVersion": "coaching-quality-absolute-grade.v1",
                        "cellID": cell_id,
                        "disposition": "judged" if valid else "unusable",
                        "scores": {dimension: score for dimension in RUBRIC_DIMENSIONS},
                        "flags": flags,
                        "evidence": ["Synthetic benchmark evidence."],
                        "judgeMetrics": self.metrics(1 if valid else 0),
                    }
                )
        records_bytes = self.jsonl(records)
        (run_root / "records.jsonl").write_bytes(records_bytes)
        run_manifest = {
            "schemaVersion": "coaching-quality-candidate-run.v1",
            "mode": "comparison",
            "diagnosticSubset": True,
            "includeHoldout": False,
            "evidence": {
                "classification": "diagnosticSubset",
                "trialEligible": False,
                "promotionEvidenceEligible": False,
            },
            "corpusSHA256": "c" * 64,
            "sourceGitSHA": "source",
            "configurations": configurations,
            "recordIDs": [record["cellID"] for record in records],
            "recordsSHA256": self.sha(records_bytes),
            "summary": {"recordCount": 8, "validCount": 7, "failedCount": 1},
        }
        (run_root / "run-manifest.json").write_text(json.dumps(run_manifest))

        pairs = []
        outcomes = ("candidateWin", "tie", "candidateWin", "candidateWin")
        for (case_id, _group_id, _step, _category), outcome in zip(cases, outcomes):
            pairs.append(
                {
                    "schemaVersion": "coaching-quality-pairwise-grade.v1",
                    "pairID": f"candidate|{case_id}|r1|vs|baseline",
                    "outcome": outcome,
                    "candidatePresentedAs": "A",
                    "evidence": ["Synthetic pair evidence."],
                    "judgeMetrics": self.metrics(0 if case_id == "s1-3" else 1),
                }
            )
        calibration = {
            "schemaVersion": "coaching-quality-calibration-result.v1",
            "passed": True,
            "severeAgreement": 1.0,
            "dimensionWithinOne": 1.0,
            "rowCount": 20,
            "calibrationSHA256": "d" * 64,
            "judgeMetrics": self.metrics(20),
        }
        absolute_bytes = self.jsonl(grades)
        pairwise_bytes = self.jsonl(pairs)
        calibration_bytes = self.pretty(calibration)
        (grade_root / "absolute-grades.jsonl").write_bytes(absolute_bytes)
        (grade_root / "pairwise-grades.jsonl").write_bytes(pairwise_bytes)
        shared_manifest = {
            "sourceRunRecordsSHA256": self.sha(records_bytes),
            "corpusSHA256": "c" * 64,
            "judgeConfigurationSHA256": "e" * 64,
            "judgePromptSHA256": "f" * 64,
            "absoluteSchemaSHA256": "1" * 64,
            "pairwiseSchemaSHA256": "2" * 64,
            "absoluteGradesSHA256": self.sha(absolute_bytes),
            "pairwiseGradesSHA256": self.sha(pairwise_bytes),
            "absoluteGradeCount": len(grades),
            "pairwiseGradeCount": len(pairs),
        }
        if legacy:
            (grade_root / "calibration.json").write_bytes(calibration_bytes)
            grade_manifest = {
                "schemaVersion": "coaching-quality-grade-run.v1",
                **shared_manifest,
                "calibrationSHA256": self.sha(calibration_bytes),
            }
        else:
            qualification = {
                "schemaVersion": "coaching-quality-judge-qualification.v2",
                "status": "accepted",
                "judgeConfigurationID": "judge-sol-v2",
                "referenceSetID": "judge-reference-v2",
                "createdAt": "2026-09-03T12:00:00Z",
                "expiresAt": "2026-10-03T12:00:00Z",
                "criteria": {
                    "repetitions": 3,
                    "minimumSevereAgreement": 0.95,
                    "minimumDimensionAgreement": 0.9,
                    "minimumPairwiseAgreement": 0.9,
                    "validDays": 30,
                },
                "bindings": {
                    "judgeConfigurationSHA256": "e" * 64,
                    "judgePromptSHA256": "f" * 64,
                    "referenceSetSHA256": "d" * 64,
                    "absoluteSchemaSHA256": "1" * 64,
                    "pairwiseSchemaSHA256": "2" * 64,
                },
                "minimumSevereAgreement": 0.95,
                "minimumDimensionAgreement": 0.925,
                "minimumPairwiseAgreement": 0.9,
                "qualificationMetrics": self.metrics(120),
                "passes": [
                    {
                        "repetition": repetition,
                        "passed": True,
                        "severeAgreement": 1.0 if repetition < 3 else 0.95,
                        "dimensionWithinOne": 0.95 if repetition < 3 else 0.925,
                        "pairwiseAgreement": 1.0 if repetition < 3 else 0.9,
                        "judgeMetrics": self.metrics(40),
                        "rows": [{} for _ in range(20)],
                        "pairwiseRows": [{} for _ in range(20)],
                    }
                    for repetition in range(1, 4)
                ],
            }
            qualification_bytes = self.pretty(qualification)
            (grade_root / "qualification.json").write_bytes(qualification_bytes)
            grade_manifest = {
                "schemaVersion": "coaching-quality-grade-run.v2",
                "status": "completed",
                "gradedAt": "2026-09-10T12:00:00Z",
                **shared_manifest,
                "qualificationSHA256": self.sha(qualification_bytes),
            }
        (grade_root / "grade-manifest.json").write_text(json.dumps(grade_manifest))
        return run_root, grade_root

    def metrics(self, calls):
        return {
            "accountingComplete": True,
            "callCount": calls,
            "usage": {
                "inputTokens": 100 * calls,
                "cachedInputTokens": 10 * calls,
                "outputTokens": 20 * calls,
                "reasoningTokens": 5 * calls,
                "totalTokens": 120 * calls,
            },
            "latencyMilliseconds": 100 * calls,
            "estimatedCostUSD": str(0.01 * calls),
        }

    @staticmethod
    def jsonl(values):
        return b"".join(json.dumps(value, sort_keys=True, separators=(",", ":")).encode() + b"\n" for value in values)

    @staticmethod
    def pretty(value):
        return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()

    @staticmethod
    def sha(value):
        return hashlib.sha256(value).hexdigest()


if __name__ == "__main__":
    unittest.main()
