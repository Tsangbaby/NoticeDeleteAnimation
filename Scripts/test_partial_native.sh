#!/bin/bash
# Real UIKit + ALL production integration sources. Only MSHookMessageEx is a
# test runtime IMP shim; NOT actual Substrate/private SpringBoard/device coverage.
set -euo pipefail
cd "$(dirname "$0")/.."
for tool in xcrun codesign python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "NOT AVAILABLE: $tool missing; partial-native NOT executed."; exit 1; }
done
[ -f build-evidence/simulator-choice.json ] || { echo 'NOT AVAILABLE: run Preferences native gate first; no simulator choice.'; exit 1; }
work="$PWD/build-evidence/partial-native"
mkdir -p "$work"
exec > >(tee "$PWD/build-evidence/partial-native-tests.txt") 2>&1
trap 's=$?; if [ "$s" -ne 0 ]; then echo "PARTIAL NATIVE FAILED (exit $s)"; fi' EXIT
udid="$(python3 -c 'import json;print(json.load(open("build-evidence/simulator-choice.json"))["udid"])')"
xcrun simctl list -j > "$work/simulators.json"
python3 - "$udid" "$work/simulators.json" <<'PY'
import json, sys
chosen, path = sys.argv[1:]
j = json.load(open(path))
for r in j.get('runtimes', []):
    if not r.get('isAvailable') or 'iOS' not in r.get('name', ''):
        continue
    if any(d.get('udid') == chosen and d.get('isAvailable') and d.get('state') == 'Booted'
           for d in j.get('devices', {}).get(r['identifier'], [])):
        break
else:
    sys.exit('NOT AVAILABLE: Preferences choice has no available, already booted iOS runtime; NOT a native pass.')
PY
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
arch="$(uname -m)"
case "$arch" in arm64|x86_64) ;; *) echo 'FAIL: unsupported simulator host architecture'; exit 1 ;; esac
triple="$arch-apple-ios15.0-simulator"
app="$work/NDAPartialNative.app"
mkdir -p "$app"
cp Tests/PartialNative/Info.plist "$app/Info.plist"
objects=()
for source in Sources/Bridge/NDABridge.m Sources/Bridge/NDACapture.m Sources/Bridge/NDADiagnostics.m Tests/PartialNative/Fixtures.m; do
  object="$work/$(basename "$source" .m).o"
  xcrun --sdk iphonesimulator clang -target "$triple" -isysroot "$sdk" \
    -fobjc-arc -fblocks -fobjc-exceptions -O1 -Wall -Wextra \
    -I Tests/PartialNative -I Sources/Bridge -c "$source" -o "$object"
  objects+=("$object")
done
xcrun --sdk iphonesimulator swiftc -parse-as-library -target "$triple" -sdk "$sdk" -swift-version 5 -O \
  -I Tests/PartialNative -I Sources/Bridge -import-objc-header Tests/PartialNative/TestBridge.h \
  Sources/Core/*.swift Sources/Tweak/AncestorGate.swift Sources/Tweak/VisibleRegion.swift \
  Sources/Tweak/Animator.swift Sources/Tweak/Entry.swift Tests/PartialNative/main.swift "${objects[@]}" \
  -framework UIKit -framework QuartzCore -framework Foundation -framework CoreFoundation -framework CoreGraphics \
  -o "$app/NDAPartialNative"
codesign --force -s - "$app/NDAPartialNative"
codesign --force -s - "$app"
codesign --verify --strict "$app"
# Spawn the LOCAL bundle executable only; no simctl install, device, or respring.
python3 - "$udid" "$app/NDAPartialNative" <<'PY'
import subprocess, sys
try:
    r = subprocess.run(['xcrun', 'simctl', 'spawn', sys.argv[1], sys.argv[2]],
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120,
                       text=True, errors='replace')
except subprocess.TimeoutExpired:
    sys.exit('FAIL: partial-native runtime timeout; no native pass.')
print(r.stdout, end='', flush=True)
if r.returncode or not any(l.startswith('PARTIAL NATIVE PASS: ') for l in r.stdout.splitlines()):
    sys.exit(r.returncode if r.returncode > 0 else 1)
PY
