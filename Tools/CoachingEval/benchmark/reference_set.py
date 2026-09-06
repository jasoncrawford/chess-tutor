"""Immutable, replayable reference cases for qualifying the benchmark judge."""

import hashlib
import json
import re
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from types import MappingProxyType
from typing import Any, Mapping, Optional

from CoachingServer.chess_native_compiler import (
    compile_context,
    compile_follow_up_context,
    parse_neutral_request,
)
from Tools.CoachingEval.benchmark.judge_contract import RUBRIC_DIMENSIONS, RUBRIC_FLAGS
from Tools.CoachingEval.chess_native_response import ChessNativeResponseContract


_TOP_LEVEL_KEYS = frozenset(
    (
        "schemaVersion",
        "id",
        "responseContract",
        "provenance",
        "sources",
        "absoluteCases",
        "pairwiseCases",
    )
)
_PROVENANCE_KEYS = frozenset(
    (
        "authoredBy",
        "authoredAt",
        "reviewStatus",
        "reviewedBy",
        "reviewedAt",
        "sourceGitSHA",
        "sourceCasesSHA256",
        "sourceManifestSHA256",
    )
)
_SOURCE_REQUIRED_KEYS = frozenset(
    (
        "schemaVersion",
        "id",
        "groupID",
        "stepIndex",
        "split",
        "category",
        "requestKind",
        "requestSHA256",
        "request",
        "graderBrief",
    )
)
_SOURCE_OPTIONAL_KEYS = frozenset(("sourceTraceID",))
_ABSOLUTE_CASE_KEYS = frozenset(
    (
        "id",
        "sourceID",
        "candidateTurn",
        "referenceScores",
        "referenceFlags",
        "rationale",
    )
)
_PAIRWISE_CASE_KEYS = frozenset(
    (
        "id",
        "sourceID",
        "responseOne",
        "responseTwo",
        "referencePreference",
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
_TURN_KEYS = frozenset(("message", "actions", "focus", "expects"))
_SPLITS = frozenset(("development", "holdout"))
_CATEGORIES = frozenset(
    ("quiet", "danger", "capture", "tentativeMove", "interaction", "specialRule")
)
_REQUEST_KINDS = frozenset(("initial", "followUp"))
_REFERENCE_PREFERENCES = frozenset(("responseOne", "responseTwo", "tie"))
_REVIEWED_STATUSES = frozenset(("humanReviewed", "agentReviewed"))
_ACTION_REFERENCES = frozenset(
    f"action:{action}"
    for action in (
        "hint",
        "noPieceNeedsHelp",
        "noSafeCapture",
        "looksSafe",
        "playMove",
        "tryAnotherMove",
        "closeHelp",
    )
)
_NO_REFERENCE_EVENTS = frozenset(("helpOpened", "helpReopened", "helpClosed"))
_PIECE_REFERENCE_EVENTS = frozenset(("pieceSelected", "squareInspected"))
_MOVE_REFERENCE_EVENTS = frozenset(("moveStaged", "moveReplaced", "moveRemoved"))
_MAXIMUM_JUDGE_CONTEXT_BYTES = 16_384
_SHA256 = re.compile(r"[0-9a-f]{64}\Z")
_GIT_SHA = re.compile(r"(?:[0-9a-f]{40}|[0-9a-f]{64})\Z")
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
    response_contract: str
    authored_by: str
    authored_at: str
    review_status: str
    reviewed_by: Optional[str]
    reviewed_at: Optional[str]
    source_git_sha: str
    source_cases_sha256: str
    source_manifest_sha256: str
    sources: tuple[Mapping[str, Any], ...]
    absolute_cases: tuple[Mapping[str, Any], ...]
    pairwise_cases: tuple[Mapping[str, Any], ...]
    sha256: str

    @property
    def cases(self) -> tuple[Mapping[str, Any], ...]:
        """Compatibility name for the absolute qualification inventory."""
        return self.absolute_cases

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
        if value["responseContract"] != "chess-native-v13":
            raise ValueError("Unsupported judge reference-set response contract")

        provenance = cls._validate_provenance(value["provenance"], require_reviewed)
        sources, compiled = cls._load_sources(value["sources"])
        absolute_cases = cls._load_absolute_cases(value["absoluteCases"], compiled)
        if tuple(case["sourceID"] for case in absolute_cases) != tuple(
            source["id"] for source in sources
        ):
            raise ValueError("Judge reference-set absolute source inventory does not match")
        pairwise_cases = cls._load_pairwise_cases(value["pairwiseCases"], compiled)

        return cls(
            identifier=cls._text(value["id"], "reference-set id"),
            response_contract=value["responseContract"],
            authored_by=provenance["authoredBy"],
            authored_at=provenance["authoredAt"],
            review_status=provenance["reviewStatus"],
            reviewed_by=provenance["reviewedBy"],
            reviewed_at=provenance["reviewedAt"],
            source_git_sha=provenance["sourceGitSHA"],
            source_cases_sha256=provenance["sourceCasesSHA256"],
            source_manifest_sha256=provenance["sourceManifestSHA256"],
            sources=tuple(cls._freeze(source) for source in sources),
            absolute_cases=tuple(cls._freeze(case) for case in absolute_cases),
            pairwise_cases=tuple(cls._freeze(case) for case in pairwise_cases),
            sha256=actual_sha256,
        )

    def render_review(self) -> str:
        if self.review_status == "humanReviewed":
            status = f"human-reviewed by {self.reviewed_by} on {self.reviewed_at}"
            review_note = (
                "Human approval of this sheet makes these judgments qualification "
                "ground truth."
            )
        elif self.review_status == "agentReviewed":
            status = f"agent-reviewed by {self.reviewed_by} on {self.reviewed_at}"
            review_note = (
                "These are provisional reference judgments delegated to an agent; "
                "this provenance does not claim human review."
            )
        else:
            status = "pending human review"
            review_note = (
                "Review every replayed context, candidate response, score, flag, "
                "preference, and rationale before these judgments become qualification "
                "ground truth."
            )
        sources = {source["id"]: source for source in self.sources}
        lines = [
            "# Judge reference set v2",
            "",
            f"Status: **{status}**",
            "",
            f"Proposed by: {self.authored_by} on {self.authored_at}",
            "",
            f"Response contract: `{self.response_contract}`",
            "",
            f"Source Git SHA: `{self.source_git_sha}`",
            "",
            f"Source corpus cases SHA-256: `{self.source_cases_sha256}`",
            "",
            f"Source corpus manifest SHA-256: `{self.source_manifest_sha256}`",
            "",
            review_note,
            "",
            "The raw source requests remain in the JSON reference set. This sheet renders the bounded facts needed for review.",
        ]
        for case in self.absolute_cases:
            source = sources[case["sourceID"]]
            lines.extend(self._review_context("Absolute", case["id"], source, case))
            turn = case["candidateTurn"]
            lines.extend(
                [
                    "",
                    f"**Candidate:** “{turn['message']}”",
                    "",
                    f"**Candidate controls:** {self._controls(turn)}",
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
        for case in self.pairwise_cases:
            source = sources[case["sourceID"]]
            lines.extend(self._review_context("Pairwise", case["id"], source, case))
            for label, key in (("Response one", "responseOne"), ("Response two", "responseTwo")):
                turn = case[key]
                lines.extend(
                    [
                        "",
                        f"**{label}:** “{turn['message']}”",
                        "",
                        f"**{label} controls:** {self._controls(turn)}",
                    ]
                )
            lines.extend(
                [
                    "",
                    f"**Reference preference:** {case['referencePreference']}",
                    "",
                    f"**Rationale:** {' '.join(case['rationale'])}",
                ]
            )
        return "\n".join(lines) + "\n"

    def _review_context(self, kind, identifier, source, case):
        request = source["request"]
        interaction = request["interaction"]
        latest = interaction["latestEvent"]
        history = " ".join(move["displayNotation"] for move in request["gameHistory"])
        staged = interaction.get("tentativeMove")
        brief = case["graderBrief"]
        return [
            "",
            f"## {kind} {identifier}",
            "",
            "**Source:** "
            f"`{source['id']}`; group=`{source['groupID']}`; step={source['stepIndex']}; "
            f"split={source['split']}; category={source['category']}; requestKind={source['requestKind']}.",
            "",
            f"**Request SHA-256:** `{source['requestSHA256']}`",
            "",
            f"**FEN:** `{request['position']['fen']}`",
            "",
            f"**Move history:** {history or 'none'}",
            "",
            "**Latest interaction:** "
            f"{latest['kind']}; references={json.dumps(list(latest['referencedIDs']))}.",
            "",
            "**Staged move:** "
            + (
                f"{staged['canonicalMove']} ({staged['san']}; special={staged['special']}; legal={str(staged['isLegal']).lower()})"
                if staged
                else "none"
            ),
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
            "**Available UI:** "
            f"actions={json.dumps(list(case['availableUI']['actions']))}; "
            f"expectedResponses={json.dumps(list(case['availableUI']['expectedResponses']))}; "
            f"allowableMoveFocus={json.dumps([list(move) for move in case['availableUI']['allowableMoveFocus']])}.",
            "",
            "**Bounded judge context:** "
            + json.dumps(self._thaw(case["judgeContext"]), sort_keys=True),
        ]

    @classmethod
    def _validate_provenance(cls, value, require_reviewed):
        if not isinstance(value, dict) or set(value) != _PROVENANCE_KEYS:
            raise ValueError("Judge reference-set provenance is invalid")
        provenance = dict(value)
        provenance["authoredBy"] = cls._text(value["authoredBy"], "reference-set author")
        provenance["authoredAt"] = cls._date(
            value["authoredAt"], "reference-set authored date"
        )
        source_git_sha = cls._text(value["sourceGitSHA"], "source Git SHA")
        if _GIT_SHA.fullmatch(source_git_sha) is None:
            raise ValueError("Judge source Git SHA is invalid")
        provenance["sourceGitSHA"] = source_git_sha
        provenance["sourceCasesSHA256"] = cls._hash(
            value["sourceCasesSHA256"], "source cases hash"
        )
        provenance["sourceManifestSHA256"] = cls._hash(
            value["sourceManifestSHA256"], "source manifest hash"
        )
        status = value["reviewStatus"]
        if status == "pending":
            if value["reviewedBy"] is not None or value["reviewedAt"] is not None:
                raise ValueError("Pending reference-set review cannot name a reviewer")
        elif status in _REVIEWED_STATUSES:
            provenance["reviewedBy"] = cls._text(
                value["reviewedBy"], "reference-set reviewer"
            )
            provenance["reviewedAt"] = cls._date(
                value["reviewedAt"], "reference-set review date"
            )
        else:
            raise ValueError("Judge reference-set review status is invalid")
        if require_reviewed and status not in _REVIEWED_STATUSES:
            raise ValueError("Judge reference set has not been reviewed")
        return provenance

    @classmethod
    def _load_sources(cls, raw_sources):
        if not isinstance(raw_sources, list) or len(raw_sources) != 20:
            raise ValueError("Judge reference set must contain exactly 20 sources")
        sources = []
        compiled = {}
        for raw in raw_sources:
            source, compilation, judge_context = cls._validate_source(raw)
            if source["id"] in compiled:
                raise ValueError("Judge reference-set source IDs must be unique")
            sources.append(source)
            compiled[source["id"]] = (source, compilation, judge_context)
        return sources, compiled

    @classmethod
    def _validate_source(cls, value):
        if not isinstance(value, dict):
            raise ValueError("Judge reference-set source is invalid")
        keys = set(value)
        if not _SOURCE_REQUIRED_KEYS.issubset(keys) or not keys.issubset(
            _SOURCE_REQUIRED_KEYS | _SOURCE_OPTIONAL_KEYS
        ):
            raise ValueError("Judge reference-set source fields do not match")
        if value["schemaVersion"] != "coaching-quality-benchmark-case.v1":
            raise ValueError("Unsupported judge reference source schema")
        source = dict(value)
        identifier = cls._text(value["id"], "source id")
        cls._text(value["groupID"], "source group id")
        step_index = value["stepIndex"]
        if isinstance(step_index, bool) or not isinstance(step_index, int) or step_index <= 0:
            raise ValueError("Judge source step index is invalid")
        if value["split"] not in _SPLITS or value["category"] not in _CATEGORIES:
            raise ValueError("Judge reference source corpus fields are invalid")
        request_kind = value["requestKind"]
        if request_kind not in _REQUEST_KINDS:
            raise ValueError("Judge reference source request kind is invalid")
        expected_kind = "initial" if step_index == 1 else "followUp"
        if request_kind != expected_kind:
            raise ValueError("Judge reference source request kind does not match its step")
        request = value["request"]
        if not isinstance(request, dict):
            raise ValueError("Judge reference source request is invalid")
        expected_hash = cls._hash(value["requestSHA256"], "source request hash")
        if cls._canonical_sha256(request) != expected_hash:
            raise ValueError("Judge reference source request hash does not match")
        if request.get("requestID") != f"benchmark:{identifier}":
            raise ValueError("Judge reference source request ID does not match")
        cls._validate_brief(value["graderBrief"])
        if "sourceTraceID" in value:
            cls._text(value["sourceTraceID"], "source trace id")

        compiler = compile_context if request_kind == "initial" else compile_follow_up_context
        try:
            parsed_request = parse_neutral_request(request)
            compilation = compiler(request, "tutor-v13")
        except (TypeError, ValueError) as error:
            raise ValueError("Judge reference source does not compile with production v13") from error
        if parsed_request["interaction"]["latestEvent"]["kind"] == "helpClosed":
            raise ValueError("Judge reference source cannot be a help-closed turn")
        cls._validate_event_semantics(parsed_request)
        judge_context = cls._judge_context(parsed_request)
        return source, compilation, judge_context

    @classmethod
    def _load_absolute_cases(cls, raw_cases, compiled):
        if not isinstance(raw_cases, list) or len(raw_cases) != 20:
            raise ValueError("Judge reference set must contain exactly 20 absolute cases")
        cases = []
        for index, raw in enumerate(raw_cases, start=1):
            if not isinstance(raw, dict) or set(raw) != _ABSOLUTE_CASE_KEYS:
                raise ValueError("Judge reference-set absolute case fields do not match")
            if raw["id"] != f"ref-{index:02}":
                raise ValueError("Judge reference-set absolute case IDs or order do not match")
            source, compilation, judge_context = cls._resolve_source(
                raw["sourceID"], compiled
            )
            contract, available_ui = cls._contract_and_ui(compilation)
            cls._validate_turn(raw["candidateTurn"], contract)
            cls._validate_scores(raw["referenceScores"])
            cls._validate_flags(raw["referenceFlags"])
            cls._text_list(raw["rationale"], "reference rationale", minimum=1, maximum=3)
            cases.append(
                dict(
                    raw,
                    graderBrief=source["graderBrief"],
                    availableUI=available_ui,
                    judgeContext=judge_context,
                )
            )
        return cases

    @classmethod
    def _load_pairwise_cases(cls, raw_cases, compiled):
        if not isinstance(raw_cases, list) or len(raw_cases) != 10:
            raise ValueError("Judge reference set must contain exactly 10 pairwise cases")
        cases = []
        for index, raw in enumerate(raw_cases, start=1):
            if not isinstance(raw, dict) or set(raw) != _PAIRWISE_CASE_KEYS:
                raise ValueError("Judge reference-set pairwise case fields do not match")
            if raw["id"] != f"pair-{index:02}":
                raise ValueError("Judge reference-set pairwise case IDs or order do not match")
            source, compilation, judge_context = cls._resolve_source(
                raw["sourceID"], compiled
            )
            contract, available_ui = cls._contract_and_ui(compilation)
            cls._validate_turn(raw["responseOne"], contract)
            cls._validate_turn(raw["responseTwo"], contract)
            if raw["referencePreference"] not in _REFERENCE_PREFERENCES:
                raise ValueError("Judge reference-set pairwise preference is invalid")
            cls._text_list(raw["rationale"], "pairwise rationale", minimum=1, maximum=3)
            cases.append(
                dict(
                    raw,
                    graderBrief=source["graderBrief"],
                    availableUI=available_ui,
                    judgeContext=judge_context,
                )
            )
        return cases

    @staticmethod
    def _resolve_source(source_id, compiled):
        if not isinstance(source_id, str) or source_id not in compiled:
            raise ValueError("Judge reference-set case source does not resolve")
        return compiled[source_id]

    @classmethod
    def _validate_brief(cls, value):
        if not isinstance(value, dict) or set(value) != _BRIEF_KEYS:
            raise ValueError("Judge reference-set grader brief is invalid")
        cls._text_list(value["verifiedFacts"], "verified facts", minimum=1)
        cls._text(value["coachingPurpose"], "coaching purpose")
        cls._text_list(value["acceptableAlternatives"], "acceptable alternatives")
        cls._text_list(value["successCriteria"], "success criteria", minimum=1)
        cls._text_list(value["severeFailureCriteria"], "severe failure criteria")

    @classmethod
    def _validate_turn(cls, value, contract):
        if not isinstance(value, dict) or set(value) != _TURN_KEYS:
            raise ValueError("Judge reference-set candidate turn is invalid")
        try:
            candidate = json.dumps(
                cls._thaw(value),
                sort_keys=True,
                separators=(",", ":"),
                ensure_ascii=True,
            )
            contract.parse_and_validate(candidate)
        except (TypeError, ValueError):
            raise ValueError("Judge reference-set candidate turn fails the app contract")

    @staticmethod
    def _contract_and_ui(compilation):
        contract = ChessNativeResponseContract(
            actions=compilation.actions,
            allowable_moves=compilation.allowable_moves,
            expected_responses=compilation.expected_responses,
        )
        return contract, {
            "actions": list(compilation.actions),
            "expectedResponses": list(compilation.expected_responses),
            "allowableMoveFocus": [list(move) for move in compilation.allowable_moves],
        }

    @classmethod
    def _validate_event_semantics(cls, request):
        interaction = request["interaction"]
        events = interaction["episodeEvents"]
        piece_ids = {piece["id"] for piece in request["pieces"]}
        legal_moves_by_id = {move["id"]: move for move in request["legalMoves"]}
        move_ids = set(legal_moves_by_id)
        tentative = interaction["tentativeMove"]
        if tentative is not None and legal_moves_by_id.get(tentative["id"]) != tentative:
            raise ValueError(
                "Judge reference source tentative move does not match legal move facts"
            )

        active_move = None
        for index, event in enumerate(events):
            kind = event["kind"]
            references = event["referencedIDs"]
            expected_count = 0 if kind in _NO_REFERENCE_EVENTS else 1
            if len(references) != expected_count:
                raise ValueError("Judge reference source event reference arity is invalid")
            if expected_count == 0:
                if kind == "helpReopened" and (
                    index == 0 or events[index - 1]["kind"] != "helpClosed"
                ):
                    raise ValueError("Judge reference source Help reopen history is invalid")
                continue

            reference = references[0]
            if kind == "actionChosen":
                if reference not in _ACTION_REFERENCES:
                    raise ValueError("Judge reference source action reference is invalid")
                continue
            if kind in _PIECE_REFERENCE_EVENTS:
                if reference not in piece_ids:
                    raise ValueError(
                        "Judge reference source event reference does not resolve"
                    )
                continue
            if kind not in _MOVE_REFERENCE_EVENTS or reference not in move_ids:
                raise ValueError("Judge reference source event reference does not resolve")

            if kind == "moveStaged":
                if active_move is not None:
                    raise ValueError("Judge reference source staged-move history is invalid")
                active_move = reference
            elif kind == "moveReplaced":
                if active_move is None or reference == active_move:
                    raise ValueError("Judge reference source replaced-move history is invalid")
                active_move = reference
            else:
                if active_move is None or reference != active_move:
                    raise ValueError("Judge reference source removed-move history is invalid")
                active_move = None

        tentative_id = tentative["id"] if tentative is not None else None
        if active_move != tentative_id:
            raise ValueError(
                "Judge reference source event history does not match the tentative move"
            )
        selected_piece = interaction["selectedPieceReference"]
        selected_square = interaction["selectedSquare"]
        if tentative is not None and (
            selected_piece != tentative["sourcePieceReference"]
            or selected_square != tentative["destinationSquare"]
        ):
            raise ValueError(
                "Judge reference source selected piece does not match the tentative move"
            )
        latest = interaction["latestEvent"]
        if latest["kind"] == "pieceSelected":
            piece = next(
                piece
                for piece in request["pieces"]
                if piece["id"] == latest["referencedIDs"][0]
            )
            if (
                selected_piece != piece["id"]
                or (
                    tentative is None
                    and selected_square != piece["square"]
                )
            ):
                raise ValueError(
                    "Judge reference source selected piece does not match its event"
                )

    @classmethod
    def _judge_context(cls, request):
        interaction = request["interaction"]
        context = {
            "position": dict(request["position"]),
            "moveHistory": [dict(move) for move in request["gameHistory"]],
            "interaction": {
                "events": [cls._event_evidence(event) for event in interaction["episodeEvents"]],
                "latestEvent": cls._event_evidence(interaction["latestEvent"]),
                "selectedPieceReference": interaction["selectedPieceReference"],
                "selectedSquare": interaction["selectedSquare"],
                "tentativeMove": (
                    cls._move_evidence(interaction["tentativeMove"])
                    if interaction["tentativeMove"] is not None
                    else None
                ),
            },
            "legalCaptures": [
                cls._move_evidence(move)
                for move in sorted(request["legalMoves"], key=lambda item: item["id"])
                if move["capturePieceReference"] is not None
            ],
            "immediateReplies": [
                cls._move_evidence(reply["move"])
                for reply in cls._scoped_replies(request)
            ],
        }
        if len(cls._canonical_json_bytes(context)) > _MAXIMUM_JUDGE_CONTEXT_BYTES:
            raise ValueError("Judge reference source derived context is too large")
        return context

    @staticmethod
    def _event_evidence(event):
        return {
            "sequence": event["sequence"],
            "kind": event["kind"],
            "referencedIDs": list(event["referencedIDs"]),
        }

    @staticmethod
    def _move_evidence(move):
        return {
            "id": move["id"],
            "sourcePieceReference": move["sourcePieceReference"],
            "destinationSquare": move["destinationSquare"],
            "capturePieceReference": move["capturePieceReference"],
            "special": move["special"],
            "isLegal": move["isLegal"],
            "givesCheck": move["givesCheck"],
            "givesCheckmate": move["givesCheckmate"],
        }

    @staticmethod
    def _scoped_replies(request):
        replies = tuple(
            sorted(request["tentativeReplies"], key=lambda item: item["move"]["id"])
        )
        interaction = request["interaction"]
        latest = interaction["latestEvent"]
        if latest["kind"] != "squareInspected" or interaction["tentativeMove"] is None:
            return replies
        inspected_id = latest["referencedIDs"][0]
        piece = next(piece for piece in request["pieces"] if piece["id"] == inspected_id)
        if piece["color"] == request["position"]["sideToMove"]:
            return replies
        return tuple(
            reply
            for reply in replies
            if reply["move"]["sourcePieceReference"] == inspected_id
        )

    @staticmethod
    def _validate_scores(scores):
        if not isinstance(scores, dict) or set(scores) != set(RUBRIC_DIMENSIONS):
            raise ValueError("Judge reference-set score fields do not match")
        if any(
            isinstance(score, bool) or not isinstance(score, int) or not 1 <= score <= 5
            for score in scores.values()
        ):
            raise ValueError("Judge reference-set scores must be integers from 1 to 5")

    @staticmethod
    def _validate_flags(flags):
        if not isinstance(flags, dict) or set(flags) != set(RUBRIC_FLAGS):
            raise ValueError("Judge reference-set flag fields do not match")
        if any(not isinstance(flag, bool) for flag in flags.values()):
            raise ValueError("Judge reference-set flags must be booleans")

    @staticmethod
    def _controls(turn):
        return (
            f"actions={json.dumps(list(turn['actions']))}; "
            f"focus={json.dumps(JudgeReferenceSet._thaw(turn['focus']))}; "
            f"expects={json.dumps(turn['expects'])}."
        )

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
    def _hash(cls, value, label):
        value = cls._text(value, label)
        if _SHA256.fullmatch(value) is None:
            raise ValueError(f"Judge {label} is invalid")
        return value

    @staticmethod
    def _canonical_sha256(value):
        return hashlib.sha256(JudgeReferenceSet._canonical_json_bytes(value)).hexdigest()

    @staticmethod
    def _canonical_json_bytes(value):
        return json.dumps(
            value,
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=False,
        ).encode("utf-8")

    @classmethod
    def _freeze(cls, value):
        if isinstance(value, dict):
            return MappingProxyType({key: cls._freeze(child) for key, child in value.items()})
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
