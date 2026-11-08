#!/bin/bash

set -euo pipefail

readonly KEYCHAIN_SERVICE="ChessTutor-CoachingEval-OpenAI"

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
artifact_root="${CHESS_TUTOR_BENCHMARK_ARTIFACT_ROOT:-$repository_root/.coaching-eval/benchmark}"
timestamp="${CHESS_TUTOR_BENCHMARK_TIMESTAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"
mode="${1:-}"
if [ -z "$mode" ] || { [ "$mode" != "quick" ] && [ "$mode" != "comparison" ]; }; then
  echo "Usage: $0 quick|comparison [--include-holdout] [--smoke] [candidate-config ...]" >&2
  exit 2
fi
shift

include_holdout=false
smoke=false
candidate_paths=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --include-holdout)
      include_holdout=true
      ;;
    --smoke)
      smoke=true
      ;;
    --*)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
    *)
      candidate_paths+=("$1")
      ;;
  esac
  shift
done

if [ "$mode" = "comparison" ] && [ "${#candidate_paths[@]}" -eq 0 ]; then
  echo "Comparison mode needs at least one candidate configuration." >&2
  exit 2
fi

if [ "$smoke" = true ]; then
  echo "Diagnostic subset evidence: not eligible for trial or promotion."
elif [ "$mode" = "comparison" ] && [ "$include_holdout" = true ]; then
  echo "Holdout comparison evidence: may support promotion only if every report gate passes."
elif [ "$mode" = "comparison" ]; then
  echo "Development comparison evidence: may narrow finalists but cannot support promotion."
else
  echo "Quick development evidence: diagnostic only and cannot support promotion."
fi

if ! openai_api_key="$(security find-generic-password -s "$KEYCHAIN_SERVICE" -w 2>/dev/null)" || [ -z "$openai_api_key" ]; then
  echo "Could not read the OpenAI key from Keychain service '$KEYCHAIN_SERVICE'." >&2
  echo "Add the key to that Keychain item, then run this command again." >&2
  exit 1
fi

cd "$repository_root"
source_sha="$(git rev-parse HEAD)"
corpus_root="$artifact_root/corpus/$source_sha-$timestamp"
session_root="$artifact_root/runs/$timestamp"
run_root="$session_root/candidates"
grade_root="$session_root/grades"
checkpoint_path="$session_root/grading-checkpoint.json"
report_root="$session_root/report"
qualification_root="$artifact_root/qualifications"
production="$repository_root/Tools/CoachingEval/benchmark/configs/production-v2.json"
judge="$repository_root/Tools/CoachingEval/benchmark/configs/judge-v4.json"
prices="$repository_root/Tools/CoachingEval/benchmark/pricing-v2.json"
cli=(python3 -m Tools.CoachingEval.benchmark.cli)
owned_child=''
registering_child=false
pending_interrupt=''
qualification_summary=''

cleanup() {
  if [ -n "$qualification_summary" ]; then
    rm -f -- "$qualification_summary"
  fi
}

saved_evidence() {
  echo "Saved evidence (paths may be partial or not yet created):" >&2
  echo "Corpus: $corpus_root" >&2
  echo "Candidates: $run_root" >&2
  echo "Grades: $grade_root" >&2
  echo "Checkpoint: $checkpoint_path" >&2
  echo "Qualification: ${qualification_path:-$qualification_root}" >&2
  echo "See Tools/CoachingEval/README.md for explicit grade --checkpoint resume instructions." >&2
  echo "Rerunning this convenience script creates a new run; it does not resume this run." >&2
}

interrupt() {
  if [ "$registering_child" = true ]; then
    # Retain the first signal until the new job's PID/group is registered.
    [ -n "$pending_interrupt" ] || pending_interrupt="$1"
    return
  fi
  trap '' INT TERM
  if [ -n "$owned_child" ]; then
    # Each owned command has its own process group, including its descendants.
    kill -TERM -- "-$owned_child" 2>/dev/null || :
    wait "$owned_child" 2>/dev/null || :
    owned_child=''
  fi
  unset openai_api_key
  echo "Benchmark interrupted; existing evidence was preserved." >&2
  saved_evidence
  exit "${pending_interrupt:-$1}"
}

