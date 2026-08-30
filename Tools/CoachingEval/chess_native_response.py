#!/usr/bin/env python3
"""Request-specific response contract for the frozen tutor-v6 pilot."""

import dataclasses
import json
import re
import unicodedata


_ACTION_NAME = re.compile(r"[a-z][A-Za-z0-9]*\Z")
_BOARD_SQUARE = re.compile(r"[a-h][1-8]\Z")
_THINKING_ENVELOPE = re.compile(
    r"\A<think>[\r\n]{0,2}[^<]{0,128}</think>[\r\n]{0,2}(?P<candidate>\{.*)\Z",
    re.DOTALL,
)
_THINKING_MARKER = re.compile(r"<\s*/?\s*think\b", re.IGNORECASE)
_FIGURINES = frozenset("♔♕♖♗♘♙♚♛♜♝♞♟")
_NOTATION_PATTERNS = tuple(
    re.compile(pattern)
    for pattern in (
        r"(?<![a-z0-9])(?:o-o(?:-o)?|0-0(?:-0)?)(?![a-z0-9])",
        r"(?<![a-z0-9])[kqrbn](?:[a-h1-8]{0,2})x?[a-h][1-8](?:=[qrbn])?(?![a-z0-9])",
        r"(?<![a-z0-9])[a-h]x[a-h][1-8](?:=[qrbn])?(?![a-z0-9])",
        r"(?<![a-z0-9])[a-h][18]=[qrbn](?![a-z0-9])",
        r"(?<![a-z0-9])[a-h][1-8][a-h][1-8][qrbn]?(?![a-z0-9])",
        r"(?<![a-z0-9])[a-h][1-8][-\u2013\u2014][a-h][1-8](?![a-z0-9])",
        r"(?<![a-z])x(?![a-z])",
        r"(?<![a-z0-9])[kqrbnp](?![a-z0-9])",
    )
)


class _DuplicateJSONKey(ValueError):
    pass


def _strict_json_object(pairs):
    value = {}
    for key, child in pairs:
        if key in value:
            raise _DuplicateJSONKey(f"Duplicate JSON key: {key}")
        value[key] = child
    return value


def _reject_json_constant(value):
    raise ValueError(f"Invalid JSON constant: {value}")


def _contains_lone_unicode_surrogate(value):
    if isinstance(value, str):
        return any(0xD800 <= ord(character) <= 0xDFFF for character in value)
    if isinstance(value, list):
        return any(_contains_lone_unicode_surrogate(child) for child in value)
    if isinstance(value, dict):
        return any(
            _contains_lone_unicode_surrogate(key)
            or _contains_lone_unicode_surrogate(child)
            for key, child in value.items()
        )
    return False


def _contains_chess_notation(message):
    normalized = unicodedata.normalize("NFKC", message).casefold()
    return (
        "+" in normalized
        or "#" in normalized
        or any(character in _FIGURINES for character in normalized)
        or any(pattern.search(normalized) is not None for pattern in _NOTATION_PATTERNS)
    )


def _gbnf_json_string(value):
    return json.dumps(json.dumps(value, ensure_ascii=False), ensure_ascii=False)


