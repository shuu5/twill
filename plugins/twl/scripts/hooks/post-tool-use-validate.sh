#!/usr/bin/env bash
# PostToolUse hook: Edit/Write 後に twl --validate + twl --check を実行
set -euo pipefail

# stdin を消費（Claude Code PostToolUse は stdin に JSON を渡す）
cat > /dev/null 2>&1 || true

# twl コマンドが存在しない場合はスキップ
if ! command -v twl &>/dev/null; then
  exit 0
fi

# deps.yaml が存在しない場合はスキップ
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ ! -f "$PLUGIN_ROOT/deps.yaml" ]]; then
  exit 0
fi

cd "$PLUGIN_ROOT"

# twl --check 実行（ファイル存在確認 + chain ステップ同期）
CHECK_EXIT=0
CHECK_OUTPUT=$(twl --check 2>&1) || CHECK_EXIT=$?

if [[ $CHECK_EXIT -ne 0 ]]; then
  echo "twl --check failed (exit $CHECK_EXIT)"
  echo "$CHECK_OUTPUT"
elif echo "$CHECK_OUTPUT" | grep -qi "missing"; then
  echo "$CHECK_OUTPUT"
fi

# twl --validate 実行（型ルール検証）
VALIDATE_EXIT=0
VALIDATE_OUTPUT=$(twl --validate 2>&1) || VALIDATE_EXIT=$?

if [[ $VALIDATE_EXIT -ne 0 ]]; then
  echo "twl --validate failed (exit $VALIDATE_EXIT)"
  echo "$VALIDATE_OUTPUT"
elif echo "$VALIDATE_OUTPUT" | grep -qi "violation"; then
  echo "$VALIDATE_OUTPUT"
fi

# PostToolUse は警告のみ、ブロックしない
exit 0
