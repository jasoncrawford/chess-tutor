"""Strict, deterministic renderer for chess-native coaching requests."""

from __future__ import annotations

import dataclasses
import re
from collections.abc import Mapping
from typing import Any


_SQUARE = re.compile(r"[a-h][1-8]\Z")
_CANONICAL_MOVE = re.compile(r"[a-h][1-8][a-h][1-8][qrbn]?\Z")
_IDENTIFIER = re.compile(r"[A-Za-z0-9:._+=>#-]{1,512}\Z")
_SAN = re.compile(
    r"(?:O-O(?:-O)?|[KQRBN]?[a-h]?[1-8]?x?[a-h][1-8](?:=[QRBN])?)[+#]?\Z"
)
_STATUS = re.compile(r"(?:ongoing|stalemate|checkmate:(?:white|black))\Z")
_CASTLING = re.compile(r"(?:-|K?Q?k?q?)\Z")
_REQUEST_FIELDS = {
    "schemaVersion",
    "requestID",
    "positionRevision",
    "position",
    "gameHistory",
    "interaction",
    "pieces",
    "legalMoves",
    "occupiedSquareRelationships",
    "tentativeReplies",
    "capabilities",
}
_EVENT_KINDS = {
    "helpOpened",
    "helpReopened",
    "pieceSelected",
    "squareInspected",
    "moveStaged",
    "moveReplaced",
    "moveRemoved",
    "actionChosen",
    "helpClosed",
}
_RELATIONSHIP_KINDS = {
    "attacks",
    "defends",
    "checks",
    "canCapture",
    "canRecapture",
}


@dataclasses.dataclass(frozen=True)
class ChessNativeCompilation:
    request_id: str
    position_revision: int
    prompt_version: str
    markdown: str
    actions: tuple[str, ...]
    allowable_moves: tuple[tuple[str, str], ...]


def compile_context(
    request: Mapping[str, object],
    prompt_version: str,
) -> ChessNativeCompilation:
    parsed = _parse_neutral_request(request)
    prompt_version = _nonempty_string(prompt_version, "promptVersion")
    pieces_by_id = {piece["id"]: piece for piece in parsed["pieces"]}
    scoped_replies = _replies_for_current_interaction(parsed, pieces_by_id)
    actions = _available_actions(parsed)
    allowable_moves = _available_move_focus(parsed, scoped_replies)

    sections = (
        ("Position", _position_lines(parsed)),
        ("Latest interaction", _latest_interaction_lines(parsed, pieces_by_id)),
        (
            "Relevant legal facts",
            _relevant_legal_fact_lines(parsed, pieces_by_id, scoped_replies),
        ),
        (
            "Available UI response",
            _available_response_lines(actions, allowable_moves),
        ),
    )
    markdown = "# Chess coaching situation\n\n" + "\n\n".join(
        "## " + heading + "\n\n" + "\n".join(lines)
        for heading, lines in sections
    )
    return ChessNativeCompilation(
        request_id=parsed["requestID"],
        position_revision=parsed["positionRevision"],
        prompt_version=prompt_version,
        markdown=markdown,
        actions=actions,
        allowable_moves=allowable_moves,
    )


def parse_neutral_request(request: Mapping[str, object]) -> dict[str, Any]:
    """Validate one request and return a detached, normalized mapping."""
    return _parse_neutral_request(request)


