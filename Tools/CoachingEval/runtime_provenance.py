#!/usr/bin/env python3
"""Record and verify the exact pinned llama-server executable."""

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parent


class RuntimeProvenanceError(RuntimeError):
    pass


def _sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _version_output(executable):
    try:
        result = subprocess.run(
            [str(Path(executable).resolve()), "--version"],
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RuntimeProvenanceError(f"Could not execute llama-server --version: {error}") from error
    output = "\n".join(part.strip() for part in (result.stdout, result.stderr) if part.strip())
    if result.returncode != 0:
        raise RuntimeProvenanceError(
            f"llama-server --version failed with status {result.returncode}: {output}"
        )
    if not output:
        raise RuntimeProvenanceError("llama-server --version returned no output")
    return output


def _pins(runtime_path):
    runtime = json.loads(Path(runtime_path).read_text(encoding="utf-8"))
    tag = runtime.get("llamaCppTag")
    commit = runtime.get("llamaCppCommit")
    if not isinstance(tag, str) or not re.fullmatch(r"b[1-9][0-9]*", tag):
        raise RuntimeProvenanceError("runtime llamaCppTag must be an exact b<number> tag")
    if not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise RuntimeProvenanceError("runtime llamaCppCommit must be a full lowercase SHA")
    return tag, commit


def _assert_version_matches(output, tag, commit):
    build = tag[1:]
    if re.search(rf"(?<![0-9]){re.escape(build)}(?![0-9])", output) is None:
        raise RuntimeProvenanceError(f"llama-server version does not report pinned tag {tag}")
    reported_commits = re.findall(r"(?<![0-9a-f])([0-9a-f]{7,40})(?![0-9a-f])", output.lower())
    if not any(commit.startswith(reported) or reported.startswith(commit) for reported in reported_commits):
        raise RuntimeProvenanceError(
            f"llama-server version does not report pinned commit {commit}"
        )


def _actual_manifest(executable, runtime_path):
    executable = Path(executable).resolve()
    if not executable.is_file():
        raise RuntimeProvenanceError(f"Pinned llama-server is missing: {executable}")
    tag, commit = _pins(runtime_path)
    output = _version_output(executable)
    _assert_version_matches(output, tag, commit)
    return {
        "sourceTag": tag,
        "sourceCommit": commit,
        "binaryPath": str(executable),
        "binarySHA256": _sha256(executable),
        "versionOutput": output,
    }


def record_runtime(executable, runtime_path, manifest_path):
    manifest = _actual_manifest(executable, runtime_path)
    manifest_path = Path(manifest_path)
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return manifest


def verify_runtime(executable, runtime_path, manifest_path):
    manifest_path = Path(manifest_path)
    if not manifest_path.is_file():
        raise RuntimeProvenanceError(f"Runtime manifest is missing: {manifest_path}")
    recorded = json.loads(manifest_path.read_text(encoding="utf-8"))
    actual = _actual_manifest(executable, runtime_path)
    for field in ("sourceTag", "sourceCommit", "binaryPath", "binarySHA256", "versionOutput"):
        if recorded.get(field) != actual[field]:
            description = "binary hash" if field == "binarySHA256" else field
            raise RuntimeProvenanceError(f"Runtime {description} mismatch")
    return actual


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("record", "verify"))
    parser.add_argument("--server", required=True, type=Path)
    parser.add_argument("--runtime", type=Path, default=TOOLS_DIR / "runtime.json")
    parser.add_argument("--manifest", required=True, type=Path)
    arguments = parser.parse_args(argv)
    try:
        if arguments.command == "record":
            result = record_runtime(arguments.server, arguments.runtime, arguments.manifest)
        else:
            result = verify_runtime(arguments.server, arguments.runtime, arguments.manifest)
    except (RuntimeProvenanceError, OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
