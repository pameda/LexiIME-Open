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
  echo '组件已安装，系统输入源已回读确认启用；尚需验证实际切换和打字。'
else
  echo '组件已复制，但系统输入源启用未通过。它现在还不能作为系统输入法使用。' >&2
  echo '设置与应用内试用：~/Applications/LexiIME-Open.app；请查看 docs/MACOS-RELEASE.md。' >&2
  exit 1
fi
