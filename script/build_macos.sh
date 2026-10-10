#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export SDKROOT="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
mkdir -p build/module-cache dist
pkill -f "$PWD/dist/LexiIME-Open.app/Contents/MacOS/LexiIME-Open" >/dev/null 2>&1 || true
pkill -f "$PWD/dist/LexiIME-Open Input.app/Contents/MacOS/LexiIME-Open" >/dev/null 2>&1 || true
ARCH="${ARCH:-$(uname -m)}"
xcrun clang++ -std=c++17 -O2 -arch "$ARCH" -mmacosx-version-min=13.0 -c core/lexi.cpp -o "build/core-$ARCH.o"
xcrun swiftc -swift-version 5 -O -target "$ARCH-apple-macosx13.0" -module-cache-path "$PWD/build/module-cache" -import-objc-header core/lexi.h platform/macos/*.swift "build/core-$ARCH.o" -lc++ -framework AppKit -framework SwiftUI -framework InputMethodKit -framework Carbon -framework Security -framework Speech -framework AVFoundation -o "build/LexiIME-Open-$ARCH"
python3 script/bundle_macos.py "$ARCH"
codesign --force --sign - dist/LexiIME-Open.app
codesign --force --sign - 'dist/LexiIME-Open Input.app'
codesign --verify --deep --strict dist/LexiIME-Open.app
codesign --verify --deep --strict 'dist/LexiIME-Open Input.app'
echo "Built developer apps for $ARCH. No system input source was installed."
