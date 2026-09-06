#!/bin/bash

set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
venv_python="$repository_root/.venv/bin/python"
if [ -x "$venv_python" ]; then
  python_command="$venv_python"
else
  python_command="python3"
fi

cd "$repository_root"
exec "$python_command" -m Tools.CoachingEval.benchmark.review_app "$@"
