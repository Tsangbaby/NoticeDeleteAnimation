#!/bin/bash
# Reuse the actual runtime selected and booted by the Preferences regression.
set -euo pipefail
mkdir -p build-evidence/ancestor-native
if [ ! -f build-evidence/simulator-choice.json ]; then
  echo 'NOT AVAILABLE: no iOS simulator runtime; production gate not executed.' | tee build-evidence/ancestor-native-tests.txt
  exit 0
fi
udid="$(python3 -c 'import json;print(json.load(open("build-evidence/simulator-choice.json"))["udid"])')"
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
triple="$(uname -m)-apple-ios15.0-simulator"
work="$PWD/build-evidence/ancestor-native"
xcrun --sdk iphonesimulator clang -target "$triple" -isysroot "$sdk" -fobjc-arc -I Sources/Bridge -c Sources/Bridge/NDADiagnostics.m -o "$work/diagnostics.o"
xcrun --sdk iphonesimulator swiftc -parse-as-library -target "$triple" -sdk "$sdk" -swift-version 5 -import-objc-header Sources/Bridge/NDABridge.h Sources/Tweak/AncestorGate.swift Tests/AncestorNative/main.swift "$work/diagnostics.o" -framework UIKit -framework QuartzCore -framework Foundation -framework CoreFoundation -o "$work/test-ancestors"
codesign -s - "$work/test-ancestors"
xcrun simctl spawn "$udid" "$work/test-ancestors" 2>&1 | tee build-evidence/ancestor-native-tests.txt
