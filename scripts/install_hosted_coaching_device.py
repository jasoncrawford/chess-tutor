#!/usr/bin/env python3
"""Build, install, and bootstrap hosted coaching on one explicitly selected iPad."""
import argparse
import json
import os
from pathlib import Path
import sys
import tempfile

from deploy_coaching_server import CoachingDeployment


class DeviceSetup:
    def __init__(self):
        self.deployment = CoachingDeployment()

    def devices(self):
        result = self.deployment.run(["xcrun", "devicectl", "list", "devices", "--json-output", "-", "--quiet"])
        devices = []
        for item in json.loads(result)["result"]["devices"]:
            properties = item.get("properties", {})
            hardware = properties.get("hardware", item.get("hardwareProperties", {}))
            state = properties.get("state", item.get("deviceProperties", {}))
            if hardware.get("reality") != "physical" or hardware.get("deviceType") != "iPad":
                continue
            devices.append({"id": item["identifier"], "udid": hardware["udid"], "name": state.get("name", "iPad"), "paired": state.get("pairingState")})
        return devices

    def install(self, selector):
        base_url = self.deployment.base_url
        matches = [device for device in self.devices() if selector in (device["id"], device["udid"], device["name"])]
        if len(matches) != 1:
            raise RuntimeError("No unique physical iPad matches --device. Connect it, unlock it, tap Trust, then use --list-devices.")
        device = matches[0]
        if device["paired"] not in (None, "paired"):
            raise RuntimeError("The selected iPad is not paired. Unlock it and trust this Mac first.")
        token = self.deployment.family_token()
        with tempfile.TemporaryDirectory(prefix="chess-device-build-") as build:
            print(f'Building ChessTutor for {device["name"]}…', flush=True)
            self.deployment.run([
                "xcodebuild", "build", "-project", str(self.deployment.root / "ChessTutor.xcodeproj"),
                "-scheme", "ChessTutor", "-configuration", "Release", "-destination", "id=" + device["udid"],
                "-derivedDataPath", build, "-allowProvisioningUpdates", "-allowProvisioningDeviceRegistration",
            ], cwd=self.deployment.root)
            app = Path(build) / "Build/Products/Release-iphoneos/ChessTutor.app"
            if not app.is_dir():
                raise RuntimeError("Build did not produce the device application")
            print("Installing ChessTutor…", flush=True)
            self.deployment.run(["xcrun", "devicectl", "device", "install", "app", "--device", device["id"], str(app)])
            environment = {key: value for key, value in os.environ.items() if not key.startswith("DEVICECTL_CHILD_")}
            environment["DEVICECTL_CHILD_CHESS_TUTOR_COACHING_BASE_URL"] = base_url
            environment["DEVICECTL_CHILD_CHESS_TUTOR_COACHING_ACCESS_TOKEN"] = token
            self.deployment.run([
                "xcrun", "devicectl", "device", "process", "launch", "--device", device["id"],
                "--terminate-existing", "org.jasoncrawford.chesstutor",
            ], environment=environment)
        print("ChessTutor launched with hosted setup. Open Help to verify it; future Home-screen launches retain the setup.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--device", help="Exact physical iPad identifier, UDID, or name")
    action.add_argument("--list-devices", action="store_true")
    args = parser.parse_args()
    try:
        setup = DeviceSetup()
        if args.list_devices:
            devices = setup.devices()
            for device in devices:
                print(f'{device["name"]}: {device["id"]}')
            if not devices:
                print("No physical iPads found. Connect and unlock the family iPad, then tap Trust.")
        else:
            setup.install(args.device)
    except (ValueError, OSError, RuntimeError, KeyError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
