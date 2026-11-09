"""Durable, conservative per-call spending guard for sequential evaluation work."""

import json
import os
import uuid
from decimal import Decimal
from pathlib import Path

from Tools.CoachingEval.benchmark.configuration import validate_candidate_usage


class BudgetExceeded(RuntimeError):
    """The next call was refused locally, before any provider transmission."""


class BudgetedClient:
    def __init__(self, client, prices, journal, limit):
        self.client = client
        self.prices = prices
        self.journal = Path(journal)
        self.limit = Decimal(limit)
        if not self.limit.is_finite() or self.limit <= 0:
            raise ValueError("Budget must be positive and finite")
        self._calls = {}
        self._contexts = {}
        if self.journal.exists():
            for line in self.journal.read_text().splitlines():
                row = json.loads(line)
                if row["pricingSHA256"] != prices.sha256:
                    raise ValueError("Budget pricing changed")
                self._remember(row)

    @property
    def spent(self):
        return sum((Decimal(row["charge"]) for row in self._calls.values()), Decimal(0))

    @property
    def unknown_calls(self):
        return sum(row["state"] != "completed" for row in self._calls.values())

    def complete(self, **arguments):
        prior = arguments.get("previous_response_id")
        if prior is not None and prior not in self._contexts:
            raise ValueError("Unknown continuation context cannot be budgeted safely")
        text_bytes = sum(len(arguments[key].encode()) for key in ("system_prompt", "user_prompt"))
        text_bytes += len(json.dumps(arguments["schema"]).encode()) + 2048
        reserve = self._cost(arguments["model"], text_bytes + self._contexts.get(prior, 0),
                             0, arguments["maximum_output_tokens"])
        if self.spent + reserve > self.limit:
            raise BudgetExceeded("Evaluation budget exhausted before the next API call")
        call = str(uuid.uuid4())
        row = dict(call=call, model=arguments["model"], state="reserved", charge=str(reserve),
                   pricingSHA256=self.prices.sha256)
        self._append(row)
        # A failure keeps its full reservation. Never serialize an exception that
        # could contain provider credentials or claim an unknown charge was zero.
        result = self.client.complete(**arguments)
        usage = result["usage"]
        normalized = dict(inputTokens=usage["input_tokens"], cachedInputTokens=usage["cached_input_tokens"],
                          outputTokens=usage["output_tokens"], reasoningTokens=usage["reasoning_tokens"],
                          totalTokens=usage["total_tokens"])
        validate_candidate_usage(normalized)
        actual = self._cost(arguments["model"], usage["input_tokens"], usage["cached_input_tokens"], usage["output_tokens"])
        self._append(dict(row, state="completed", charge=str(actual), response={
            "id": result.get("id"), "output_text": result.get("output_text"), "usage": usage,
        }))
        return result

    def _cost(self, model, inputs, cached, outputs):
        price = self.prices.models[model]
        # Frozen table estimate plus a conservative 25% premium on uncached input;
        # this is an estimate/reservation, not the provider's invoice.
        return ((inputs - cached) * price.uncached_input_per_million * Decimal("1.25")
                + cached * price.cached_input_per_million + outputs * price.output_per_million) / 1_000_000

    def _append(self, row):
        self.journal.parent.mkdir(parents=True, exist_ok=True)
        with self.journal.open("a", encoding="utf-8") as file:
            file.write(json.dumps(row, sort_keys=True) + "\n")
            file.flush()
            os.fsync(file.fileno())
        self._remember(row)

    def _remember(self, row):
        self._calls[row["call"]] = row
        response = row.get("response", {})
        if response.get("id"):
            usage = response["usage"]
            self._contexts[response["id"]] = usage["input_tokens"] + usage["output_tokens"]
