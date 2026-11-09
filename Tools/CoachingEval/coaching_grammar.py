#!/usr/bin/env python3
"""Strict b10516 GBNF for the immutable model-coaching-turn.v1 schema."""

import hashlib
import json


EXPECTED_SCHEMA_SHA256 = "0f4c427f07cabeae9a6be611eb8a5959b5b916c8648649265d0f4a23f09f15d7"


def _canonical_sha256(value):
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def strict_grammar(
    schema,
    *,
    enable_thinking,
    request_id=None,
    permitted_aliases=None,
):
    """Return a strict grammar, refusing any schema other than the pinned contract.

    b10516's JSON-schema converter embeds string ``pattern`` expressions without
    intersecting them with JSON string syntax. A pattern such as ``[^ ]+`` can
    therefore consume a closing quote and let syntactically invalid JSON through.
    This grammar preserves the exact contract while making the three bounded prose
    strings slightly stricter: they may use literal Unicode and ordinary JSON
    escapes, but not ``\\u`` escapes. The strict Python validator still checks the
    decoded response against the request after generation.
    """
    if _canonical_sha256(schema) != EXPECTED_SCHEMA_SHA256:
        raise ValueError("Schema does not match the pinned coaching contract")

    intents = schema["properties"]["teachingIntent"]["enum"]
    intent_rule = " | ".join(f'\"\\\"{value}\\\"\"' for value in intents)
    root = (
        'root ::= thinking-block coaching-turn\n'
        'thinking-block ::= "<think>" line-break{0,2} reasoning "</think>" line-break{0,2}\n'
        'reasoning ::= [^<]{0,128}\n'
        'line-break ::= [\\r\\n]\n'
        if enable_thinking
        else "root ::= coaching-turn\n"
    )
    grammar = root + _GRAMMAR_PREFIX + intent_rule + _GRAMMAR_SUFFIX
    if request_id is None and permitted_aliases is None:
        return grammar
    if not isinstance(request_id, str) or not isinstance(permitted_aliases, dict):
        raise ValueError("Request-specific grammar requires request_id and permitted_aliases")
    return _request_specific_grammar(grammar, request_id, permitted_aliases)


def _gbnf_json_string(value):
    return json.dumps(json.dumps(value, ensure_ascii=False), ensure_ascii=False)


def _alias_rule(name, values):
    alternatives = " | ".join(
        _gbnf_json_string(value) for value in sorted(set(values))
    )
    return f"{name} ::= ({alternatives})" if alternatives else None


def _request_specific_grammar(grammar, request_id, permitted):
    replacements = {
        'requestID-kv ::= "\\\"requestID\\\"" space ":" space json-string': (
            'requestID-kv ::= "\\\"requestID\\\"" space ":" space '
            + _gbnf_json_string(request_id)
        ),
    }
    action_rule = _alias_rule("actionReference", permitted.get("actions", []))
    if action_rule:
        replacements[
            'actionReferences ::= "[" space (json-string ("," space json-string){0,2})? space "]"'
        ] = (
            'actionReferences ::= "[" space "]" | "[" space actionReference '
            '("," space actionReference){0,2} space "]"\n' + action_rule
        )
    else:
        replacements[
            'actionReferences ::= "[" space (json-string ("," space json-string){0,2})? space "]"'
        ] = 'actionReferences ::= "[" space "]"'

    task_rule = _alias_rule("boardTaskReferenceValue", permitted.get("boardTasks", []))
    replacements['boardTaskReference ::= "null" | json-string'] = (
        'boardTaskReference ::= "null"'
        + (" | boardTaskReferenceValue\n" + task_rule if task_rule else "")
    )
    for field, grammar_rule, alias_rule_name, key in (
        ("boardFocusReferences", "string-array", "boardFocusReference", "boardFocus"),
        ("relationshipReferences", "string-array", "relationshipReference", "relationships"),
    ):
        alias_rule = _alias_rule(alias_rule_name, permitted.get(key, []))
        replacement = f'{field} ::= "[" space "]"'
        if alias_rule:
            replacement += (
                f' | "[" space {alias_rule_name} '
                f'("," space {alias_rule_name})* space "]"\n{alias_rule}'
            )
        replacements[f"{field} ::= {grammar_rule}"] = replacement

    evidence_rule = _alias_rule("evidenceReference", permitted.get("evidence", []))
    if evidence_rule:
        replacements["supportingEvidenceReferences ::= nonempty-string-array"] = (
            'supportingEvidenceReferences ::= "[" space evidenceReference '
            '("," space evidenceReference)* space "]"\n' + evidence_rule
        )
    else:
        replacements[
            "supportingEvidenceReferences ::= nonempty-string-array"
        ] = "supportingEvidenceReferences ::= impossible-reference"

    for original, replacement in replacements.items():
        if original not in grammar:
            raise ValueError(f"Pinned grammar shape changed before replacement: {original}")
        grammar = grammar.replace(original, replacement, 1)
    if not evidence_rule:
        grammar += "\nimpossible-reference ::= [^\\x00-\\U0010FFFF]\n"
    return grammar