def _parse_neutral_request(request: Mapping[str, object]) -> dict[str, Any]:
    root = _object(request, "request")
    _exact_fields(root, _REQUEST_FIELDS, "request")
    if root["schemaVersion"] != "model-coaching-neutral-request.v1":
        raise ValueError("Unsupported neutral request schema version")

    request_id = _identifier(root["requestID"], "request.requestID")
    position_revision = _nonnegative_int(
        root["positionRevision"], "request.positionRevision"
    )
    position = _parse_position(root["position"])
    history = _parse_history(root["gameHistory"])
    interaction = _parse_interaction(root["interaction"])
    pieces = tuple(_parse_piece(value, index) for index, value in enumerate(_array(root["pieces"], "request.pieces")))
    _unique((piece["id"] for piece in pieces), "piece IDs")
    piece_ids = {piece["id"] for piece in pieces}

    legal_moves = tuple(
        _parse_move(value, f"request.legalMoves[{index}]", piece_ids)
        for index, value in enumerate(_array(root["legalMoves"], "request.legalMoves"))
    )
    _unique((move["id"] for move in legal_moves), "legal move IDs")
    relationships = tuple(
        _parse_relationship(value, index, piece_ids)
        for index, value in enumerate(
            _array(root["occupiedSquareRelationships"], "request.occupiedSquareRelationships")
        )
    )
    _unique((relationship["id"] for relationship in relationships), "relationship IDs")
    replies = tuple(
        _parse_reply(value, index, piece_ids)
        for index, value in enumerate(_array(root["tentativeReplies"], "request.tentativeReplies"))
    )
    _unique((reply["move"]["id"] for reply in replies), "reply move IDs")
    capabilities = _parse_capabilities(root["capabilities"])

    selected_id = interaction["selectedPieceReference"]
    if selected_id is not None and selected_id not in piece_ids:
        raise ValueError("Selected piece reference is unknown")
    tentative = interaction["tentativeMove"]
    if tentative is not None:
        tentative = _parse_move(tentative, "request.interaction.tentativeMove", piece_ids)
        interaction = dict(interaction, tentativeMove=tentative)

    return {
        "schemaVersion": root["schemaVersion"],
        "requestID": request_id,
        "positionRevision": position_revision,
        "position": position,
        "gameHistory": history,
        "interaction": interaction,
        "pieces": pieces,
        "legalMoves": legal_moves,
        "occupiedSquareRelationships": relationships,
        "tentativeReplies": replies,
        "capabilities": capabilities,
    }


def _parse_position(value: object) -> dict[str, Any]:
    item = _object(value, "request.position")
    _exact_fields(item, {"fen", "sideToMove", "status"}, "request.position")
    side = _enum(item["sideToMove"], {"white", "black"}, "request.position.sideToMove")
    return {
        "fen": _fen(item["fen"], "request.position.fen"),
        "sideToMove": side,
        "status": _status(item["status"], "request.position.status"),
    }


def _parse_history(value: object) -> tuple[dict[str, Any], ...]:
    history = []
    expected_ply = 1
    for index, raw in enumerate(_array(value, "request.gameHistory")):
        item = _object(raw, f"request.gameHistory[{index}]")
        _exact_fields(item, {"ply", "canonicalMove", "displayNotation"}, f"request.gameHistory[{index}]")
        ply = _positive_int(item["ply"], f"request.gameHistory[{index}].ply")
        if ply != expected_ply:
            raise ValueError("Game history plies must be sequential")
        expected_ply += 1
        history.append({
            "ply": ply,
            "canonicalMove": _canonical_move(item["canonicalMove"], f"request.gameHistory[{index}].canonicalMove"),
            "displayNotation": _san(item["displayNotation"], f"request.gameHistory[{index}].displayNotation"),
        })
    return tuple(history)


def _parse_interaction(value: object) -> dict[str, Any]:
    item = _object(value, "request.interaction")
    _fields(
        item,
        required={"latestEvent", "episodeEvents"},
        optional={"selectedSquare", "selectedPieceReference", "tentativeMove"},
        path="request.interaction",
    )
    selected_square = _optional_square(item.get("selectedSquare"), "request.interaction.selectedSquare")
    selected_piece = _optional_identifier(item.get("selectedPieceReference"), "request.interaction.selectedPieceReference")
    latest = _parse_event(item["latestEvent"], "request.interaction.latestEvent")
    events = tuple(
        _parse_event(raw, f"request.interaction.episodeEvents[{index}]")
        for index, raw in enumerate(_array(item["episodeEvents"], "request.interaction.episodeEvents"))
    )
    sequences = [event["sequence"] for event in events]
    if sequences != sorted(sequences) or len(sequences) != len(set(sequences)):
        raise ValueError("Episode event sequences must be unique and ordered")
    if not events or latest != events[-1]:
        raise ValueError("Latest event must be the final episode event")
    tentative = item.get("tentativeMove")
    if tentative is not None and not isinstance(tentative, Mapping):
        raise ValueError("request.interaction.tentativeMove must be an object or null")
    return {
        "selectedSquare": selected_square,
        "selectedPieceReference": selected_piece,
        "tentativeMove": tentative,
        "latestEvent": latest,
        "episodeEvents": events,
    }


