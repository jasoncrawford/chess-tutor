"""Safe command-line entry points for coaching quality benchmarks."""

import argparse
import json
import os
import re
import sys
from dataclasses import replace
from pathlib import Path

from Tools.CoachingEval.benchmark.configuration import (
    load_candidate,
    load_judge,
    load_prices,
)
from Tools.CoachingEval.benchmark.corpus import load_corpus
from Tools.CoachingEval.benchmark.grader import grade_run
from Tools.CoachingEval.benchmark.report import write_report
from Tools.CoachingEval.benchmark.runner import run_candidates
from Tools.CoachingEval.openai_responses import OpenAIResponsesClient, OpenAIResponsesError


_ENVIRONMENT_NAME = re.compile(r"[A-Z_][A-Z0-9_]*\Z")


class _SafeCLIError(ValueError):
    def __init__(self, category, message):
        super().__init__(message)
        self.category = category


def main(argv=None):
    parser = _parser()
    arguments = parser.parse_args(argv)
    try:
        if arguments.command == "run":
            summary = _run(arguments)
        elif arguments.command == "grade":
            summary = _grade(arguments)
        else:
            summary = _report(arguments)
    except _SafeCLIError as error:
        _print_json(
            {"status": "failed", "category": error.category, "message": str(error)},
            sys.stderr,
        )
        return 1
    except OpenAIResponsesError as error:
        _print_json(
            {
                "status": "failed",
                "category": error.category,
                "message": "The hosted model request failed.",
            },
            sys.stderr,
        )
        return 1
    except (OSError, ValueError) as error:
        message = str(error)
        if len(message) > 500:
            message = "The benchmark command failed validation."
        _print_json(
            {"status": "failed", "category": "validation", "message": message},
            sys.stderr,
        )
        return 1
    _print_json(summary, sys.stdout)
    return 0


def _run(arguments):
    api_key = _credential(arguments.api_key_env)
    repository_root = _repository_root()
    corpus = load_corpus(Path(arguments.corpus))
    if arguments.case_ids:
        corpus = _select_cases(corpus, arguments.case_ids, arguments.include_holdout)
    configurations = tuple(
        load_candidate(Path(path), repository_root) for path in arguments.candidates
    )
    prices = load_prices(Path(arguments.pricing))

    def provider_factory(_configuration):
        return OpenAIResponsesClient(api_key=api_key)

    manifest = run_candidates(
        corpus=corpus,
        configurations=configurations,
        mode=arguments.mode,
        destination=Path(arguments.output),
        provider_factory=provider_factory,
        include_holdout=arguments.include_holdout,
        price_table=prices,
        diagnostic_subset=bool(arguments.case_ids),
    )
    return {
        "status": "completed",
        "command": "run",
        "output": str(Path(arguments.output)),
        "mode": arguments.mode,
        "configurationIDs": [value.identifier for value in configurations],
        "recordCount": manifest["summary"]["recordCount"],
        "validCount": manifest["summary"]["validCount"],
        "failedCount": manifest["summary"]["failedCount"],
        "diagnosticSubset": bool(arguments.case_ids),
    }


def _grade(arguments):
    api_key = _credential(arguments.api_key_env)
    repository_root = _repository_root()
    corpus = load_corpus(Path(arguments.corpus))
    judge = load_judge(Path(arguments.judge), repository_root)
    prices = load_prices(Path(arguments.pricing))
    client = OpenAIResponsesClient(api_key=api_key)
    destination = grade_run(
        run_root=Path(arguments.run),
        corpus=corpus,
        judge_configuration=judge,
        client=client,
        destination=Path(arguments.output),
        price_table=prices,
    )
    return {
        "status": "completed",
        "command": "grade",
        "output": str(destination),
        "judgeID": judge.identifier,
    }


def _report(arguments):
    prices = load_prices(Path(arguments.pricing))
    aggregate, summary = write_report(
        Path(arguments.run),
        Path(arguments.grades),
        prices,
        Path(arguments.output),
    )
    return {
        "status": "completed",
        "command": "report",
        "output": str(Path(arguments.output)),
        "aggregate": str(aggregate),
        "summary": str(summary),
    }


def _credential(name):
    if not isinstance(name, str) or not _ENVIRONMENT_NAME.fullmatch(name):
        raise _SafeCLIError("invalidCredentialName", "API-key environment variable name is invalid.")
    value = os.environ.get(name)
    if not value:
        raise _SafeCLIError(
            "missingCredential",
            f"API key environment variable {name} is not configured.",
        )
    return value


def _select_cases(corpus, identifiers, include_holdout):
    allowed = corpus.select(include_holdout=include_holdout)
    requested = tuple(identifiers)
    if len(set(requested)) != len(requested):
        raise ValueError("Diagnostic benchmark case IDs must be unique")
    by_id = {turn.identifier: turn for turn in allowed}
    missing = [identifier for identifier in requested if identifier not in by_id]
    if missing:
        raise ValueError("Diagnostic benchmark contains an unavailable case ID")
    requested_set = set(requested)
    selected = tuple(turn for turn in allowed if turn.identifier in requested_set)
    raw_by_id = {
        value.get("id"): value
        for value in corpus.raw_cases
        if isinstance(value, dict) and isinstance(value.get("id"), str)
    }
    raw = tuple(raw_by_id[turn.identifier] for turn in selected if turn.identifier in raw_by_id)
    return replace(corpus, turns=selected, raw_cases=raw)


def _parser():
    parser = argparse.ArgumentParser(prog="coaching-quality-benchmark")
    commands = parser.add_subparsers(dest="command", required=True)

    run = commands.add_parser("run")
    run.add_argument("--corpus", required=True)
    run.add_argument("--mode", choices=("quick", "comparison"), required=True)
    run.add_argument("--candidate", dest="candidates", action="append", required=True)
    run.add_argument("--pricing", required=True)
    run.add_argument("--output", required=True)
    run.add_argument("--api-key-env", default="OPENAI_API_KEY")
    run.add_argument("--include-holdout", action="store_true")
    run.add_argument("--case", dest="case_ids", action="append", default=[])

    grade = commands.add_parser("grade")
    grade.add_argument("--run", required=True)
    grade.add_argument("--corpus", required=True)
    grade.add_argument("--judge", required=True)
    grade.add_argument("--pricing", required=True)
    grade.add_argument("--output", required=True)
    grade.add_argument("--api-key-env", default="OPENAI_API_KEY")

    report = commands.add_parser("report")
    report.add_argument("--run", required=True)
    report.add_argument("--grades", required=True)
    report.add_argument("--pricing", required=True)
    report.add_argument("--output", required=True)
    return parser


def _repository_root():
    return Path(__file__).resolve().parents[3]


def _print_json(value, stream):
    stream.write(json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n")


if __name__ == "__main__":
    raise SystemExit(main())