@dataclasses.dataclass(frozen=True)
class ChessNativeResponseContract:
    actions: tuple
    allowable_moves: tuple

    @classmethod
    def from_markdown(cls, markdown):
        marker = "## Available UI response\n\n"
        if not isinstance(markdown, str) or markdown.count(marker) != 1:
            raise ValueError("Model-facing Markdown must contain one Available UI response")
        section = markdown.split(marker, 1)[1]
        lines = section.rstrip("\n").splitlines()
        if len(lines) != 3:
            raise ValueError("Available UI response must contain exactly three fields")
        actions_line, square_line, moves_line = lines
        if not actions_line.startswith("Actions: "):
            raise ValueError("Available UI response has invalid actions")
        if square_line != "Square focus: any board square":
            raise ValueError("Available UI response has invalid square focus")
        if not moves_line.startswith("Allowable move focus: "):
            raise ValueError("Available UI response has invalid move focus")

        actions = tuple(actions_line.removeprefix("Actions: ").split(", "))
        if (
            not actions
            or any(_ACTION_NAME.fullmatch(action) is None for action in actions)
            or len(actions) != len(set(actions))
        ):
            raise ValueError("Available UI response has invalid actions")
        raw_moves = moves_line.removeprefix("Allowable move focus: ")
        if raw_moves == "none":
            allowable_moves = ()
        else:
            allowable_moves = tuple(
                tuple(move.split("-", 1)) for move in raw_moves.split(", ")
            )
            if (
                any(
                    len(move) != 2
                    or any(_BOARD_SQUARE.fullmatch(square) is None for square in move)
                    for move in allowable_moves
                )
                or len(allowable_moves) != len(set(allowable_moves))
            ):
                raise ValueError("Available UI response has invalid move focus")
        return cls(actions=actions, allowable_moves=allowable_moves)

    def grammar(self, *, enable_thinking):
        if not isinstance(enable_thinking, bool):
            raise ValueError("enable_thinking must be a boolean")
        action_values = " | ".join(_gbnf_json_string(value) for value in self.actions)
        move_values = " | ".join(
            self._move_focus_grammar(origin, destination)
            for origin, destination in self.allowable_moves
        )
        focus_object = "square-focus" + (" | move-focus" if move_values else "")
        root = (
            'root ::= thinking-block turn\n'
            'thinking-block ::= "<think>" line-break{0,2} reasoning "</think>" line-break{0,2}\n'
            'reasoning ::= [^<]{0,128}\n'
            'line-break ::= [\\r\\n]\n'
            if enable_thinking
            else "root ::= turn\n"
        )
        grammar = (
            root
            + _GRAMMAR_PREFIX
            + f"action ::= ({action_values})\n"
            + f"focus-object ::= {focus_object}\n"
        )
        if move_values:
            grammar += f"move-focus ::= ({move_values})\n"
        return grammar + _GRAMMAR_SUFFIX

    def strip_thinking(self, response, *, enable_thinking):
        if not isinstance(enable_thinking, bool):
            raise ValueError("enable_thinking must be a boolean")
        if not isinstance(response, str):
            raise ValueError("Model response must be text")
        if enable_thinking:
            match = _THINKING_ENVELOPE.fullmatch(response)
            if match is None:
                raise ValueError("Response does not have one bounded thinking envelope")
            candidate = match.group("candidate")
        else:
            candidate = response
        if _THINKING_MARKER.search(candidate):
            raise ValueError("Trace marker remains in response candidate")
        return candidate

    def parse_and_validate(self, candidate):
        try:
            turn = json.loads(
                candidate,
                object_pairs_hook=_strict_json_object,
                parse_constant=_reject_json_constant,
            )
        except _DuplicateJSONKey:
            raise
        except (TypeError, ValueError) as error:
            raise ValueError("Response is not valid JSON") from error
        if _contains_lone_unicode_surrogate(turn):
            raise ValueError("Response contains a lone Unicode surrogate")
        issues = self.validation_issues(turn)
        if issues:
            raise ValueError("Invalid chess-native response: " + ", ".join(issues))
        return turn

    def validation_issues(self, turn):
        if not isinstance(turn, dict):
            return ["shape.turn"]
        if set(turn) != {"message", "actions", "focus"}:
            return ["shape.turnFields"]
        if not isinstance(turn["message"], str):
            return ["shape.message"]
        if not isinstance(turn["actions"], list) or any(
            not isinstance(action, str) for action in turn["actions"]
        ):
            return ["shape.actions"]
        if not isinstance(turn["focus"], list):
            return ["shape.focus"]

        for item in turn["focus"]:
            if not isinstance(item, dict):
                return ["shape.focusObject"]
            if item.get("type") == "square":
                if set(item) != {"type", "square"} or not isinstance(
                    item.get("square"), str
                ):
                    return ["shape.squareFocus"]
            elif item.get("type") == "move":
                if set(item) != {"type", "from", "to"} or any(
                    not isinstance(item.get(key), str) for key in ("from", "to")
                ):
                    return ["shape.moveFocus"]
            else:
                return ["shape.focusObject"]

        issues = []
        message = turn["message"]
        if not message.strip():
            issues.append("message.empty")
        else:
            if len(message.split()) > 18:
                issues.append("message.wordLimitExceeded")
            if _contains_chess_notation(message):
                issues.append("message.chessNotation")

        permitted_actions = set(self.actions)
        unavailable_actions = set()
        for action in turn["actions"]:
            if action not in permitted_actions and action not in unavailable_actions:
                issues.append(f"actions.unavailable:{action}")
                unavailable_actions.add(action)
        seen_actions = set()
        duplicate_actions = set()
        for action in turn["actions"]:
            if action in seen_actions and action not in duplicate_actions:
                issues.append(f"actions.duplicate:{action}")
                duplicate_actions.add(action)
            seen_actions.add(action)
        if len(turn["actions"]) > 3:
            issues.append("actions.limitExceeded")

        permitted_moves = set(self.allowable_moves)
        seen_focus = set()
        duplicate_focus = set()
        invalid_focus = set()
        for item in turn["focus"]:
            if item["type"] == "square":
                identity = ("square", item["square"])
                description = f"square-{item['square']}"
                if (
                    _BOARD_SQUARE.fullmatch(item["square"]) is None
                    and identity not in invalid_focus
                ):
                    issues.append(f"focus.offBoardSquare:{item['square']}")
                    invalid_focus.add(identity)
            else:
                move = (item["from"], item["to"])
                identity = ("move", *move)
                description = f"move-{item['from']}-{item['to']}"
                if (
                    (
                        any(_BOARD_SQUARE.fullmatch(square) is None for square in move)
                        or move not in permitted_moves
                    )
                    and identity not in invalid_focus
                ):
                    issues.append(f"focus.unavailableMove:{item['from']}-{item['to']}")
                    invalid_focus.add(identity)
            if identity in seen_focus and identity not in duplicate_focus:
                issues.append(f"focus.duplicate:{description}")
                duplicate_focus.add(identity)
            seen_focus.add(identity)
        if len(turn["focus"]) > 4:
            issues.append("focus.limitExceeded")
        return issues

    @staticmethod
    def _move_focus_grammar(origin, destination):
        return (
            '"{" space "\\\"type\\\"" space ":" space "\\\"move\\\"" '
            '"," space "\\\"from\\\"" space ":" space '
            f'{_gbnf_json_string(origin)} "," space '
            '"\\\"to\\\"" space ":" space '
            f'{_gbnf_json_string(destination)} space "}}"'
        )


_GRAMMAR_PREFIX = r'''turn ::= "{" space message-kv "," space actions-kv "," space focus-kv space "}"
message-kv ::= "\"message\"" space ":" space message
message ::= "\"" message-space* message-word message-tail{0,17} message-space* "\""
message-tail ::= message-space+ message-word
actions-kv ::= "\"actions\"" space ":" space actions
actions ::= "[" space "]" | "[" space action actions-tail{0,2} space "]"
actions-tail ::= "," space action
focus-kv ::= "\"focus\"" space ":" space focus
focus ::= "[" space "]" | "[" space focus-object focus-tail{0,3} space "]"
focus-tail ::= "," space focus-object
'''

_GRAMMAR_SUFFIX = r'''square-focus ::= "{" space "\"type\"" space ":" space "\"square\"" "," space "\"square\"" space ":" space board-square space "}"
board-square ::= "\"" [a-h] [1-8] "\""
message-word ::= message-char+
message-char ::= [^"\\ \x7F\x00-\x1F] | [\\] ["\\/bf]
message-space ::= [ \t\r\n] | [\\] [nrt]
space ::= [ \t\r\n]*
'''
