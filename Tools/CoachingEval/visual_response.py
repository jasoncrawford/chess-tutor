"""Strict visual-coaching output, grounded in the app's mechanical request facts."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass

from Tools.CoachingEval.chess_native_response import (
    ChessNativeResponseContract,
    ChessNativeResponseValidationError,
)


@dataclass(frozen=True)
class VisualResponseContract:
    pieces: tuple
    attacks: frozenset
    moves: frozenset
    learner: str
    is_hint: bool
    has_draft: bool

    EXPECTED_RESPONSES = (
        "findEndangeredPiece", "findSafeCapture", "stageMove",
        "judgeMoveSafety", "chooseWhetherToPlay",
    )

    @classmethod
    def from_request(cls, request):
        """Consume a neutral request already validated at the transport boundary."""
        interaction = request["interaction"]
        draft = interaction["tentativeMove"] is not None
        displayed = request.get("tentativePosition") if draft else request
        # A legacy request without draft facts cannot ground displayed references.
        pieces = tuple(dict(p) for p in (displayed or {}).get("pieces", ()))
        by_id = {p["id"]: p["square"] for p in pieces}
        attacks = frozenset(
            (by_id[r["sourcePieceReference"]], by_id[r["targetPieceReference"]])
            for r in (displayed or {}).get("occupiedSquareRelationships", ())
            if r["kind"] == "attacks" and r["sourcePieceReference"] in by_id
            and r["targetPieceReference"] in by_id
        )
        moves = frozenset(
            (m["canonicalMove"][:2], m["canonicalMove"][2:4])
            for m in request["legalMoves"] if m["isLegal"]
        )
        event = interaction["latestEvent"]
        return cls(pieces, attacks, moves, request["position"]["sideToMove"],
                   event["kind"] == "actionChosen" and "action:hint" in event["referencedIDs"], draft)

    @staticmethod
    def plain_text(turn):
        return "".join(run["text"] for run in turn["message"])

    @staticmethod
    def _object(properties):
        return {"type": "object", "properties": properties,
                "required": list(properties), "additionalProperties": False}

    def json_schema(self):
        square = {"type": "string", "pattern": "^[a-h][1-8]$"}
        runs = [self._object({"type": {"type": "string", "enum": ["text"]},
                              "text": {"type": "string"}})]
        for kind in ("piece", "square"):
            runs.append(self._object({"type": {"type": "string", "enum": [kind]},
                                     "text": {"type": "string"}, "square": square}))
        cues = [self._object({"type": {"type": "string", "enum": [kind]},
                             "from": square, "to": square}) for kind in ("attack", "move")]
        return self._object({
            "message": {"type": "array", "items": {"anyOf": runs}, "minItems": 1, "maxItems": 9},
            "actions": {"type": "array", "items": {"type": "string", "enum": ["hint"]}, "maxItems": 1},
            "visuals": {"type": "array", "items": {"anyOf": cues}, "maxItems": 1},
            "expects": {"type": "string", "enum": list(self.EXPECTED_RESPONSES if self.has_draft
                else self.EXPECTED_RESPONSES[:3])},
        })

    @staticmethod
    def _strict_object(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ChessNativeResponseValidationError("duplicateKey")
            result[key] = value
        return result

    @staticmethod
    def _reject_constant(_value):
        raise ChessNativeResponseValidationError("invalidJSON")

    def parse_and_validate(self, candidate):
        try:
            turn = json.loads(candidate, object_pairs_hook=self._strict_object,
                              parse_constant=self._reject_constant)
        except ChessNativeResponseValidationError:
            raise
        except (TypeError, ValueError):
            raise ChessNativeResponseValidationError("invalidJSON") from None
        self._validate(turn)
        return turn

    def _validate(self, turn):
        def require(condition, category="shape"):
            if not condition:
                raise ChessNativeResponseValidationError(category)

        require(isinstance(turn, dict) and set(turn) == {"message", "actions", "visuals", "expects"})
        runs = turn["message"]
        require(isinstance(runs, list) and 1 <= len(runs) <= 9)
        pieces = {p["square"]: p for p in self.pieces}
        references = []
        for run in runs:
            require(isinstance(run, dict))
            kind = run.get("type")
            require(kind in ("text", "piece", "square"))
            require(set(run) == ({"type", "text"} if kind == "text" else {"type", "text", "square"}))
            require(isinstance(run["text"], str) and bool(run["text"]))
            require(not any(0xD800 <= ord(c) <= 0xDFFF for c in run["text"]), "invalidUnicode")
            if kind != "text":
                require(isinstance(run["square"], str) and re.fullmatch(r"[a-h][1-8]", run["square"]), "reference")
                require(bool(run["text"].strip()), "reference")
                require(kind != "piece" or run["square"] in pieces, "reference")
                references.append(run)
        require(len(references) <= 2, "reference")
        # Reuse the mature v13 prose/action checks rather than a second notation policy.
        legacy = ChessNativeResponseContract(actions=("hint",), allowable_moves=(),
                                             expected_responses=self.EXPECTED_RESPONSES)
        legacy.parse_and_validate(json.dumps({"message": self.plain_text(turn),
            "actions": turn["actions"], "focus": [], "expects": turn["expects"]}))
        require(self.has_draft or turn["expects"] not in ("judgeMoveSafety", "chooseWhetherToPlay"),
                "unavailableExpectedResponse")
        visuals = turn["visuals"]
        require(isinstance(visuals, list) and len(visuals) <= 1)
        for cue in visuals:
            require(isinstance(cue, dict) and set(cue) == {"type", "from", "to"})
            require(cue["type"] in ("attack", "move"))
            require(all(isinstance(cue[k], str) and re.fullmatch(r"[a-h][1-8]", cue[k]) for k in ("from", "to")))
            pair = (cue["from"], cue["to"])
            require(pair in (self.attacks if cue["type"] == "attack" else self.moves), "visual")
        if turn["expects"] in ("findEndangeredPiece", "findSafeCapture"):
            require(not visuals, "discoveryFocus")
            require(not references or (self.is_hint and len(references) == 1), "discoveryFocus")
            for run in references:
                require(run["type"] == "piece", "discoveryFocus")
                own = pieces[run["square"]]["color"] == self.learner
                require(own == (turn["expects"] == "findSafeCapture"), "discoveryFocus")
