#!/usr/bin/env python3
"""Resolve, download, and verify pinned coaching-evaluation GGUF artifacts."""

import argparse
import hashlib
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from http_security import (
    SameOriginAuthorizationRedirectHandler,
    is_https_origin,
)


TOOLS_DIR = Path(__file__).resolve().parent
REPOSITORY_ROOT = TOOLS_DIR.parents[1]
DEFAULT_STORE_ROOT = REPOSITORY_ROOT / ".coaching-eval" / "models"
DEFAULT_API_BASE = "https://huggingface.co"


class ModelStoreError(RuntimeError):
    pass


class ModelAccessError(ModelStoreError):
    pass


SafeAuthorizationRedirectHandler = SameOriginAuthorizationRedirectHandler


def load_models(path=TOOLS_DIR / "models.json"):
    models = json.loads(Path(path).read_text(encoding="utf-8"))
    ids = [candidate.get("id") for candidate in models]
    if len(ids) != len(set(ids)) or any(not identifier for identifier in ids):
        raise ModelStoreError("models.json must contain unique, nonempty model IDs")
    return models


class ModelStore:
    def __init__(
        self,
        root=DEFAULT_STORE_ROOT,
        *,
        api_base=DEFAULT_API_BASE,
        download_base=DEFAULT_API_BASE,
        environment=None,
    ):
        self.root = Path(root)
        self.api_base = api_base.rstrip("/")
        self.download_base = download_base.rstrip("/")
        self.environment = dict(os.environ if environment is None else environment)
        self.opener = urllib.request.build_opener(SafeAuthorizationRedirectHandler())

    def fetch(self, candidate):
        if candidate.get("requiresToken") and not self.environment.get("HF_TOKEN"):
            raise ModelAccessError(self._access_guidance(candidate))

        try:
            metadata = self._request_json(
                f"{self.api_base}/api/models/{candidate['repository']}/revision/main"
            )
        except urllib.error.HTTPError as error:
            if candidate.get("requiresToken") and error.code in (401, 403):
                raise ModelAccessError(self._access_guidance(candidate)) from error
            raise
        revision = metadata.get("sha")
        if not isinstance(revision, str) or not revision or revision == "main":
            raise ModelStoreError("Hugging Face did not resolve main to an immutable revision")
        filename = self._select_filename(candidate, metadata.get("siblings", []))
        target_dir = self.root / candidate["id"]
        target = target_dir / filename
        manifest_path = target_dir / "artifact-manifest.json"

        if self._existing_artifact_is_valid(target, manifest_path, candidate, revision):
            return target

        target_dir.mkdir(parents=True, exist_ok=True)
        quoted_filename = urllib.parse.quote(filename, safe="/")
        url = f"{self.download_base}/{candidate['repository']}/resolve/{revision}/{quoted_filename}"
        temporary = target.with_suffix(target.suffix + ".part")
        digest = hashlib.sha256()
        size = 0
        try:
            try:
                with self._open(url) as response, temporary.open("wb") as output:
                    while True:
                        chunk = response.read(1024 * 1024)
                        if not chunk:
                            break
                        output.write(chunk)
                        digest.update(chunk)
                        size += len(chunk)
                temporary.replace(target)
            except urllib.error.HTTPError as error:
                if candidate.get("requiresToken") and error.code in (401, 403):
                    raise ModelAccessError(self._access_guidance(candidate)) from error
                raise
        finally:
            if temporary.exists():
                temporary.unlink()

        manifest = {
            "modelID": candidate["id"],
            "repository": candidate["repository"],
            "requestedRevision": "main",
            "resolvedRevision": revision,
            "selector": candidate["selector"],
            "filename": filename,
            "license": candidate["license"],
            "bytes": size,
            "sha256": digest.hexdigest(),
        }
        manifest_path.write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        return target

    def fetch_all(self, candidates):
        outcomes = []
        for candidate in candidates:
            try:
                target = self.fetch(candidate)
                outcomes.append(
                    {"modelID": candidate["id"], "status": "fetched", "path": str(target)}
                )
            except ModelAccessError as error:
                outcomes.append(
                    {"modelID": candidate["id"], "status": "accessError", "error": str(error)}
                )
            except (ModelStoreError, OSError, urllib.error.URLError) as error:
                outcomes.append(
                    {"modelID": candidate["id"], "status": "error", "error": str(error)}
                )
        return outcomes

    @staticmethod
    def _access_guidance(candidate):
        return (
            f"This {candidate['id']} artifact requires accepting the {candidate['license']} "
            "on Hugging Face and supplying HF_TOKEN in the environment. "
            "No substitute will be downloaded."
        )

    def verify(self, candidate):
        target_dir = self.root / candidate["id"]
        manifest_path = target_dir / "artifact-manifest.json"
        if not manifest_path.is_file():
            return False
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return False
        if not self._manifest_matches_candidate(manifest, candidate):
            return False
        target = target_dir / manifest.get("filename", "")
        return self._file_matches_manifest(target, manifest)

    def _request_json(self, url):
        with self._open(url) as response:
            return json.load(response)

    def _open(self, url):
        headers = {"User-Agent": "ChessTutor-CoachingEval/1"}
        if is_https_origin(url, "huggingface.co"):
            token = self.environment.get("HF_TOKEN")
            if token:
                headers["Authorization"] = f"Bearer {token}"
        return self.opener.open(urllib.request.Request(url, headers=headers), timeout=60)

    @staticmethod
    def _select_filename(candidate, siblings):
        filenames = [entry.get("rfilename") for entry in siblings if entry.get("rfilename")]
        exact = candidate.get("filename")
        if exact is not None:
            if exact not in filenames:
                raise ModelStoreError(f"Pinned file is absent from resolved revision: {exact}")
            return exact
        selector = candidate["selector"].lower()
        matches = [
            name for name in filenames
            if name.lower().endswith(".gguf") and selector in name.lower()
        ]
        if len(matches) != 1:
            raise ModelStoreError(
                f"Expected one {candidate['selector']} GGUF, found {len(matches)}: {matches}"
            )
        return matches[0]

    @classmethod
    def _existing_artifact_is_valid(cls, target, manifest_path, candidate, revision):
        if not target.is_file() or not manifest_path.is_file():
            return False
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return False
        if not cls._manifest_matches_candidate(manifest, candidate):
            return False
        if manifest.get("resolvedRevision") != revision:
            return False
        if manifest.get("filename") != target.name:
            return False
        return cls._file_matches_manifest(target, manifest)

    @staticmethod
    def _manifest_matches_candidate(manifest, candidate):
        if manifest.get("modelID") != candidate["id"]:
            return False
        if manifest.get("repository") != candidate["repository"]:
            return False
        if manifest.get("selector") != candidate["selector"]:
            return False
        if manifest.get("license") != candidate["license"]:
            return False
        if manifest.get("requestedRevision") != "main":
            return False
        revision = manifest.get("resolvedRevision")
        if not isinstance(revision, str) or not revision or revision == "main":
            return False
        pinned_filename = candidate.get("filename")
        return pinned_filename is None or manifest.get("filename") == pinned_filename

    @staticmethod
    def _file_matches_manifest(path, manifest):
        if not path.is_file() or path.stat().st_size != manifest.get("bytes"):
            return False
        digest = hashlib.sha256()
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
        return digest.hexdigest() == manifest.get("sha256")


def _candidate_by_id(identifier):
    for candidate in load_models():
        if candidate["id"] == identifier:
            return candidate
    raise ModelStoreError(f"Unknown model ID: {identifier}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("list")
    fetch = subparsers.add_parser("fetch")
    fetch.add_argument("model")
    subparsers.add_parser("fetch-all")
    subparsers.add_parser("verify")
    arguments = parser.parse_args(argv)
    store = ModelStore()

    try:
        if arguments.command == "list":
            for candidate in load_models():
                print(json.dumps(candidate, sort_keys=True))
            return 0
        if arguments.command == "fetch":
            print(store.fetch(_candidate_by_id(arguments.model)))
            return 0
        if arguments.command == "fetch-all":
            outcomes = store.fetch_all(load_models())
            for outcome in outcomes:
                print(json.dumps(outcome, sort_keys=True))
            return 1 if any(outcome["status"] != "fetched" for outcome in outcomes) else 0
        failures = []
        for candidate in load_models():
            verified = store.verify(candidate)
            print(f"{candidate['id']}: {'verified' if verified else 'missing or invalid'}")
            if not verified:
                failures.append(candidate["id"])
        return 1 if failures else 0
    except (ModelStoreError, OSError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
