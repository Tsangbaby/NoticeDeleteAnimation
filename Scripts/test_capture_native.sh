#!/bin/bash
# Real UIKit only. Reuse the runtime selected/booted by Preferences; never install
# an app on a device (or simulator), boot a replacement, or turn absence into PASS.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build-evidence/capture-native
work="$PWD/build-evidence/capture-native"
log="$PWD/build-evidence/capture-native-tests.txt"
run_capture() {
trap 'status=$?; if [ "$status" -ne 0 ]; then echo "CAPTURE NATIVE FAILED (exit $status)"; fi' EXIT
for tool in xcrun codesign python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "NOT AVAILABLE: $tool missing; real UIKit capture regression NOT executed."
    exit 1
  fi
done
if [ ! -f build-evidence/simulator-choice.json ]; then
  echo 'NOT AVAILABLE: no existing simulator choice; real UIKit capture regression NOT executed.'
  exit 1
fi
udid="$(python3 -c 'import json; print(json.load(open("build-evidence/simulator-choice.json"))["udid"])')"
xcrun simctl list devices --json > "$work/devices.json"
python3 - "$udid" "$work/devices.json" <<'PY'
import json, sys
chosen, path = sys.argv[1:]
devices = [d for group in json.load(open(path))['devices'].values() for d in group]
if not any(d.get('udid') == chosen and d.get('isAvailable') and d.get('state') == 'Booted' for d in devices):
    sys.exit('NOT AVAILABLE: chosen iOS simulator is not available and already booted; capture gate NOT executed.')
PY
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
arch="$(uname -m)"
case "$arch" in arm64|x86_64) ;; *) echo 'FAIL: unsupported simulator host architecture'; exit 1 ;; esac
triple="$arch-apple-ios15.0-simulator"
app="$work/NDACaptureNative.app"
mkdir -p "$app"
# A test-only bundle identity makes UIApplicationMain usable with simctl spawn;
# this is NOT the installed Preferences/tweak application identity.
python3 - "$app/Info.plist" <<'PY'
import plistlib, sys
info = {
    'CFBundleIdentifier': 'com.tsangbaby.noticedeleteanimation.capture-native-tests',
    'CFBundleExecutable': 'NDACaptureNative', 'CFBundleName': 'NDACaptureNative',
    'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1',
    'CFBundleShortVersionString': '1.0', 'MinimumOSVersion': '15.0',
    'CFBundleSupportedPlatforms': ['iPhoneSimulator'], 'LSRequiresIPhoneOS': True,
    'UIDeviceFamily': [1, 2], 'UISupportedInterfaceOrientations': ['UIInterfaceOrientationPortrait'],
    'UILaunchScreen': {},
}
with open(sys.argv[1], 'wb') as f:
    plistlib.dump(info, f)
PY
# Compile the actual production .m, not a snapshot algorithm copied into tests.
xcrun --sdk iphonesimulator clang -target "$triple" -isysroot "$sdk" \
  -fobjc-arc -fblocks -fobjc-exceptions -Wall -Wextra -Werror \
  -I Sources/Bridge Sources/Bridge/NDACapture.m Tests/CaptureNative/main.m \
  -framework UIKit -framework QuartzCore -framework Foundation -framework CoreGraphics \
  -o "$app/NDACaptureNative"
codesign --force -s - "$app/NDACaptureNative"
codesign --verify --strict "$app/NDACaptureNative"
python3 - "$udid" "$app/NDACaptureNative" <<'PY'
import subprocess, sys
try:
    result = subprocess.run(['xcrun', 'simctl', 'spawn', sys.argv[1], sys.argv[2]],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=120, text=True, errors='replace')
except subprocess.TimeoutExpired:
    sys.exit('FAIL: real UIKit capture runtime timed out (no PASS).')
# Output contains fixed test labels and UIKit runtime messages, never images.
print(result.stdout, end='', flush=True)
if result.returncode != 0:
    sys.exit(result.returncode if result.returncode > 0 else 1)
if not any(line.startswith('CAPTURE NATIVE PASS: ') for line in result.stdout.splitlines()):
    sys.exit('FAIL: runtime exited without completing the pixel assertions.')
PY
}
run_capture 2>&1 | tee "$log"
