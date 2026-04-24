#!/usr/bin/env bats
# spec-review-orchestrator-inject-classify.bats - spec-review-orchestrator の
# ウィンドウ消失・タイムアウト時の失敗シグナル検証 (#946 B4 方針 a)
#
# spec-review-orchestrator.sh は inject ポーリングループを持たない。
# ウィンドウ消失時に "TIMEOUT:" を result_file に書き、
# 結果サマリーが grep "^TIMEOUT:" で FAILED を計上することを確認する。
#
# Scenarios covered:
#   - ウィンドウ消失 → result_file が "TIMEOUT:" で始まる
#   - 結果サマリーが "TIMEOUT:" を FAILED として計上する

load '../helpers/common'

SCRIPT_SRC=""

setup() {
  common_setup
  SCRIPT_SRC="$REPO_ROOT/scripts/spec-review-orchestrator.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Scenario: ウィンドウ消失 → TIMEOUT: ファイル生成
# WHEN ウィンドウが消失し result_file が存在しない
# THEN result_file が "TIMEOUT:" で始まる内容で生成される
# ---------------------------------------------------------------------------

@test "spec-review-inject: ウィンドウ消失時の TIMEOUT: ファイル生成コードが存在する" {
  grep -qE 'TIMEOUT:.*' "$SCRIPT_SRC" \
    || fail "TIMEOUT: result file generation not found in spec-review-orchestrator.sh"
}

@test "spec-review-inject: ウィンドウ消失検知 (tmux list-windows 判定) が存在する" {
  grep -q 'list-windows\|ウィンドウ消失' "$SCRIPT_SRC" \
    || fail "Window disappearance detection not found in spec-review-orchestrator.sh"
}

# ---------------------------------------------------------------------------
# Scenario: 結果サマリーが "TIMEOUT:" を FAILED として計上する
# ---------------------------------------------------------------------------

@test "spec-review-inject: 結果サマリーが TIMEOUT: を FAILED としてカウントするロジックがある" {
  grep -qE 'grep.*TIMEOUT|TIMEOUT.*grep' "$SCRIPT_SRC" \
    || fail "'grep TIMEOUT' pattern not found in result summary section"
}

@test "spec-review-inject: TIMEOUT 検出時に FAILED インクリメントが発生する" {
  local timeout_section
  timeout_section=$(grep -A3 'grep.*TIMEOUT\|TIMEOUT.*grep' "$SCRIPT_SRC" | head -10)
  echo "$timeout_section" | grep -qE 'FAILED\+\+|FAILED.*\+.*1|FAILED=\$\(\(' \
    || fail "FAILED counter increment not found after TIMEOUT detection. Context: $timeout_section"
}

# ---------------------------------------------------------------------------
# Scenario: ポーリングタイムアウト時の TIMEOUT: ファイル生成
# ---------------------------------------------------------------------------

@test "spec-review-inject: MAX_POLL 超過時にも TIMEOUT: ファイルが生成される" {
  grep -q 'ポーリング上限到達\|poll_limit_reached\|MAX_POLL' "$SCRIPT_SRC" \
    || fail "MAX_POLL timeout handling not found in spec-review-orchestrator.sh"
}

# ---------------------------------------------------------------------------
# Scenario: inject loop が存在しない (方針 a: 既存構造を尊重)
# ---------------------------------------------------------------------------

@test "spec-review-inject: inject ポーリングループが存在しない (方針 a 確認)" {
  # spec-review-orchestrator.sh は inject loop を持たない (B4 方針 a)
  grep -qE 'inject_count|auto-inject|input-waiting.*inject' "$SCRIPT_SRC" \
    && fail "inject loop found in spec-review-orchestrator.sh — B4 approach (a) requires no inject loop" \
    || true
}
