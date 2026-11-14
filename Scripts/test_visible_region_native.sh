#!/bin/bash
# Actual UIKit + production planner, not a Foundation/geometry mock.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build-evidence/visible-region-native
log=build-evidence/visible-region-native-tests.txt
unavailable() {
  echo "NOT AVAILABLE: $*; production visible-region UIKit tests NOT executed." | tee "$log"
  exit 1
}
command -v xcrun >/dev/null 2>&1 || unavailable 'Xcode/iOS simulator runtime is missing'
[ -f build-evidence/simulator-choice.json ] || unavailable 'Preferences regression selected no iOS simulator'
udid="$(python3 -c 'import json;print(json.load(open("build-evidence/simulator-choice.json"))["udid"])')"
work="$PWD/build-evidence/visible-region-native"
xcrun simctl list -j > "$work/simulators.json"
# Reuse, but verify, the Preferences choice: a stale choice cannot be a pass.
python3 - "$udid" "$work/simulators.json" <<'PY'
import json, sys
udid, path = sys.argv[1:]
j = json.load(open(path))
for r in j.get('runtimes', []):
    if not r.get('isAvailable') or 'iOS' not in r.get('name', ''):
        continue
    for d in j.get('devices', {}).get(r['identifier'], []):
        if d.get('udid') == udid and d.get('isAvailable'):
            raise SystemExit(0)
raise SystemExit('NOT AVAILABLE: selected real iOS runtime/device is unavailable; NOT a native pass.')
PY
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
triple="$(uname -m)-apple-ios15.0-simulator"
xcrun simctl boot "$udid" || true
xcrun simctl bootstatus "$udid" -b
xcrun --sdk iphonesimulator swiftc -parse-as-library -target "$triple" -sdk "$sdk" -swift-version 5 \
  Sources/Tweak/AncestorGate.swift Sources/Tweak/VisibleRegion.swift Tests/VisibleRegionNative/main.swift \
  -framework UIKit -framework QuartzCore -framework Foundation -o "$work/test-visible-region"
codesign -s - "$work/test-visible-region"
xcrun simctl spawn "$udid" "$work/test-visible-region" 2>&1 | tee "$log"