def _parse_event(value: object, path: str) -> dict[str, Any]:
    item = _object(value, path)
    _exact_fields(item, {"sequence", "kind", "referencedIDs"}, path)
    references = tuple(
        _identifier(reference, f"{path}.referencedIDs[{index}]")
        for index, reference in enumerate(_array(item["referencedIDs"], f"{path}.referencedIDs"))
    )
    return {
        "sequence": _positive_int(item["sequence"], f"{path}.sequence"),
        "kind": _enum(item["kind"], _EVENT_KINDS, f"{path}.kind"),
        "referencedIDs": references,
    }


def _parse_piece(value: object, index: int) -> dict[str, str]:
    path = f"request.pieces[{index}]"
    item = _object(value, path)
    _exact_fields(item, {"id", "color", "kind", "square"}, path)
    return {
        "id": _identifier(item["id"], f"{path}.id"),
        "color": _enum(item["color"], {"white", "black"}, f"{path}.color"),
        "kind": _enum(item["kind"], {"king", "queen", "rook", "bishop", "knight", "pawn"}, f"{path}.kind"),
        "square": _square(item["square"], f"{path}.square"),
    }


def _parse_move(value: object, path: str, piece_ids: set[str]) -> dict[str, Any]:
    item = _object(value, path)
    _fields(
        item,
        required={"id", "san", "canonicalMove", "sourcePieceReference", "destinationSquare", "special", "isLegal", "givesCheck", "givesCheckmate"},
        optional={"capturePieceReference"},
        path=path,
    )
    source = _identifier(item["sourcePieceReference"], f"{path}.sourcePieceReference")
    capture = _optional_identifier(item.get("capturePieceReference"), f"{path}.capturePieceReference")
    if source not in piece_ids:
        raise ValueError(f"{path} contains an unknown source piece reference")
    canonical = _canonical_move(item["canonicalMove"], f"{path}.canonicalMove")
    destination = _square(item["destinationSquare"], f"{path}.destinationSquare")
    if canonical[2:4] != destination:
        raise ValueError(f"{path} destination does not match canonical move")
    return {
        "id": _identifier(item["id"], f"{path}.id"),
        "san": _san(item["san"], f"{path}.san"),
        "canonicalMove": canonical,
        "sourcePieceReference": source,
        "destinationSquare": destination,
        "capturePieceReference": capture,
        "special": _enum(
            item["special"],
            {"none", "castle-kingside", "castle-queenside", "en-passant", "promote-queen", "promote-rook", "promote-bishop", "promote-knight"},
            f"{path}.special",
        ),
        "isLegal": _boolean(item["isLegal"], f"{path}.isLegal"),
        "givesCheck": _boolean(item["givesCheck"], f"{path}.givesCheck"),
        "givesCheckmate": _boolean(item["givesCheckmate"], f"{path}.givesCheckmate"),
    }


def _parse_relationship(value: object, index: int, piece_ids: set[str]) -> dict[str, str]:
    path = f"request.occupiedSquareRelationships[{index}]"
    item = _object(value, path)
    _exact_fields(item, {"id", "kind", "sourcePieceReference", "targetPieceReference"}, path)
    source = _identifier(item["sourcePieceReference"], f"{path}.sourcePieceReference")
    target = _identifier(item["targetPieceReference"], f"{path}.targetPieceReference")
    if source not in piece_ids or target not in piece_ids:
        raise ValueError(f"{path} contains an unknown piece reference")
    return {
        "id": _identifier(item["id"], f"{path}.id"),
        "kind": _enum(item["kind"], _RELATIONSHIP_KINDS, f"{path}.kind"),
        "sourcePieceReference": source,
        "targetPieceReference": target,
    }


