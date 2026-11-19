#!/usr/bin/env python3
"""Package only the coach runtime; deploy using secret-safe Keychain/CLI inputs."""
import argparse
import hashlib
import json
from pathlib import Path
import secrets
import shlex
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit


class CoachingDeployment:
    def __init__(self):
        self.root = Path(__file__).resolve().parents[1]
        self.manifest = json.loads((self.root / "CoachingServer/deployment.json").read_text())

    @property
    def base_url(self):
        value = self.manifest["baseURL"]
        parsed = urlsplit(value)
        if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment or parsed.path not in ("", "/"):
            raise ValueError("Deployment baseURL must be an HTTPS origin")
        return value.rstrip("/")

    @staticmethod
    def run(arguments, *, cwd=None, input=None, environment=None):
        # Subprocess diagnostics can echo environment values or secret stdin. Never
        # propagate raw stderr/stdout on failure, nor put credentials in argv.
        result = subprocess.run(arguments, cwd=cwd, input=input, env=environment, capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(f"{Path(arguments[0]).name} failed (exit {result.returncode}); no credentials were printed")
        return result.stdout

    def read_secret(self, service, *, optional=False):
        result = subprocess.run(["security", "find-generic-password", "-s", service, "-w"], capture_output=True, text=True)
        if optional and result.returncode == 44:
            return None
        if result.returncode or not result.stdout.strip():
            raise RuntimeError(f"Keychain credential unavailable: {service}")
        return result.stdout.strip()

    def family_token(self, *, create=False):
        service = self.manifest["familyKeychainService"]
        token = self.read_secret(service, optional=create)
        if token is None:
            token = secrets.token_urlsafe(48)
            # Interactive command input is a pipe, not a command-line password.
            command = shlex.join(["add-generic-password", "-a", "ChessTutor", "-s", service, "-w", token]) + "\n"
            self.run(["security", "-i"], input=command)
            if self.read_secret(service) != token:
                raise RuntimeError("Could not verify the new family credential in Keychain")
        return token

    def deploy(self):
        self.base_url  # Validate before any external writes.
        api_key = self.read_secret(self.manifest["openAIKeychainService"])
        scope = self.manifest["scope"]
        project = self.manifest["project"]

        def vercel(arguments, *, cwd, input=None):
            return self.run(["vercel", *arguments, "--scope", scope], cwd=cwd, input=input)

        with tempfile.TemporaryDirectory(prefix="chess-coaching-deploy-") as temporary:
            bundle = self.package(Path(temporary) / "runtime")
            listing = json.loads(vercel(["api", "/v9/projects?limit=100", "--raw"], cwd=bundle))
            if listing.get("pagination", {}).get("next"):
                raise RuntimeError("Project listing needs pagination; refusing ambiguous project creation")
            if not any(item["name"] == project for item in listing["projects"]):
                vercel(["project", "add", project], cwd=bundle)
            metadata = json.loads(vercel(["api", "/v9/projects/" + project, "--raw"], cwd=bundle))
            if metadata["accountId"] != self.manifest["teamID"]:
                raise RuntimeError("Project belongs to the wrong Vercel team")
            vercel(["link", "--yes", "--project", project], cwd=bundle)
            linked = json.loads((bundle / ".vercel/project.json").read_text())
            if linked["projectId"] != metadata["id"] or linked["orgId"] != self.manifest["teamID"]:
                raise RuntimeError("Linked Vercel project does not match the manifest")
            variables = json.loads(vercel(["api", f'/v10/projects/{metadata["id"]}/env', "--raw"], cwd=bundle))
            existing = {item["key"] for item in variables["envs"] if "production" in item["target"]}
            # Never silently rotate an existing server credential when this Mac
            # lacks its local copy: already-provisioned devices would stop working.
            family = self.family_token(create="CHESS_TUTOR_COACHING_ACCESS_TOKEN" not in existing)
            for name, value in (("OPENAI_API_KEY", api_key), ("CHESS_TUTOR_COACHING_ACCESS_TOKEN", family)):
                if name not in existing:
                    vercel(["env", "add", name, "production", "--sensitive", "--yes"], cwd=bundle, input=value)
            print("Deploying authenticated coaching server…", flush=True)
            deployment = vercel(["deploy", "--prod", "--yes"], cwd=bundle).strip()
            # Vercel returns the deployment URL, never secret values, on stdout.
            if not deployment.startswith("https://") or "\n" in deployment:
                raise RuntimeError("Deployment completed but did not return one HTTPS URL")
            return deployment

    def package(self, destination):
        destination = Path(destination)
        if destination.exists():
            raise ValueError("Package destination must not already exist")
        model_path = self.manifest["modelConfiguration"]
        model = json.loads((self.root / model_path).read_text())
        prompt_path = model["systemPromptPath"]
        if hashlib.sha256((self.root / prompt_path).read_bytes()).hexdigest() != model["systemPromptSHA256"]:
            raise ValueError("Pinned prompt hash does not match")
        vercel = json.loads((self.root / "vercel.json").read_text())
        if vercel["env"]["CHESS_TUTOR_COACHING_MODEL_CONFIG"] != model_path:
            raise ValueError("Deployment model selection does not match manifest")
        for relative in self.manifest["runtimeFiles"] + [model_path, prompt_path]:
            source = self.root / relative
            if source.is_symlink() or not source.resolve().is_relative_to(self.root):
                raise ValueError("Runtime file escapes the repository")
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
        return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--package", type=Path, help="Create a fresh runtime-only directory (no deployment or secrets)")
    action.add_argument("--deploy", action="store_true", help="Deploy production using existing Vercel login and macOS Keychain")
    args = parser.parse_args()
    try:
        deployment = CoachingDeployment()
        if args.package:
            deployment.package(args.package)
            print("Coaching runtime packaged.")
        else:
            url = deployment.deploy()
            print(f"Deployment: {url}\nStable endpoint: {deployment.base_url}")
    except (ValueError, OSError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
