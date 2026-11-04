"""One bounded evaluation of the exact local coach against separate regression suites."""

import argparse
import hashlib
import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path

from Tools.CoachingEval.benchmark.budget import BudgetedClient, BudgetExceeded
from Tools.CoachingEval.benchmark.configuration import load_candidate, load_judge, load_prices
from Tools.CoachingEval.benchmark.corpus import load_corpus
from Tools.CoachingEval.benchmark.grader import grade_run
from Tools.CoachingEval.benchmark.experience_metrics import ExperienceMetrics
from Tools.CoachingEval.benchmark.qualification import JudgeQualification
from Tools.CoachingEval.benchmark.report import write_report
from Tools.CoachingEval.benchmark.runner import run_candidates
from Tools.CoachingEval.benchmark.sensitivity import JudgeSensitivity
from Tools.CoachingEval.openai_responses import OpenAIResponsesClient


class RegressionEvaluation:
    @classmethod
    def run(cls, *, repository_root, corpus_path, regression_path, output, client,
            qualification_root, max_cost="10", candidate_path=None, include_holdout=False,
            experience_path=None):
        root = Path(repository_root)
        output = Path(output).resolve()
        if output.exists():
            raise FileExistsError("Refusing to overwrite or replay an evaluation; use saved grading checkpoints")
        config_root = root / "Tools/CoachingEval/benchmark"
        candidate = load_candidate(Path(candidate_path) if candidate_path else config_root / "configs/astra-discovery-v2-low.json", root)
        judge = load_judge(config_root / "configs/judge-v4.json", root)
        prices = load_prices(config_root / "pricing-v2.json")
        corpus = load_corpus(corpus_path)
        regression = load_corpus(regression_path)
        experience = load_corpus(experience_path) if experience_path is not None else None
        if corpus.is_regression or not regression.is_regression:
            raise ValueError("Expected the frozen benchmark and a separate playthrough suite")
        if corpus.source_git_sha != regression.source_git_sha:
            raise ValueError("Both suites must be exported from the same source revision")
        if experience is not None and (not experience.is_regression or experience.source_git_sha != corpus.source_git_sha):
            raise ValueError("Experience suite must be a regression exported from the same source revision")
        controls = config_root / "judge-sensitivity-v1.json"
        meter = BudgetedClient(client, prices, output / "budget.jsonl", max_cost)
        result = dict(schemaVersion="coaching-regression-evaluation.v1", status="running",
                      createdAt=datetime.now(timezone.utc).isoformat(), sourceGitSHA=corpus.source_git_sha,
                      executionSource=cls._execution_source(),
                      candidateID=candidate.identifier, candidateSHA256=candidate.sha256,
                      modelConfigurationSHA256=candidate.model_configuration_sha256,
                      systemPromptSHA256=candidate.model_configuration.system_prompt_sha256,
                      judgeSHA256=judge.sha256, controlsSHA256=hashlib.sha256(controls.read_bytes()).hexdigest(),
                      pricingSHA256=prices.sha256, maxConservativeCostUSD=str(meter.limit),
                      repetitions=3, includeHoldout=include_holdout,
                      corpora={"benchmark": corpus.sha256, "playthrough": regression.sha256}, suites={})
        experience_controls = config_root / "judge-experience-v1.json"
        if experience is not None:
            result["corpora"]["experience"] = experience.sha256
            result["experienceControlsSHA256"] = hashlib.sha256(experience_controls.read_bytes()).hexdigest()
        output.mkdir(parents=True)
        cls._save(output, result, meter)
        try:
            qualification = JudgeQualification.ensure(judge, meter, prices, qualification_root, datetime.now(timezone.utc))
            result["qualification"] = str(qualification)
            sensitivity = JudgeSensitivity.run(controls, regression, judge, meter, prices, output / "sensitivity")
            result["sensitivityPassed"] = sensitivity["passed"]
            if not sensitivity["passed"]:
                result["status"] = "judgeSensitivityFailed"
                return result
            suites = [("playthrough", regression), ("benchmark", corpus)]
            if experience is not None:
                gate = JudgeSensitivity.run(experience_controls, experience, judge, meter, prices, output / "experience-sensitivity")
                result["experienceSensitivityPassed"] = gate["passed"]
                if not gate["passed"]:
                    result["status"] = "judgeSensitivityFailed"
                    return result
                suites.insert(0, ("experience", experience))
            for name, suite in suites:
                suite_root = output / name
                run_root = suite_root / "candidates"
                grades = suite_root / "grades"
                run_candidates(corpus=suite, configurations=[candidate], mode="regression",
                               destination=run_root, provider_factory=lambda _: meter,
                               include_holdout=include_holdout and not suite.is_regression, price_table=prices)
                grade_run(run_root=run_root, corpus=suite, judge_configuration=judge, client=meter,
                          destination=grades, qualification_path=qualification, price_table=prices,
                          checkpoint_path=suite_root / "grading-checkpoint.json")
                aggregate, summary = write_report(run_root, grades, prices, suite_root / "report")
                report = json.loads(aggregate.read_text())
                result["suites"][name] = dict(report=str(summary), aggregate=str(aggregate),
                                             integrityIssues=report["integrityIssues"])
                cls._save(output, result, meter)
            result["status"] = "completed" if all(not v["integrityIssues"] for v in result["suites"].values()) else "integrityFailure"
            return result
        except BudgetExceeded:
            result["status"] = "budgetStopped"
            raise
        except (KeyboardInterrupt, SystemExit):
            result["status"] = "interrupted"
            raise
        except Exception as error:
            result["status"] = "failed"
            result["failureCategory"] = type(error).__name__
            raise
        finally:
            for name in ("experience", "playthrough", "benchmark"):
                progress = output / name / "candidates.progress.jsonl"
                if progress.exists():
                    rows = [json.loads(line) for line in progress.read_text().splitlines()]
                    result.setdefault("experienceMetrics", {})[name] = ExperienceMetrics.summarize(
                        rows, {candidate.identifier: candidate.model_configuration.conversation_reuse})
            cls._save(output, result, meter)

    @staticmethod
    def _execution_source():
        # Saved board exports may be replayed by a newer prompt compiler. Bind
        # actual executing Python sources separately, never relabel the corpus.
        root = Path(__file__).resolve().parents[3]
        return dict(
            gitSHA=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
            dirty=bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=root, text=True).strip()),
            pythonFilesSHA256={str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
                              for directory in ("CoachingServer", "Tools/CoachingEval")
                              for path in sorted((root / directory).rglob("*.py"))},
        )

    @staticmethod
    def _save(output, result, meter):
        result["conservativeCostOrReservationUSD"] = str(meter.spent)
        result["unknownAccountingCalls"] = meter.unknown_calls
        temporary = output / ".evaluation.json.tmp"
        temporary.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
        temporary.replace(output / "evaluation.json")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", required=True, type=Path)
    parser.add_argument("--regressions", required=True, type=Path)
    parser.add_argument("--experience", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--qualification-root", required=True, type=Path)
    parser.add_argument("--candidate", type=Path)
    parser.add_argument("--max-cost", default="10")
    parser.add_argument("--include-holdout", action="store_true")
    args = parser.parse_args(argv)
    key = os.environ.get("OPENAI_API_KEY")
    if not key:
        parser.error("OPENAI_API_KEY is not configured")
    try:
        result = RegressionEvaluation.run(repository_root=Path(__file__).resolve().parents[3],
            corpus_path=args.corpus, regression_path=args.regressions, output=args.output,
            qualification_root=args.qualification_root, max_cost=args.max_cost, candidate_path=args.candidate,
            include_holdout=args.include_holdout, experience_path=args.experience,
            client=OpenAIResponsesClient(api_key=key))
    except (Exception, KeyboardInterrupt) as error:
        print(json.dumps(dict(status="stopped", category=type(error).__name__, evidence=str(args.output))))
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0 if result["status"] == "completed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
