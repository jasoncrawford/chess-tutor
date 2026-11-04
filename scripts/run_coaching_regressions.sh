#!/bin/bash
# Export real Swift inputs and evaluate the current local coach. Paid calls are opt-in.
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repository_root"
if [ -n "$(git status --porcelain)" ]; then
  echo "Commit your changes before evaluation so the report identifies the exact tested source." >&2
  exit 2
fi
source_sha="$(git rev-parse HEAD)"
artifact_root="${CHESS_TUTOR_REGRESSION_ARTIFACT_ROOT:-$repository_root/.coaching-eval/regression}"
timestamp="${CHESS_TUTOR_REGRESSION_TIMESTAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"
session_root="$artifact_root/$timestamp"
qualification_root="${CHESS_TUTOR_BENCHMARK_QUALIFICATION_ROOT:-$repository_root/.coaching-eval/benchmark/qualifications}"
python="${CHESS_TUTOR_EVAL_PYTHON:-$repository_root/.venv/bin/python}"
if [ ! -x "$python" ]; then python=python3; fi
destination="${CHESS_TUTOR_REGRESSION_DESTINATION:-platform=iOS Simulator,name=ChessTutor Coaching Smoke}"
mkdir -p "$artifact_root"
mkdir "$session_root"

owned_child=''
registering_child=false
pending_interrupt=''
interrupt() {
  if [ "$registering_child" = true ]; then pending_interrupt="$1"; return; fi
  trap '' INT TERM
  if [ -n "$owned_child" ]; then
    kill -TERM -- "-$owned_child" 2>/dev/null || :
    wait "$owned_child" 2>/dev/null || :
  fi
  echo "Interrupted; retained evidence: $session_root" >&2
  exit "$1"
}
run_owned() {
  local status=0
  registering_child=true
  set -m
  "$@" &
  owned_child=$!
  set +m
  registering_child=false
  if [ -n "$pending_interrupt" ]; then interrupt "$pending_interrupt"; fi
  wait "$owned_child" || status=$?
  owned_child=''
  return "$status"
}
trap 'interrupt 130' INT
trap 'interrupt 143' TERM

echo "Exporting the frozen benchmark, playthrough and experience regressions on Coaching Smoke..."
COACHING_QUALITY_BENCHMARK_OUTPUT_DIR="$session_root/benchmark-corpus" \
COACHING_PLAYTHROUGH_BENCHMARK_OUTPUT_DIR="$session_root/playthrough-corpus" \
COACHING_EXPERIENCE_BENCHMARK_OUTPUT_DIR="$session_root/experience-corpus" \
COACHING_QUALITY_BENCHMARK_SOURCE_SHA="$source_sha" \
  run_owned xcodebuild test -quiet -project ChessTutor.xcodeproj -scheme ChessTutor \
    -destination "$destination" \
    -only-testing:ChessTutorTests/CoachingQualityBenchmarkCorpusTests/testOptInExport \
    -only-testing:ChessTutorTests/CoachingPlaythroughBenchmarkTests/testOptInExport \
    -only-testing:ChessTutorTests/CoachingExperienceBenchmarkTests/testOptInExport \
    > "$session_root/export.log" 2>&1

if ! evaluation_key="$(security find-generic-password -s ChessTutor-CoachingEval-OpenAI -w 2>/dev/null)" || [ -z "$evaluation_key" ]; then
  echo "Could not read ChessTutor-CoachingEval-OpenAI from Keychain." >&2
  exit 1
fi
echo "Checking judge sensitivity, then evaluating the current local trial (three repetitions)."
echo "Default conservative cap: \$10; override with --max-cost. Evidence: $session_root"
OPENAI_API_KEY="$evaluation_key" run_owned "$python" -m Tools.CoachingEval.benchmark.regression \
  --corpus "$session_root/benchmark-corpus" --regressions "$session_root/playthrough-corpus" \
  --experience "$session_root/experience-corpus" \
  --output "$session_root/evaluation" --qualification-root "$qualification_root" "$@"
unset evaluation_key
echo "Finished. Reports: $session_root/evaluation/{experience,playthrough,benchmark}/report/summary.md"
