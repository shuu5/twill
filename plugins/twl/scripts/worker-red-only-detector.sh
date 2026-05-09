#!/usr/bin/env bash
# worker-red-only-detector.sh - RED-only PR 検出（--pr-json 入力版）
#
# PR JSON を受け取り、変更ファイルがテストファイルのみで実装ファイルがない場合に CRITICAL を出力する。
# Issue #1482 AC2/AC5 の検出ロジックを bash で実装。
# Issue #1626 AC1: red-only label 付き PR で follow-up Issue 存在の AND 条件を機械強制。
#                   不在なら WARNING → CRITICAL 昇格 (escape hatch 完全閉鎖)。
#
# Usage: bash worker-red-only-detector.sh --pr-json '{"labels":[],"files":[...],"number":N}'
# Exit: 0（常に成功、CRITICAL/WARNING は stdout に出力）

set -uo pipefail

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

# PR 番号取得 (Issue #1626 AC1: follow-up Issue 検索の引数)
PR_NUMBER=$(echo "$PR_JSON" | jq -r '.number // empty')

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

# AC1: follow-up Issue 存在チェック (ローカルフィルタ方式)
#   <!-- follow-up-for: PR #${pr_num} --> marker を body に含む Issue を検索する。
#   GitHub search のデフォルトでは HTML コメントが index されないため、
#   gh issue list の結果を jq でローカルフィルタする。
# 返値: 0 = follow-up 存在, 1 = 不在, 2 = gh / jq 失敗 (graceful skip)
_check_followup_issue() {
  local pr_num="$1"
  [[ -z "$pr_num" ]] && return 2
  local marker="<!-- follow-up-for: PR #${pr_num} -->"
  local issues_json
  # --limit 200: gh issue list のデフォルトは 30 件。30 件超で false absence を防ぐ
  if ! issues_json=$(gh issue list --state all --limit 200 --json number,body 2>/dev/null); then
    return 2
  fi
  local count
  # jq 失敗 (非 JSON 入力 / rate limit text 返却 等) → graceful skip
  if ! count=$(printf '%s' "$issues_json" \
      | jq --arg m "$marker" \
          '[.[] | select(.body != null and (.body | contains($m)))] | length' 2>/dev/null); then
    return 2
  fi
  [[ -z "$count" ]] && return 2
  if [[ "${count:-0}" -gt 0 ]]; then
    return 0
  fi
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
    # AC1: follow-up Issue AND 条件で WARNING/CRITICAL を判定
    # - follow-up 存在 → WARNING 維持 (TDD RED phase の正規 path)
    # - follow-up 不在 → CRITICAL 昇格 (escape hatch 閉鎖)
    # - gh 失敗 / PR_NUMBER 不明 → WARNING 維持 (graceful skip)
    _followup_status=2  # default: skip
    if [[ -n "$PR_NUMBER" ]]; then
      _check_followup_issue "$PR_NUMBER"
      _followup_status=$?
    fi

    if [[ $_followup_status -eq 1 ]]; then
      # follow-up 不在: CRITICAL 昇格
      echo "CRITICAL: RED-only PR を検出しました（red-only label 付き、follow-up Issue 不在、confidence: 90）"
      echo "変更ファイルに実装ファイルが含まれていません。"
      echo "follow-up Issue（GREEN 実装 PR）が存在しないため merge を block します。"
      echo "scripts/red-only-followup-create.sh --pr-number ${PR_NUMBER} で起票してください。"
      exit 0
    fi

    # follow-up 存在 (status=0) または graceful skip (status=2) → WARNING
    echo "WARNING: RED-only PR を検出しました（red-only label 付き、confidence: 85）"
    echo "変更ファイルに実装ファイルが含まれていません。"
    if [[ $_followup_status -eq 0 ]]; then
      echo "follow-up Issue（GREEN 実装 PR）の存在を確認しました。"
    else
      echo "follow-up Issue（GREEN 実装 PR）の存在を verify してください — 不在なら scripts/red-only-followup-create.sh で起票。"
    fi
    exit 0
  fi
  echo "CRITICAL: RED-only PR を検出しました（confidence: 85）"
  echo "変更ファイルに実装ファイルが含まれていません。"
  exit 0
fi

echo "OK: 実装ファイルが含まれています"
exit 0