def _parse_reply(value: object, index: int, piece_ids: set[str]) -> dict[str, Any]:
    path = f"request.tentativeReplies[{index}]"
    item = _object(value, path)
    _exact_fields(item, {"move", "directRelationships"}, path)
    move = _parse_move(item["move"], f"{path}.move", piece_ids)
    direct = tuple(
        _parse_reply_relationship(raw, f"{path}.directRelationships[{child_index}]")
        for child_index, raw in enumerate(_array(item["directRelationships"], f"{path}.directRelationships"))
    )
    return {"move": move, "directRelationships": direct}


def _parse_reply_relationship(value: object, path: str) -> dict[str, Any]:
    item = _object(value, path)
    _exact_fields(item, {"id", "phase", "kind", "sourcePiece", "targetPiece"}, path)
    return {
        "id": _identifier(item["id"], f"{path}.id"),
        "phase": _enum(item["phase"], {"afterTentative", "afterReply"}, f"{path}.phase"),
        "kind": _enum(item["kind"], _RELATIONSHIP_KINDS, f"{path}.kind"),
        "sourcePiece": _parse_embedded_piece(item["sourcePiece"], f"{path}.sourcePiece"),
        "targetPiece": _parse_embedded_piece(item["targetPiece"], f"{path}.targetPiece"),
    }


def _parse_embedded_piece(value: object, path: str) -> dict[str, str]:
    item = _object(value, path)
    _exact_fields(item, {"id", "color", "kind", "square"}, path)
    return {
        "id": _identifier(item["id"], f"{path}.id"),
        "color": _enum(item["color"], {"white", "black"}, f"{path}.color"),
        "kind": _enum(item["kind"], {"king", "queen", "rook", "bishop", "knight", "pawn"}, f"{path}.kind"),
        "square": _square(item["square"], f"{path}.square"),
    }


def _parse_capabilities(value: object) -> dict[str, bool]:
    path = "request.capabilities"
    item = _object(value, path)
    fields = {"canSelectBoardPiece", "canInspectSquare", "canStageMove", "canReplaceMove", "canRemoveMove"}
    _exact_fields(item, fields, path)
    return {key: _boolean(item[key], f"{path}.{key}") for key in sorted(fields)}


def _position_lines(request: dict[str, Any]) -> tuple[str, ...]:
    history = request["gameHistory"]
    return (
        f"Side to move: {_display_color(request['position']['sideToMove'])}",
        f"Status: {request['position']['status']}",
        f"FEN: {request['position']['fen']}",
        "Moves: " + (" ".join(move["displayNotation"] for move in history) if history else "none"),
        "Tentative move: " + (request["interaction"]["tentativeMove"]["san"] if request["interaction"]["tentativeMove"] else "none"),
    )


