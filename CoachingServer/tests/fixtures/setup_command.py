#!/usr/bin/env python3
"""Fake OS/cloud command boundary for provisioning CLI tests; never live credentials."""
import json
import os
from pathlib import Path
import shlex
import sys

directory = Path(os.environ["SETUP_TEST_STATE"])
name = Path(sys.argv[0]).name
arguments = sys.argv[1:]
secret_input = sys.stdin.read() if name == "security" and arguments == ["-i"] or name == "vercel" and arguments[:2] == ["env", "add"] else ""
with (directory / "calls.jsonl").open("a") as output:
    child_environment = {key: value for key, value in os.environ.items() if key.startswith("DEVICECTL_CHILD_")}
    output.write(json.dumps({"command": name, "args": arguments, "input": secret_input, "childEnvironment": child_environment}) + "\n")
if name == "security":
    keys_file = directory / "keys.json"
    keys = json.loads(keys_file.read_text())
    if arguments == ["-i"]:
        command = shlex.split(secret_input)
        keys[command[command.index("-s") + 1]] = command[command.index("-w") + 1]
        keys_file.write_text(json.dumps(keys))
    else:
        key = keys.get(arguments[arguments.index("-s") + 1])
        if key is None:
            sys.exit(44)
        print(key)
elif name == "vercel":
    if os.environ.get("SETUP_TEST_FAIL") == "vercel":
        print("diagnostic containing test-openai-key", file=sys.stderr)
        sys.exit(1)
    if arguments[:2] == ["api", "/v9/projects?limit=100"]:
        print(json.dumps({"projects": [], "pagination": {"next": None}}))
    elif arguments[:2] == ["api", "/v9/projects/chess-tutor-coaching"]:
        print(json.dumps({"id": "prj_test", "accountId": "team_Po8VYnXvTN5MGKEp4Z7TP6G4"}))
    elif arguments[:2] == ["api", "/v10/projects/prj_test/env"]:
        print(json.dumps({"envs": []}))
    elif arguments[0] == "link":
        target = Path.cwd() / ".vercel"
        target.mkdir()
        (target / "project.json").write_text(json.dumps({"projectId": "prj_test", "orgId": "team_Po8VYnXvTN5MGKEp4Z7TP6G4"}))
    elif arguments[0] == "deploy":
        print("https://test-deployment.vercel.app")
elif name == "xcrun":
    if arguments[:3] == ["devicectl", "list", "devices"]:
        print(json.dumps({"result": {"devices": [{"identifier": "test-device-id", "properties": {"hardware": {"reality": os.environ.get("SETUP_TEST_REALITY", "physical"), "deviceType": "iPad", "udid": "test-hardware-udid"}, "state": {"name": "Family iPad", "pairingState": os.environ.get("SETUP_TEST_PAIRING", "paired")}, "connection": {"state": "connected"}}}]}}))
    elif arguments[:4] == ["devicectl", "device", "install", "app"] and os.environ.get("SETUP_TEST_FAIL") == "install":
        print("error containing test-family-token", file=sys.stderr)
        sys.exit(1)
    elif arguments[:4] == ["devicectl", "device", "process", "launch"]:
        print("Simulated diagnostic test-family-token")
elif name == "xcodebuild":
    build = Path(arguments[arguments.index("-derivedDataPath") + 1])
    (build / "Build/Products/Release-iphoneos/ChessTutor.app").mkdir(parents=True)
