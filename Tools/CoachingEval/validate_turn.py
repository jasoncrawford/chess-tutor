#!/usr/bin/env python3
"""Strict standard-library validation for one model-authored coaching turn."""

import argparse
import json
import sys
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parent
TEACHING_INTENTS = [
    "orient",
    "scanDanger",
    "scanCapture",
    "chooseMove",
    "evaluateMove",
    "reviseMove",
    "confirmMove",
    "resolveCheck",
    "findMate",
    "other",
]
REQUIRED_FIELDS = [
    "schemaVersion",
    "requestID",
    "teachingIntent",
    "primaryMessage",
    "actionReferences",
    "boardFocusReferences",
    "relationshipReferences",
    "supportingEvidenceReferences",
]
OPTIONAL_FIELDS = ["instruction", "responseToLatestAction", "boardTaskReference"]
ARRAY_FIELDS = [
    "actionReferences",
    "boardFocusReferences",
    "relationshipReferences",
    "supportingEvidenceReferences",
]


def _word_count(value):
    return len(value.split())


def _duplicates(values):
    seen = set()
    reported = set()
    duplicates = []
    for value in values:
        if value in seen and value not in reported:
            duplicates.append(value)
            reported.add(value)
        seen.add(value)
    return duplicates


def validate_shape(turn):
    if not isinstance(turn, dict):
        return ["shape.type:turn"]
    issues = []
    allowed = set(REQUIRED_FIELDS + OPTIONAL_FIELDS)
    for key in turn:
        if key not in allowed:
            issues.append(f"shape.additionalProperty:{key}")
    for key in REQUIRED_FIELDS:
        if key not in turn:
            issues.append(f"shape.missing:{key}")
    if any(issue.startswith("shape.missing:") for issue in issues):
        return issues

    string_fields = ["schemaVersion", "requestID", "teachingIntent", "primaryMessage"]
    for key in string_fields:
        if not isinstance(turn[key], str):
            issues.append(f"shape.type:{key}")
    for key in OPTIONAL_FIELDS:
        if key in turn and turn[key] is not None and not isinstance(turn[key], str):
            issues.append(f"shape.type:{key}")
    for key in ARRAY_FIELDS:
        value = turn[key]
        if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
            issues.append(f"shape.type:{key}")
    if isinstance(turn.get("teachingIntent"), str) and turn["teachingIntent"] not in TEACHING_INTENTS:
        issues.append("shape.teachingIntent")
    return issues


def validate_turn(turn, request):
    issues = validate_shape(turn)
    if any(issue.startswith("shape.missing:") or issue.startswith("shape.type:") for issue in issues):
        return issues

    if turn["schemaVersion"] != "model-coaching-turn.v1":
        issues.append("unsupportedTurnSchemaVersion")
    if turn["requestID"] != request.get("requestID"):
        issues.append("requestIDMismatch")

    permitted = request.get("permittedReferences", {})
    action_ids = {entry.get("id") for entry in permitted.get("actions", [])}
    board_task_ids = {entry.get("id") for entry in permitted.get("boardTasks", [])}
    board_focus_ids = set(permitted.get("boardFocus", []))
    relationship_ids = set(permitted.get("relationships", []))
    evidence_ids = set(permitted.get("evidence", []))

    for reference in dict.fromkeys(turn["actionReferences"]):
        if reference not in action_ids:
            issues.append(f"unknownActionReference:{reference}")
    for reference in _duplicates(turn["actionReferences"]):
        issues.append(f"duplicateActionReference:{reference}")
    if len(turn["actionReferences"]) > 3:
        issues.append("actionReferenceLimitExceeded")

    board_task = turn.get("boardTaskReference")
    if board_task is not None and board_task not in board_task_ids:
        issues.append(f"unknownBoardTaskReference:{board_task}")

    for reference in dict.fromkeys(turn["boardFocusReferences"]):
        if reference not in board_focus_ids:
            issues.append(f"unknownBoardFocusReference:{reference}")
    for reference in _duplicates(turn["boardFocusReferences"]):
        issues.append(f"duplicateBoardFocusReference:{reference}")

    for reference in dict.fromkeys(turn["relationshipReferences"]):
        if reference not in relationship_ids:
            issues.append(f"unknownRelationshipReference:{reference}")
    for reference in _duplicates(turn["relationshipReferences"]):
        issues.append(f"duplicateRelationshipReference:{reference}")

    for reference in dict.fromkeys(turn["supportingEvidenceReferences"]):
        if reference not in evidence_ids:
            issues.append(f"unknownSupportingEvidenceReference:{reference}")
    for reference in _duplicates(turn["supportingEvidenceReferences"]):
        issues.append(f"duplicateSupportingEvidenceReference:{reference}")

    if _word_count(turn["primaryMessage"]) > 18:
        issues.append("primaryMessageWordLimitExceeded")
    if turn.get("instruction") is not None and _word_count(turn["instruction"]) > 14:
        issues.append("instructionWordLimitExceeded")
    if turn.get("responseToLatestAction") is not None and _word_count(turn["responseToLatestAction"]) > 16:
        issues.append("responseWordLimitExceeded")
    for action in permitted.get("actions", []):
        if _word_count(action.get("title", "")) > 5:
            issues.append(f"actionTitleWordLimitExceeded:{action.get('id')}")
    if not turn["supportingEvidenceReferences"]:
        issues.append("missingSupportingEvidenceReference")
    return issues


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--turn", required=True, type=Path)
    parser.add_argument("--request", required=True, type=Path)
    arguments = parser.parse_args(argv)
    turn = json.loads(arguments.turn.read_text(encoding="utf-8"))
    request = json.loads(arguments.request.read_text(encoding="utf-8"))
    issues = validate_turn(turn, request)
    print(json.dumps({"valid": not issues, "errors": issues}, indent=2, sort_keys=True))
    return 1 if issues else 0


if __name__ == "__main__":
    raise SystemExit(main())
