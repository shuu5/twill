#!/usr/bin/env bats
# merge-gate-loop-cleanup.bats
# Requirement: reject-final確定失敗後のworktreeとリモートブランチのクリーンアップ
# Requirement: failure.reasonによるreject-final識別
# Spec: openspec/changes/reject-final-cleanup/specs/cleanup-on-reject-final/spec.md
#
# orchestratorのmerge-gateループ（autopilot-orchestrator.sh lines 858-878）の
# cleanup_worker呼び出し条件を抽出したtest doubleで検証する。
#
# test double: scripts/merge-gate-loop-dispatch.sh
#   Usage: merge-gate-loop-dispatch.sh <issue>
#   - MOCK_STATUS_AFTER       : merge-gate後のstatus（done/failed/など）
#   - MOCK_RETRY_COUNT        : top-level retry_count
#   - MOCK_FAILURE_REASON     : failure.reason（未設定時は空文字列）
#   - cleanup_worker呼び出しをSANDBOX/cleanup.logに記録

load '../../bats/helpers/common'

# ---------------------------------------------------------------------------
# setup: merge-gateループのcleanup判定ロジックを抽出したtest doubleを生成
# ---------------------------------------------------------------------------

setup() {
  common_setup

  # cleanup_workerの呼び出しを記録するスクリプト
  cat > "$SANDBOX/scripts/cleanup-worker-dispatch.sh" << 'DISPATCH_EOF'
#!/usr/bin/env bash
issue="$1"
echo "cleanup_worker $issue" >> "${CLEANUP_LOG:-/dev/null}"
DISPATCH_EOF
  chmod +x "$SANDBOX/scripts/cleanup-worker-dispatch.sh"

  # merge-gateループのcleanup判定ロジックを抽出したtest double
  #
  # 修正後のロジック（spec準拠）:
  #   if status_after == done    → cleanup_worker
  #   elif status_after == failed:
  #     _failure_reason = state-read failure.reason (または空文字列)
  #     if _failure_reason == "merge_gate_rejected_final" → cleanup_worker
  #     elif retry_count >= 1                             → cleanup_worker
  #     # else: cleanup_worker を呼ばない（リトライ対象）
  #
  # このtest doubleは修正後のロジックを実装し、テストで動作を検証する。
  cat > "$SANDBOX/scripts/merge-gate-loop-dispatch.sh" << 'DISPATCH_EOF'
#!/usr/bin/env bash
# merge-gate-loop-dispatch.sh
# merge-gateループのcleanup判定ロジックtest double
# 修正後のコード（failure.reason == "merge_gate_rejected_final" 条件追加）を再現
set -uo pipefail

SCRIPTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
issue="$1"

# 環境変数でmockデータを注入
_status_after="${MOCK_STATUS_AFTER:-}"
_retry="${MOCK_RETRY_COUNT:-0}"
_failure_reason="${MOCK_FAILURE_REASON:-}"

if [[ "$_status_after" == "done" ]]; then
  echo "[merge-gate-loop] Issue #${issue}: done → cleanup_worker" >&2
  bash "$SCRIPTS_ROOT/cleanup-worker-dispatch.sh" "$issue"
elif [[ "$_status_after" == "failed" ]]; then
  # failure.reasonを確認してreject-final判定
  if [[ "$_failure_reason" == "merge_gate_rejected_final" ]]; then
    echo "[merge-gate-loop] Issue #${issue}: reject-final → cleanup_worker" >&2
    bash "$SCRIPTS_ROOT/cleanup-worker-dispatch.sh" "$issue"
  elif [[ "${_retry:-0}" -ge 1 ]]; then
    echo "[merge-gate-loop] Issue #${issue}: retry_count=${_retry} >= 1 → cleanup_worker" >&2
    bash "$SCRIPTS_ROOT/cleanup-worker-dispatch.sh" "$issue"
  else
    echo "[merge-gate-loop] Issue #${issue}: failed, retry_count=0, reason=normal → skip cleanup" >&2
  fi
else
  echo "[merge-gate-loop] Issue #${issue}: status=${_status_after} → no action" >&2
fi
DISPATCH_EOF
  chmod +x "$SANDBOX/scripts/merge-gate-loop-dispatch.sh"

  # 呼び出し記録ファイル
  CLEANUP_LOG="$SANDBOX/cleanup.log"
  export CLEANUP_LOG
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: reject-final確定失敗後のworktreeとリモートブランチのクリーンアップ
# ---------------------------------------------------------------------------

# Scenario: 初回実行でreject-final（retry_count=0）
# WHEN merge-gateが--reject-finalを呼び、
#      status=failed, failure.reason=merge_gate_rejected_final, retry_count=0 の状態で
#      merge-gateループが結果を評価するとき
# THEN cleanup_workerが呼ばれる
@test "merge-gate-loop: reject-final（retry_count=0）でcleanup_workerが呼ばれる" {
  MOCK_STATUS_AFTER="failed" \
  MOCK_FAILURE_REASON="merge_gate_rejected_final" \
  MOCK_RETRY_COUNT="0" \
  CLEANUP_LOG="$CLEANUP_LOG" \
    run bash "$SANDBOX/scripts/merge-gate-loop-dispatch.sh" "42"

  assert_success
  grep -q "cleanup_worker 42" "$CLEANUP_LOG"
}

# Scenario: リトライ後のreject-final（retry_count>=1）
# WHEN Issueが一度リトライされた後（retry_count=1）、
#      merge-gateが--reject-finalを呼んだとき
# THEN 既存のretry_count >= 1条件が真となり、cleanup_workerが呼ばれる（既存動作の維持）
@test "merge-gate-loop: リトライ後のreject-final（retry_count=1）でcleanup_workerが呼ばれる" {
  MOCK_STATUS_AFTER="failed" \
  MOCK_FAILURE_REASON="merge_gate_rejected_final" \
  MOCK_RETRY_COUNT="1" \
  CLEANUP_LOG="$CLEANUP_LOG" \
    run bash "$SANDBOX/scripts/merge-gate-loop-dispatch.sh" "43"

  assert_success
  grep -q "cleanup_worker 43" "$CLEANUP_LOG"
}

# Edge case: retry_count=2 でもreject-finalはcleanup_workerが呼ばれる
@test "merge-gate-loop: reject-final（retry_count=2）でcleanup_workerが呼ばれる" {
  MOCK_STATUS_AFTER="failed" \
  MOCK_FAILURE_REASON="merge_gate_rejected_final" \
  MOCK_RETRY_COUNT="2" \
  CLEANUP_LOG="$CLEANUP_LOG" \
    run bash "$SANDBOX/scripts/merge-gate-loop-dispatch.sh" "44"

  assert_success
  grep -q "cleanup_worker 44" "$CLEANUP_LOG"
}

# Scenario: 通常reject（retry_count=0、リトライ可）
# WHEN merge-gateが--reject（リトライ可）を呼び、
#      status=failed, failure.reason=merge_gate_rejected, retry_count=0 になったとき
# THEN cleanup_workerが呼ばれず、Issueはリトライ対象として残る
@test "merge-gate-loop: 通常reject（failure.reason=merge_gate_rejected, retry_count=0）ではcleanup_workerが呼ばれない" {
  MOCK_STATUS_AFTER="failed" \
  MOCK_FAILURE_REASON="merge_gate_rejected" \
  MOCK_RETRY_COUNT="0" \
  CLEANUP_LOG="$CLEANUP_LOG" \
    run bash "$SANDBOX/scripts/merge-gate-loop-dispatch.sh" "50"

  assert_success
  # cleanup.logが存在しないか、issue 50 のエントリが含まれないこと
  ! grep -q "cleanup_worker 50" "$CLEANUP_LOG" 2>/dev/null
}

# Edge case: 通常rejectでretry_count=1の場合はcleanup_workerが呼ばれる（既存動作）
@test "merge-gate-loop: 通常reject（retry_count=1）ではcleanup_workerが呼ばれる" {
  MOCK_STATUS_AFTER="failed" \
  MOCK_FAILURE_REASON="merge_gate_rejected" \
  MOCK_RETRY_COUNT="1" \
  CLEANUP_LOG="$CLEANUP_LOG" \
    run bash "$SANDBOX/scripts/merge-gate-loop-dispatch.sh" "51"

  assert_success
  grep -q "cleanup_worker 51" "$CLEANUP_LOG"
}

# ---------------------------------------------------------------------------
# Requirement: failure.reasonによるreject-final識別
# ---------------------------------------------------------------------------

# Scenario: failure.reasonが存在しない古いstateファイル
# WHEN stateファイルにfailureオブジェクトがない（またはfailure.reasonがnull）とき
# THEN _failure_reasonは空文字列となり、既存のretry_count >= 1判定のみが適用される
@test "merge-gate-loop: failure.reasonが空文字列の場合、retry_count=0ではcleanup_workerが呼ばれない" {
  MOCK_STATUS_AFTER="failed" \
  MOCK_FAILURE_REASON="" \
  MOCK_RETRY_COUNT="0" \
  CLEANUP_LOG="$CLEANUP_LOG" \
    run bash "$SANDBOX/scripts/merge-gate-loop-dispatch.sh" "60"

  assert_success
  # retry_count=0 かつ failure.reason なし → cleanup_worker を呼ばない（修正前と同一動作）
  ! grep -q "cleanup_worker 60" "$CLEANUP_LOG" 2>/dev/null
}

@test "merge-gate-loop: failure.reasonが空文字列でもretry_count=1ではcleanup_workerが呼ばれる" {
  MOCK_STATUS_AFTER="failed" \
  MOCK_FAILURE_REASON="" \
  MOCK_RETRY_COUNT="1" \
  CLEANUP_LOG="$CLEANUP_LOG" \
    run bash "$SANDBOX/scripts/merge-gate-loop-dispatch.sh" "61"

  assert_success
  # retry_count >= 1 条件で cleanup_worker が呼ばれる（既存動作の維持）
  grep -q "cleanup_worker 61" "$CLEANUP_LOG"
}

# Edge case: failure.reasonが未設定（MOCK_FAILURE_REASON環境変数なし）の場合、
# reject-finalとして識別されず既存ロジックのみ適用される
@test "merge-gate-loop: failure.reason未設定（古いstateファイル）でretry_count=0はcleanup_workerを呼ばない" {
  MOCK_STATUS_AFTER="failed" \
  MOCK_RETRY_COUNT="0" \
  CLEANUP_LOG="$CLEANUP_LOG" \
    run bash "$SANDBOX/scripts/merge-gate-loop-dispatch.sh" "62"

  assert_success
  ! grep -q "cleanup_worker 62" "$CLEANUP_LOG" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Regression: done の場合は従来通り cleanup_worker が呼ばれる
# ---------------------------------------------------------------------------

@test "merge-gate-loop: status=done でcleanup_workerが呼ばれる（既存動作）" {
  MOCK_STATUS_AFTER="done" \
  MOCK_FAILURE_REASON="" \
  MOCK_RETRY_COUNT="0" \
  CLEANUP_LOG="$CLEANUP_LOG" \
    run bash "$SANDBOX/scripts/merge-gate-loop-dispatch.sh" "70"

  assert_success
  grep -q "cleanup_worker 70" "$CLEANUP_LOG"
}

# Edge case: status=merge-ready のまま（merge-gate未実行）ではcleanup_workerが呼ばれない
@test "merge-gate-loop: status=merge-ready のままではcleanup_workerが呼ばれない" {
  MOCK_STATUS_AFTER="merge-ready" \
  MOCK_FAILURE_REASON="" \
  MOCK_RETRY_COUNT="0" \
  CLEANUP_LOG="$CLEANUP_LOG" \
    run bash "$SANDBOX/scripts/merge-gate-loop-dispatch.sh" "71"

  assert_success
  ! grep -q "cleanup_worker 71" "$CLEANUP_LOG" 2>/dev/null
}
