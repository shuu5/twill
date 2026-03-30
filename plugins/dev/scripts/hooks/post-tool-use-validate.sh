#!/usr/bin/env bash
# PostToolUse hook: Edit/Write 後に loom validate を実行
set -euo pipefail

# stdin を消費（Claude Code PostToolUse は stdin に JSON を渡す）
cat > /dev/null 2>&1 || true

# loom コマンドが存在しない場合はスキップ
if ! command -v loom &>/dev/null; then
  exit 0
fi

# deps.yaml が存在しない場合はスキップ
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ ! -f "$PLUGIN_ROOT/deps.yaml" ]]; then
  exit 0
fi

# loom validate 実行
cd "$PLUGIN_ROOT"
VALIDATE_EXIT=0
OUTPUT=$(loom validate 2>&1) || VALIDATE_EXIT=$?

# loom クラッシュ時は報告
if [[ $VALIDATE_EXIT -ne 0 ]]; then
  echo "loom validate failed (exit $VALIDATE_EXIT)"
  echo "$OUTPUT"
elif echo "$OUTPUT" | grep -qi "violation"; then
  echo "$OUTPUT"
fi
