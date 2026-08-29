"""Validation and fail-closed alias restoration for compact coaching contexts."""

import copy
import re


CONTEXT_SCHEMA_VERSION = "model-coaching-context.v1"
PROMPT_VERSION = "tutor-v3"
_ALIAS_PATTERN = re.compile(
    r"\b(?:action|task|piece|move|relationship|reply|fact)-[a-z0-9-]+\b"
)
_CATEGORIES = {
    "action",
    "boardTask",
    "piece",
    "move",
    "relationship",
    "reply",
    "tacticalFact",
}
_FIELD_CATEGORIES = {
    "actionReferences": {"action"},
    "boardTaskReference": {"boardTask"},
    "boardFocusReferences": {"piece"},
    "relationshipReferences": {"relationship"},
    "supportingEvidenceReferences": {"move", "reply", "tacticalFact"},
}


def _source_categories(request):
    evidence = request.get("chessEvidence", {})
    permitted = request.get("permittedReferences", {})
    categories = {}

    def add(identifier, category):
        if isinstance(identifier, str):
            categories[identifier] = category

    for action in permitted.get("actions", []):
        add(action.get("id"), "action")
    for task in permitted.get("boardTasks", []):
        add(task.get("id"), "boardTask")
    for identifier in permitted.get("boardFocus", []):
        add(identifier, "piece")
    for piece in evidence.get("pieces", []):
        add(piece.get("id"), "piece")
    for move in evidence.get("legalMoves", []):
        add(move.get("id"), "move")
    for relationship in evidence.get("relationships", []):
        add(relationship.get("id"), "relationship")
    for reply in evidence.get("immediateReplies", []):
        add(reply.get("id"), "reply")
    for fact in evidence.get("tacticalFacts", []):
        add(fact.get("id"), "tacticalFact")
    return categories


def validate_compilation(evaluation_case):
    """Return deterministic issues for a compact compilation and its source request."""
    issues = []
    request = evaluation_case.get("request", {})
    compilation = evaluation_case.get("compactContext", {})
    if compilation.get("schemaVersion") != CONTEXT_SCHEMA_VERSION:
        issues.append("compilation.schemaVersionMismatch")
    if compilation.get("promptVersion") != PROMPT_VERSION:
        issues.append("compilation.promptVersionMismatch")
    if compilation.get("requestID") != request.get("requestID"):
        issues.append("compilation.requestIDMismatch")
    if compilation.get("positionRevision") != request.get("positionRevision"):
        issues.append("compilation.positionRevisionMismatch")

    source_categories = _source_categories(request)
    bindings = compilation.get("referenceBindings", [])
    omissions = compilation.get("omissions", [])
    aliases = {}
    bound_stable_ids = set()
    seen_aliases = set()
    seen_stable_ids = set()
    for binding in bindings:
        alias = binding.get("alias")
        stable_id = binding.get("stableID")
        category = binding.get("category")
        if alias in seen_aliases:
            issues.append(f"bindings.duplicateAlias:{alias}")
        seen_aliases.add(alias)
        if stable_id in seen_stable_ids:
            issues.append(f"bindings.duplicateStableID:{stable_id}")
        seen_stable_ids.add(stable_id)
        if category not in _CATEGORIES:
            issues.append(f"bindings.unknownCategory:{stable_id}")
        elif source_categories.get(stable_id) != category:
            issues.append(f"bindings.categoryMismatch:{stable_id}")
        aliases[alias] = binding
        bound_stable_ids.add(stable_id)

    omitted_stable_ids = set()
    for omission in omissions:
        stable_id = omission.get("stableID")
        category = omission.get("category")
        if stable_id in omitted_stable_ids:
            issues.append(f"omissions.duplicateStableID:{stable_id}")
        omitted_stable_ids.add(stable_id)
        if source_categories.get(stable_id) != category:
            issues.append(f"omissions.categoryMismatch:{stable_id}")

    for stable_id in sorted(set(source_categories) - bound_stable_ids - omitted_stable_ids):
        issues.append(f"accounting.missing:{stable_id}")
    for stable_id in sorted((bound_stable_ids | omitted_stable_ids) - set(source_categories)):
        issues.append(f"accounting.unknown:{stable_id}")
    for stable_id in sorted(bound_stable_ids & omitted_stable_ids):
        issues.append(f"accounting.boundAndOmitted:{stable_id}")

    markdown = compilation.get("markdown", "")
    if not isinstance(markdown, str) or not markdown:
        issues.append("compilation.markdownMissing")
    else:
        for alias in sorted(set(_ALIAS_PATTERN.findall(markdown)) - set(aliases)):
            issues.append(f"markdown.unknownAlias:{alias}")
        for alias in sorted(set(aliases) - set(_ALIAS_PATTERN.findall(markdown))):
            issues.append(f"markdown.missingBoundAlias:{alias}")
    return sorted(set(issues))


def restore_stable_turn(turn, compilation):
    """Map request-local response aliases to stable IDs without guessing."""
    restored = copy.deepcopy(turn)
    bindings = {
        binding.get("alias"): binding
        for binding in compilation.get("referenceBindings", [])
        if isinstance(binding.get("alias"), str)
    }
    issues = []

    def restore_array(field):
        aliases = turn.get(field, [])
        if not isinstance(aliases, list):
            return
        mapped = []
        field_issues = []
        for alias in aliases:
            binding = bindings.get(alias)
            if binding is None:
                field_issues.append(f"alias.unknown:{field}:{alias}")
            elif binding.get("category") not in _FIELD_CATEGORIES[field]:
                field_issues.append(f"alias.categoryMismatch:{field}:{alias}")
            else:
                mapped.append(binding.get("stableID"))
        issues.extend(field_issues)
        if not field_issues:
            restored[field] = mapped

    for field in (
        "actionReferences",
        "boardFocusReferences",
        "relationshipReferences",
        "supportingEvidenceReferences",
    ):
        restore_array(field)

    field = "boardTaskReference"
    alias = turn.get(field)
    if alias is not None:
        binding = bindings.get(alias)
        if binding is None:
            issues.append(f"alias.unknown:{field}:{alias}")
        elif binding.get("category") not in _FIELD_CATEGORIES[field]:
            issues.append(f"alias.categoryMismatch:{field}:{alias}")
        else:
            restored[field] = binding.get("stableID")

    return restored, sorted(set(issues))


def permitted_aliases(compilation):
    """Project validated bindings into the five response-reference categories."""
    result = {
        "actions": [],
        "boardTasks": [],
        "boardFocus": [],
        "relationships": [],
        "evidence": [],
    }
    destinations = {
        "action": "actions",
        "boardTask": "boardTasks",
        "piece": "boardFocus",
        "relationship": "relationships",
        "move": "evidence",
        "reply": "evidence",
        "tacticalFact": "evidence",
    }
    for binding in compilation.get("referenceBindings", []):
        destination = destinations.get(binding.get("category"))
        alias = binding.get("alias")
        if destination is not None and isinstance(alias, str):
            result[destination].append(alias)
    return {key: sorted(set(values)) for key, values in result.items()}