def _latest_interaction_lines(request: dict[str, Any], pieces_by_id: dict[str, Any]) -> tuple[str, ...]:
    interaction = request["interaction"]
    event = interaction["latestEvent"]
    kind = event["kind"]
    actor = _display_color(request["position"]["sideToMove"])
    if kind == "helpOpened":
        line = "Help opened."
    elif kind == "helpReopened":
        line = "Help reopened."
    elif kind == "pieceSelected":
        piece_id = interaction["selectedPieceReference"] or _first(event["referencedIDs"])
        line = f"{actor} selected {_selected_piece_with_article(piece_id, pieces_by_id)}."
    elif kind == "squareInspected":
        line = f"The child tapped {_piece_with_article(_first(event['referencedIDs']), pieces_by_id)}."
    elif kind == "moveStaged":
        line = f"{actor} tentatively played {_current_or_event_move(request, event)}."
    elif kind == "moveReplaced":
        prior = [candidate for candidate in interaction["episodeEvents"] if candidate["sequence"] < event["sequence"] and candidate["kind"] in {"moveStaged", "moveReplaced"}]
        old_id = _first(max(prior, key=lambda candidate: candidate["sequence"])["referencedIDs"]) if prior else None
        line = f"{actor} replaced {_move_notation(old_id, request)} with {_current_or_event_move(request, event)}."
    elif kind == "moveRemoved":
        line = f"{actor} removed {_move_notation(_first(event['referencedIDs']), request)}."
    elif kind == "actionChosen":
        reference = _first(event["referencedIDs"])
        action = reference.split(":", 1)[-1] if reference else "an action"
        line = f"The child chose {action}."
    else:
        line = "Help closed."
    return (line,)


def _relevant_legal_fact_lines(request: dict[str, Any], pieces_by_id: dict[str, Any], scoped_replies: tuple[dict[str, Any], ...]) -> tuple[str, ...]:
    lines = [_check_status_line(request)]
    interaction = request["interaction"]
    tentative = interaction["tentativeMove"]
    if tentative:
        lines.append(f"Tentative move {tentative['san']} is {'legal' if tentative['isLegal'] else 'not legal'}.")
        inspected_id = _inspected_piece_id(request, pieces_by_id)
        if inspected_id:
            lines.append(f"Inspected piece: {_piece_label(inspected_id, pieces_by_id)}")
            lines.append(f"Matching immediate replies: {_move_list(scoped_replies)}")
        else:
            lines.append(f"Opponent immediate replies that capture, check, or mate: {_move_list(scoped_replies)}")
    elif interaction["selectedPieceReference"]:
        selected_id = interaction["selectedPieceReference"]
        selected = _piece_label(selected_id, pieces_by_id)
        moves = sorted((move for move in request["legalMoves"] if move["sourcePieceReference"] == selected_id), key=lambda move: move["id"])
        lines.extend((f"Selected piece: {selected}", f"Legal moves for {selected}: {_move_list(moves)}"))
    return tuple(lines)


def _available_response_lines(actions: tuple[str, ...], moves: tuple[tuple[str, str], ...]) -> tuple[str, ...]:
    return (
        "Actions: " + (", ".join(actions) if actions else "none"),
        "Square focus: any board square",
        "Allowable move focus: " + (", ".join(f"{origin}-{destination}" for origin, destination in moves) if moves else "none"),
    )


def _available_actions(request: dict[str, Any]) -> tuple[str, ...]:
    actions = ["hint"]
    tentative = request["interaction"]["tentativeMove"]
    if tentative and tentative["isLegal"]:
        actions.append("playMove")
    capabilities = request["capabilities"]
    if capabilities["canReplaceMove"] or capabilities["canRemoveMove"]:
        actions.append("tryAnotherMove")
    return tuple(actions)


def _available_move_focus(request: dict[str, Any], scoped_replies: tuple[dict[str, Any], ...]) -> tuple[tuple[str, str], ...]:
    interaction = request["interaction"]
    if interaction["tentativeMove"]:
        moves = (interaction["tentativeMove"],) + tuple(reply["move"] for reply in scoped_replies)
    elif interaction["selectedPieceReference"]:
        moves = tuple(sorted((move for move in request["legalMoves"] if move["sourcePieceReference"] == interaction["selectedPieceReference"]), key=lambda move: move["id"]))
    else:
        moves = ()
    result = []
    for move in moves:
        focus = (move["canonicalMove"][:2], move["canonicalMove"][2:4])
        if focus not in result:
            result.append(focus)
    return tuple(result)


def _replies_for_current_interaction(request: dict[str, Any], pieces_by_id: dict[str, Any]) -> tuple[dict[str, Any], ...]:
    replies = tuple(sorted(request["tentativeReplies"], key=lambda reply: reply["move"]["id"]))
    inspected_id = _inspected_piece_id(request, pieces_by_id)
    if not inspected_id:
        return replies
    return tuple(reply for reply in replies if reply["move"]["sourcePieceReference"] == inspected_id)


