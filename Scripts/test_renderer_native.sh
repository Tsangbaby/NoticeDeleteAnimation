#!/bin/bash
# macOS/Xcode. Real registered UIKit app; Metal protocol fixtures, NOT GPU tests.
set -euo pipefail
cd "$(dirname "$0")/.."
for tool in xcrun codesign python3; do
  command -v "$tool" >/dev/null || { echo "FAIL: $tool required (macOS/Xcode)" >&2; exit 1; }
done
mkdir -p build-evidence/renderer-regression
run() {
  local work sdk arch udid bundle identifier
  work="$PWD/build-evidence/renderer-regression"
  test -f build-evidence/simulator-choice.json || {
    echo 'FAIL: run Preferences native smoke first; booted simulator-choice.json required' >&2; return 1;
  }
  xcrun simctl list -j > "$work/simulators.json"
  python3 - "$work" <<'PY'
import json,pathlib,sys
work=pathlib.Path(sys.argv[1])
c=json.loads(pathlib.Path('build-evidence/simulator-choice.json').read_text())
i=json.loads((work/'simulators.json').read_text())
r=next((r for r in i['runtimes'] if r['identifier']==c['runtime']),None)
d=next((d for d in i['devices'].get(c['runtime'],[]) if d['udid']==c['udid']),None)
if not (r and r.get('isAvailable') and r['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS-') and d and d.get('isAvailable') and d['state']=='Booted'):
    raise SystemExit('FAIL: selected available iOS simulator must already be Booted')
(work/'udid.txt').write_text(c['udid']+'\n')
print('RENDERER: reusing real booted iOS Simulator',c['udid'])
PY
  read -r udid < "$work/udid.txt"
  sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"; arch="$(uname -m)"
  case "$arch" in arm64|x86_64) ;; *) echo "FAIL: unsupported simulator architecture $arch" >&2; return 1;; esac
  bundle="$work/NLRendererRegression.app"
  identifier="org.native-regression.renderer.run$(date +%s)-$$"
  mkdir -p "$bundle"
  python3 - "$bundle" "$identifier" <<'PY'
import pathlib,plistlib,sys
plist=dict(CFBundleIdentifier=sys.argv[2],CFBundleExecutable='NLRendererRegression',CFBundleName='Renderer Regression',CFBundleVersion='1',CFBundleShortVersionString='1.0',CFBundlePackageType='APPL',LSRequiresIPhoneOS=True,MinimumOSVersion='15.0',CFBundleSupportedPlatforms=['iPhoneSimulator'],UIDeviceFamily=[1,2],UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait'],UILaunchScreen={})
pathlib.Path(sys.argv[1],'Info.plist').write_bytes(plistlib.dumps(plist))
PY
  # main.m includes the unchanged production renderer implementation to inject
  # file-static dependencies. The production snapshot is a separate real unit.
  xcrun --sdk iphonesimulator clang -target "$arch-apple-ios15.0-simulator" -isysroot "$sdk" \
    -fobjc-arc -fblocks -Wall -Wextra -Werror=objc-method-access \
    -Werror=implicit-function-declaration -Wno-unused-parameter -Wno-deprecated-declarations \
    -I src Tests/RendererRegression/main.m src/NLNotificationDismissalSnapshot.m src/DustShaderSource.m \
    -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics -framework Metal \
    -o "$bundle/NLRendererRegression"
  codesign -f -s - "$bundle/NLRendererRegression"
  codesign -f -s - "$bundle"
  codesign --verify --strict "$bundle"
  xcrun simctl install "$udid" "$bundle"
  python3 - "$udid" "$identifier" "$work" <<'PY'
import pathlib,re,subprocess,sys
udid,identifier,work=sys.argv[1:]
command=['xcrun','simctl','launch','--console','--terminate-running-process',udid,identifier]
try:
    p=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=90)
    output=p.stdout
except subprocess.TimeoutExpired as e:
    output=e.stdout or b''
    if isinstance(output,bytes): output=output.decode(errors='replace')
    pathlib.Path(work,'console.txt').write_text(output)
    print(output,end='',flush=True)
    raise SystemExit('FAIL: renderer app timed out (90s bound)')
finally:
    subprocess.run(['xcrun','simctl','terminate',udid,identifier],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    subprocess.run(['xcrun','simctl','uninstall',udid,identifier],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
pathlib.Path(work,'console.txt').write_text(output)
print(output,end='',flush=True)
markers=[s for s in output.splitlines() if s.startswith('RENDERER NATIVE PASS:')]
if p.returncode or len(markers)!=1 or not re.fullmatch(r'RENDERER NATIVE PASS: [1-9][0-9]* checks; real UIKit \+ Metal protocol fixtures; NO GPU render/readback claim',markers[0]):
    raise SystemExit('FAIL: renderer native app failed or missing/duplicate completion marker')
PY
}
run 2>&1 | tee build-evidence/renderer-native-tests.txt
