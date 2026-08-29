import contextlib
import hashlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

import preflight_prompts
import run_eval


PILOT_IDS = (
    "t1Entry",
    "t3Entry",
    "t7NoSafeCapture",
    "t1PreferredKnight",
    "t11UnsafeBishopFound",
    "t11Safe",
    "t11BenignCaptureTap",
    "t12Block",
    "t9Hint",
    "t12UnsupportedEntry",
)


class FakeTemplateTokenServer:
    instances = []
    events = []
    token_counts = []

    def __init__(self, executable, model_path, *, context_tokens):
        self.model_path = Path(model_path)
        self.executable = Path(executable)
        self.context_tokens = context_tokens
        self.render_calls = []
        self.token_calls = []
        self.completion_calls = []
        self.__class__.instances.append(self)

    def start(self):
        self.__class__.events.append(("start", self.model_path.name))

    def stop(self):
        self.__class__.events.append(("stop", self.model_path.name))

    def render_prompt(self, **arguments):
        self.render_calls.append(arguments)
        self.__class__.events.append(("render", self.model_path.name))
        return "rendered:{model}:{thinking}:{markdown}".format(
            model=self.model_path.name,
            thinking=arguments["enable_thinking"],
            markdown=arguments["user_content"],
        )

    def token_count(self, prompt, **arguments):
        self.token_calls.append((prompt, arguments))
        self.__class__.events.append(("tokenize", self.model_path.name))
        return self.__class__.token_counts.pop(0)

    def complete_rendered(self, **arguments):
        self.completion_calls.append(arguments)
        raise AssertionError("Preflight must never request completion")


