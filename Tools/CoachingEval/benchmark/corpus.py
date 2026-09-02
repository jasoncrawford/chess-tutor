"""Strict loader for immutable coaching quality benchmark corpora."""

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Mapping, Optional, Tuple


_SPLITS = frozenset(("development", "holdout"))
_CATEGORIES = frozenset(
    ("quiet", "danger", "capture", "tentativeMove", "interaction", "specialRule")
)
_CASE_KEYS = frozenset(
    (
        "schemaVersion",
        "id",
        "groupID",
        "stepIndex",
        "split",
        "category",
        "request",
        "graderBrief",
        "sourceTraceID",
    )
)
_BRIEF_KEYS = frozenset(
    (
        "verifiedFacts",
        "coachingPurpose",
        "acceptableAlternatives",
        "successCriteria",
        "severeFailureCriteria",
    )
)
_MANIFEST_KEYS = frozenset(
    (
        "schemaVersion",
        "sourceGitSHA",
        "independentGroupCount",
        "sequenceGroupCount",
        "turnCount",
        "developmentTurnCount",
        "holdoutTurnCount",
        "turnIDs",
        "casesSHA256",
    )
)


@dataclass(frozen=True)
class BenchmarkGraderBrief:
    verified_facts: Tuple[str, ...]
    coaching_purpose: str
    acceptable_alternatives: Tuple[str, ...]
    success_criteria: Tuple[str, ...]
    severe_failure_criteria: Tuple[str, ...]


@dataclass(frozen=True)
class BenchmarkTurn:
    identifier: str
    group_id: str
    step_index: int
    split: str
    category: str
    request: Mapping[str, Any]
    grader_brief: BenchmarkGraderBrief
    source_trace_id: Optional[str]


@dataclass(frozen=True)
class BenchmarkCorpus:
    root: Path
    source_git_sha: str
    sha256: str
    turns: Tuple[BenchmarkTurn, ...]
    raw_cases: Tuple[Mapping[str, Any], ...]

    def select(self, *, include_holdout: bool = False) -> Tuple[BenchmarkTurn, ...]:
        if not isinstance(include_holdout, bool):
            raise ValueError("include_holdout must be a boolean")
        if include_holdout:
            return self.turns
        return tuple(turn for turn in self.turns if turn.split == "development")

    def by_id(self) -> Dict[str, BenchmarkTurn]:
        return {turn.identifier: turn for turn in self.turns}


def load_corpus(root: Path) -> BenchmarkCorpus:
    root = Path(root).resolve()
    cases_path = root / "cases.jsonl"
    manifest_path = root / "benchmark-manifest.json"
    cases_bytes = cases_path.read_bytes()
    manifest = _load_object(manifest_path)
    _require_exact_keys(manifest, _MANIFEST_KEYS, "Benchmark manifest")
    if manifest["schemaVersion"] != "coaching-quality-benchmark-manifest.v1":
        raise ValueError("Unsupported benchmark manifest schema")
    cases_sha = hashlib.sha256(cases_bytes).hexdigest()
    if manifest["casesSHA256"] != cases_sha:
        raise ValueError("Benchmark cases hash does not match manifest")

    raw_cases = tuple(_load_jsonl(cases_bytes))
    turns = tuple(_parse_turn(value) for value in raw_cases)
    _validate_inventory(turns, manifest)
    return BenchmarkCorpus(
        root=root,
        source_git_sha=_nonempty_string(manifest["sourceGitSHA"], "sourceGitSHA"),
        sha256=cases_sha,
        turns=turns,
        raw_cases=raw_cases,
    )


def _parse_turn(value: Mapping[str, Any]) -> BenchmarkTurn:
    if not isinstance(value, dict):
        raise ValueError("Each benchmark case must be an object")
    case_keys = set(value)
    required_case_keys = set(_CASE_KEYS) - {"sourceTraceID"}
    if case_keys not in (required_case_keys, set(_CASE_KEYS)):
        raise ValueError("Benchmark case fields do not match the contract")
    if value["schemaVersion"] != "coaching-quality-benchmark-case.v1":
        raise ValueError("Unsupported benchmark case schema")
    split = _nonempty_string(value["split"], "split")
    category = _nonempty_string(value["category"], "category")
    if split not in _SPLITS:
        raise ValueError("Unknown benchmark split")
    if category not in _CATEGORIES:
        raise ValueError("Unknown benchmark category")
    step_index = _positive_integer(value["stepIndex"], "stepIndex")
    request = value["request"]
    if not isinstance(request, dict) or not request:
        raise ValueError("Benchmark request must be a nonempty object")
    brief = _parse_brief(value["graderBrief"])
    trace_id = value.get("sourceTraceID")
    if trace_id is not None:
        trace_id = _nonempty_string(trace_id, "sourceTraceID")
    return BenchmarkTurn(
        identifier=_nonempty_string(value["id"], "id"),
        group_id=_nonempty_string(value["groupID"], "groupID"),
        step_index=step_index,
        split=split,
        category=category,
        request=request,
        grader_brief=brief,
        source_trace_id=trace_id,
    )


