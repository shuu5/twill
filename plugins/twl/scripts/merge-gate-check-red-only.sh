#!/usr/bin/env bash
# merge-gate-check-red-only.sh - RED-only PR 検出チェック（merge-gate Step）
#
# PR の変更ファイルがテストファイルのみ（実装ファイルなし）の場合を検出して REJECT する。
# Issue #1476: PR #1470 が test のみで実装欠落のまま merge された問題の再発防止。
#
# 呼び出し: bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-check-red-only.sh"

set -euo pipefail

# 変更ファイルリストを取得
CHANGED_FILES=$(git diff --name-only origin/main 2>/dev/null || git diff --name-only HEAD 2>/dev/null || true)

if [[ -z "$CHANGED_FILES" ]]; then
  exit 0
fi

# テストファイルパターン判定
_is_test_file() {
  local f="$1"
  [[ "$f" == *.bats ]] && return 0
  [[ "$f" == *test_*.py ]] && return 0
  [[ "$f" == *_test.py ]] && return 0
  [[ "$f" == *.test.ts ]] && return 0
  [[ "$f" == *.spec.ts ]] && return 0
  [[ "$f" == *.test.js ]] && return 0
  [[ "$f" == *.spec.js ]] && return 0
  [[ "$f" == */tests/* ]] && return 0
  [[ "$f" == */test/* ]] && return 0
  [[ "$f" == ac-test-mapping*.yaml ]] && return 0
  return 1
}

# 実装ファイルが1つでも含まれるか確認
has_impl_file=false
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  if ! _is_test_file "$file"; then
    has_impl_file=true
    break
  fi
done <<< "$CHANGED_FILES"

if [[ "$has_impl_file" == "false" ]]; then
  echo "REJECT: RED-only PR を検出しました。変更ファイルがテストファイルのみで実装ファイルが含まれていません" >&2
  echo "変更ファイル:" >&2
  echo "$CHANGED_FILES" | sed 's/^/  /' >&2
  exit 1
fi

exit 0