class PreflightPromptTests(unittest.TestCase):
    def setUp(self):
        FakeTemplateTokenServer.instances = []
        FakeTemplateTokenServer.events = []
        FakeTemplateTokenServer.token_counts = [2000] * 60

    def _write_corpus(self, root, *, hidden=None, duplicate=False):
        cases = []
        for index, identifier in enumerate(PILOT_IDS):
            cases.append(
                {
                    "id": identifier,
                    "split": "hidden" if identifier == hidden else "visible",
                    "request": {
                        "requestID": f"request-{index}",
                        "positionRevision": index,
                    },
                    "compactContext": {
                        "markdown": f"# Compact context\n\n- Case: `{identifier}`\n",
                    },
                }
            )
        if duplicate:
            cases.append(dict(cases[0]))
        path = root / "visible.jsonl"
        path.write_text("".join(json.dumps(case) + "\n" for case in cases), encoding="utf-8")
        return path

    def _write_models(self, root, count=3):
        models = []
        for index in range(count):
            path = root / f"model-{index}.gguf"
            path.write_bytes(f"model-{index}".encode("utf-8"))
            models.append((f"model-{index}", path))
        return models

    def _preflight(self, root, *, output_name="preflight.json", model_count=3):
        corpus = self._write_corpus(root)
        models = self._write_models(root, model_count)
        output = root / output_name
        provenance = {
            "sourceTag": "b10516",
            "sourceCommit": "b" * 40,
            "binarySHA256": "a" * 64,
            "versionOutput": "version: 10516",
        }
        with mock.patch.object(
            preflight_prompts.runtime_provenance,
            "verify_runtime",
            return_value=provenance,
        ):
            result = preflight_prompts.preflight(
                server=root / "llama-server",
                models=models,
                runtime_path=TOOLS_DIR / "runtime.json",
                runtime_manifest=root / "runtime-manifest.json",
                corpus=corpus,
                pilot=TOOLS_DIR / "pilots" / "compact-markdown-v1.json",
                output=output,
                server_factory=FakeTemplateTokenServer,
            )
        return result, output, corpus, models, provenance

    def test_preflight_persists_the_ordered_complete_token_only_matrix(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            result, output, corpus, models, provenance = self._preflight(root)

            self.assertEqual(result, json.loads(output.read_text(encoding="utf-8")))
            self.assertEqual("coaching-prompt-preflight.v1", result["schemaVersion"])
            self.assertEqual("tutor-v4", result["promptVersion"])
            self.assertEqual(4000, result["budgetTokens"])
            self.assertEqual(3000, result["preferredTargetTokens"])
            self.assertEqual(provenance, result["runtimeProvenance"])
            self.assertEqual(
                hashlib.sha256((TOOLS_DIR / "runtime.json").read_bytes()).hexdigest(),
                result["runtimeSHA256"],
            )
            self.assertEqual(hashlib.sha256(corpus.read_bytes()).hexdigest(), result["corpusSHA256"])
            self.assertEqual(
                hashlib.sha256(
                    (TOOLS_DIR / "pilots" / "compact-markdown-v1.json").read_bytes()
                ).hexdigest(),
                result["pilotSHA256"],
            )
            self.assertEqual([], run_eval._load_prompt_bundle("tutor-v4").examples)
            self.assertEqual(0, result["exampleCount"])
            self.assertEqual(64, len(result["promptSHA256"]))
            self.assertEqual(64, len(result["examplesSHA256"]))
            self.assertEqual(3, len(result["models"]))
            self.assertEqual(60, len(result["cells"]))
            self.assertEqual(60, result["summary"]["cellCount"])
            self.assertEqual(0, result["summary"]["overBudgetCount"])
            self.assertEqual(0, result["summary"]["abovePreferredTargetCount"])
            self.assertEqual(2000, result["summary"]["minimumTokens"])
            self.assertEqual(2000, result["summary"]["medianTokens"])
            self.assertEqual(2000, result["summary"]["p90Tokens"])
            self.assertEqual(2000, result["summary"]["maximumTokens"])

            expected = [
                (model_id, mode, case_id)
                for model_id, _path in models
                for mode in ("off", "bounded")
                for case_id in PILOT_IDS
            ]
            self.assertEqual(
                expected,
                [(cell["modelID"], cell["mode"], cell["caseID"]) for cell in result["cells"]],
            )
            for cell in result["cells"]:
                self.assertEqual("visible", cell["caseSplit"])
                self.assertEqual("tutor-v4", cell["promptVersion"])
                self.assertEqual(result["promptSHA256"], cell["promptSHA256"])
                self.assertEqual(result["examplesSHA256"], cell["examplesSHA256"])
                self.assertEqual(0, cell["exampleCount"])
                self.assertEqual(result["corpusSHA256"], cell["corpusSHA256"])
                self.assertEqual(result["pilotSHA256"], cell["pilotSHA256"])
                self.assertEqual(provenance, cell["runtimeProvenance"])
                self.assertEqual(result["runtimeSHA256"], cell["runtimeSHA256"])
                self.assertEqual(2000, cell["renderedPromptTokens"])
                self.assertEqual("withinBudget", cell["budgetStatus"])
                self.assertEqual(64, len(cell["renderedPromptSHA256"]))
                self.assertGreater(cell["renderedPromptUTF8Bytes"], 0)

            self.assertEqual(3, len(FakeTemplateTokenServer.instances))
            self.assertEqual(60, sum(len(item.render_calls) for item in FakeTemplateTokenServer.instances))
            self.assertEqual(60, sum(len(item.token_calls) for item in FakeTemplateTokenServer.instances))
            self.assertEqual([], sum((item.completion_calls for item in FakeTemplateTokenServer.instances), []))
            self.assertEqual(
                [
                    ("start", "model-0.gguf"),
                    ("stop", "model-0.gguf"),
                    ("start", "model-1.gguf"),
                    ("stop", "model-1.gguf"),
                    ("start", "model-2.gguf"),
                    ("stop", "model-2.gguf"),
                ],
                [event for event in FakeTemplateTokenServer.events if event[0] != "render" and event[0] != "tokenize"],
            )

    def test_preflight_is_deterministic_for_deterministic_clients(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self._preflight(root, output_name="first.json")
            FakeTemplateTokenServer.instances = []
            FakeTemplateTokenServer.events = []
            FakeTemplateTokenServer.token_counts = [2000] * 60
            self._preflight(root, output_name="second.json")

            self.assertEqual(
                (root / "first.json").read_text(encoding="utf-8"),
                (root / "second.json").read_text(encoding="utf-8"),
            )

    def test_preflight_refuses_hidden_duplicate_existing_or_incomplete_inputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            models = self._write_models(root)
            output = root / "preflight.json"
            common = {
                "server": root / "llama-server",
                "models": models,
                "runtime_path": TOOLS_DIR / "runtime.json",
                "runtime_manifest": root / "runtime-manifest.json",
                "pilot": TOOLS_DIR / "pilots" / "compact-markdown-v1.json",
                "output": output,
                "server_factory": FakeTemplateTokenServer,
            }
            with mock.patch.object(
                preflight_prompts.runtime_provenance,
                "verify_runtime",
                return_value={"sourceTag": "b10516"},
            ):
                with self.assertRaisesRegex(ValueError, "hidden"):
                    preflight_prompts.preflight(
                        corpus=self._write_corpus(root, hidden="t1Entry"), **common
                    )
                with self.assertRaisesRegex(ValueError, "duplicate"):
                    preflight_prompts.preflight(
                        corpus=self._write_corpus(root, duplicate=True), **common
                    )
                output.write_text("already immutable", encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "overwrite"):
                    preflight_prompts.preflight(
                        corpus=self._write_corpus(root), **common
                    )
                output.unlink()
                with self.assertRaisesRegex(ValueError, "exactly three"):
                    preflight_prompts.preflight(
                        corpus=self._write_corpus(root),
                        models=models[:2],
                        **{key: value for key, value in common.items() if key != "models"},
                    )

    def test_atomic_writer_refuses_a_destination_created_before_publish(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "preflight.json"
            original_fsync = preflight_prompts.os.fsync
            competitor_created = False

            def fsync_then_create_competitor(descriptor):
                nonlocal competitor_created
                original_fsync(descriptor)
                if not competitor_created:
                    competitor_created = True
                    output.write_text("competing manifest", encoding="utf-8")

            with mock.patch.object(
                preflight_prompts.os, "fsync", side_effect=fsync_then_create_competitor
            ):
                with self.assertRaisesRegex(ValueError, "overwrite"):
                    preflight_prompts._write_immutable_manifest(output, {"new": "manifest"})

            self.assertTrue(competitor_created)
            self.assertEqual("competing manifest", output.read_text(encoding="utf-8"))

    def test_matrix_validator_refuses_duplicate_cells(self):
        models = [(f"model-{index}", Path(f"model-{index}.gguf")) for index in range(3)]
        cases = [{"id": f"case-{index}"} for index in range(10)]
        cells = [
            {"modelID": model_id, "mode": mode, "caseID": case["id"]}
            for model_id, _path in models
            for mode in ("off", "bounded")
            for case in cases
        ]
        cells[-1] = dict(cells[-2])

        with self.assertRaisesRegex(ValueError, "duplicate"):
            preflight_prompts._validate_complete_matrix(cells, models, cases)

    def test_matrix_validator_refuses_incomplete_cells(self):
        models = [(f"model-{index}", Path(f"model-{index}.gguf")) for index in range(3)]
        cases = [{"id": f"case-{index}"} for index in range(10)]
        cells = [
            {"modelID": model_id, "mode": mode, "caseID": case["id"]}
            for model_id, _path in models
            for mode in ("off", "bounded")
            for case in cases
        ]

        with self.assertRaisesRegex(ValueError, "incomplete"):
            preflight_prompts._validate_complete_matrix(cells[:-1], models, cases)

    def test_cli_persists_a_4001_token_manifest_and_returns_nonzero(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            corpus = self._write_corpus(root)
            models = self._write_models(root)
            output = root / "preflight.json"
            FakeTemplateTokenServer.token_counts = [4001] + [4000] * 59
            real_preflight = preflight_prompts.preflight

            def preflight_with_fake_server(**arguments):
                return real_preflight(
                    **arguments, server_factory=FakeTemplateTokenServer
                )

            arguments = [
                "--server", str(root / "llama-server"),
                "--runtime-manifest", str(root / "runtime-manifest.json"),
                "--corpus", str(corpus),
                "--pilot", str(TOOLS_DIR / "pilots" / "compact-markdown-v1.json"),
                "--model", f"model-0={models[0][1]}",
                "--model", f"model-1={models[1][1]}",
                "--model", f"model-2={models[2][1]}",
                "--output", str(output),
            ]
            with mock.patch.object(
                preflight_prompts.runtime_provenance,
                "verify_runtime",
                return_value={"sourceTag": "b10516"},
            ), mock.patch.object(
                preflight_prompts,
                "preflight",
                side_effect=preflight_with_fake_server,
            ), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(1, preflight_prompts.main(arguments))

            manifest = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(1, manifest["summary"]["overBudgetCount"])
            self.assertEqual(4001, manifest["cells"][0]["renderedPromptTokens"])

    def test_cli_returns_zero_when_the_summary_is_within_budget(self):
        result = {"summary": {"overBudgetCount": 0}}
        arguments = [
            "--server", "server",
            "--runtime-manifest", "runtime-manifest.json",
            "--corpus", "visible.jsonl",
            "--pilot", "pilot.json",
            "--model", "model-0=model-0.gguf",
            "--model", "model-1=model-1.gguf",
            "--model", "model-2=model-2.gguf",
            "--output", "unused.json",
        ]
        with mock.patch.object(preflight_prompts, "preflight", return_value=result):
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(0, preflight_prompts.main(arguments))

    def test_over_budget_cell_is_persisted_and_classified(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            FakeTemplateTokenServer.token_counts = [4001] + [4000] * 59
            result, output, _corpus, _models, _provenance = self._preflight(root)

            self.assertTrue(output.is_file())
            self.assertEqual("overBudget", result["cells"][0]["budgetStatus"])
            self.assertEqual(1, result["summary"]["overBudgetCount"])
            self.assertEqual(60, result["summary"]["abovePreferredTargetCount"])


if __name__ == "__main__":
    unittest.main()
