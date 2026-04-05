#!/usr/bin/env bats
# poll-single-cleanup.bats
# Requirement: poll_single done/failed 時の cleanup
# Spec: openspec/changes/worker-tmux-cleanup/specs/orchestrator-cleanup/spec.md
#
# poll_single() はオーケストレーター本体に埋め込まれているため、
# ポーリング→cleanup_worker 呼び出しロジックを抽出した test double で検証する。
#
# test double: scripts/poll-single-dispatch.sh
#   Usage: poll-single-dispatch.sh <issue> <status>
#   - state-read.sh stub が <status> を返すように設定された環境で動作
#   - cleanup_worker の呼び出しを SANDBOX/cleanup.log に記録

load '../../bats/helpers/common'

setup() {
  common_setup

  # cleanup_worker の呼び出しを記録するスクリプト
  cat > "$SANDBOX/scripts/cleanup-worker-dispatch.sh" << 'DISPATCH_EOF'
#!/usr/bin/env bash
issue="$1"
echo "cleanup_worker $issue" >> "${CLEANUP_LOG:-/dev/null}"
tmux kill-window -t "ap-#${issue}" 2>/dev/null || true
DISPATCH_EOF
  chmod +x "$SANDBOX/scripts/cleanup-worker-dispatch.sh"

  # poll_single の状態遷移ロジックを抽出した test double を生成
  # 実際の sleep/ポーリングループは行わず、1回だけ状態を確認して返す
  cat > "$SANDBOX/scripts/poll-single-dispatch.sh" << 'DISPATCH_EOF'
#!/usr/bin/env bash
# poll-single-dispatch.sh - poll_single() の状態遷移 + cleanup 呼び出しロジック test double
# Usage: poll-single-dispatch.sh <issue>
# 環境変数 MOCK_STATUS でポーリング結果をシミュレート
set -uo pipefail

SCRIPTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
issue="$1"
status="${MOCK_STATUS:-running}"

case "$status" in
  done)
    echo "[poll_single] Issue #${issue}: 完了" >&2
    bash "$SCRIPTS_ROOT/cleanup-worker-dispatch.sh" "$issue"
    exit 0
    ;;
  failed)
    echo "[poll_single] Issue #${issue}: 失敗" >&2
    bash "$SCRIPTS_ROOT/cleanup-worker-dispatch.sh" "$issue"
    exit 0
    ;;
  merge-ready)
    echo "[poll_single] Issue #${issue}: merge-ready" >&2
    # cleanup_worker は呼ばない
    exit 0
    ;;
  *)
    echo "[poll_single] Issue #${issue}: 不明な状態 $status" >&2
    exit 0
    ;;
esac
DISPATCH_EOF
  chmod +x "$SANDBOX/scripts/poll-single-dispatch.sh"

  # 呼び出し記録ファイル
  CLEANUP_LOG="$SANDBOX/cleanup.log"
  export CLEANUP_LOG

  stub_command "tmux" "exit 0"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: poll_single done/failed 時の cleanup
# ---------------------------------------------------------------------------

# Scenario: poll_single で done 検知
# WHEN poll_single がポーリング中に status=done を取得する
# THEN cleanup_worker "$issue" を実行してから return 0 する
@test "poll_single: status=done で cleanup_worker を呼び出して正常終了する" {
  MOCK_STATUS=done CLEANUP_LOG="$CLEANUP_LOG" \
    run bash "$SANDBOX/scripts/poll-single-dispatch.sh" "10"

  assert_success
  grep -q "cleanup_worker 10" "$CLEANUP_LOG"
}

# Scenario: poll_single で failed 検知
# WHEN poll_single がポーリング中に status=failed を取得する
# THEN cleanup_worker "$issue" を実行してから return 0 する
@test "poll_single: status=failed で cleanup_worker を呼び出して正常終了する" {
  MOCK_STATUS=failed CLEANUP_LOG="$CLEANUP_LOG" \
    run bash "$SANDBOX/scripts/poll-single-dispatch.sh" "11"

  assert_success
  grep -q "cleanup_worker 11" "$CLEANUP_LOG"
}

# Scenario: poll_single で merge-ready 検知
# WHEN poll_single がポーリング中に status=merge-ready を取得する
# THEN cleanup_worker を呼ばず return 0 する
@test "poll_single: status=merge-ready では cleanup_worker を呼ばずに正常終了する" {
  MOCK_STATUS=merge-ready CLEANUP_LOG="$CLEANUP_LOG" \
    run bash "$SANDBOX/scripts/poll-single-dispatch.sh" "12"

  assert_success
  # cleanup.log が存在しないか、issue 12 のエントリが含まれない
  ! grep -q "cleanup_worker 12" "$CLEANUP_LOG" 2>/dev/null
}

# Edge case: done 検知時に cleanup_worker が issue 番号を正しく渡す
@test "poll_single: done 検知時の cleanup_worker 呼び出しに正しい issue 番号が渡される" {
  MOCK_STATUS=done CLEANUP_LOG="$CLEANUP_LOG" \
    run bash "$SANDBOX/scripts/poll-single-dispatch.sh" "999"

  assert_success
  grep -q "cleanup_worker 999" "$CLEANUP_LOG"
}

# Edge case: failed 検知時に cleanup_worker が issue 番号を正しく渡す
@test "poll_single: failed 検知時の cleanup_worker 呼び出しに正しい issue 番号が渡される" {
  MOCK_STATUS=failed CLEANUP_LOG="$CLEANUP_LOG" \
    run bash "$SANDBOX/scripts/poll-single-dispatch.sh" "888"

  assert_success
  grep -q "cleanup_worker 888" "$CLEANUP_LOG"
}
