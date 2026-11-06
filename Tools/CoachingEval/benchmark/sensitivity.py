"""Check that the real judge detects retained coaching failures and accepts controls."""

import hashlib
import json
import os
from pathlib import Path

from CoachingServer.chess_native_compiler import compile_context
from Tools.CoachingEval.benchmark.grader import absolute_payload
from Tools.CoachingEval.benchmark.judge_contract import (
    RUBRIC_DIMENSIONS, RUBRIC_FLAGS, absolute_schema, judge_call, validate_absolute,
)
from Tools.CoachingEval.chess_native_response import ChessNativeResponseContract


class JudgeSensitivity:
    @classmethod
    def run(cls, controls_path, corpus, judge, client, prices, destination):
        destination = Path(destination)
        if destination.exists():
            raise FileExistsError("Refusing to overwrite judge sensitivity evidence")
        control_bytes = Path(controls_path).read_bytes()
        controls = json.loads(control_bytes)
        if (set(controls) != {"schemaVersion", "provenance", "cases"}
                or controls["schemaVersion"] != "coaching-judge-sensitivity.v1"
                or not isinstance(controls["cases"], list) or not controls["cases"]):
            raise ValueError("Invalid judge sensitivity controls")
        cases = controls["cases"]
        if len({row["id"] for row in cases}) != len(cases):
            raise ValueError("Duplicate sensitivity IDs")
        payloads = [cls._payload(row, corpus) for row in cases]
        destination.mkdir(parents=True)
        rows = []
        for repetition in range(1, 4):
            for control, payload in zip(cases, payloads):
                output, metrics = judge_call(judge, client, payload, absolute_schema(), prices)
                grade = validate_absolute(output)
                passed = cls._matches(control, grade)
                row = dict(id=control["id"], repetition=repetition, passed=passed, grade=grade, metrics=metrics)
                with (destination / "rows.jsonl").open("a", encoding="utf-8") as file:
                    file.write(json.dumps(row, sort_keys=True) + "\n")
                    file.flush()
                    os.fsync(file.fileno())
                rows.append(row)
        result = dict(schemaVersion="coaching-judge-sensitivity-result.v1", passed=all(r["passed"] for r in rows),
                      controlsSHA256=hashlib.sha256(control_bytes).hexdigest(), corpusSHA256=corpus.sha256,
                      judgeConfigurationSHA256=judge.sha256, judgePromptSHA256=judge.system_prompt_sha256,
                      repetitions=3, provenance=controls["provenance"], rows=rows)
        (destination / "result.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
        return result

    @staticmethod
    def _payload(row, corpus):
        if set(row) != {"id", "caseID", "source", "position", "candidateTurn", "scores", "flags"}:
            raise ValueError("Sensitivity fields do not match")
        turn = corpus.by_id().get(row["caseID"])
        if turn is None:
            raise ValueError("Unknown sensitivity case")
        request = turn.request
        interaction = request["interaction"]
        staged = interaction.get("tentativeMove")
        position = dict(id=turn.identifier, fen=request["position"]["fen"],
                        move=staged["canonicalMove"] if staged else None,
                        event=interaction["latestEvent"]["kind"])
        if row["position"] != position:
            raise ValueError("Sensitivity position changed; review the retained answer binding")
        if not row["scores"] or any(key not in RUBRIC_DIMENSIONS for key in row["scores"]):
            raise ValueError("Invalid sensitivity score expectations")
        for bounds in row["scores"].values():
            if (not bounds or not set(bounds) <= {"min", "max"}
                    or any(type(value) is not int or not 1 <= value <= 5 for value in bounds.values())
                    or bounds.get("min", 1) > bounds.get("max", 5)):
                raise ValueError("Invalid sensitivity score bounds")
        if any(key not in RUBRIC_FLAGS or type(value) is not bool for key, value in row["flags"].items()):
            raise ValueError("Invalid sensitivity flag expectations")
        compilation = compile_context(request, "tutor-v13")
        contract = ChessNativeResponseContract.from_markdown(compilation.markdown)
        contract.parse_and_validate(json.dumps(row["candidateTurn"]))
        return absolute_payload(turn, dict(userPrompt=compilation.markdown, parsedTurn=row["candidateTurn"]))

    @staticmethod
    def _matches(control, grade):
        return all(bounds.get("min", 1) <= grade["scores"][key] <= bounds.get("max", 5)
                   for key, bounds in control["scores"].items()) and all(
                       grade["flags"][key] == value for key, value in control["flags"].items())
