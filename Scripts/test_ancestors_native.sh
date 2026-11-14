#!/bin/bash
# Reuse the actual runtime selected and booted by the Preferences regression.
set -euo pipefail
mkdir -p build-evidence/ancestor-native
if [ ! -f build-evidence/simulator-choice.json ]; then
  echo 'NOT AVAILABLE: no iOS simulator runtime; production gate not executed.' | tee build-evidence/ancestor-native-tests.txt
  exit 1
fi
udid="$(python3 -c 'import json;print(json.load(open("build-evidence/simulator-choice.json"))["udid"])')"
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
triple="$(uname -m)-apple-ios15.0-simulator"
work="$PWD/build-evidence/ancestor-native"
# Compile the pinned, hash-verified production alpha5 gate as a differential control.
python3 - <<'PY'
import hashlib,pathlib,subprocess
baseline='1e6b54ed910cc307103698af0224e26667a32caa'
b=subprocess.check_output(['git','show',baseline+':Sources/Tweak/AncestorGate.swift'])
assert hashlib.sha256(b).hexdigest()=='73efa1ada05f13d0d8950e673406136794c7855f5b8b7ffe613e9dc0b9b72356'
p=pathlib.Path('build-evidence/ancestor-native')
(p/'alpha5-original.swift').write_bytes(b)
s=b.decode().replace('NDAAncestor','NDAAlpha5Ancestor')
(p/'alpha5-baseline.swift').write_text(s)
(p/'baseline-commit.txt').write_text(baseline+'\n')
PY
xcrun --sdk iphonesimulator clang -target "$triple" -isysroot "$sdk" -fobjc-arc -I Sources/Bridge -c Sources/Bridge/NDADiagnostics.m -o "$work/diagnostics.o"
xcrun --sdk iphonesimulator swiftc -parse-as-library -target "$triple" -sdk "$sdk" -swift-version 5 -import-objc-header Sources/Bridge/NDABridge.h Sources/Tweak/AncestorGate.swift "$work/alpha5-baseline.swift" Tests/AncestorNative/main.swift "$work/diagnostics.o" -framework UIKit -framework QuartzCore -framework Foundation -framework CoreFoundation -o "$work/test-ancestors"
codesign -s - "$work/test-ancestors"
xcrun simctl spawn "$udid" "$work/test-ancestors" 2>&1 | tee build-evidence/ancestor-native-tests.txt
