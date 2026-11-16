#!/bin/sh
# Required: real iOS MSL 2.1 compilation. --runtime additionally requires macOS GPU.
set -eu
case "${1-}" in
    '') runtime=0 ;;
    --runtime) runtime=1 ;;
    *) echo "usage: $0 [--runtime]" >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || exit 2
root=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
command -v xcrun >/dev/null 2>&1 || {
    echo "BLOCKED: xcrun/Xcode and the iPhoneOS Metal compiler are required" >&2
    exit 1
}
python3 "$root/Scripts/generate_shader.py" --check
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun --sdk iphoneos --find metal >/dev/null
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nlshader.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
set -x
xcrun --sdk iphoneos metal -std=ios-metal2.1 -mios-version-min=12.0 \
    -isysroot "$sdk" -c "$root/src/DustShader.metal" -o "$tmp/DustShader.air"
set +x
test -s "$tmp/DustShader.air"
echo "PASS: production iOS MSL 2.1 compiled to AIR (not a rendering test)"
if [ "$runtime" -eq 0 ]; then
    echo "NOTAVAILABLE: macOS runtime not requested; no GPU/pipeline result"
    exit 0
fi
set -x
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror \
    -mmacosx-version-min=10.14 -framework Foundation -framework Metal \
    "$root/Tests/ShaderNative/main.m" "$root/src/DustShaderSource.m" \
    -o "$tmp/shader-native"
"$tmp/shader-native" "$root/src/DustShader.metal"
