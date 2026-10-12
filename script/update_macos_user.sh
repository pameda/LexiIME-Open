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
# Refresh only this component's registration after input-mode metadata changes.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -u "$INPUT_TARGET"
"$LSREGISTER" -f "$INPUT_TARGET"
pkill -x TextInputMenuAgent >/dev/null 2>&1 || true
if ! build/tisctl register-enable "$INPUT_TARGET"; then
  echo '启用请求尚未确认，正在独立进程中再次核对。' >&2
fi
# A changed registration can invalidate the menu agent's first snapshot.
# Retry once in fresh processes; never treat a successful request as verification.
if ! build/tisctl verify-enabled local.inputmethod.lexiime.open >/dev/null; then
  pkill -x TextInputMenuAgent >/dev/null 2>&1 || true
  build/tisctl register-enable "$INPUT_TARGET" || true
  build/tisctl enable local.inputmethod.lexiime.open || true
fi
if build/tisctl verify-enabled local.inputmethod.lexiime.open; then
  echo '组件已更新，系统输入源已回读确认启用；实际切换和打字仍需验证。'
else
  echo '组件已更新并保留备份，但系统输入源启用未通过，尚不能作为系统输入法使用。' >&2
  echo "原组件备份：$BACKUP" >&2
  exit 1
fi