_GRAMMAR_PREFIX = r'''coaching-turn ::= "{" space schemaVersion-kv "," space requestID-kv "," space teachingIntent-kv "," space primaryMessage-kv "," space actionReferences-kv "," space boardFocusReferences-kv "," space relationshipReferences-kv "," space supportingEvidenceReferences-kv ("," space (instruction-kv instruction-rest | responseToLatestAction-kv responseToLatestAction-rest | boardTaskReference-kv))? space "}"
schemaVersion-kv ::= "\"schemaVersion\"" space ":" space "\"model-coaching-turn.v1\""
requestID-kv ::= "\"requestID\"" space ":" space json-string
teachingIntent-kv ::= "\"teachingIntent\"" space ":" space teachingIntent
teachingIntent ::= ('''

_GRAMMAR_SUFFIX = r''')
primaryMessage-kv ::= "\"primaryMessage\"" space ":" space primaryMessage
primaryMessage ::= "\"" message-space* (message-word primaryMessage-tail{0,17})? message-space* "\""
primaryMessage-tail ::= message-space+ message-word
instruction-kv ::= "\"instruction\"" space ":" space instruction
instruction ::= "null" | "\"" message-space* (message-word instruction-tail{0,13})? message-space* "\""
instruction-tail ::= message-space+ message-word
responseToLatestAction-kv ::= "\"responseToLatestAction\"" space ":" space responseToLatestAction
responseToLatestAction ::= "null" | "\"" message-space* (message-word responseToLatestAction-tail{0,15})? message-space* "\""
responseToLatestAction-tail ::= message-space+ message-word
actionReferences-kv ::= "\"actionReferences\"" space ":" space actionReferences
actionReferences ::= "[" space (json-string ("," space json-string){0,2})? space "]"
boardTaskReference-kv ::= "\"boardTaskReference\"" space ":" space boardTaskReference
boardTaskReference ::= "null" | json-string
boardFocusReferences-kv ::= "\"boardFocusReferences\"" space ":" space boardFocusReferences
boardFocusReferences ::= string-array
relationshipReferences-kv ::= "\"relationshipReferences\"" space ":" space relationshipReferences
relationshipReferences ::= string-array
supportingEvidenceReferences-kv ::= "\"supportingEvidenceReferences\"" space ":" space supportingEvidenceReferences
supportingEvidenceReferences ::= nonempty-string-array
instruction-rest ::= ("," space responseToLatestAction-kv)? responseToLatestAction-rest
responseToLatestAction-rest ::= ("," space boardTaskReference-kv)?
string-array ::= "[" space (json-string ("," space json-string)*)? space "]"
nonempty-string-array ::= "[" space json-string ("," space json-string)* space "]"
json-string ::= "\"" json-char* "\""
json-char ::= [^"\\\x7F\x00-\x1F] | [\\] (["\\/bfnrt] | "u" [0-9a-fA-F]{4})
message-word ::= message-char+
message-char ::= [^"\\ \t\r\n] | [\\] ["\\/bf]
message-space ::= [ \t\r\n] | [\\] [nrt]
space ::= [ \t\r\n]*
'''
