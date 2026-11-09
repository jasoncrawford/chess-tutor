"""Read-only local review surface for the pinned judge reference set."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import threading
from typing import Any, Mapping, Optional, Sequence
import webbrowser

from flask import Flask, Response, jsonify

from Tools.CoachingEval.benchmark.configuration import load_judge
from Tools.CoachingEval.benchmark.judge_contract import RUBRIC_DIMENSIONS, RUBRIC_FLAGS
from Tools.CoachingEval.benchmark.reference_set import JudgeReferenceSet


_REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
_ASSET_ROOT = Path(__file__).resolve().parent
_JUDGE_CONFIGURATION_PATH = _ASSET_ROOT / "configs/judge-v2.json"
_STORAGE_PREFIX = "chess-tutor:judge-reference-review:"
_SCORE_LABELS = {
    "chessCorrectness": "Chess correctness",
    "coachingJudgment": "Coaching judgment",
    "latestActionResponsiveness": "Responds to the latest action",
    "discoveryAndIndependence": "Supports discovery and independence",
    "coherenceAndAnswerability": "Coherent and answerable",
    "childClarity": "Clear for a child",
}
_FLAG_LABELS = {
    "factualOrIllegalAdvice": "Factual error or illegal advice",
    "wrongUrgentPriority": "Misses the urgent priority",
    "answerRevealingGuidance": "Reveals the answer",
    "obsoleteStage": "Responds to an obsolete stage",
    "mixedStages": "Mixes stages",
    "unavailableUIOrDeadEnd": "Uses unavailable controls or reaches a dead end",
    "severeError": "Severe error",
}


def load_reference_set() -> JudgeReferenceSet:
    """Load the configured pin while allowing its pending review state."""
    configuration = load_judge(_JUDGE_CONFIGURATION_PATH, _REPOSITORY_ROOT)
    if configuration.reference_set_path is None or configuration.reference_set_sha256 is None:
        raise ValueError("Judge configuration does not pin a reference set")
    return JudgeReferenceSet.load(
        configuration.reference_set_path,
        configuration.reference_set_sha256,
        require_reviewed=False,
    )


def build_review_view_model(reference: JudgeReferenceSet) -> dict[str, Any]:
    """Create the deterministic, review-only projection consumed by the browser."""
    sources = {source["id"]: source for source in reference.sources}
    cases = []
    for case in reference.absolute_cases:
        cases.append(_absolute_case(len(cases) + 1, case, sources[case["sourceID"]]))
    for case in reference.pairwise_cases:
        cases.append(_pairwise_case(len(cases) + 1, case, sources[case["sourceID"]]))
    return {
        "schemaVersion": "judge-reference-review-view.v1",
        "reference": {
            "id": reference.identifier,
            "sha256": reference.sha256,
            "reviewStatus": reference.review_status,
            "reviewedBy": reference.reviewed_by,
            "reviewedAt": reference.reviewed_at,
            "authoredBy": reference.authored_by,
            "authoredAt": reference.authored_at,
            "responseContract": reference.response_contract,
            "sourceGitSHA": reference.source_git_sha,
            "sourceCasesSHA256": reference.source_cases_sha256,
            "sourceManifestSHA256": reference.source_manifest_sha256,
        },
        "reviewStorageKey": _STORAGE_PREFIX + reference.sha256,
        "rubric": {
            "scores": [
                {"id": dimension, "label": _SCORE_LABELS[dimension], "minimum": 1, "maximum": 5}
                for dimension in RUBRIC_DIMENSIONS
            ],
            "flags": [
                {"id": flag, "label": _FLAG_LABELS[flag]} for flag in RUBRIC_FLAGS
            ],
            "preferences": [
                {"id": "responseOne", "label": "Response one"},
                {"id": "responseTwo", "label": "Response two"},
                {"id": "tie", "label": "Tie"},
            ],
        },
        "cases": cases,
    }


def _absolute_case(index: int, case: Mapping[str, Any], source: Mapping[str, Any]):
    return {
        "id": case["id"],
        "index": index,
        "kind": "absolute",
        "source": _source_summary(source),
        "position": _position_summary(source),
        "brief": _thaw(case["graderBrief"]),
        "technical": _technical_summary(source, case),
        "candidate": _turn(case["candidateTurn"]),
        "proposed": {
            "scores": {dimension: case["referenceScores"][dimension] for dimension in RUBRIC_DIMENSIONS},
            "flags": {flag: case["referenceFlags"][flag] for flag in RUBRIC_FLAGS},
            "rationale": list(case["rationale"]),
        },
    }


def _pairwise_case(index: int, case: Mapping[str, Any], source: Mapping[str, Any]):
    return {
        "id": case["id"],
        "index": index,
        "kind": "pairwise",
        "source": _source_summary(source),
        "position": _position_summary(source),
        "brief": _thaw(case["graderBrief"]),
        "technical": _technical_summary(source, case),
        "responses": [_turn(case["responseOne"]), _turn(case["responseTwo"])],
        "proposed": {
            "preference": case["referencePreference"],
            "rationale": list(case["rationale"]),
        },
    }


def _source_summary(source: Mapping[str, Any]):
    return {
        "category": source["category"],
        "stepIndex": source["stepIndex"],
        "sideToMove": source["request"]["position"]["sideToMove"],
    }


def _position_summary(source: Mapping[str, Any]):
    request = source["request"]
    interaction = request["interaction"]
    staged = interaction.get("tentativeMove")
    return {
        "fen": request["position"]["fen"],
        "sideToMove": request["position"]["sideToMove"],
        "status": request["position"]["status"],
        "moveHistory": [move["displayNotation"] for move in request["gameHistory"]],
        "latestInteraction": {
            "kind": interaction["latestEvent"]["kind"],
            "referencedIDs": list(interaction["latestEvent"]["referencedIDs"]),
        },
        "tentativeMove": (
            {
                "canonicalMove": staged["canonicalMove"],
                "san": staged["san"],
                "special": staged["special"],
                "isLegal": staged["isLegal"],
            }
            if staged is not None
            else None
        ),
    }


def _technical_summary(source: Mapping[str, Any], case: Mapping[str, Any]):
    return {
        "sourceID": source["id"],
        "groupID": source["groupID"],
        "stepIndex": source["stepIndex"],
        "split": source["split"],
        "category": source["category"],
        "requestKind": source["requestKind"],
        "requestSHA256": source["requestSHA256"],
        "availableUI": _thaw(case["availableUI"]),
        "judgeContext": _thaw(case["judgeContext"]),
    }


def _turn(turn: Mapping[str, Any]):
    return {
        "message": turn["message"],
        "actions": list(turn["actions"]),
        "focus": _thaw(turn["focus"]),
        "expects": turn["expects"],
    }


def _thaw(value: Any):
    if isinstance(value, Mapping):
        return {key: _thaw(child) for key, child in value.items()}
    if isinstance(value, (tuple, list)):
        return [_thaw(child) for child in value]
    return value


def create_application(view_model: Mapping[str, Any]) -> Flask:
    """Serve only the fixed review shell and immutable view-model response."""
    model = _thaw(view_model)
    application = Flask(__name__, static_folder=None)
    application.json.sort_keys = False

    @application.after_request
    def security_headers(response):
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; script-src 'self'; style-src 'self'; "
            "img-src 'self' data:; connect-src 'self'; object-src 'none'; "
            "base-uri 'none'; frame-ancestors 'none'"
        )
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Cache-Control"] = "no-store"
        return response

    @application.get("/")
    def index():
        return _asset_response("review_app.html", "text/html; charset=utf-8")

    @application.get("/review_app.css")
    def stylesheet():
        return _asset_response("review_app.css", "text/css; charset=utf-8")

    @application.get("/review_core.js")
    def review_core():
        return _asset_response("review_core.js", "text/javascript; charset=utf-8")

    @application.get("/review_app.js")
    def javascript():
        return _asset_response("review_app.js", "text/javascript; charset=utf-8")

    @application.get("/api/review")
    def review_data():
        return jsonify(model)

    return application


def _asset_response(name: str, content_type: str) -> Response:
    return Response((_ASSET_ROOT / name).read_bytes(), content_type=content_type)


def create_default_application() -> Flask:
    return create_application(build_review_view_model(load_reference_set()))


def _argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Review the pinned judge reference set locally.")
    parser.add_argument("--port", type=int, default=4173)
    parser.add_argument("--no-open", action="store_true", help="Do not open a browser window.")
    parser.add_argument("--check", action="store_true", help="Validate the reference and exit.")
    return parser


def main(arguments: Optional[Sequence[str]] = None) -> int:
    options = _argument_parser().parse_args(arguments)
    reference = load_reference_set()
    view_model = build_review_view_model(reference)
    if options.check:
        print(
            f"Judge reference review ready: {len(view_model['cases'])} cases, "
            f"SHA-256 {reference.sha256}"
        )
        return 0
    application = create_application(view_model)
    address = f"http://127.0.0.1:{options.port}/"
    print(f"Judge reference review: {address}")
    if not options.no_open:
        threading.Timer(0.4, lambda: webbrowser.open(address)).start()
    application.run(host="127.0.0.1", port=options.port, debug=False, use_reloader=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
