#!/bin/bash
# Collect EVERY native source diagnostic before make; never use local stubs.
set -uo pipefail
cd "$(dirname "$0")/.."
: "${THEOS:?Pinned actual RootHide Theos required}"
mkdir -p build-evidence
sdk="$(xcrun --sdk iphoneos --show-sdk-path)" || exit 1
headers="$THEOS/include"
[ -d "$headers/Preferences" ] || headers="$THEOS/vendor/include"
status=0
for arch in arm64 arm64e; do
  for source in src/*.m prefs/*.m; do
    echo "NATIVE SOURCE: $arch $source"
    xcrun --sdk iphoneos clang -target "$arch-apple-ios15.0" -isysroot "$sdk" \
      -fobjc-arc -fblocks -fsyntax-only -ferror-limit=0 -Wall -Wextra \
      -Werror=implicit-function-declaration -Werror=incompatible-pointer-types \
      -Werror=objc-method-access -Wno-deprecated-declarations \
      -I "$headers" -I "$THEOS/vendor/include" -I src -I prefs "$source" || status=1
  done
done
if [ "$status" -eq 0 ]; then echo 'NATIVE SOURCE PASS: actual Apple SDK both architectures (not link or runtime)'; fi
exit "$status"
