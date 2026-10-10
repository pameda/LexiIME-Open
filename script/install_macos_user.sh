#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SETTINGS_TARGET="$HOME/Applications/LexiIME-Open.app"
INPUT_TARGET="$HOME/Library/Input Methods/LexiIME-Open Input.app"
if [[ -e "$SETTINGS_TARGET" || -e "$INPUT_TARGET" ]]; then
  echo 'An existing LexiIME-Open installation was found; inspect it before updating.' >&2
  exit 1
fi
codesign --verify --deep --strict dist/LexiIME-Open.app
codesign --verify --deep --strict 'dist/LexiIME-Open Input.app'
mkdir -p "$HOME/Applications" "$HOME/Library/Input Methods" build/system-test
build/tisctl current > build/system-test/input-before.json
build/tisctl list > build/system-test/sources-before.json
ditto --noextattr --noqtn dist/LexiIME-Open.app "$SETTINGS_TARGET"
ditto --noextattr --noqtn 'dist/LexiIME-Open Input.app' "$INPUT_TARGET"
codesign --verify --deep --strict "$SETTINGS_TARGET"
codesign --verify --deep --strict "$INPUT_TARGET"
build/tisctl register-enable "$INPUT_TARGET"
echo 'Installed in the current user account; the original input source remains selected.'
