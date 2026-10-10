#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export SDKROOT="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
xcrun clang++ -std=c++17 -Wall -Wextra -Werror -O2 core/lexi.cpp tests/core_test.cpp -o build/core-tests
build/core-tests "$PWD"
xcrun clang++ -std=c++17 -g -fsanitize=address,undefined core/lexi.cpp tests/core_test.cpp -o build/core-tests-sanitized
build/core-tests-sanitized "$PWD"
