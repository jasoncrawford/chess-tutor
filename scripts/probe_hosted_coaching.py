"""Use a disposable Vercel project for a bounded hosted timeout replay."""

import argparse
import json
import os
from pathlib import Path
import re
import secrets
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

from scripts.deploy_coaching_server import CoachingDeployment
from Tools.CoachingEval.http_security import SameOriginAuthorizationRedirectHandler


class HostedProbe(CoachingDeployment):
    def package(self, destination):
        bundle = super().package(destination)
        path = bundle / self.manifest["modelConfiguration"]
        policy = json.loads(path.read_text())
        policy["timeoutSeconds"] = 90
        path.write_text(json.dumps(policy))
        config = json.loads((bundle / "vercel.json").read_text())
        config["functions"]["api/index.py"]["maxDuration"] = 120
        (bundle / "vercel.json").write_text(json.dumps(config))
        (bundle / "api/index.py").write_bytes((self.root / "Tools/CoachingEval/hosted_probe_entrypoint.py").read_bytes())
        (bundle / "Tools/CoachingEval/hosted_transport_probe.py").write_bytes(
            (self.root / "Tools/CoachingEval/hosted_transport_probe.py").read_bytes())
        return bundle

    @staticmethod
    def _emit(event, **fields):
        print(json.dumps(dict(event=event, **fields)), flush=True)

    def _api(self, path, *, method="GET", body=None, origin="https://api.vercel.com"):
        query = urllib.parse.urlencode({"teamId": self.manifest["teamID"]})
        url = origin + path + ("&" if "?" in path else "?") + query
        request = urllib.request.Request(url, method=method,
                    headers={"Authorization": "Bearer " + os.environ["VERCEL_TOKEN"], "Content-Type": "application/json"},
                    data=None if body is None else json.dumps(body).encode())
        opener = urllib.request.build_opener(SameOriginAuthorizationRedirectHandler())
        try:
            with opener.open(request, timeout=30) as response:
                raw = response.read()
                if not raw:
                    return {}
                try:
                    return json.loads(raw)
                except ValueError:
                    raise RuntimeError(f"Vercel API returned non-JSON for {method} {path.split('?')[0]} (HTTP {response.status})") from None
        except urllib.error.HTTPError as error:
            code = "unknown"
            try:
                value = json.load(error).get("error", {}).get("code", "unknown")
                if isinstance(value, str) and re.fullmatch(r"[a-zA-Z0-9_-]{1,80}", value):
                    code = value
            except (ValueError, AttributeError):
                pass
            raise RuntimeError(f"Vercel API HTTP {error.code} ({code})") from None

    def replay(self, request_path, *, calls):
        if type(calls) is not int or not 1 <= calls <= 4:
            raise ValueError("Diagnostic run must contain 1–4 calls")
        neutral = json.loads(Path(request_path).read_text())
        if neutral["position"]["fen"] != "r2q2k1/ppp5/6N1/2PP1r1p/3Q4/5p2/PPP2PP1/R4RK1 w - - 0 24":
            raise ValueError("Expected the recorded November 18 incident position")
        original = self._api("/v9/projects/" + self.manifest["project"])
        if original["accountId"] != self.manifest["teamID"]:
            raise ValueError("Wrong Vercel team")
        production_id = original["targets"]["production"]["id"]
        name = "chess-tutor-diag-" + uuid.uuid4().hex[:10]
        project = self._api("/v11/projects", method="POST", body={
            "name": name, "framework": None,
            "resourceConfig": {"fluid": True, "functionDefaultRegions": ["iad1"]},
        })
        if project["id"] == original["id"] or project["name"] != name:
            raise RuntimeError("Refusing a non-diagnostic project")
        self._emit("diagnostic_project_created", project_id=project["id"], name=name)
        try:
            self._replay_project(neutral, calls, project, production_id)
        finally:
            self._api("/v9/projects/" + project["id"], method="DELETE")
            current = self._api("/v9/projects/" + self.manifest["project"])
            self._emit("diagnostic_project_removed", project_id=project["id"],
                       production_unchanged=current["targets"]["production"]["id"] == production_id,
                       production_protection_unchanged=current.get("ssoProtection") == original.get("ssoProtection"))

    def _replay_project(self, neutral, calls, project, production_id):
        token = secrets.token_urlsafe(48)
        started = int(time.time() * 1000)
        game_id = str(uuid.uuid4())
        with tempfile.TemporaryDirectory(prefix="chess-hosted-probe-") as temporary:
            bundle = self.package(Path(temporary) / "runtime")
            payload = dict(name=project["name"], project=project["id"], target="production",
                           files=[dict(file=str(path.relative_to(bundle)), data=path.read_text())
                                  for path in sorted(bundle.rglob("*")) if path.is_file()],
                           env={"OPENAI_API_KEY": self.read_secret(self.manifest["openAIKeychainService"]),
                                "CHESS_TUTOR_COACHING_ACCESS_TOKEN": token,
                                "COACHING_DIAGNOSTIC_EXPIRES_AT": str(time.time() + 3600)},
                           meta={"diagnostic": "coaching-timeout-20261118"})
            # The file-upload REST API consumes deployment configuration in the
            # request, as the Vercel CLI does; uploading vercel.json alone is not enough.
            config = json.loads((bundle / "vercel.json").read_text())
            payload.update(functions=config["functions"], rewrites=config["rewrites"])
            payload["env"].update(config["env"])
            deployment = self._api("/v13/deployments", method="POST", body=payload)
        identifier = deployment["id"]
        if not re.fullmatch(r"dpl_[a-zA-Z0-9]+", identifier) or identifier == production_id:
            raise RuntimeError("Refusing non-diagnostic deployment")
        self._emit("preview_created", deployment_id=identifier, game_id=game_id)
        attempted = 0
        try:
            for _ in range(30):
                deployment = self._api("/v13/deployments/" + identifier)
                if deployment["readyState"] == "READY":
                    break
                if deployment["readyState"] in ("ERROR", "CANCELED"):
                    raise RuntimeError("Diagnostic preview build failed")
                time.sleep(10)
            else:
                raise RuntimeError("Diagnostic preview did not become ready")
            host = project["name"] + ".vercel.app"
            if not re.fullmatch(r"chess-tutor-diag-[a-f0-9]{10}\.vercel\.app", host):
                raise RuntimeError("Unexpected diagnostic hostname")
            opener = urllib.request.build_opener(SameOriginAuthorizationRedirectHandler())
            headers = {"Content-Type": "application/json", "Authorization": "Bearer " + token}
            # Verify access with a free health request before any paid replay.
            health_url = "https://" + host + "/health"
            with opener.open(urllib.request.Request(health_url), timeout=20) as response:
                raw = response.read()
                self._emit("health_response", status=response.status,
                           content_type=response.headers.get("Content-Type"), bytes=len(raw))
                if json.loads(raw) != {"status": "ok"}:
                    raise RuntimeError("Preview health check failed")
            try:
                opener.open(urllib.request.Request("https://" + host + "/v1/coaching-turn", data=b"{}",
                            headers={"Content-Type": "application/json"}, method="POST"), timeout=20)
            except urllib.error.HTTPError as error:
                if error.code != 401:
                    raise RuntimeError("Preview authentication check failed") from None
                error.close()
            else:
                raise RuntimeError("Preview failed to require authentication")
            self._emit("preview_ready", deployment_id=identifier, calls=calls, provider_timeout_seconds=90)
            for index in range(calls):
                envelope = dict(schemaVersion="hosted-coaching-request.v3", gameID=game_id,
                                episodeID=str(uuid.uuid4()), request=neutral, previousResponseID=None)
                call_started = time.monotonic()
                self._emit("replay_started", index=index + 1)
                request = urllib.request.Request("https://" + host + "/v1/coaching-turn", headers=headers,
                                                 data=json.dumps(envelope).encode(), method="POST")
                attempted += 1
                try:
                    with opener.open(request, timeout=110) as response:
                        value = json.load(response)
                        self._emit("replay_completed", index=index + 1, status=response.status,
                                   elapsed_ms=round((time.monotonic() - call_started) * 1000, 3), metrics=value.get("metrics"))
                except urllib.error.HTTPError as error:
                    self._emit("replay_failed", index=index + 1, status=error.code,
                               elapsed_ms=round((time.monotonic() - call_started) * 1000, 3))
                    error.close()
        finally:
            try:
                if attempted:
                    self._collect_transport_logs(project["id"], game_id, started, calls=attempted)
            finally:
                self._api("/v13/deployments/" + identifier, method="DELETE")
                self._emit("preview_removed", deployment_id=identifier)

    def _collect_transport_logs(self, project_id, game_id, started, *, calls):
        # Runtime log ingestion can lag a successful response. Keep the disposable
        # project alive until terminal events arrive, or explicitly report gaps.
        seen = set()
        completed = set()
        fields = ("timestamp", "stage", "client_request_id", "elapsed_ms", "http_status",
                  "provider_processing_ms", "category", "usage")
        for attempt in range(15):
            query = urllib.parse.urlencode(dict(projectId=project_id, ownerId=self.manifest["teamID"],
                                                page="0", startDate=started, endDate=int(time.time() * 1000), search=game_id))
            logs = self._api("/api/logs/request-logs?" + query, origin="https://vercel.com")
            # The log API may evolve; never dump an unrecognized response or raw log line.
            rows = logs if isinstance(logs, list) else logs.get("rows", logs.get("data", []))
            for row in rows:
                for record in row.get("logs", []):
                    try:
                        value = json.loads(record.get("message", ""))
                    except ValueError:
                        continue
                    if not isinstance(value, dict) or value.get("event") != "diagnostic_transport":
                        continue
                    key = (value.get("client_request_id"), value.get("stage"))
                    if not all(isinstance(part, str) for part in key):
                        continue
                    if key not in seen:
                        self._emit("transport", record={field: value[field] for field in fields if field in value})
                        seen.add(key)
                    if key[1] in ("complete", "failed"):
                        completed.add(key[0])
            if len(completed) >= calls:
                return
            if attempt < 14:
                time.sleep(4)
        self._emit("transport_logs_incomplete", expected=calls, completed=len(completed))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--request", type=Path, required=True)
    parser.add_argument("--calls", type=int, choices=range(1, 5), default=2)
    args = parser.parse_args()
    try:
        HostedProbe().replay(args.request, calls=args.calls)
    except urllib.error.HTTPError as error:
        location = urllib.parse.urlsplit(error.headers.get("Location", ""))
        print(json.dumps(dict(event="preview_http_error", status=error.code,
                              redirect_host=location.hostname, redirect_path=location.path)), flush=True)
        return 1
    except (ValueError, RuntimeError) as error:
        print(str(error), flush=True)
        return 1
    except Exception as error:
        # HTTP/URL exceptions may include credential-bearing URLs: never print them.
        print("Diagnostic failed: " + type(error).__name__, flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