def _parse_brief(value: Any) -> BenchmarkGraderBrief:
    if not isinstance(value, dict):
        raise ValueError("Benchmark grader brief must be an object")
    _require_exact_keys(value, _BRIEF_KEYS, "Benchmark grader brief")
    return BenchmarkGraderBrief(
        verified_facts=_string_tuple(value["verifiedFacts"], "verifiedFacts", nonempty=True),
        coaching_purpose=_nonempty_string(value["coachingPurpose"], "coachingPurpose"),
        acceptable_alternatives=_string_tuple(
            value["acceptableAlternatives"], "acceptableAlternatives", nonempty=True
        ),
        success_criteria=_string_tuple(value["successCriteria"], "successCriteria", nonempty=True),
        severe_failure_criteria=_string_tuple(
            value["severeFailureCriteria"], "severeFailureCriteria", nonempty=True
        ),
    )


def _validate_inventory(turns: Tuple[BenchmarkTurn, ...], manifest: Mapping[str, Any]) -> None:
    identifiers = tuple(turn.identifier for turn in turns)
    if len(set(identifiers)) != len(identifiers):
        raise ValueError("Benchmark case IDs must be unique")
    if manifest["turnIDs"] != list(identifiers):
        raise ValueError("Benchmark turn order does not match manifest")
    groups: Dict[str, list] = {}
    for turn in turns:
        groups.setdefault(turn.group_id, []).append(turn)
    independent = [group for group in groups.values() if len(group) == 1]
    sequences = [group for group in groups.values() if len(group) == 3]
    if len(independent) != 40 or len(sequences) != 10 or len(groups) != 50:
        raise ValueError("Benchmark must contain exactly 40 independent and 10 sequence groups")
    for group in independent:
        if group[0].step_index != 1:
            raise ValueError("Independent benchmark turns must use step 1")
    for group in sequences:
        if [turn.step_index for turn in group] != [1, 2, 3]:
            raise ValueError("Benchmark sequence steps must be ordered 1, 2, 3")
        if len({turn.split for turn in group}) != 1:
            raise ValueError("Benchmark sequence split must be stable")
    development_count = sum(turn.split == "development" for turn in turns)
    holdout_count = sum(turn.split == "holdout" for turn in turns)
    expected = {
        "independentGroupCount": 40,
        "sequenceGroupCount": 10,
        "turnCount": 70,
        "developmentTurnCount": 56,
        "holdoutTurnCount": 14,
    }
    actual = dict(expected)
    actual["independentGroupCount"] = len(independent)
    actual["sequenceGroupCount"] = len(sequences)
    actual["turnCount"] = len(turns)
    actual["developmentTurnCount"] = development_count
    actual["holdoutTurnCount"] = holdout_count
    for key, expected_value in expected.items():
        if manifest[key] != expected_value or actual[key] != expected_value:
            raise ValueError(f"Benchmark {key} is invalid")


def _load_object(path: Path) -> Mapping[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ValueError(f"Cannot load benchmark JSON: {path.name}") from error
    if not isinstance(value, dict):
        raise ValueError(f"Benchmark JSON must be an object: {path.name}")
    return value


def _load_jsonl(data: bytes):
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ValueError("Benchmark cases must be UTF-8") from error
    for line_number, line in enumerate(text.splitlines(), start=1):
        if not line:
            raise ValueError(f"Benchmark cases contain a blank line at {line_number}")
        try:
            yield json.loads(line)
        except json.JSONDecodeError as error:
            raise ValueError(f"Invalid benchmark case JSON at line {line_number}") from error


def _require_exact_keys(value: Mapping[str, Any], expected, label: str) -> None:
    if set(value) != set(expected):
        raise ValueError(f"{label} fields do not match the contract")


def _nonempty_string(value: Any, name: str) -> str:
    if not isinstance(value, str) or not value:
        raise ValueError(f"{name} must be a nonempty string")
    return value


def _positive_integer(value: Any, name: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ValueError(f"{name} must be a positive integer")
    return value


def _string_tuple(value: Any, name: str, *, nonempty: bool) -> Tuple[str, ...]:
    if not isinstance(value, list) or (nonempty and not value):
        raise ValueError(f"{name} must be a nonempty array")
    result = tuple(_nonempty_string(item, name) for item in value)
    return result
