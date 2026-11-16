#!/bin/sh
# 语法检查：用 stubs/ 里的最小桩头跑 clang -fsyntax-only。
# 这不是真实 iOS 构建，只验证 ObjC 语法、类型引用、方法可见性。
cd "$(dirname "$0")"

STUBS=stubs
CFLAGS="-fsyntax-only -fobjc-arc -fblocks -fobjc-runtime=ios-15.0 -x objective-c
        -I $STUBS -I src -Wall -Wextra
        -Wno-unused-parameter -Wno-unused-variable -Wno-unused-function
        -Wno-objc-missing-super-calls -Wno-nullability-completeness
        -Wno-macro-redefined -Wno-arc-performSelector-leaks
        -Wno-incompatible-pointer-types -Wno-pointer-to-enum-cast
        -Wno-unused-but-set-variable -Wno-incompatible-function-pointer-types"

fail=0
for f in src/*.m; do
    out=$(clang $CFLAGS "$f" 2>&1 | grep -E 'error|warning:' | head -6)
    if [ -n "$out" ]; then
        echo "FAIL $f"
        echo "$out"
        fail=1
    else
        echo "OK   $f"
    fi
done

for f in prefs/*.m; do
    out=$(clang -fsyntax-only -fobjc-arc -fblocks -fobjc-runtime=ios-15.0 -x objective-c \
          -I $STUBS -I prefs -Wno-everything "$f" 2>&1 | head -6)
    if [ -n "$out" ]; then
        echo "FAIL $f"
        echo "$out"
        fail=1
    else
        echo "OK   $f"
    fi
done

if [ $fail -eq 0 ]; then
    echo
    echo "全部通过（仅语法层面；不是 iOS 构建，也没有真机验证）"
else
    echo
    echo "有失败项"
fi
exit $fail