run_owned() {
  local status=0
  # Monitor mode gives this command a distinct process group on macOS Bash too.
  # Waiting asynchronously lets a signal sent only to the launcher run its trap.
  registering_child=true
  set -m
  "$@" &
  owned_child=$!
  set +m
  registering_child=false
  if [ -n "$pending_interrupt" ]; then
    interrupt "$pending_interrupt"
  fi
  wait "$owned_child" || status=$?
  owned_child=''
  return "$status"
}

trap cleanup EXIT
trap 'interrupt 130' INT
trap 'interrupt 143' TERM

mkdir -p "$qualification_root" "$(dirname "$corpus_root")" "$(dirname "$session_root")"

echo "Ensuring the automatic judge is qualified..."
qualification_summary="$(mktemp "${TMPDIR:-/tmp}/chess-benchmark-qualification.XXXXXX")"
set +e
OPENAI_API_KEY="$openai_api_key" run_owned "${cli[@]}" qualify \
  --judge "$judge" --pricing "$prices" --artifact-root "$qualification_root" > "$qualification_summary"
qualification_status=$?
set -e
if [ "$qualification_status" -ne 0 ]; then
  unset openai_api_key
  echo "Judge qualification failed; candidate work was not started." >&2
  exit "$qualification_status"
fi
qualification_path="$(/usr/bin/python3 -c '
import json, sys
summary = sys.stdin.read(65537)
if len(summary) > 65536:
    sys.exit("Qualification summary exceeds the size limit")
print(json.loads(summary)["qualification"])
' < "$qualification_summary")"

echo "Exporting the deterministic coaching corpus..."
COACHING_QUALITY_BENCHMARK_OUTPUT_DIR="$corpus_root" \
COACHING_QUALITY_BENCHMARK_SOURCE_SHA="$source_sha" \
  run_owned xcodebuild test -quiet -scheme ChessTutor \
    -destination 'platform=iOS Simulator,name=iPad (A16)' \
    -only-testing:ChessTutorTests/CoachingQualityBenchmarkCorpusTests/testOptInExport

run_arguments=(
  run --corpus "$corpus_root" --mode "$mode"
  --candidate "$production" --pricing "$prices" --output "$run_root"
)
if [ "${#candidate_paths[@]}" -gt 0 ]; then
  for candidate in "${candidate_paths[@]}"; do
    run_arguments+=(--candidate "$candidate")
  done
fi
if [ "$include_holdout" = true ]; then
  run_arguments+=(--include-holdout)
fi
if [ "$smoke" = true ]; then
  run_arguments+=(
    --case q01-starting-position
    --case d01-loose-bishop
    --case s01-danger-selection-response-01
    --case s01-danger-selection-response-02
    --case s01-danger-selection-response-03
  )
fi

echo "Running candidate coaching configurations..."
OPENAI_API_KEY="$openai_api_key" run_owned "${cli[@]}" "${run_arguments[@]}"

echo "Running the qualified automatic judge..."
set +e
OPENAI_API_KEY="$openai_api_key" run_owned "${cli[@]}" grade \
  --run "$run_root" --corpus "$corpus_root" --judge "$judge" \
  --pricing "$prices" --output "$grade_root" --checkpoint "$checkpoint_path" \
  --qualification "$qualification_path"
grade_status=$?
set -e
unset openai_api_key

if [ "$grade_status" -ne 0 ]; then
  echo "Judge grading failed; evidence was preserved and report generation was not attempted." >&2
  saved_evidence
  exit "$grade_status"
fi

echo "Building the benchmark report..."
run_owned "${cli[@]}" report --run "$run_root" --grades "$grade_root" \
  --pricing "$prices" --output "$report_root"

echo "Benchmark complete."
echo "Report: $report_root/summary.md"
