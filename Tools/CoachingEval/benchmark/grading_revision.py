"""Regrade retained responses after a private-brief correction, without rerolling."""

import hashlib
import json
import shutil
from pathlib import Path

from Tools.CoachingEval.benchmark.corpus import load_corpus


class GradingRevision:
    @staticmethod
    def prepare(source, destination, original_corpus_path, revised_corpus_path):
        source, destination = Path(source).resolve(), Path(destination).resolve()
        if destination.is_relative_to(source):
            raise ValueError("Cannot copy a run into itself")
        if destination.exists():
            raise FileExistsError("Refusing to overwrite a grading revision")
        original, revised = load_corpus(original_corpus_path), load_corpus(revised_corpus_path)
        original_cases, revised_cases = original.raw_cases, revised.raw_cases
        strip = lambda case: {key: value for key, value in case.items() if key != "graderBrief"}
        if ([strip(case) for case in original_cases] != [strip(case) for case in revised_cases]
                or not original_cases):
            raise ValueError("A grading revision cannot change candidate inputs or case membership")
        manifest_bytes = (source / "run-manifest.json").read_bytes()
        manifest = json.loads(manifest_bytes)
        records = (source / "records.jsonl").read_bytes()
        if (manifest["corpusSHA256"] != original.sha256
                or manifest["recordsSHA256"] != hashlib.sha256(records).hexdigest()):
            raise ValueError("Original run/corpus binding changed")
        requests = {case["id"]: case["request"] for case in original_cases}
        seen = set()
        for line in records.splitlines():
            row = json.loads(line)
            request = requests.get(row["caseID"])
            request_sha = hashlib.sha256(json.dumps(request, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
            if request is None or row["requestSHA256"] != request_sha or row["cellID"] in seen:
                raise ValueError("Original candidate request binding changed")
            seen.add(row["cellID"])
        manifest["gradingRevision"] = dict(originalRun=str(source), originalCorpusSHA256=original.sha256,
            originalRunManifestSHA256=hashlib.sha256(manifest_bytes).hexdigest(), candidateCalls=0)
        manifest["corpusSHA256"] = revised.sha256
        manifest["corpusManifestSchema"] = json.loads(revised.manifest_path.read_bytes())["schemaVersion"]
        shutil.copytree(source, destination)
        (destination / "run-manifest.json").write_text(json.dumps(manifest, sort_keys=True, indent=2) + "\n")
