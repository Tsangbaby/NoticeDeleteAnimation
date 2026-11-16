#!/bin/bash
# Actual CoreGraphics helper on the cloud Mac; no simulator or GPU substitute.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build-evidence/geometry-native
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror -I src \
  Tests/GeometryNative/main.m -framework Foundation -framework CoreGraphics \
  -o build-evidence/geometry-native/test-geometry
build-evidence/geometry-native/test-geometry | tee build-evidence/geometry-native-tests.txt
