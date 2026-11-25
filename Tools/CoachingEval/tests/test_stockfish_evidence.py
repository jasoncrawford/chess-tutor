import unittest

import chess
import chess.engine

from Tools.CoachingEval.stockfish_evidence import StockfishEvidence


class EngineDouble:
    id = {"name": "Stockfish test"}

    def __init__(self, replies):
        self.replies = iter(replies)
        self.calls = []

    def configure(self, options):
        pass

    def analyse(self, board, limit, **options):
        self.calls.append((board.copy(), limit, options))
        return next(self.replies)


class StockfishEvidenceTests(unittest.TestCase):
    def request(self):
        board = chess.Board()
        board.push_uci("e2e4")
        displayed = board.copy()
        displayed.push_uci("e7e5")
        return dict(position={"fen": board.fen(en_passant="fen")}, gameHistory=[{"canonicalMove": "e2e4"}],
                    interaction={"tentativeMove": {"canonicalMove": "e7e5"}},
                    tentativePosition={"fen": displayed.fen(en_passant="fen")})

    def info(self, move, score):
        return dict(score=chess.engine.PovScore(score, chess.WHITE), pv=[chess.Move.from_uci(move)], depth=12, nodes=100)

    def test_scores_use_movers_perspective_and_draft_is_restricted_on_original_board(self):
        engine = EngineDouble([[self.info("d7d5", chess.engine.Cp(120))], self.info("e7e5", chess.engine.Mate(-3))])
        analysis = StockfishEvidence(engine, binary_sha256="a" * 64, nodes=100).analyze(self.request())
        self.assertEqual({"centipawns": -120}, analysis["candidates"][0]["score"])
        self.assertEqual({"mate": 3}, analysis["proposed"]["score"])
        self.assertEqual("e7e5", analysis["proposed"]["move"])
        self.assertEqual("fullGame", analysis["historyMode"])
        self.assertEqual([chess.Move.from_uci("e2e4")], engine.calls[1][0].move_stack)
        self.assertEqual(chess.BLACK, engine.calls[1][0].turn)
        self.assertEqual([chess.Move.from_uci("e7e5")], engine.calls[1][2]["root_moves"])
        self.assertEqual(100, engine.calls[1][1].nodes)

    def test_inconsistent_history_and_double_applied_drafts_fail_before_engine_call(self):
        for mutate in [lambda r: r["gameHistory"][0].update(canonicalMove="d2d4"),
                       lambda r: r["interaction"]["tentativeMove"].update(canonicalMove="e5e4")]:
            request = self.request()
            mutate(request)
            engine = EngineDouble([])
            with self.assertRaises(ValueError):
                StockfishEvidence(engine, binary_sha256="a" * 64).analyze(request)
            self.assertEqual([], engine.calls)

    def test_engine_lines_are_legal_and_terminal_mate_is_not_a_centipawn_number(self):
        engine = EngineDouble([[self.info("e7e4", chess.engine.Cp(10))]])
        with self.assertRaises(ValueError):
            StockfishEvidence(engine, binary_sha256="a" * 64).analyze(self.request())
        info = self.info("d7d5", chess.engine.Mate(0))
        engine = EngineDouble([[info], self.info("e7e5", chess.engine.Cp(0))])
        result = StockfishEvidence(engine, binary_sha256="a" * 64).analyze(self.request())
        self.assertEqual({"mate": 0}, result["candidates"][0]["score"])

    def test_stopped_search_preserves_score_bounds_in_normalized_perspective(self):
        bounded = dict(self.info("d7d5", chess.engine.Cp(120)), upperbound=True)
        engine = EngineDouble([[bounded], self.info("e7e5", chess.engine.Cp(10))])
        result = StockfishEvidence(engine, binary_sha256="a" * 64).analyze(self.request())
        self.assertEqual("lower", result["candidates"][0]["bound"])
        self.assertEqual({"centipawns": -120}, result["candidates"][0]["score"])


if __name__ == "__main__":
    unittest.main()
