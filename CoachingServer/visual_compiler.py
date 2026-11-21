"""Add concise displayed-board grounding to the existing chess context."""

from dataclasses import replace

from Tools.CoachingEval.visual_response import VisualResponseContract


class VisualContextCompiler:
    @staticmethod
    def compile(request, base, prompt_version):
        contract = VisualResponseContract.from_request(request)
        pieces = "; ".join(f"{p['color']} {p['kind']} {p['square']}" for p in contract.pieces)
        attacks = ", ".join(f"{a}->{b}" for a, b in sorted(contract.attacks)) or "none"
        moves = ", ".join(f"{a}-{b}" for a, b in sorted(contract.moves)) or "none"
        # Replace a section emitted by our own deterministic compiler, not model prose.
        position_context = base.markdown.split("## Available UI response\n", 1)[0].rstrip()
        markdown = position_context + (
            "\n\n## Displayed board references\n\n"
            f"Pieces now visible: {pieces or 'unavailable'}\n"
            f"Directed attacks now visible: {attacks}\n"
            "References point to this displayed board; move arrows use the original move below.\n\n"
            "## Available UI response\n\n"
            "Actions: hint\n"
            "Expected response: " + ", ".join(contract.EXPECTED_RESPONSES if contract.has_draft
                                              else contract.EXPECTED_RESPONSES[:3]) + "\n"
            f"Legal move arrows (original board): {moves}\n"
            "Use linked piece/square phrases when they clarify the explanation; no coordinates needed in the prose."
        )
        if contract.has_draft:
            move = request["interaction"]["tentativeMove"]["canonicalMove"]
            markdown += f"\nThe piece from {move[:2]} is displayed on {move[2:4]}; changing its draft needs no reset button."
        if contract.is_hint:
            markdown += "\nHint requested: a discovery question may link one source clue, never its answer."
        return replace(base, prompt_version=prompt_version, markdown=markdown,
                       allowable_moves=tuple(sorted(contract.moves)),
                       expected_responses=contract.EXPECTED_RESPONSES if contract.has_draft
                       else contract.EXPECTED_RESPONSES[:3])
