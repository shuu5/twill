#!/usr/bin/env bats
# issue-1319-co-issue-step2c-auto-decompose.bats
#
# TDD RED テスト: feat(co-issue): Step 2c 分解確認 menu 自動化 (Wave 26 sub-2, Tier A)
# Issue #1319
#
# 全テストは実装前に FAIL（RED）する。
# 実装完了後に GREEN になることを意図している。
#
# AC 対応:
#   AC-1: co-issue/SKILL.md L61 分解確認 AskUserQuestion 削除
#   AC-2: [A]分解で進める 自動選択 + log 出力
#   AC-3: regression bats: 分解自動進行確認

load 'helpers/common'

CO_ISSUE_SKILL=""
PHASE2_BUNDLES=""

setup() {
  common_setup
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  TESTS_DIR="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
  CO_ISSUE_SKILL="${REPO_ROOT}/skills/co-issue/SKILL.md"
  PHASE2_BUNDLES="${REPO_ROOT}/skills/co-issue/refs/co-issue-phase2-bundles.md"
  export REPO_ROOT CO_ISSUE_SKILL PHASE2_BUNDLES
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC-1: co-issue/SKILL.md L61 分解確認 AskUserQuestion 削除
# ===========================================================================

@test "ac1: co-issue/SKILL.md が存在すること" {
  [ -f "${CO_ISSUE_SKILL}" ]
}

@test "ac1: SKILL.md の Step 2c 行に AskUserQuestion が存在しないこと（RED: 現状 L61 に存在する）" {
  # AC: Step 2c 記述から AskUserQuestion を削除する
  # RED: 現在 L61 に `AskUserQuestion で [A] この分解で進める` が存在するため FAIL
  [ -f "${CO_ISSUE_SKILL}" ] || { echo "SKILL.md not found: ${CO_ISSUE_SKILL}" >&2; return 1; }
  if grep -qE "Step 2c.*AskUserQuestion|分解確認.*AskUserQuestion" "${CO_ISSUE_SKILL}"; then
    echo "FAIL: SKILL.md の Step 2c 行に AskUserQuestion が残存している（削除必須）:" >&2
    grep -nE "Step 2c.*AskUserQuestion|分解確認.*AskUserQuestion" "${CO_ISSUE_SKILL}" >&2
    return 1
  fi
}

@test "ac1: SKILL.md の Step 2c 行に [B] 調整 が存在しないこと（RED: 現状 L61 に存在する）" {
  # AC: Step 2c のユーザー選択肢 [B] 調整 / [C] 単一のまま が削除される
  # RED: 現在 L61 に `[B] 調整 / [C] 単一のまま` が存在するため FAIL
  [ -f "${CO_ISSUE_SKILL}" ] || { echo "SKILL.md not found" >&2; return 1; }
  local count
  count=$(grep -cE "Step 2c.*\[B\].*調整|\[B\].*調整.*\[C\].*単一" "${CO_ISSUE_SKILL}" 2>/dev/null || echo "0")
  if [ "${count}" -gt 0 ]; then
    echo "FAIL: SKILL.md の Step 2c 行にユーザー選択肢 [B]調整/[C]単一が ${count} 件残存している（削除必須）:" >&2
    grep -nE "Step 2c.*\[B\]|\[B\].*調整.*\[C\].*単一" "${CO_ISSUE_SKILL}" >&2 || true
    return 1
  fi
}

@test "ac1: SKILL.md の Step 2c 記述が自動進行を示す形式になっていること（RED: 現状 menu 形式）" {
  # AC: Step 2c が「[A] 自動選択」または「自動進行」を示す記述になる
  # RED: 現在は AskUserQuestion menu 形式のため fail
  [ -f "${CO_ISSUE_SKILL}" ] || { echo "SKILL.md not found" >&2; return 1; }
  if ! grep -qE "Step 2c.*(自動|auto|AUTO|Layer 0|AskUserQuestion 不要)" "${CO_ISSUE_SKILL}"; then
    echo "FAIL: SKILL.md の Step 2c 記述が自動進行を示す形式になっていない" >&2
    echo "  現状の Step 2c 行:" >&2
    grep -n "Step 2c" "${CO_ISSUE_SKILL}" >&2 || echo "  (Step 2c 行が見つからない)" >&2
    return 1
  fi
}

# ===========================================================================
# AC-2: [A]分解で進める 自動選択 + log 出力
# ===========================================================================

@test "ac2: co-issue-phase2-bundles.md が存在すること" {
  [ -f "${PHASE2_BUNDLES}" ]
}

@test "ac2: phase2-bundles.md に Step 2c 自動選択ロジックが存在すること（RED: 現状不在）" {
  # AC: phase2-bundles.md に Step 2c の自動選択ロジックを追加する
  # RED: 現在 phase2-bundles.md に Step 2c セクションが存在しないため FAIL
  [ -f "${PHASE2_BUNDLES}" ] || { echo "phase2-bundles.md not found: ${PHASE2_BUNDLES}" >&2; return 1; }
  if ! grep -qE "Step 2c|分解確認.*auto|分解確認.*自動" "${PHASE2_BUNDLES}"; then
    echo "FAIL: phase2-bundles.md に Step 2c 自動選択ロジックが存在しない（追加必須）" >&2
    echo "  現状の phase2-bundles.md の Step 見出し:" >&2
    grep -n "^#### Step" "${PHASE2_BUNDLES}" >&2 || echo "  (Step 見出しなし)" >&2
    return 1
  fi
}

@test "ac2: Step 2c 自動選択で log 出力ロジックが存在すること（RED: 現状不在）" {
  # AC: [A]分解で進める を自動選択した際に log 出力する
  #     期待フォーマット: `>>> Step 2c 分解確認 (auto): [A] 分解で進める` 相当
  # RED: 現在 log 出力ロジックが存在しないため FAIL
  [ -f "${PHASE2_BUNDLES}" ] || { echo "phase2-bundles.md not found" >&2; return 1; }
  if ! grep -qE "Step 2c.*(auto|log|log_event|echo|printf|>>)" "${PHASE2_BUNDLES}"; then
    echo "FAIL: phase2-bundles.md に Step 2c auto 選択の log 出力ロジックが存在しない" >&2
    echo "  期待: '>>> Step 2c 分解確認 (auto): [A] 分解で進める' 相当の log 出力" >&2
    return 1
  fi
}

@test "ac2: SKILL.md または phase2-bundles.md に Step 2c auto-decisions.log 記録が示されること（RED: 現状不在）" {
  # AC: auto-decisions.log または同等の決定ログへの記録が明示される
  # RED: 現在どちらのファイルにも auto-decisions.log への記録ロジックが存在しないため FAIL
  [ -f "${CO_ISSUE_SKILL}" ] || { echo "SKILL.md not found" >&2; return 1; }
  [ -f "${PHASE2_BUNDLES}" ] || { echo "phase2-bundles.md not found" >&2; return 1; }
  local found=0
  grep -qE "auto-decisions\.log|auto_decisions|Step 2c.*log" "${CO_ISSUE_SKILL}" 2>/dev/null && found=1
  grep -qE "auto-decisions\.log|auto_decisions|Step 2c.*log" "${PHASE2_BUNDLES}" 2>/dev/null && found=1
  if [ "${found}" -eq 0 ]; then
    echo "FAIL: SKILL.md / phase2-bundles.md のどちらにも Step 2c の auto-decisions 記録ロジックが存在しない" >&2
    return 1
  fi
}

# ===========================================================================
# AC-3: regression bats: 分解自動進行確認
# ===========================================================================

@test "ac3: SKILL.md に Step 2c AskUserQuestion なしで自動進行することが保証されていること（RED: 現状 menu 形式）" {
  # AC: regression — Step 2c でユーザーへの確認 menu が表示されないことを確認
  # RED: 現在 SKILL.md L61 に AskUserQuestion menu 形式が存在するため FAIL
  [ -f "${CO_ISSUE_SKILL}" ] || { echo "SKILL.md not found" >&2; return 1; }

  # 現状の Step 2c 行: `複数の場合は AskUserQuestion で [A] ... / [B] ... / [C] ...`
  # 実装後は menu なし（自動進行）の形式に変わる
  local askuserq_count
  askuserq_count=$(grep -cE "Step 2c.*AskUserQuestion|分解確認.*AskUserQuestion" "${CO_ISSUE_SKILL}" 2>/dev/null || echo "0")
  if [ "${askuserq_count}" -gt 0 ]; then
    echo "FAIL: SKILL.md の Step 2c に AskUserQuestion が ${askuserq_count} 件存在する（regression: ユーザー menu 非表示が保証されない）" >&2
    grep -nE "Step 2c.*AskUserQuestion|分解確認.*AskUserQuestion" "${CO_ISSUE_SKILL}" >&2
    return 1
  fi
}

@test "ac3: Step 2c で選択肢 [B] 調整 / [C] 単一が提示されないこと（RED: 現状 L61 に存在する）" {
  # AC: regression — [B] 調整 / [C] 単一のまま の選択肢が Step 2c から消える
  # RED: 現在 SKILL.md L61 に [B] 調整 / [C] 単一のまま が存在するため FAIL
  [ -f "${CO_ISSUE_SKILL}" ] || { echo "SKILL.md not found" >&2; return 1; }
  local count
  count=$(grep -cE "分解確認.*\[B\]|\[B\].*調整.*\[C\].*単一" "${CO_ISSUE_SKILL}" 2>/dev/null || echo "0")
  if [ "${count}" -gt 0 ]; then
    echo "FAIL: SKILL.md の Step 2c に選択肢 [B]調整/[C]単一が ${count} 件残存している（regression）" >&2
    grep -nE "分解確認.*\[B\]|\[B\].*調整.*\[C\].*単一" "${CO_ISSUE_SKILL}" >&2 || true
    return 1
  fi
}