def _inspected_piece_id(request: dict[str, Any], pieces_by_id: dict[str, Any]) -> str | None:
    interaction = request["interaction"]
    event = interaction["latestEvent"]
    inspected_id = _first(event["referencedIDs"])
    piece = pieces_by_id.get(inspected_id)
    if event["kind"] != "squareInspected" or interaction["tentativeMove"] is None or not piece or piece["color"] == request["position"]["sideToMove"]:
        return None
    return inspected_id


def _check_status_line(request: dict[str, Any]) -> str:
    side = _display_color(request["position"]["sideToMove"])
    status = request["position"]["status"]
    if status == "stalemate":
        return f"{side} is in stalemate."
    if status.startswith("checkmate:"):
        return f"{side} is in checkmate."
    king_ids = [piece["id"] for piece in request["pieces"] if piece["color"] == request["position"]["sideToMove"] and piece["kind"] == "king"]
    king_id = king_ids[0] if king_ids else None
    in_check = bool(king_id and any(relationship["kind"] == "checks" and relationship["targetPieceReference"] == king_id for relationship in request["occupiedSquareRelationships"]))
    return f"{side} is {'' if in_check else 'not '}in check."


def _move_notation(move_id: str | None, request: dict[str, Any]) -> str:
    if move_id is None:
        return "an unknown move"
    moves = list(request["legalMoves"]) + [reply["move"] for reply in request["tentativeReplies"]]
    if request["interaction"]["tentativeMove"]:
        moves.append(request["interaction"]["tentativeMove"])
    for move in moves:
        if move["id"] == move_id:
            return move["san"]
    return move_id.removeprefix("move:") if move_id.startswith("move:") else move_id


def _current_or_event_move(request: dict[str, Any], event: dict[str, Any]) -> str:
    tentative = request["interaction"]["tentativeMove"]
    return tentative["san"] if tentative else _move_notation(_first(event["referencedIDs"]), request)


def _move_list(moves: Any) -> str:
    values = [item["move"]["san"] if "move" in item else item["san"] for item in moves]
    return ", ".join(values) if values else "none"


def _piece_label(piece_id: str, pieces_by_id: dict[str, Any]) -> str:
    piece = pieces_by_id.get(piece_id)
    return f"{_display_color(piece['color'])} {piece['kind']} on {piece['square']}" if piece else piece_id


def _piece_with_article(piece_id: str | None, pieces_by_id: dict[str, Any]) -> str:
    piece = pieces_by_id.get(piece_id)
    return f"the {piece['color']} {piece['kind']} on {piece['square']}" if piece else "the piece"


def _selected_piece_with_article(piece_id: str | None, pieces_by_id: dict[str, Any]) -> str:
    piece = pieces_by_id.get(piece_id)
    return f"the {piece['kind']} on {piece['square']}" if piece else "the piece"


def _display_color(value: str) -> str:
    return value[:1].upper() + value[1:]


def _first(values: tuple[str, ...]) -> str | None:
    return values[0] if values else None


def _object(value: object, path: str) -> dict[str, Any]:
    if not isinstance(value, Mapping):
        raise ValueError(f"{path} must be an object")
    if any(not isinstance(key, str) for key in value):
        raise ValueError(f"{path} keys must be strings")
    return dict(value)


def _array(value: object, path: str) -> list[object]:
    if not isinstance(value, list):
        raise ValueError(f"{path} must be an array")
    return value


def _exact_fields(value: dict[str, Any], expected: set[str], path: str) -> None:
    actual = set(value)
    if actual != expected:
        raise ValueError(f"{path} fields do not match the contract")


