"""Bounded, repeatable coaching-experience experiments with a frozen grading gate."""

import argparse
import hashlib
import json
import math
import os
import re
import statistics
from datetime import datetime, timezone
from pathlib import Path

from Tools.CoachingEval.benchmark.budget import BudgetedClient, BudgetExceeded
from Tools.CoachingEval.benchmark.configuration import load_candidate, load_judge, load_prices
from Tools.CoachingEval.benchmark.corpus import load_corpus
from Tools.CoachingEval.benchmark.grader import grade_run
from Tools.CoachingEval.benchmark.qualification import JudgeQualification
from Tools.CoachingEval.benchmark.regression import RegressionEvaluation
from Tools.CoachingEval.benchmark.report import write_report
from Tools.CoachingEval.benchmark.runner import run_candidates
from Tools.CoachingEval.benchmark.sensitivity import JudgeSensitivity
from Tools.CoachingEval.openai_responses import OpenAIResponsesClient


class ExperienceEvaluation:
    @classmethod
    def run(cls, *, repository_root, corpus_path, candidate_paths, controls_path,
            output, client, qualification_path, journal, max_cost="10", sensitivity_path=None):
        root, output = Path(repository_root), Path(output)
        if output.exists():
            raise FileExistsError("Refusing to overwrite or replay an experience evaluation")
        config = root / "Tools/CoachingEval/benchmark"
        corpus = load_corpus(corpus_path)
        candidates = [load_candidate(path, root) for path in candidate_paths]
        if not candidates:
            raise ValueError("At least one candidate is required")
        judge = load_judge(config / "configs/judge-v4.json", root)
        prices = load_prices(config / "pricing-v2.json")
        JudgeQualification.load_compatible(qualification_path, judge, datetime.now(timezone.utc))
        bindings = dict(controlsSHA256=hashlib.sha256(Path(controls_path).read_bytes()).hexdigest(),
                        corpusSHA256=corpus.sha256, judgeConfigurationSHA256=judge.sha256,
                        judgePromptSHA256=judge.system_prompt_sha256)
        sensitivity = None
        if sensitivity_path:
            sensitivity = json.loads(Path(sensitivity_path).read_text())
            if (sensitivity.get("passed") is not True or sensitivity.get("repetitions") != 3
                    or any(sensitivity.get(k) != v for k, v in bindings.items())
                    or not sensitivity.get("rows") or not all(r.get("passed") is True for r in sensitivity["rows"])):
                raise ValueError("Sensitivity evidence is failed or incompatible")
        meter = BudgetedClient(client, prices, journal, max_cost)
        result = dict(schemaVersion="coaching-experience-evaluation.v1", status="running",
                      createdAt=datetime.now(timezone.utc).isoformat(),
                      executionSource=RegressionEvaluation._execution_source(),
                      sourceGitSHA=corpus.source_git_sha, bindings=bindings,
                      candidates={c.identifier: c.sha256 for c in candidates},
                      pricingSHA256=prices.sha256, qualification=str(qualification_path),
                      repetitions=3, includeHoldout=False, maxConservativeCostUSD=str(meter.limit),
                      budgetJournal=str(Path(journal).resolve()), startingCostUSD=str(meter.spent))
        output.mkdir(parents=True)
        try:
            RegressionEvaluation._save(output, result, meter)
            if sensitivity is None:
                sensitivity = JudgeSensitivity.run(controls_path, corpus, judge, meter, prices, output / "sensitivity")
                sensitivity_path = output / "sensitivity/result.json"
            result["sensitivity"] = str(sensitivity_path)
            if not sensitivity["passed"]:
                result["status"] = "judgeSensitivityFailed"
                return result
            run_candidates(corpus=corpus, configurations=candidates, mode="regression",
                           destination=output / "candidates", provider_factory=lambda _: meter,
                           price_table=prices, stop_on_provider_failure=True)
            grade_run(run_root=output / "candidates", corpus=corpus, judge_configuration=judge,
                      client=meter, destination=output / "grades", qualification_path=qualification_path,
                      price_table=prices, checkpoint_path=output / "grading-checkpoint.json")
            aggregate, summary = write_report(output / "candidates", output / "grades", prices, output / "report")
            report = json.loads(aggregate.read_text())
            records = [json.loads(line) for line in (output / "candidates/records.jsonl").read_text().splitlines()]
            result["experienceMetrics"] = cls.metrics(records, {
                c.identifier: c.model_configuration.conversation_reuse for c in candidates})
            result.update(report=str(summary), integrityIssues=report["integrityIssues"],
                          status="completed" if not report["integrityIssues"] else "integrityFailure")
            return result
        except BudgetExceeded:
            result["status"] = "budgetStopped"
            raise
        except BaseException as error:
            result.update(status="stopped", failureCategory=type(error).__name__)
            raise
        finally:
            progress = output / "candidates.progress.jsonl"
            if progress.exists():
                rows = [json.loads(line) for line in progress.read_text().splitlines()]
                result["experienceMetrics"] = cls.metrics(rows, {
                    c.identifier: c.model_configuration.conversation_reuse for c in candidates})
            RegressionEvaluation._save(output, result, meter)

    @staticmethod
    def metrics(records, conversation_reuse):
        """Latency thresholds are diagnostic UX targets, not chess grades.

        Include failed/invalid requests in timing. This counts conventional
        keep/play confirmation questions; it is a repetition indicator, not a
        semantic judge of whether a response was useful.
        """
        result = {}
        for identifier, reuse in conversation_reuse.items():
            rows = [r for r in records if r["configurationID"] == identifier]
            timings = {"fresh": [], "followUp": []}
            endings, confirmation_count = [], 0
            failed = 0
            blocked = 0
            for row in rows:
                if row.get("generationStatus") == "blockedByPriorTurn":
                    blocked += 1
                    continue
                bucket = "followUp" if reuse and row["stepIndex"] > 1 else "fresh"
                latency = row.get("latencyMilliseconds")
                if isinstance(latency, (int, float)) and math.isfinite(latency) and latency >= 0:
                    timings[bucket].append(latency)
                valid = row.get("mechanicalValidation", {}).get("valid") is True
                failed += not valid
                turn = row.get("parsedTurn") or {}
                if valid and turn.get("expects") == "chooseWhetherToPlay":
                    confirmation_count += 1
                    message = turn.get("message", "").strip().lower()
                    closing = re.split(r"[.!]", message)[-1].strip()
                    if closing.endswith("?") and re.search(r"\b(keep|play|try another)\b", closing):
                        endings.append(closing)
            stats = dict(failedOrInvalidCount=failed, blockedCount=blocked, confirmationTurnCount=confirmation_count,
                         confirmationQuestionCount=len(endings),
                         mostRepeatedConfirmationEndingCount=max((endings.count(s) for s in set(endings)), default=0))
            for bucket, values in timings.items():
                target = 3000 if bucket == "followUp" else 5000
                stats[bucket] = dict(count=len(values), targetMilliseconds=target,
                                    overTargetCount=sum(v > target for v in values),
                                    medianMilliseconds=statistics.median(values) if values else None,
                                    p90Milliseconds=sorted(values)[math.ceil(len(values) * .9) - 1] if values else None,
                                    maximumMilliseconds=max(values) if values else None)
            result[identifier] = stats
        return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("corpus", "controls", "output", "qualification", "journal"):
        parser.add_argument("--" + name, required=True, type=Path)
    parser.add_argument("--candidate", required=True, action="append", type=Path)
    parser.add_argument("--sensitivity", type=Path)
    parser.add_argument("--max-cost", default="10")
    args = parser.parse_args(argv)
    key = os.environ.get("OPENAI_API_KEY")
    if not key:
        parser.error("OPENAI_API_KEY is not configured")
    root = Path(__file__).resolve().parents[3]
    result = ExperienceEvaluation.run(repository_root=root, corpus_path=args.corpus,
        candidate_paths=args.candidate, controls_path=args.controls, output=args.output,
        qualification_path=args.qualification, journal=args.journal, max_cost=args.max_cost,
        sensitivity_path=args.sensitivity, client=OpenAIResponsesClient(api_key=key))
    print(json.dumps(result, sort_keys=True))
    return 0 if result["status"] == "completed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
