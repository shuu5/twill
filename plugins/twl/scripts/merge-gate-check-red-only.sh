#!/usr/bin/env bash
# merge-gate-check-red-only.sh - RED-only PR 検出チェック（merge-gate Step）
#
# PR の変更ファイルがテストファイルのみ（実装ファイルなし）の場合を検出して REJECT する。
# Issue #1476: PR #1470 が test のみで実装欠落のまま merge された問題の再発防止。
# Issue #1626 AC4: git diff 失敗時 gh pr view fallback + 双方失敗で fail-closed REJECT。
# Issue #1626 AC2: REJECT path で red-only label PR の follow-up Issue を自動起票（idempotent）。
#
# 呼び出し: bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-check-red-only.sh"

set -uo pipefail

# 変更ファイルリストを取得（fail-closed 二段式: git diff → gh pr view fallback）
CHANGED_FILES=""

# Primary: git diff --name-only origin/main → HEAD fallback
if _files=$(git diff --name-only origin/main 2>/dev/null) && [[ -n "$_files" ]]; then
  CHANGED_FILES="$_files"
elif _files=$(git diff --name-only HEAD 2>/dev/null) && [[ -n "$_files" ]]; then
  CHANGED_FILES="$_files"
fi

# Fallback: gh pr view --json files (PR コンテキストがある場合のみ)
# AC4: git diff が空 (fetch 不全 / origin ref 不在) の場合に gh API で再試行
if [[ -z "$CHANGED_FILES" ]]; then
  if _files=$(gh pr view --json files -q '.files[].path' 2>/dev/null) && [[ -n "$_files" ]]; then
    CHANGED_FILES="$_files"
  fi
fi

# AC4: 双方失敗 → fail-closed REJECT (silent PASS を排除)
if [[ -z "$CHANGED_FILES" ]]; then
  echo "REJECT: 変更ファイル取得不能 (git diff + gh pr view 双方 fail) — fail-closed" >&2
  echo "  fail-closed: RED-only 検出不能のため merge を block します" >&2
  exit 1
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
  [[ "$f" == *ac-test-mapping*.yaml ]] && return 0
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

  # AC2: red-only label 付き PR で follow-up Issue が不在なら自動起票（idempotent guard 付き）
  # PR 番号と label を gh pr view で取得（失敗時は起票スキップ、REJECT 自体は確実に exit 1）
  _pr_number=$(gh pr view --json number -q '.number' 2>/dev/null || echo "")
  _has_red_only_label=$(gh pr view --json labels \
    -q '[.labels[]?.name] | map(select(. == "red-only")) | length > 0' 2>/dev/null || echo "false")

  if [[ -n "$_pr_number" && "$_has_red_only_label" == "true" ]]; then
    # follow-up Issue 存在チェック（idempotent guard）
    # ローカルフィルタ方式（HTML コメントは GitHub search のデフォルト検索対象外のため）
    _marker="<!-- follow-up-for: PR #${_pr_number} -->"
    _existing=$(gh issue list --state all --json number,body 2>/dev/null \
      | jq --arg m "$_marker" \
          '[.[] | select(.body != null and (.body | contains($m)))] | length' 2>/dev/null || echo "0")

    if [[ "${_existing:-0}" -eq 0 ]]; then
      _script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      bash "${_script_dir}/red-only-followup-create.sh" \
        --pr-number "$_pr_number" \
        --merge-gate-result REJECTED \
        --labels "red-only-followup" >&2 2>&1 || \
        echo "WARN: follow-up Issue 起票失敗（手動起票が必要）" >&2
    else
      echo "INFO: follow-up Issue 起票済み（idempotent skip）" >&2
    fi
  fi

  exit 1
fi

exit 0
