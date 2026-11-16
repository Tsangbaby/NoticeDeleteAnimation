#!/bin/bash
# macOS/Xcode; official pinned Theos headers only.
set -euo pipefail
cd "$(dirname "$0")/.."
for tool in xcrun codesign python3; do
  command -v "$tool" >/dev/null || { echo "FAIL: $tool required (macOS/Xcode)" >&2; exit 1; }
done
mkdir -p build-evidence
run() {
  : "${THEOS:?Set THEOS to the pinned official checkout}"
  local sdk headers work bundle arch
  sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
  headers="$THEOS/include"
  [ -f "$headers/Preferences/PSListController.h" ] || headers="$THEOS/vendor/include"
  test -f "$headers/Preferences/PSListController.h"
  test -f "$headers/Preferences/PSSpecifier.h"
  xcrun simctl list -j > build-evidence/simulators.json
  python3 - <<'PY'
import json,pathlib
out=pathlib.Path('build-evidence/simulator-choice.json')
out.unlink(missing_ok=True)
j=json.load(open('build-evidence/simulators.json'))
candidates=[]
for r in j['runtimes']:
    if not r.get('isAvailable') or not r.get('identifier','').startswith('com.apple.CoreSimulator.SimRuntime.iOS-'):
        continue
    fw=pathlib.Path(r['bundlePath'])/'Contents/Resources/RuntimeRoot/System/Library/PrivateFrameworks/Preferences.framework'
    for d in j['devices'].get(r['identifier'],[]):
        if d.get('isAvailable') and fw.is_dir():
            candidates.append(dict(udid=d['udid'],name=d['name'],state=d['state'],runtime=r['identifier'],frameworks=str(fw.parent)))
            print('AVAILABLE real Preferences:',d)
if not candidates:
    raise SystemExit('FAIL: no available installed iOS simulator with real Preferences.framework')
candidates.sort(key=lambda d:d['state']!='Booted')
out.write_text(json.dumps(candidates[0],indent=2)+'\n')
print('SELECTED',json.dumps(candidates[0]))
PY
  local udid state
  read -r udid state < <(python3 -c 'import json;d=json.load(open("build-evidence/simulator-choice.json"));print(d["udid"],d["state"])')
  [ "$state" = Booted ] || xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b
  arch="$(uname -m)"
  case "$arch" in arm64|x86_64) ;; *) echo "FAIL: unsupported simulator architecture $arch"; return 1;; esac
  work="$PWD/build-evidence/preferences-smoke"
  bundle="$work/NoticeDeleteAnimation.bundle"
  mkdir -p "$bundle" "$work/link/Preferences.framework"
  cp -R layout/Library/PreferenceBundles/NoticeDeleteAnimation.bundle/. "$bundle/"
  cp layout/Library/PreferenceLoader/Preferences/com.tsangbaby.noticedeleteanimation.plist "$work/entry.plist"
  # Link-only exports; runtime class images are checked.
  cat > "$work/link/Preferences.framework/Preferences.tbd" <<'TBD'
--- !tapi-tbd
tbd-version: 4
targets: [ arm64-ios-simulator, x86_64-ios-simulator ]
install-name: /System/Library/PrivateFrameworks/Preferences.framework/Preferences
exports:
  - targets: [ arm64-ios-simulator, x86_64-ios-simulator ]
    objc-classes: [ PSListController, PSSpecifier ]
    objc-ivars: [ PSListController._specifiers ]
...
TBD
  local flags=(-target "$arch-apple-ios15.0-simulator" -isysroot "$sdk" -fobjc-arc -Werror=objc-method-access -Wno-deprecated-declarations -I "$headers" -I prefs -F "$work/link")
  local frameworks=(-framework UIKit -framework Foundation -framework CoreFoundation -framework Preferences)
  xcrun --sdk iphonesimulator clang "${flags[@]}" -dynamiclib prefs/NLRootListController.m prefs/NLBannerStatusController.m "${frameworks[@]}" -o "$bundle/NoticeDeleteAnimation"
  xcrun --sdk iphonesimulator clang "${flags[@]}" Tests/PreferencesSmoke/main.m "${frameworks[@]}" -o "$work/preferences-smoke"
  codesign -f -s - "$bundle/NoticeDeleteAnimation"
  codesign -f -s - "$work/preferences-smoke"
  xcrun simctl spawn "$udid" "$work/preferences-smoke" "$bundle" "$work/entry.plist"
}
run 2>&1 | tee build-evidence/preferences-native-tests.txt
python3 - <<'PY'
from pathlib import Path
lines=Path('build-evidence/preferences-native-tests.txt').read_text().splitlines()
if sum(s.startswith('PREFERENCES NATIVE PASS:') for s in lines)!=1:
    raise SystemExit('FAIL: missing or duplicate native completion marker')
PY
