#!/usr/bin/env bash
# worker-red-only-detector.sh - RED-only PR 検出（--pr-json 入力版）
#
# PR JSON を受け取り、変更ファイルがテストファイルのみで実装ファイルがない場合に CRITICAL を出力する。
# Issue #1482 AC2/AC5 の検出ロジックを bash で実装。
#
# Usage: bash worker-red-only-detector.sh --pr-json '{"labels":[],"files":[...]}'
# Exit: 0（常に成功、CRITICAL は stdout に出力）

set -euo pipefail

PR_JSON=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr-json)
      PR_JSON="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$PR_JSON" ]]; then
  echo "Usage: worker-red-only-detector.sh --pr-json '<json>'" >&2
  exit 1
fi

# red-only ラベルチェック（Issue #1613: SKIP path 廃止 → WARNING 発行に変更）
# 旧仕様: red-only label 付き PR は SKIP exit 0 で検出を pass-through していたが、
# PR #1608 で「label 付与 + 手動 merge」による content-REJECT bypass が発生したため、
# label が付いていても WARNING を発行し follow-up Issue の存在を verify する責務を残す。
has_red_only_label=$(echo "$PR_JSON" | jq -r '[.labels[]?.name] | map(select(. == "red-only")) | length > 0')

# ファイルリスト取得
mapfile -t FILE_PATHS < <(echo "$PR_JSON" | jq -r '.files[]?.path // empty')

if [[ ${#FILE_PATHS[@]} -eq 0 ]]; then
  echo "OK: 変更ファイルなし"
  exit 0
fi

# テストファイル判定
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
  [[ "$f" == *ac-test-mapping*.yaml ]] && return 0
  return 1
}

# impl-candidate ファイルが存在するか確認
has_impl_file=false
for file in "${FILE_PATHS[@]}"; do
  if ! _is_test_file "$file"; then
    has_impl_file=true
    break
  fi
done

if [[ "$has_impl_file" == "false" ]]; then
  if [[ "$has_red_only_label" == "true" ]]; then
    # Issue #1613 AC2: red-only label 付き RED-only PR は WARNING に降格し、
    # follow-up Issue（実装 PR）の存在 verify を要求する。
    echo "WARNING: RED-only PR を検出しました（red-only label 付き、confidence: 85）"
    echo "変更ファイルに実装ファイルが含まれていません。"
    echo "follow-up Issue（GREEN 実装 PR）の存在を verify してください — 不在なら scripts/red-only-followup-create.sh で起票。"
    exit 0
  fi
  echo "CRITICAL: RED-only PR を検出しました（confidence: 85）"
  echo "変更ファイルに実装ファイルが含まれていません。"
  exit 0
fi

echo "OK: 実装ファイルが含まれています"
exit 0
