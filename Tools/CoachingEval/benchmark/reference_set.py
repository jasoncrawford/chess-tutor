"""Immutable, reviewable reference cases for qualifying the benchmark judge."""

import hashlib
import json
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from types import MappingProxyType
from typing import Any, Mapping, Optional

from Tools.CoachingEval.chess_native_response import ChessNativeResponseContract
from Tools.CoachingEval.benchmark.judge_contract import RUBRIC_DIMENSIONS, RUBRIC_FLAGS


_TOP_LEVEL_KEYS = frozenset(("schemaVersion", "id", "provenance", "cases"))
_PROVENANCE_KEYS = frozenset(
    ("authoredBy", "authoredAt", "reviewStatus", "reviewedBy", "reviewedAt")
)
_CASE_KEYS = frozenset(
    (
        "id",
        "graderBrief",
        "availableUI",
        "candidateTurn",
        "referenceScores",
        "referenceFlags",
        "rationale",
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
_UI_KEYS = frozenset(("actions", "expectedResponses", "allowableMoveFocus"))
_TURN_REQUIRED_KEYS = frozenset(("message", "actions", "focus"))
_TURN_OPTIONAL_KEYS = frozenset(("expects",))
_DIMENSION_LABELS = {
    "chessCorrectness": "Chess correctness",
    "coachingJudgment": "Coaching judgment",
    "latestActionResponsiveness": "Latest-action responsiveness",
    "discoveryAndIndependence": "Discovery and independence",
    "coherenceAndAnswerability": "Coherence and answerability",
    "childClarity": "Child clarity",
}


@dataclass(frozen=True)
class JudgeReferenceSet:
    identifier: str
    authored_by: str
    authored_at: str
    review_status: str
    reviewed_by: Optional[str]
    reviewed_at: Optional[str]
    cases: tuple[Mapping[str, Any], ...]
    sha256: str

    @classmethod
    def load(
        cls,
        path: Path,
        expected_sha256: str,
        *,
        require_reviewed: bool = True,
    ) -> "JudgeReferenceSet":
        path = Path(path)
        try:
            data = path.read_bytes()
            value = json.loads(data.decode("utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as error:
            raise ValueError("Cannot load judge reference set") from error
        actual_sha256 = hashlib.sha256(data).hexdigest()
        if actual_sha256 != expected_sha256:
            raise ValueError("Judge reference-set hash does not match")
        if not isinstance(value, dict) or set(value) != _TOP_LEVEL_KEYS:
            raise ValueError("Judge reference-set fields do not match")
        if value["schemaVersion"] != "coaching-quality-judge-reference-set.v2":
            raise ValueError("Unsupported judge reference-set schema")
        identifier = cls._text(value["id"], "reference-set id")
        provenance = value["provenance"]
        if not isinstance(provenance, dict) or set(provenance) != _PROVENANCE_KEYS:
            raise ValueError("Judge reference-set provenance is invalid")
        authored_by = cls._text(provenance["authoredBy"], "reference-set author")
        authored_at = cls._date(provenance["authoredAt"], "reference-set authored date")
        review_status = provenance["reviewStatus"]
        reviewed_by = provenance["reviewedBy"]
        reviewed_at = provenance["reviewedAt"]
        if review_status == "pending":
            if reviewed_by is not None or reviewed_at is not None:
                raise ValueError("Pending reference-set review cannot name a reviewer")
        elif review_status == "humanReviewed":
            reviewed_by = cls._text(reviewed_by, "reference-set reviewer")
            reviewed_at = cls._date(reviewed_at, "reference-set review date")
        else:
            raise ValueError("Judge reference-set review status is invalid")
        if require_reviewed and review_status != "humanReviewed":
            raise ValueError("Judge reference set has not been human-reviewed")

        raw_cases = value["cases"]
        if not isinstance(raw_cases, list) or len(raw_cases) != 20:
            raise ValueError("Judge reference set must contain exactly 20 cases")
        cases = []
        for index, case in enumerate(raw_cases, start=1):
            cls._validate_case(case, index)
            cases.append(cls._freeze(case))
        return cls(
            identifier=identifier,
            authored_by=authored_by,
            authored_at=authored_at,
            review_status=review_status,
            reviewed_by=reviewed_by,
            reviewed_at=reviewed_at,
            cases=tuple(cases),
            sha256=actual_sha256,
        )

    def render_review(self) -> str:
        if self.review_status == "humanReviewed":
            status = f"human-reviewed by {self.reviewed_by} on {self.reviewed_at}"
        else:
            status = "pending human review"
        lines = [
            "# Judge reference set v2",
            "",
            f"Status: **{status}**",
            "",
            f"Proposed by: {self.authored_by} on {self.authored_at}",
            "",
            "Review each context, candidate response, score, flag, and rationale. Approval of this sheet is required before these judgments become qualification ground truth.",
        ]
        for case in self.cases:
            brief = case["graderBrief"]
            turn = case["candidateTurn"]
            lines.extend(
                [
                    "",
                    f"## {case['id']}",
                    "",
                    f"**Facts:** {' '.join(brief['verifiedFacts'])}",
                    "",
                    f"**Purpose:** {brief['coachingPurpose']}",
                    "",
                    f"**Acceptable alternatives:** {' | '.join(brief['acceptableAlternatives']) or 'none'}",
                    "",
                    f"**Success criteria:** {' | '.join(brief['successCriteria'])}",
                    "",
                    f"**Severe-failure criteria:** {' | '.join(brief['severeFailureCriteria']) or 'none'}",
                    "",
                    f"**Candidate:** “{turn['message']}”",
                    "",
                    "**Available UI:** "
                    f"actions={json.dumps(list(case['availableUI']['actions']))}; "
                    f"expectedResponses={json.dumps(list(case['availableUI']['expectedResponses']))}; "
                    f"allowableMoveFocus={json.dumps([list(move) for move in case['availableUI']['allowableMoveFocus']])}.",
                    "",
                    "**Candidate controls:** "
                    f"actions={json.dumps(list(turn['actions']))}; "
                    f"focus={json.dumps(self._thaw(turn['focus']))}; "
                    f"expects={json.dumps(turn.get('expects'))}.",
                    "",
                    "**Scores:** "
                    + "; ".join(
                        f"{_DIMENSION_LABELS[dimension]}: {case['referenceScores'][dimension]}"
                        for dimension in RUBRIC_DIMENSIONS
                    )
                    + ".",
                    "",
                    "**Flags:** "
                    + "; ".join(
                        f"{flag}: {str(case['referenceFlags'][flag]).lower()}"
                        for flag in RUBRIC_FLAGS
                    )
                    + ".",
                    "",
                    f"**Rationale:** {' '.join(case['rationale'])}",
                ]
            )
        return "\n".join(lines) + "\n"

    @classmethod
    def _validate_case(cls, value, index):
        if not isinstance(value, dict) or set(value) != _CASE_KEYS:
            raise ValueError("Judge reference-set case fields do not match")
        if value["id"] != f"ref-{index:02}":
            raise ValueError("Judge reference-set case IDs or order do not match")
        brief = value["graderBrief"]
        if not isinstance(brief, dict) or set(brief) != _BRIEF_KEYS:
            raise ValueError("Judge reference-set grader brief is invalid")
        cls._text_list(brief["verifiedFacts"], "verified facts", minimum=1)
        cls._text(brief["coachingPurpose"], "coaching purpose")
        cls._text_list(brief["acceptableAlternatives"], "acceptable alternatives")
        cls._text_list(brief["successCriteria"], "success criteria", minimum=1)
        cls._text_list(brief["severeFailureCriteria"], "severe failure criteria")

        available_ui = value["availableUI"]
        if not isinstance(available_ui, dict) or set(available_ui) != _UI_KEYS:
            raise ValueError("Judge reference-set available UI is invalid")
        cls._text_list(available_ui["actions"], "available actions")
        cls._text_list(available_ui["expectedResponses"], "expected responses")
        moves = available_ui["allowableMoveFocus"]
        if not isinstance(moves, list) or any(
            not isinstance(move, list)
            or len(move) != 2
            or any(not isinstance(square, str) or not square for square in move)
            for move in moves
        ):
            raise ValueError("Judge reference-set allowable move focus is invalid")

        turn = value["candidateTurn"]
        if (
            not isinstance(turn, dict)
            or not _TURN_REQUIRED_KEYS.issubset(turn)
            or not set(turn).issubset(_TURN_REQUIRED_KEYS | _TURN_OPTIONAL_KEYS)
        ):
            raise ValueError("Judge reference-set candidate turn is invalid")
        cls._text(turn["message"], "candidate message")
        cls._text_list(turn["actions"], "candidate actions")
        if any(action not in available_ui["actions"] for action in turn["actions"]):
            raise ValueError("Judge reference-set candidate action is unavailable")
        if not isinstance(turn["focus"], list):
            raise ValueError("Judge reference-set candidate focus is invalid")
        if "expects" in turn:
            expects = cls._text(turn["expects"], "candidate expected response")
            if expects not in available_ui["expectedResponses"]:
                raise ValueError("Judge reference-set expected response is unavailable")
        contract = ChessNativeResponseContract(
            actions=tuple(available_ui["actions"]),
            allowable_moves=tuple(tuple(move) for move in moves),
            expected_responses=tuple(available_ui["expectedResponses"]),
        )
        if contract.validation_issues(cls._thaw(turn)):
            raise ValueError("Judge reference-set candidate turn fails the app contract")

        scores = value["referenceScores"]
        if not isinstance(scores, dict) or set(scores) != set(RUBRIC_DIMENSIONS):
            raise ValueError("Judge reference-set score fields do not match")
        if any(
            isinstance(score, bool) or not isinstance(score, int) or not 1 <= score <= 5
            for score in scores.values()
        ):
            raise ValueError("Judge reference-set scores must be integers from 1 to 5")
        flags = value["referenceFlags"]
        if not isinstance(flags, dict) or set(flags) != set(RUBRIC_FLAGS):
            raise ValueError("Judge reference-set flag fields do not match")
        if any(not isinstance(flag, bool) for flag in flags.values()):
            raise ValueError("Judge reference-set flags must be booleans")
        cls._text_list(value["rationale"], "reference rationale", minimum=1, maximum=3)

    @staticmethod
    def _text(value, label):
        if not isinstance(value, str) or not value or len(value) > 500:
            raise ValueError(f"Judge {label} is invalid")
        return value

    @classmethod
    def _text_list(cls, value, label, *, minimum=0, maximum=20):
        if not isinstance(value, list) or not minimum <= len(value) <= maximum:
            raise ValueError(f"Judge {label} are invalid")
        for item in value:
            cls._text(item, label)

    @classmethod
    def _date(cls, value, label):
        value = cls._text(value, label)
        try:
            date.fromisoformat(value)
        except ValueError as error:
            raise ValueError(f"Judge {label} is invalid") from error
        return value

    @classmethod
    def _freeze(cls, value):
        if isinstance(value, dict):
            return MappingProxyType(
                {key: cls._freeze(child) for key, child in value.items()}
            )
        if isinstance(value, list):
            return tuple(cls._freeze(child) for child in value)
        return value

    @classmethod
    def _thaw(cls, value):
        if isinstance(value, Mapping):
            return {key: cls._thaw(child) for key, child in value.items()}
        if isinstance(value, (list, tuple)):
            return [cls._thaw(child) for child in value]
        return value
