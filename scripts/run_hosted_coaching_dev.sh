#!/bin/bash

set -euo pipefail

readonly KEYCHAIN_SERVICE="ChessTutor-CoachingEval-OpenAI"
readonly DEFAULT_SIMULATOR="iPad (A16)"
readonly BUNDLE_IDENTIFIER="org.jasoncrawford.chesstutor"

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
simulator_name="${1:-$DEFAULT_SIMULATOR}"
server_pid=""

if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [simulator-name]" >&2
  exit 2
fi

cleanup() {
  if [ -n "$server_pid" ] && kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

cd "$repository_root"

if ! openai_api_key="$(security find-generic-password -s "$KEYCHAIN_SERVICE" -w 2>/dev/null)" || [ -z "$openai_api_key" ]; then
  echo "Could not read the OpenAI key from Keychain service '$KEYCHAIN_SERVICE'." >&2
  echo "Add the key to that Keychain item, then run this command again." >&2
  exit 1
fi

access_token="$(openssl rand -hex 32)"
port="${CHESS_TUTOR_COACHING_DEV_PORT:-}"
if [ -z "$port" ]; then
  port="$(/usr/bin/python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
fi

simulator_info="$(
  xcrun simctl list devices available -j |
    /usr/bin/jq -r --arg name "$simulator_name" '
      [.devices[][] | select(.isAvailable == true and .name == $name)]
      | sort_by(if .state == "Booted" then 0 else 1 end)
      | (.[0] // empty)
      | [.udid, .state]
      | @tsv
    '
)"

if [ -z "$simulator_info" ]; then
  echo "No available Simulator named '$simulator_name' was found." >&2
  echo "Pass a simulator name as the only argument to choose another one." >&2
  exit 1
fi

IFS=$'\t' read -r simulator_udid simulator_state <<< "$simulator_info"

echo "Using $simulator_name."
if [ "$simulator_state" != "Booted" ]; then
  echo "Booting Simulator..."
  xcrun simctl boot "$simulator_udid"
fi
xcrun simctl bootstatus "$simulator_udid" -b
open -a Simulator

echo "Starting the coaching server..."
OPENAI_API_KEY="$openai_api_key" \
CHESS_TUTOR_COACHING_ACCESS_TOKEN="$access_token" \
  python3 -m CoachingServer.local --host 127.0.0.1 --port "$port" &
server_pid=$!
unset openai_api_key

server_ready=false
for _ in {1..100}; do
  if ! kill -0 "$server_pid" 2>/dev/null; then
    echo "The coaching server stopped before it became ready." >&2
    exit 1
  fi
  if curl -fsS --max-time 1 "http://127.0.0.1:$port/health" >/dev/null 2>&1; then
    if kill -0 "$server_pid" 2>/dev/null; then
      server_ready=true
      break
    fi
  fi
  sleep 0.1
done

if [ "$server_ready" != true ]; then
  echo "The coaching server did not become ready." >&2
  exit 1
fi

echo "Building ChessTutor..."
xcodebuild build \
  -project "$repository_root/ChessTutor.xcodeproj" \
  -scheme ChessTutor \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator_udid" \
  -derivedDataPath "$repository_root/DerivedData" \
  -quiet

app_path="$repository_root/DerivedData/Build/Products/Debug-iphonesimulator/ChessTutor.app"
if [ ! -d "$app_path" ]; then
  echo "The ChessTutor build completed, but the app was not found at $app_path." >&2
  exit 1
fi

echo "Installing and launching ChessTutor..."
xcrun simctl terminate "$simulator_udid" "$BUNDLE_IDENTIFIER" >/dev/null 2>&1 || true
xcrun simctl install "$simulator_udid" "$app_path"

launch_environment=(/usr/bin/env)
while IFS='=' read -r variable_name _; do
  case "$variable_name" in
    SIMCTL_CHILD_CHESS_TUTOR_COACHING_BASE_URL|SIMCTL_CHILD_CHESS_TUTOR_COACHING_ACCESS_TOKEN)
      ;;
    SIMCTL_CHILD_*)
      launch_environment+=(-u "$variable_name")
      ;;
  esac
done < <(/usr/bin/env)

SIMCTL_CHILD_CHESS_TUTOR_COACHING_BASE_URL="http://127.0.0.1:$port" \
SIMCTL_CHILD_CHESS_TUTOR_COACHING_ACCESS_TOKEN="$access_token" \
  "${launch_environment[@]}" xcrun simctl launch --terminate-running-process "$simulator_udid" "$BUNDLE_IDENTIFIER" >/dev/null

echo "ChessTutor is ready with hosted coaching."
echo "Leave this terminal open while you use the app. Press Ctrl-C when finished."

wait "$server_pid"
echo "The coaching server stopped." >&2
exit 1
