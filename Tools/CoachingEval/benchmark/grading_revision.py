"""Regrade retained responses after a private-brief correction, without rerolling."""

import hashlib
import json
import shutil
from pathlib import Path


class GradingRevision:
    @staticmethod
    def prepare(source, destination, original_cases, revised_cases, *, original_sha, revised_sha, revised_schema):
        source, destination = Path(source).resolve(), Path(destination).resolve()
        if destination.exists():
            raise FileExistsError("Refusing to overwrite a grading revision")
        strip = lambda case: {key: value for key, value in case.items() if key != "graderBrief"}
        if ([strip(case) for case in original_cases] != [strip(case) for case in revised_cases]
                or not original_cases):
            raise ValueError("A grading revision cannot change candidate inputs or case membership")
        manifest_bytes = (source / "run-manifest.json").read_bytes()
        manifest = json.loads(manifest_bytes)
        records = (source / "records.jsonl").read_bytes()
        if (manifest["corpusSHA256"] != original_sha
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
        manifest["gradingRevision"] = dict(originalRun=str(source), originalCorpusSHA256=original_sha,
            originalRunManifestSHA256=hashlib.sha256(manifest_bytes).hexdigest(), candidateCalls=0)
        manifest["corpusSHA256"] = revised_sha
        manifest["corpusManifestSchema"] = revised_schema
        shutil.copytree(source, destination)
        (destination / "run-manifest.json").write_text(json.dumps(manifest, sort_keys=True, indent=2) + "\n")
