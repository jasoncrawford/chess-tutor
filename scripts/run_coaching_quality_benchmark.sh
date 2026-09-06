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
report_root="$session_root/report"
qualification_root="$artifact_root/qualifications"
production="$repository_root/Tools/CoachingEval/benchmark/configs/production-v2.json"
judge="$repository_root/Tools/CoachingEval/benchmark/configs/judge-v4.json"
prices="$repository_root/Tools/CoachingEval/benchmark/pricing-v2.json"
cli=(python3 -m Tools.CoachingEval.benchmark.cli)
completed=false
interrupted=false

cleanup() {
  if [ "$interrupted" = true ]; then
    [ ! -e "$corpus_root" ] || rm -rf "$corpus_root"
    [ ! -e "$session_root" ] || rm -rf "$session_root"
  fi
}
trap cleanup EXIT
trap 'interrupted=true; exit 130' INT
trap 'interrupted=true; exit 143' TERM

mkdir -p "$qualification_root" "$(dirname "$corpus_root")" "$(dirname "$session_root")"

echo "Ensuring the automatic judge is qualified..."
set +e
qualification_summary="$(OPENAI_API_KEY="$openai_api_key" "${cli[@]}" qualify \
  --judge "$judge" --pricing "$prices" --artifact-root "$qualification_root")"
qualification_status=$?
set -e
if [ "$qualification_status" -ne 0 ]; then
  unset openai_api_key
  echo "Judge qualification failed; candidate work was not started." >&2
  exit "$qualification_status"
fi
qualification_path="$(printf '%s' "$qualification_summary" | /usr/bin/python3 -c \
  'import json, sys; print(json.load(sys.stdin)["qualification"])')"

echo "Exporting the deterministic coaching corpus..."
COACHING_QUALITY_BENCHMARK_OUTPUT_DIR="$corpus_root" \
COACHING_QUALITY_BENCHMARK_SOURCE_SHA="$source_sha" \
  xcodebuild test -quiet -scheme ChessTutor \
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
OPENAI_API_KEY="$openai_api_key" "${cli[@]}" "${run_arguments[@]}"

echo "Running the qualified automatic judge..."
set +e
OPENAI_API_KEY="$openai_api_key" "${cli[@]}" grade \
  --run "$run_root" --corpus "$corpus_root" --judge "$judge" \
  --pricing "$prices" --output "$grade_root" \
  --qualification "$qualification_path"
grade_status=$?
set -e
unset openai_api_key

echo "Building the benchmark report..."
"${cli[@]}" report --run "$run_root" --grades "$grade_root" \
  --pricing "$prices" --output "$report_root"

if [ "$grade_status" -ne 0 ]; then
  completed=true
  echo "Judge grading did not pass; a diagnostic report was preserved." >&2
  echo "Report: $report_root/summary.md" >&2
  exit "$grade_status"
fi

completed=true
echo "Benchmark complete."
echo "Report: $report_root/summary.md"
