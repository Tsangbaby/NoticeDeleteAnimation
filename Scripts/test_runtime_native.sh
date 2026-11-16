#!/bin/bash
# macOS/Xcode only. Real iOS Simulator + production loader/ABI; explicitly NOT
# production deletion, Substrate, private SpringBoard, shader or rendering tests.
set -euo pipefail
cd "$(dirname "$0")/.."
for tool in xcrun codesign python3; do
  command -v "$tool" >/dev/null || { echo "FAIL: $tool required (macOS/Xcode)" >&2; exit 1; }
done
mkdir -p build-evidence/runtime-smoke
run() {
  local work sdk arch udid
  work="$PWD/build-evidence/runtime-smoke"
  # Reuse the Preferences smoke choice; never install a runtime or boot a device.
  test -f build-evidence/simulator-choice.json || {
    echo 'FAIL: run Preferences native smoke first; simulator-choice.json is required' >&2
    return 1
  }
  xcrun simctl list -j > "$work/simulators.json"
  python3 - "$work" <<'PY'
import json
import pathlib
import sys

work = pathlib.Path(sys.argv[1])
choice = json.loads(pathlib.Path('build-evidence/simulator-choice.json').read_text())
inventory = json.loads((work / 'simulators.json').read_text())
runtime_id = choice.get('runtime', '')
runtime = next((r for r in inventory['runtimes'] if r['identifier'] == runtime_id), None)
if not (runtime and runtime.get('isAvailable') and
        runtime_id.startswith('com.apple.CoreSimulator.SimRuntime.iOS-')):
    raise SystemExit('FAIL: selected iOS simulator runtime is not available')
device = next((d for d in inventory['devices'].get(runtime_id, [])
               if d['udid'] == choice.get('udid')), None)
if not (device and device.get('isAvailable') and device.get('state') == 'Booted'):
    raise SystemExit('FAIL: Preferences-selected simulator must already be available and Booted')
(work / 'simulator-udid.txt').write_text(device['udid'] + '\n')
(work / 'simulator-choice.json').write_text(json.dumps(dict(runtime=runtime_id, **device), indent=2) + '\n')
print('REUSED booted iOS simulator:', runtime_id, device['udid'], flush=True)
PY
  read -r udid < "$work/simulator-udid.txt"
  sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
  arch="$(uname -m)"
  case "$arch" in arm64|x86_64) ;; *) echo "FAIL: unsupported simulator architecture $arch" >&2; return 1;; esac
  # Test include path precedes src; never use repository stubs/ or a real Substrate
  # library. Compile the unchanged production installer, NOT a copied installer.
  xcrun --sdk iphonesimulator clang \
    -target "$arch-apple-ios15.0-simulator" -isysroot "$sdk" \
    -fobjc-arc -fblocks -Wall -Wextra -Werror=objc-method-access \
    -Werror=implicit-function-declaration -Wno-unused-parameter -Wno-deprecated-declarations \
    -I Tests/RuntimeSmoke -I src \
    Tests/RuntimeSmoke/main.m src/NLNotificationHookLoader.m \
    -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics -framework Metal \
    -o "$work/runtime-smoke"
  codesign -f -s - "$work/runtime-smoke"
  # Always launch through simctl, never execute the simulator binary on the host.
  # Two fresh processes isolate production static/global installation state.
  python3 - "$udid" "$work/runtime-smoke" "$work" <<'PY'
import pathlib
import re
import subprocess
import sys

udid, executable, directory = sys.argv[1:]
counts = []
for name, arguments in [('valid-accessor', []), ('repaired-accessor', ['--invalid-accessor'])]:
    command = ['xcrun', 'simctl', 'spawn', udid, executable, *arguments]
    print('RUN', name, '(60 second bound)', flush=True)
    try:
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, timeout=60)
    except subprocess.TimeoutExpired as error:
        output = error.stdout or b''
        if isinstance(output, bytes):
            output = output.decode(errors='replace')
        pathlib.Path(directory, 'case-' + name + '.txt').write_text(output)
        print(output, end='', flush=True)
        raise SystemExit('FAIL: runtime smoke timed out: ' + name)
    pathlib.Path(directory, 'case-' + name + '.txt').write_text(result.stdout)
    print(result.stdout, end='', flush=True)
    if result.returncode != 0:
        raise SystemExit(f'FAIL: {name} exited {result.returncode}')
    markers = [line for line in result.stdout.splitlines()
               if line.startswith('RUNTIME NATIVE CASE PASS:')]
    pattern = r'RUNTIME NATIVE CASE PASS: ' + re.escape(name) + r' ([1-9][0-9]*) checks'
    match = re.fullmatch(pattern, markers[0]) if len(markers) == 1 else None
    if not match:
        raise SystemExit('FAIL: missing/duplicate/invalid completion marker: ' + name)
    counts.append(int(match.group(1)))
print(f'RUNTIME NATIVE PASS: {sum(counts)} checks', flush=True)
PY
}
run 2>&1 | tee build-evidence/runtime-native-tests.txt
