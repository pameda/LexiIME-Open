#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Only stop this project's settings app, never an installed input-method process.
pkill -f "$PWD/dist/LexiIME-Open.app/Contents/MacOS/LexiIME-Open" >/dev/null 2>&1 || true
bash script/build_macos.sh
case "${1:-run}" in
  run) open -n "$PWD/dist/LexiIME-Open.app" ;;
  --verify) open -n "$PWD/dist/LexiIME-Open.app"; sleep 2; pgrep -f "$PWD/dist/LexiIME-Open.app/Contents/MacOS/LexiIME-Open" ;;
  --debug) lldb -- "$PWD/dist/LexiIME-Open.app/Contents/MacOS/LexiIME-Open" ;;
  --logs|--telemetry) open -n "$PWD/dist/LexiIME-Open.app"; /usr/bin/log stream --info --style compact --predicate 'process == "LexiIME-Open"' ;;
  *) echo 'Usage: build_and_run.sh [--verify|--debug|--logs|--telemetry]' >&2; exit 2 ;;
esac
