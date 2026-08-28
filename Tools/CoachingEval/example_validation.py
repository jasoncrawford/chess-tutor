"""Mechanical validation for the versioned, visible tutor examples."""

import validate_turn


def _synthetic_request(example):
    permitted_ids = example["requestExcerpt"]["permittedIDs"]
    return {
        "requestID": example["requestExcerpt"]["requestID"],
        "permittedReferences": {
            "actions": [
                {"id": identifier, "title": "Choose action"}
                for identifier in permitted_ids
                if identifier.startswith("action:")
            ],
            "boardTasks": [
                {"id": identifier}
                for identifier in permitted_ids
                if identifier.startswith("task:")
            ],
            "boardFocus": [
                identifier for identifier in permitted_ids if identifier.startswith("piece:")
            ],
            "relationships": [
                identifier
                for identifier in permitted_ids
                if identifier.startswith("relationship:")
            ],
            "evidence": [
                identifier
                for identifier in permitted_ids
                if identifier.startswith(("fact:", "reply:"))
            ],
        },
    }


def validate_examples(examples, contracts):
    """Return deterministic issues for example shape, references, and semantic oracles."""
    issues = []
    examples_by_id = {example.get("sourceCaseID"): example for example in examples}
    contracts_by_id = {contract.get("sourceCaseID"): contract for contract in contracts}

    if len(examples_by_id) != len(examples):
        issues.append("examples.duplicateSourceCaseID")
    if len(contracts_by_id) != len(contracts):
        issues.append("contracts.duplicateSourceCaseID")
    if set(examples_by_id) != set(contracts_by_id):
        issues.append("contracts.sourceCaseIDMismatch")

    for source_id in sorted(set(examples_by_id) & set(contracts_by_id)):
        example = examples_by_id[source_id]
        contract = contracts_by_id[source_id]
        turn = example.get("turn", {})
        for issue in validate_turn.validate_turn(turn, _synthetic_request(example)):
            issues.append(f"{source_id}.{issue}")

        permitted_intents = contract.get("permittedTeachingIntents", [])
        if turn.get("teachingIntent") not in permitted_intents:
            issues.append(f"{source_id}.teachingIntentNotPermitted")

        actions = set(turn.get("actionReferences", []))
        for action in contract.get("requiredActionReferences", []):
            if action not in actions:
                issues.append(f"{source_id}.missingRequiredAction:{action}")
        for action in contract.get("forbiddenActionReferences", []):
            if action in actions:
                issues.append(f"{source_id}.forbiddenAction:{action}")

        rendered_text = " ".join(
            text
            for text in (
                turn.get("primaryMessage"),
                turn.get("instruction"),
                turn.get("responseToLatestAction"),
            )
            if isinstance(text, str)
        ).lower()
        for phrase in contract.get("prohibitedPhrases", []):
            if phrase.lower() in rendered_text:
                issues.append(f"{source_id}.prohibitedPhrase:{phrase}")

    return issues
