import unittest

from Tools.CoachingEval.benchmark.judgment_metrics import JudgmentMetrics


class JudgmentMetricsTests(unittest.TestCase):
    def test_failures_and_missing_grades_cannot_inflate_useful_response_rate(self):
        rows = [dict(cellID=f"a|j1|r{i}", configurationID="a", caseID="j1",
                     mechanicalValidation={"valid": i != 3}) for i in range(1, 5)]
        grades = [dict(cellID="a|j1|r1", disposition="judged", scores={"coachingJudgment": 5}, flags={"severeError": False}),
                  dict(cellID="a|j1|r2", disposition="judged", scores={"coachingJudgment": 2}, flags={"severeError": False}),
                  dict(cellID="a|j1|r3", disposition="invalidResponse", scores=None, flags={})]
        result = JudgmentMetrics.summarize(rows, grades)["a"]
        self.assertEqual(3.5, result["judgedMean"])
        self.assertEqual(0.25, result["usefulResponseRate"])
        self.assertEqual(1, result["failedOrInvalidCount"])
        self.assertEqual(1, result["ungradedValidCount"])
        self.assertEqual([5, 2], result["cases"]["j1"]["scores"])

    def test_high_judgment_with_a_severe_error_is_not_a_useful_response(self):
        rows = [dict(cellID="a|j1|r1", configurationID="a", caseID="j1", mechanicalValidation={"valid": True})]
        grades = [dict(cellID="a|j1|r1", disposition="judged", scores={"coachingJudgment": 5}, flags={"severeError": True})]
        self.assertEqual(0, JudgmentMetrics.summarize(rows, grades)["a"]["usefulResponseRate"])
        with self.assertRaises(ValueError):
            JudgmentMetrics.summarize(rows, grades + grades)
        with self.assertRaises(ValueError):
            JudgmentMetrics.summarize([], grades)


if __name__ == "__main__":
    unittest.main()
