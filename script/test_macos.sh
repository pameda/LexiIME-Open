#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export SDKROOT="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
mkdir -p build/module-cache
xcrun clang++ -std=c++17 -O2 -mmacosx-version-min=13.0 -c core/lexi.cpp -o build/core-test.o
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$PWD/build/module-cache" -import-objc-header core/lexi.h platform/macos/Model.swift platform/macos/Typing.swift platform/macos/CandidateLayout.swift platform/macos/Availability.swift platform/macos/Voice.swift platform/macos/Writing.swift platform/macos/DictionarySync.swift tests/macos/sync_checks.swift tests/macos/main.swift build/core-test.o -lc++ -framework Security -framework Combine -framework Carbon -framework AppKit -framework SwiftUI -framework Speech -framework AVFoundation -o build/cloud-tests
build/cloud-tests
