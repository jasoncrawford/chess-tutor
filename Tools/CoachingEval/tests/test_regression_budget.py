import json
import tempfile
import unittest
from decimal import Decimal
from pathlib import Path
from unittest.mock import Mock

from Tools.CoachingEval.benchmark.budget import BudgetedClient, BudgetExceeded
from Tools.CoachingEval.benchmark.configuration import load_prices


ROOT = Path(__file__).resolve().parents[3]


class RegressionBudgetTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "budget.jsonl"
        self.prices = load_prices(ROOT / "Tools/CoachingEval/benchmark/pricing-v2.json")
        self.arguments = dict(model="gpt-6-astra", system_prompt="system", user_prompt="user",
                              schema={}, maximum_output_tokens=2048, previous_response_id=None)
        self.response = dict(id="response-one", output_text='{}', usage=dict(
            input_tokens=100, cached_input_tokens=20, output_tokens=10, reasoning_tokens=0, total_tokens=110))

    def test_refuses_before_api_when_reservation_does_not_fit(self):
        client = Mock()
        budget = BudgetedClient(client, self.prices, self.path, Decimal("0.001"))
        with self.assertRaises(BudgetExceeded):
            budget.complete(**self.arguments)
        client.complete.assert_not_called()

    def test_failure_keeps_reservation_and_success_settles_usage(self):
        client = Mock()
        client.complete.side_effect = [RuntimeError("sk-must-not-appear"), self.response]
        budget = BudgetedClient(client, self.prices, self.path, Decimal("10"))
        with self.assertRaises(RuntimeError):
            budget.complete(**self.arguments)
        reserved = budget.spent
        self.assertGreater(reserved, 0)
        budget.complete(**self.arguments)
        self.assertGreater(budget.spent, reserved)
        self.assertLess(budget.spent, reserved * 2)
        self.assertNotIn("sk-must-not-appear", self.path.read_text())
        self.assertEqual(1, budget.unknown_calls)
        restored = BudgetedClient(client, self.prices, self.path, Decimal("10"))
        self.assertEqual(budget.spent, restored.spent)

    def test_followup_reserves_prior_context_and_unknown_response_is_not_free(self):
        client = Mock()
        large = dict(self.response, usage=dict(input_tokens=5000, cached_input_tokens=0,
                     output_tokens=10, reasoning_tokens=0, total_tokens=5010))
        client.complete.side_effect = [large, self.response]
        budget = BudgetedClient(client, self.prices, self.path, Decimal("10"))
        budget.complete(**self.arguments)
        budget.complete(**dict(self.arguments, previous_response_id="response-one"))
        rows = [json.loads(line) for line in self.path.read_text().splitlines()]
        reservations = [r for r in rows if r["state"] == "reserved"]
        self.assertGreater(Decimal(reservations[1]["charge"]), Decimal(reservations[0]["charge"]))
        with self.assertRaisesRegex(ValueError, "continuation"):
            budget.complete(**dict(self.arguments, previous_response_id="unknown"))


if __name__ == "__main__":
    unittest.main()
