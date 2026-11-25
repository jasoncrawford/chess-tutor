"""Bind frozen, locally generated engine evidence to the exact benchmark inputs."""

import hashlib
import json
import math
from dataclasses import replace
from pathlib import Path


class EngineContext:
    def __init__(self, path, corpus):
        data = Path(path).read_bytes()
        raw = json.loads(data)
        self.sha256 = hashlib.sha256(data).hexdigest()
        self.corpus_sha256 = corpus.sha256
        if raw.get("schemaVersion") != "coaching-engine-evidence.v1" or raw.get("corpusSHA256") != corpus.sha256:
            raise ValueError("Engine evidence corpus binding changed")
        entries = raw["entries"]
        self._entries = {entry["caseID"]: entry for entry in entries}
        if len(self._entries) != len(entries) or set(self._entries) != {turn.identifier for turn in corpus.turns}:
            raise ValueError("Engine evidence must cover exactly this corpus")
        self.metadata = raw["metadata"]
        for turn in corpus.turns:
            entry = self._entries[turn.identifier]
            sha = hashlib.sha256(json.dumps(turn.request, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
            analysis = entry["analysis"]
            draft = (turn.request["interaction"].get("tentativeMove") or {}).get("canonicalMove")
            side = "white" if turn.request["position"]["fen"].split()[1] == "w" else "black"
            elapsed = analysis["analysisMilliseconds"]
            if (entry["requestSHA256"] != sha or analysis["positionFEN"] != turn.request["position"]["fen"]
                    or analysis["draft"] != draft or analysis["sideToMove"] != side
                    or type(elapsed) not in (int, float) or not math.isfinite(elapsed) or elapsed < 0
                    or not 1 <= len(analysis["candidates"]) <= 3):
                raise ValueError("Engine evidence request/position binding changed")

    def augment(self, turn, compilation):
        analysis = self._entries[turn.identifier]["analysis"]
        text = ["", "## Optional engine cross-check",
                f"{self.metadata['engine']}; {self.metadata['nodesPerSearch']} nodes per search, 1 thread. Scores favor {analysis['sideToMove']} when positive.",
                "Scores are approximate pawn units, not a child's win probability. Small differences are not reasons to reject a sound move. Sample continuations are not forced; verify any explanation on the board."]
        for index, line in enumerate(analysis["candidates"], 1):
            text.append(self._line(f"Candidate {index}", line))
        if analysis["proposed"]:
            text.append(self._line("Child's proposed move (searched from the same original position)", analysis["proposed"]))
        return replace(compilation, markdown=compilation.markdown + "\n".join(text) + "\n")

    def analysis_milliseconds(self, case_id):
        return self._entries[case_id]["analysis"]["analysisMilliseconds"]

    @staticmethod
    def _line(label, line):
        score = line["score"]
        if set(score) == {"centipawns"} and type(score["centipawns"]) is int:
            value = f"{score['centipawns'] / 100:+.2f}"
        elif set(score) == {"mate"} and type(score["mate"]) is int:
            mate = score["mate"]
            value = f"can mate in {mate}" if mate > 0 else f"opponent can mate in {abs(mate)}"
        else:
            raise ValueError("Invalid engine score")
        bound = line.get("bound", "exact")
        if bound not in ("exact", "lower", "upper"):
            raise ValueError("Invalid engine score bound")
        if bound != "exact":
            value += f" ({bound} bound, not an exact score)"
        notation = line["notation"]
        if not isinstance(notation, list) or not 1 <= len(notation) <= 5:
            raise ValueError("Engine continuation exceeds its bound")
        return f"{label}: {line['move']}, {value}; sample {' '.join(notation)}; depth {line['depth']}."
