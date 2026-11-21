#!/bin/bash
# Deterministic export by default. Network calls require --paid --max-cost USD.
set -euo pipefail
repository_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repository_root"
paid=false
cap=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --paid) paid=true; shift ;;
    --max-cost) cap="${2:?Supply a positive dollar cap}"; shift 2 ;;
    *) echo "Usage: $0 [--paid --max-cost USD]" >&2; exit 2 ;;
  esac
done
if [ "$paid" = true ] && [ -z "$cap" ]; then
  echo "Paid evaluation requires an explicit --max-cost." >&2; exit 2
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "Commit changes first so the export identifies the tested source." >&2; exit 2
fi
python="$repository_root/.venv/bin/python"
mkdir -p .coaching-eval/visual
run_dir="$(mktemp -d "$repository_root/.coaching-eval/visual/run-XXXXXX")"
COACHING_VISUAL_BENCHMARK_OUTPUT_DIR="$run_dir/corpus" \
COACHING_QUALITY_BENCHMARK_SOURCE_SHA="$(git rev-parse HEAD)" \
  xcodebuild test -quiet -project ChessTutor.xcodeproj -scheme ChessTutor \
    -destination 'platform=iOS Simulator,name=ChessTutor Coaching Smoke' \
    -only-testing:ChessTutorTests/CoachingVisualBenchmarkTests/testOptInExport > "$run_dir/export.log" 2>&1
if [ "$paid" = true ]; then
  evaluation_key="$(security find-generic-password -s ChessTutor-CoachingEval-OpenAI -w 2>/dev/null)"
  OPENAI_API_KEY="$evaluation_key" "$python" -m Tools.CoachingEval.benchmark.visual_evaluation \
    --corpus "$run_dir/corpus" --output "$run_dir/evaluation" --paid --max-cost "$cap"
  unset evaluation_key
else
  "$python" -m Tools.CoachingEval.benchmark.visual_evaluation --corpus "$run_dir/corpus" --output "$run_dir/evaluation"
fi
echo "Visual coaching evidence: $run_dir"