def _fields(
    value: dict[str, Any],
    required: set[str],
    optional: set[str],
    path: str,
) -> None:
    actual = set(value)
    if not required.issubset(actual) or not actual.issubset(required | optional):
        raise ValueError(f"{path} fields do not match the contract")


def _nonempty_string(value: object, path: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{path} must be a nonempty string")
    if len(value.encode("utf-8")) > 512 or any(
        ord(character) < 0x20 or ord(character) == 0x7F for character in value
    ):
        raise ValueError(f"{path} contains unsupported text")
    return value


def _optional_string(value: object, path: str) -> str | None:
    return None if value is None else _nonempty_string(value, path)


def _identifier(value: object, path: str) -> str:
    result = _nonempty_string(value, path)
    if _IDENTIFIER.fullmatch(result) is None:
        raise ValueError(f"{path} must be a canonical identifier")
    return result


def _optional_identifier(value: object, path: str) -> str | None:
    return None if value is None else _identifier(value, path)


def _san(value: object, path: str) -> str:
    result = _nonempty_string(value, path)
    if _SAN.fullmatch(result) is None:
        raise ValueError(f"{path} must be standard chess notation")
    return result


def _status(value: object, path: str) -> str:
    result = _nonempty_string(value, path)
    if _STATUS.fullmatch(result) is None:
        raise ValueError(f"{path} must be a canonical game status")
    return result


def _fen(value: object, path: str) -> str:
    result = _nonempty_string(value, path)
    fields = result.split(" ")
    if len(fields) != 6:
        raise ValueError(f"{path} must be a canonical FEN")
    board, side, castling, en_passant, halfmove, fullmove = fields
    ranks = board.split("/")
    if len(ranks) != 8 or any(not _valid_fen_rank(rank) for rank in ranks):
        raise ValueError(f"{path} must be a canonical FEN")
    if side not in {"w", "b"} or _CASTLING.fullmatch(castling) is None:
        raise ValueError(f"{path} must be a canonical FEN")
    if en_passant != "-" and re.fullmatch(r"[a-h][36]", en_passant) is None:
        raise ValueError(f"{path} must be a canonical FEN")
    if not _canonical_decimal(halfmove, allow_zero=True) or not _canonical_decimal(fullmove, allow_zero=False):
        raise ValueError(f"{path} must be a canonical FEN")
    return result


def _valid_fen_rank(rank: str) -> bool:
    if not rank or re.fullmatch(r"[prnbqkPRNBQK1-8]+", rank) is None:
        return False
    return sum(int(token) if token.isdigit() else 1 for token in rank) == 8


def _canonical_decimal(value: str, *, allow_zero: bool) -> bool:
    if re.fullmatch(r"0|[1-9][0-9]*", value) is None:
        return False
    return allow_zero or value != "0"


def _square(value: object, path: str) -> str:
    result = _nonempty_string(value, path)
    if _SQUARE.fullmatch(result) is None:
        raise ValueError(f"{path} must be a board square")
    return result


def _optional_square(value: object, path: str) -> str | None:
    return None if value is None else _square(value, path)


def _canonical_move(value: object, path: str) -> str:
    result = _nonempty_string(value, path)
    if _CANONICAL_MOVE.fullmatch(result) is None:
        raise ValueError(f"{path} must be a canonical move")
    return result


def _enum(value: object, allowed: set[str], path: str) -> str:
    result = _nonempty_string(value, path)
    if result not in allowed:
        raise ValueError(f"{path} has an unsupported value")
    return result


def _boolean(value: object, path: str) -> bool:
    if not isinstance(value, bool):
        raise ValueError(f"{path} must be a boolean")
    return value


def _nonnegative_int(value: object, path: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise ValueError(f"{path} must be a nonnegative integer")
    return value


def _positive_int(value: object, path: str) -> int:
    result = _nonnegative_int(value, path)
    if result == 0:
        raise ValueError(f"{path} must be positive")
    return result


def _unique(values: Any, description: str) -> None:
    values = list(values)
    if len(values) != len(set(values)):
        raise ValueError(f"Duplicate {description}")
