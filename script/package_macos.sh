#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash script/build_macos.sh
STAGE="$(mktemp -d "$PWD/build/pkg-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Applications" "$STAGE/Library/Input Methods"
ditto --noextattr --noqtn dist/LexiIME-Open.app "$STAGE/Applications/LexiIME-Open.app"
ditto --noextattr --noqtn 'dist/LexiIME-Open Input.app' "$STAGE/Library/Input Methods/LexiIME-Open Input.app"
pkgbuild --analyze --root "$STAGE" build/components.plist
python3 - <<'PY'
import plistlib
path='build/components.plist'
with open(path,'rb') as f: components=plistlib.load(f)
for component in components:
    component['BundleIsRelocatable']=False
    component['BundleIsVersionChecked']=True
with open(path,'wb') as f: plistlib.dump(components,f)
PY
PACKAGE_ARCH="${ARCH:-$(uname -m)}"
pkgbuild --root "$STAGE" --component-plist build/components.plist --identifier local.lexiime.open.developer --version 0.1.1 --install-location / "dist/LexiIME-Open-macOS-$PACKAGE_ARCH-0.1.1-developer.pkg"
ditto --noextattr --noqtn -c -k --keepParent dist/LexiIME-Open.app "dist/LexiIME-Open-macOS-$PACKAGE_ARCH-0.1.1-preview.zip"
shasum -a 256 dist/*.pkg dist/*preview.zip > dist/SHA256SUMS.txt
echo 'Developer package created; unsigned installer, ad-hoc apps, not notarized. Not installed.'
