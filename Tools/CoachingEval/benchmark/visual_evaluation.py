"""Opt-in, bounded visual-coaching evaluation; export and prompt inspection are free."""
import argparse
import hashlib
import json
import os
from datetime import datetime, timezone
from pathlib import Path

from Tools.CoachingEval.benchmark.budget import BudgetedClient
from Tools.CoachingEval.benchmark.configuration import load_candidate, load_judge, load_prices
from Tools.CoachingEval.benchmark.corpus import load_corpus
from Tools.CoachingEval.benchmark.grader import grade_run
from Tools.CoachingEval.benchmark.qualification import JudgeQualification
from Tools.CoachingEval.benchmark.report import write_report
from Tools.CoachingEval.benchmark.regression import RegressionEvaluation
from Tools.CoachingEval.benchmark.runner import run_candidates, preview_prompts
from Tools.CoachingEval.benchmark.sensitivity import JudgeSensitivity
from Tools.CoachingEval.benchmark.visual_metrics import VisualMetrics
from Tools.CoachingEval.openai_responses import OpenAIResponsesClient


def run(corpus_path, output, *, client=None, max_cost=None, qualification_root=None, budget_journal=None, resume=False):
    root = Path(__file__).resolve().parents[3]
    config = root / "Tools/CoachingEval/benchmark"
    corpus = load_corpus(corpus_path)
    if json.loads(corpus.manifest_path.read_text())["schemaVersion"] != "coaching-quality-visual-regression-manifest.v1":
        raise ValueError("Expected the native visual corpus")
    output = Path(output)
    if output.exists() and not resume:
        raise FileExistsError("Refusing to replay a saved run; retain its budget and grading checkpoints")
    candidate = load_candidate(config / "configs/astra-visual-v3-low.json", root)
    prices = load_prices(config / "pricing-v2.json")
    # Validate a paid cap before creating anything or transmitting a request.
    if client is not None and max_cost is None:
        raise ValueError("Paid visual evaluation requires an explicit --max-cost")
    meter = BudgetedClient(client, prices, budget_journal or output / "budget.jsonl", max_cost) if client else None
    prompts = preview_prompts(corpus, candidate, prices)
    if resume:
        old = json.loads((output / "evaluation.json").read_text())
        expected = dict(corpusSHA256=corpus.sha256, candidateSHA256=candidate.sha256,
                        systemPromptSHA256=candidate.model_configuration.system_prompt_sha256)
        if (client is None or any(old.get(k) != v for k, v in expected.items())
                or Path(old["budgetJournal"]).resolve() != meter.journal.resolve()
                or json.loads((output / "prompts.json").read_text()) != prompts):
            raise ValueError("Resume binding changed; keep the original corpus, prompts and budget journal")
        if old["status"] in ("completed", "visualAcceptanceFailed", "integrityFailure"):
            return old
    else:
        output.mkdir(parents=True)
        (output / "prompts.json").write_text(json.dumps(prompts, ensure_ascii=False, indent=2) + "\n")
    if client is None:
        return {"status": "exportedOnly", "paidCalls": 0, "turns": len(prompts)}
    judge = load_judge(config / "configs/judge-v4.json", root)
    result = {"status": "running", "corpusSHA256": corpus.sha256, "candidateSHA256": candidate.sha256,
              "maxConservativeCostUSD": str(meter.limit), "sourceGitSHA": corpus.source_git_sha,
              "executionSource": RegressionEvaluation._execution_source(),
              "systemPromptSHA256": candidate.model_configuration.system_prompt_sha256,
              "budgetJournal": str(meter.journal)}
    if resume:
        result["priorExecutionSources"] = old.get("priorExecutionSources", []) + [old["executionSource"]]
    try:
        qualification = JudgeQualification.ensure(judge, meter, prices, qualification_root, datetime.now(timezone.utc))
        controls = config / "judge-visual-v1.json"
        if resume and (output / "sensitivity/result.json").is_file():
            gate = json.loads((output / "sensitivity/result.json").read_text())
            for key, value in dict(corpusSHA256=corpus.sha256, judgeConfigurationSHA256=judge.sha256,
                                   judgePromptSHA256=judge.system_prompt_sha256,
                                   controlsSHA256=hashlib.sha256(controls.read_bytes()).hexdigest()).items():
                if gate.get(key) != value:
                    raise ValueError("Saved judge sensitivity binding changed")
        else:
            gate = JudgeSensitivity.run(controls, corpus, judge, meter, prices, output / "sensitivity")
        if not gate["passed"]:
            result["status"] = "judgeSensitivityFailed"
            return result
        if not (resume and (output / "candidates").is_dir()):
            run_candidates(corpus=corpus, configurations=[candidate], mode="regression", destination=output / "candidates",
                           provider_factory=lambda _: meter, price_table=prices, stop_on_provider_failure=True,
                           resume=resume and (output / "candidates.progress.jsonl").is_file())
        if not (resume and (output / "grades").is_dir()):
            grade_run(run_root=output / "candidates", corpus=corpus, judge_configuration=judge, client=meter,
                      destination=output / "grades", qualification_path=qualification, price_table=prices,
                      checkpoint_path=output / "grading-checkpoint.json")
        aggregate, _ = write_report(output / "candidates", output / "grades", prices, output / "report")
        records = [json.loads(line) for line in (output / "candidates/records.jsonl").read_text().splitlines()]
        result["missingRequestedMoveArrows"] = VisualMetrics.missing_move_arrows(records, {"v04-move-hint", "v05-draft-revision"})
        result["status"] = "completed" if not json.loads(aggregate.read_text())["integrityIssues"] else "integrityFailure"
        if result["status"] == "completed" and result["missingRequestedMoveArrows"]:
            result["status"] = "visualAcceptanceFailed"
        return result
    except BaseException:
        result["status"] = "stopped"
        raise
    finally:
        result["conservativeCostOrReservationUSD"] = str(meter.spent)
        result["unknownAccountingCalls"] = meter.unknown_calls
        (output / "evaluation.json").write_text(json.dumps(result, indent=2) + "\n")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--paid", action="store_true")
    parser.add_argument("--max-cost")
    parser.add_argument("--budget-journal", type=Path)
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--qualification-root", type=Path, default=Path(".coaching-eval/benchmark/qualifications"))
    args = parser.parse_args(argv)
    if args.paid and (not args.max_cost or not os.environ.get("OPENAI_API_KEY")):
        parser.error("--paid requires --max-cost and OPENAI_API_KEY")
    result = run(args.corpus, args.output,
                 client=OpenAIResponsesClient(api_key=os.environ["OPENAI_API_KEY"]) if args.paid else None,
                 max_cost=args.max_cost, qualification_root=args.qualification_root, budget_journal=args.budget_journal,
                 resume=args.resume)
    print(json.dumps(result))
    return 0 if result["status"] in ("completed", "exportedOnly") else 1


if __name__ == "__main__":
    raise SystemExit(main())
