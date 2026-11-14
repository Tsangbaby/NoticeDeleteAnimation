#!/bin/bash
# Best feasible native smoke: actual simulator framework, never an ABI mock.
set -euo pipefail
mkdir -p build-evidence
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun simctl list -j > build-evidence/simulators.json
python3 - <<'PY'
import json,pathlib
j=json.load(open('build-evidence/simulators.json'))
for r in j['runtimes']:
    if r.get('isAvailable') and 'iOS' in r.get('name',''):
        root=pathlib.Path(r['bundlePath'])/'Contents/Resources/RuntimeRoot'
        fw=root/'System/Library/PrivateFrameworks/Preferences.framework'
        devices=j['devices'].get(r['identifier'],[])
        for d in devices:
            if d.get('isAvailable') and fw.exists():
                pathlib.Path('build-evidence/simulator-choice.json').write_text(json.dumps({'frameworks':str(fw.parent),'udid':d['udid']}))
                raise SystemExit(0)
pathlib.Path('build-evidence/preferences-native-load.txt').write_text('NOT AVAILABLE: no installed iOS simulator runtime containing real Preferences.framework. Native compile/package is not a UIKit load test.\n')
PY
if [ ! -f build-evidence/simulator-choice.json ]; then
  cat build-evidence/preferences-native-load.txt
  exit 0
fi
fw="$(python3 -c 'import json;print(json.load(open("build-evidence/simulator-choice.json"))["frameworks"])')"
udid="$(python3 -c 'import json;print(json.load(open("build-evidence/simulator-choice.json"))["udid"])')"
xcrun simctl boot "$udid" || true
xcrun simctl bootstatus "$udid" -b
arch="$(uname -m)"
triple="$arch-apple-ios15.0-simulator"
headers="$THEOS/include"
[ -d "$headers/Preferences" ] || headers="$THEOS/vendor/include"
mkdir -p build-evidence/native-load
work="$PWD/build-evidence/native-load"
# A link-only declaration; dyld must resolve the REAL simulator Preferences image.
# Simulator private frameworks live in the runtime shared cache, not the public SDK.
mkdir -p "$work/link/Preferences.framework"
cat > "$work/link/Preferences.framework/Preferences.tbd" <<'TBD'
--- !tapi-tbd
tbd-version: 4
targets: [ arm64-ios-simulator, x86_64-ios-simulator ]
install-name: /System/Library/PrivateFrameworks/Preferences.framework/Preferences
exports:
  - targets: [ arm64-ios-simulator, x86_64-ios-simulator ]
    objc-classes: [ PSListController, PSSpecifier ]
...
TBD
fw="$work/link"
for mode in new old; do
  bundle="$work/$mode/NDAPreferences.bundle"
  mkdir -p "$bundle"
  cp Preferences/Resources/Info.plist "$bundle/Info.plist"
  cp layout/Library/PreferenceLoader/Preferences/NoticeDeleteAnimation.plist "$work/$mode/entry.plist"
  src="$PWD/Preferences/NDASettingsController.swift"
  if [ "$mode" = old ]; then
    git show 4ff6ab8af383582b929a12bdf51b97f8319a5d22:Preferences/NDASettingsController.swift > "$work/old.swift"
    git show 4ff6ab8af383582b929a12bdf51b97f8319a5d22:layout/Library/PreferenceLoader/Preferences/NoticeDeleteAnimation.plist > "$work/$mode/entry.plist"
    src="$work/old.swift"
  fi
  xcrun --sdk iphonesimulator clang -target "$triple" -isysroot "$sdk" -fobjc-arc -I "$headers" -c Preferences/NDAPreferencesBridge.m -o "$work/$mode/bridge.o"
  xcrun --sdk iphonesimulator swiftc -target "$triple" -sdk "$sdk" -swift-version 5 -I "$headers" -F "$fw" -import-objc-header Preferences/NDAPreferencesBridge.h -emit-library -module-name NDAPreferences "$src" "$work/$mode/bridge.o" -framework UIKit -framework Foundation -framework CoreFoundation -framework Preferences -o "$bundle/NDAPreferences"
  codesign -s - "$bundle/NDAPreferences"
done
xcrun --sdk iphonesimulator clang -target "$triple" -isysroot "$sdk" -fobjc-arc -I "$headers" -F "$fw" Tests/PreferencesLoad/main.m -framework UIKit -framework Foundation -framework Preferences -o "$work/test-load"
codesign -s - "$work/test-load"
for mode in old new; do
  xcrun simctl spawn "$udid" "$work/test-load" "$work/$mode/NDAPreferences.bundle" "$work/$mode/entry.plist" "$mode" 2>&1 | tee -a build-evidence/preferences-native-load.txt
done
