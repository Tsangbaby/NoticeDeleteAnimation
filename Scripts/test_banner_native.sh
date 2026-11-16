#!/bin/bash
# macOS/Xcode only: real visible UIKit CI app; production NLBannerDust.m.
# Effect + IMP shim are TEST DOUBLES, not Metal, Substrate, SB or real tap tests.
set -euo pipefail
cd "$(dirname "$0")/.."
for tool in xcrun codesign python3; do
  command -v "$tool" >/dev/null || { echo "FAIL: $tool required (macOS/Xcode)" >&2; exit 1; }
done
mkdir -p build-evidence/banner-regression
run() {
  local work sdk arch udid bundle app
  work="$PWD/build-evidence/banner-regression"
  test -f build-evidence/simulator-choice.json || {
    echo 'FAIL: Preferences-selected simulator-choice.json required' >&2; return 1;
  }
  xcrun simctl list -j > "$work/simulators.json"
  python3 - "$work" <<'PY'
import json, pathlib, sys, uuid
work = pathlib.Path(sys.argv[1])
choice = json.loads(pathlib.Path('build-evidence/simulator-choice.json').read_text())
items = json.loads((work / 'simulators.json').read_text())
rid = choice.get('runtime', '')
runtime = next((r for r in items['runtimes'] if r['identifier'] == rid), None)
if not (runtime and runtime.get('isAvailable') and rid.startswith('com.apple.CoreSimulator.SimRuntime.iOS-')):
    raise SystemExit('FAIL: selected iOS runtime unavailable')
device = next((d for d in items['devices'].get(rid, []) if d['udid'] == choice.get('udid')), None)
if not (device and device.get('isAvailable') and device.get('state') == 'Booted'):
    raise SystemExit('FAIL: selected iOS simulator must already be Booted')
(work / 'udid.txt').write_text(device['udid'] + '\n')
(work / 'bundle.txt').write_text('org.noticeci.banner-regression.' + uuid.uuid4().hex + '\n')
(work / 'simulator-choice.json').write_text(json.dumps(dict(runtime=rid, **device), indent=2) + '\n')
print('REUSED booted iOS simulator:', rid, device['udid'], flush=True)
PY
  read -r udid < "$work/udid.txt"
  read -r bundle < "$work/bundle.txt"
  sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
  arch="$(uname -m)"
  case "$arch" in arm64|x86_64) ;; *) echo "FAIL: unsupported architecture $arch" >&2; return 1;; esac
  app="$work/BannerRegression.app"
  mkdir -p "$app"
  # Test shim header only; NO stubs/ or real Substrate library; actual production TU.
  xcrun --sdk iphonesimulator clang \
    -target "$arch-apple-ios15.0-simulator" -isysroot "$sdk" \
    -fobjc-arc -fblocks -Wall -Wextra -Werror=objc-method-access \
    -Werror=implicit-function-declaration -Wno-unused-parameter -Wno-deprecated-declarations \
    -I Tests/BannerRegression -I src \
    Tests/BannerRegression/main.m src/NLBannerDust.m \
    -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore -framework Metal \
    -o "$app/BannerRegression"
  python3 - "$app" "$bundle" <<'PY'
import pathlib, plistlib, sys
app, bundle = sys.argv[1:]
pathlib.Path(app, 'Info.plist').write_bytes(plistlib.dumps(dict(
    CFBundleIdentifier=bundle, CFBundleExecutable='BannerRegression',
    CFBundleName='BannerRegression', CFBundlePackageType='APPL',
    CFBundleVersion='1', CFBundleShortVersionString='1.0', MinimumOSVersion='15.0',
    LSRequiresIPhoneOS=True, UIDeviceFamily=[1, 2], UILaunchScreen={})))
PY
  codesign -f -s - "$app"
  # A unique simulator-only app provides a real visible window (not user device).
  python3 - "$udid" "$bundle" "$app" "$work" <<'PY'
import pathlib, re, subprocess, sys
udid, bundle, app, work = sys.argv[1:]
try:
    subprocess.run(['xcrun', 'simctl', 'install', udid, app], check=True, timeout=60)
    try:
        result = subprocess.run(['xcrun', 'simctl', 'launch', '--console', '--terminate-running-process',
                                 udid, bundle], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, timeout=90)
        output = result.stdout
    except subprocess.TimeoutExpired as error:
        output = error.stdout or b''
        if isinstance(output, bytes): output = output.decode(errors='replace')
        pathlib.Path(work, 'runtime.txt').write_text(output)
        print(output, end='', flush=True)
        raise SystemExit('FAIL: banner native app timed out / missing completion')
    pathlib.Path(work, 'runtime.txt').write_text(output)
    print(output, end='', flush=True)
    if result.returncode != 0: raise SystemExit(f'FAIL: native launch exited {result.returncode}')
    markers = [line for line in output.splitlines() if line.startswith('BANNER NATIVE PASS:')]
    pattern = r'BANNER NATIVE PASS: ([1-9][0-9]*) checks \(fake effect; no Metal/Substrate/private SpringBoard/click routing\)'
    if len(markers) != 1 or not re.fullmatch(pattern, markers[0]):
        raise SystemExit('FAIL: missing/duplicate/invalid native completion marker')
finally:
    subprocess.run(['xcrun', 'simctl', 'terminate', udid, bundle], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
    subprocess.run(['xcrun', 'simctl', 'uninstall', udid, bundle], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
PY
}
run 2>&1 | tee build-evidence/banner-native-tests.txt
