#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SETTINGS_TARGET="$HOME/Applications/LexiIME-Open.app"
INPUT_TARGET="$HOME/Library/Input Methods/LexiIME-Open Input.app"
[[ -d "$SETTINGS_TARGET" && -d "$INPUT_TARGET" ]] || { echo 'No per-user installation found' >&2; exit 1; }
codesign --verify --deep --strict dist/LexiIME-Open.app
codesign --verify --deep --strict 'dist/LexiIME-Open Input.app'
pkill -f "$SETTINGS_TARGET/Contents/MacOS/LexiIME-Open" >/dev/null 2>&1 || true
pkill -f "$INPUT_TARGET/Contents/MacOS/LexiIME-Open" >/dev/null 2>&1 || true
BACKUP="$(mktemp -d "$PWD/build/system-test/installed-backup.XXXXXX")"
ditto --noextattr --noqtn "$SETTINGS_TARGET" "$BACKUP/LexiIME-Open.app"
ditto --noextattr --noqtn "$INPUT_TARGET" "$BACKUP/LexiIME-Open Input.app"
ditto --noextattr --noqtn dist/LexiIME-Open.app "$SETTINGS_TARGET"
ditto --noextattr --noqtn 'dist/LexiIME-Open Input.app' "$INPUT_TARGET"
codesign --verify --deep --strict "$SETTINGS_TARGET"
codesign --verify --deep --strict "$INPUT_TARGET"
build/tisctl register-enable "$INPUT_TARGET"
echo 'Updated local development components; previous files preserved in build/system-test.'
