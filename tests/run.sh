#!/usr/bin/env bash
# Runs the headless test suite. Fails on any test failure or GDScript error.
# Usage: GODOT=/path/to/godot tests/run.sh
set -uo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
"$GODOT" --headless --path . --import >/dev/null 2>&1
out="$("$GODOT" --headless --path . -s tests/run_tests.gd 2>&1)"
status=$?
echo "$out"
if grep -q "SCRIPT ERROR" <<<"$out"; then
  echo "GDScript errors found" >&2
  exit 1
fi
exit $status
