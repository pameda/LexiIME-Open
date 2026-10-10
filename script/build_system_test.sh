#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export SDKROOT="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
LEXI_TEST_APP="$PWD/build/LexiIME-Open System Test.app"
mkdir -p "$LEXI_TEST_APP/Contents/MacOS" build/system-test
xcrun clang -fobjc-arc -framework AppKit -framework Carbon -framework ApplicationServices tests/system/macos/main.m -o "$LEXI_TEST_APP/Contents/MacOS/LexiSystemTest"
xcrun clang -fobjc-arc -framework AppKit -framework Carbon -framework ApplicationServices script/native_ax.m -o build/native-ax
xcrun clang -fobjc-arc -framework AppKit -framework Carbon script/tisctl.m -o build/tisctl
xcrun clang++ -std=c++17 -O2 -dynamiclib core/lexi.cpp -o build/libLexiCore-test.dylib
python3 - <<'PY'
import plistlib
from pathlib import Path
p=Path('build/LexiIME-Open System Test.app/Contents/Info.plist')
p.write_bytes(plistlib.dumps(dict(CFBundleExecutable='LexiSystemTest',CFBundleIdentifier='local.lexiime.open.systemtest',CFBundleName='LexiIME-Open System Test',CFBundlePackageType='APPL',CFBundleVersion='1',NSPrincipalClass='NSApplication',LSMinimumSystemVersion='13.0')))
PY
codesign --force --sign - "$LEXI_TEST_APP"
echo 'Built isolated native UI test app; not launched.'
