#!/bin/sh
# 汇总所有 REVERIFY 标记，生成 REVERIFY-LIST.md
cd "$(dirname "$0")"
OUT=REVERIFY-LIST.md
{
  echo "# REVERIFY 清单"
  echo
  echo "以下位置是从反汇编**推断**而非直接证据的地方。首次真机验证时优先看这些。"
  echo
  echo "| 文件:行 | 内容 |"
  echo "|---|---|"
  rg -n --no-heading -o 'REVERIFY:?\s*(.*)$' src prefs 2>/dev/null \
    | sed -E 's/^(src\/[^:]+|prefs\/[^:]+):([0-9]+):REVERIFY:?[[:space:]]*/\1:\2\t/' \
    | awk -F'\t' '{gsub(/\|/,"\\|",$2); printf "| %s | %s |\n", $1, $2}'
} > "$OUT"
echo "wrote $OUT"
grep -c '^| ' "$OUT" || true
