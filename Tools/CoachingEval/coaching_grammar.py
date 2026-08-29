#!/usr/bin/env python3
"""Strict b10516 GBNF for the immutable model-coaching-turn.v1 schema."""

import hashlib
import json


EXPECTED_SCHEMA_SHA256 = "0f4c427f07cabeae9a6be611eb8a5959b5b916c8648649265d0f4a23f09f15d7"


def _canonical_sha256(value):
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def strict_grammar(schema, *, enable_thinking):
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
    return root + _GRAMMAR_PREFIX + intent_rule + _GRAMMAR_SUFFIX


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
boardFocusReferences-kv ::= "\"boardFocusReferences\"" space ":" space string-array
relationshipReferences-kv ::= "\"relationshipReferences\"" space ":" space string-array
supportingEvidenceReferences-kv ::= "\"supportingEvidenceReferences\"" space ":" space nonempty-string-array
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
