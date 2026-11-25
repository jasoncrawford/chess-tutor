"""Local, bounded Stockfish evidence for benchmark experiments (not deployed)."""

import argparse
import hashlib
import json
import time
from pathlib import Path

import chess
import chess.engine

from Tools.CoachingEval.benchmark.corpus import load_corpus


class StockfishEvidence:
    def __init__(self, engine, *, binary_sha256, nodes=200_000):
        if type(nodes) is not int or not 1 <= nodes <= 2_000_000:
            raise ValueError("Engine node budget must be between 1 and 2,000,000")
        self.engine = engine
        self.nodes = nodes
        self.metadata = dict(engine=engine.id["name"], binarySHA256=binary_sha256,
                             libraryVersion=chess.__version__, threads=1, hashMB=64,
                             nodesPerSearch=nodes, multiPV=3, maximumLinePlies=5)
        engine.configure({"Threads": 1, "Hash": 64})

    def analyze(self, request):
        fen = request["position"]["fen"]
        board = chess.Board(fen)
        if not board.is_valid():
            raise ValueError("Invalid chess position")
        history = request["gameHistory"]
        if history:
            board = chess.Board()
            for item in history:
                board.push_uci(item["canonicalMove"])
            if board.fen(en_passant="fen") != fen:
                raise ValueError("Game history does not reach the committed FEN")
        draft = request["interaction"].get("tentativeMove")
        proposed = chess.Move.from_uci(draft["canonicalMove"]) if draft else None
        if proposed is not None:
            if proposed not in board.legal_moves:
                raise ValueError("Draft is not legal on the committed board")
            displayed = board.copy()
            displayed.push(proposed)
            supplied = request.get("tentativePosition") or {}
            if supplied.get("fen") and supplied["fen"] != displayed.fen(en_passant="fen"):
                raise ValueError("Displayed draft does not match one application of the move")
        started = time.monotonic()
        self.engine.configure({"Clear Hash": None})
        top = self.engine.analyse(board, chess.engine.Limit(nodes=self.nodes), multipv=3, game=object())
        candidates = [self._line(board, info) for info in top]
        selected = None
        if proposed:
            self.engine.configure({"Clear Hash": None})
            info = self.engine.analyse(board, chess.engine.Limit(nodes=self.nodes),
                                       root_moves=[proposed], game=object())
            selected = self._line(board, info)
            if selected["move"] != proposed.uci():
                raise ValueError("Engine did not evaluate the requested root move")
        return dict(positionFEN=fen, sideToMove="white" if board.turn else "black",
                    historyMode="fullGame" if history else "fenOnly", draft=proposed.uci() if proposed else None,
                    candidates=candidates, proposed=selected,
                    analysisMilliseconds=round((time.monotonic() - started) * 1000, 3))

    @staticmethod
    def _line(board, info):
        if not info.get("pv"):
            raise ValueError("Engine returned incomplete evidence")
        bound = "lower" if info.get("lowerbound") else "upper" if info.get("upperbound") else "exact"
        if info["score"].turn != board.turn:
            bound = {"lower": "upper", "upper": "lower", "exact": "exact"}[bound]
        score = info["score"].pov(board.turn)
        value = {"mate": score.mate()} if score.is_mate() else {"centipawns": score.score()}
        position = board.copy()
        moves, notation = [], []
        for move in info["pv"][:5]:
            if move not in position.legal_moves:
                raise ValueError("Engine returned an illegal continuation")
            moves.append(move.uci())
            notation.append(position.san(move))
            position.push(move)
        return dict(move=moves[0], score=value, bound=bound, line=moves, notation=notation,
                    depth=info["depth"], nodes=info["nodes"])


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", required=True, type=Path)
    parser.add_argument("--engine", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--nodes", type=int, default=200_000)
    args = parser.parse_args(argv)
    if args.output.exists():
        raise FileExistsError("Refusing to overwrite frozen engine evidence")
    corpus = load_corpus(args.corpus)
    binary_sha = hashlib.sha256(args.engine.read_bytes()).hexdigest()
    with chess.engine.SimpleEngine.popen_uci(str(args.engine.resolve()), timeout=15) as engine:
        analyzer = StockfishEvidence(engine, binary_sha256=binary_sha, nodes=args.nodes)
        entries = []
        for turn in corpus.turns:
            request_sha = hashlib.sha256(json.dumps(turn.request, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
            entries.append(dict(caseID=turn.identifier, requestSHA256=request_sha, analysis=analyzer.analyze(turn.request)))
        artifact = dict(schemaVersion="coaching-engine-evidence.v1", corpusSHA256=corpus.sha256,
                        metadata=analyzer.metadata, entries=entries)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x") as file:
        json.dump(artifact, file, indent=2)
        file.write("\n")
    print(f"Saved {len(entries)} engine analyses to {args.output}; no model calls.")


if __name__ == "__main__":
    main()
