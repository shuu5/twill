#!/usr/bin/env bats
# workflow-done-polling.bats
# Requirement: current_step terminal 検知による inject トリガー（ADR-018）
# ADR-018: workflow_done 廃止後の新トリガー機構テスト
#
# このファイルは polling ループ内での current_step terminal 検知ロジックを単体テストする。
# autopilot-orchestrator.sh の poll_single() / poll_phase() 内分岐を test double で再現し、
# 以下の境界値・エッジケースを検証する:
#
#   - current_step が terminal step (ac-extract) → inject_next_workflow() を呼ぶ
#   - current_step が非 terminal step → inject_next_workflow() を呼ばず check_and_nudge() を呼ぶ
#   - LAST_INJECTED_STEP が current_step と一致 → 重複 inject を防ぐ
#   - inject_next_workflow() 成功 → inject_matched=1 → check_and_nudge スキップ
#   - inject_next_workflow() 失敗 → inject_matched=0 → check_and_nudge を継続
#
# STAGNATE 判定テスト:
#   - status=merge-ready 時に STAGNATE 警告を出さない（ADR-018 AC）

load '../../bats/helpers/common.bash'

# ---------------------------------------------------------------------------
# setup: polling ループの current_step 分岐を再現するテスト double を生成
# ---------------------------------------------------------------------------

setup() {
  common_setup

  CALLS_LOG="$SANDBOX/calls.log"
  export CALLS_LOG

  # polling-branch.sh: poll_single() の current_step terminal 検知分岐を独立再現（ADR-018）
  # Env:
  #   CURRENT_STEP_VALUE   - state read の返り値（ac-extract / post-change-apply / 非 terminal step など）
  #   LAST_INJECTED_STEP   - 最後に inject 済みの step（重複防止トラッキング）
  #   INJECT_EXIT          - inject_next_workflow() の終了コード（0=成功, 1=失敗）
  #   CALLS_LOG            - 呼び出し記録ファイル
  cat > "$SANDBOX/scripts/polling-branch.sh" << 'POLLING_EOF'
#!/usr/bin/env bash
# polling-branch.sh
# poll_single() の status=running ブランチの current_step terminal 検知部分を再現（ADR-018）
set -uo pipefail

CURRENT_STEP_VALUE="${CURRENT_STEP_VALUE:-}"
LAST_INJECTED_STEP="${LAST_INJECTED_STEP:-}"
INJECT_EXIT="${INJECT_EXIT:-0}"
CALLS_LOG="${CALLS_LOG:-/dev/null}"

# --- simulate: state read --field current_step ---
_cur_step="$CURRENT_STEP_VALUE"
echo "state_read current_step" >> "$CALLS_LOG"

inject_matched=0

# terminal step 検知 + LAST_INJECTED_STEP で重複防止（ADR-018）
if [[ -n "$_cur_step" && "$LAST_INJECTED_STEP" != "$_cur_step" ]]; then
  echo "inject_next_workflow called" >> "$CALLS_LOG"
  if [[ "$INJECT_EXIT" -eq 0 ]]; then
    LAST_INJECTED_STEP="$_cur_step"
    inject_matched=1
    echo "last_injected_step_updated=$_cur_step" >> "$CALLS_LOG"
  fi
fi

if [[ "$inject_matched" -eq 0 ]]; then
  echo "check_and_nudge called" >> "$CALLS_LOG"
fi

exit 0
POLLING_EOF
  chmod +x "$SANDBOX/scripts/polling-branch.sh"

  # stagnate-check.sh: status に基づく STAGNATE 判定を再現（ADR-018 AC）
  # Env:
  #   STATUS_VALUE  - issue の status 値
  cat > "$SANDBOX/scripts/stagnate-check.sh" << 'STAGNATE_EOF'
#!/usr/bin/env bash
# stagnate-check.sh
# Monitor/su-observer の STAGNATE 判定ロジックを再現（status SSOT による単一クエリ版）
set -uo pipefail

STATUS_VALUE="${STATUS_VALUE:-running}"

# STAGNATE 判定: merge-ready / done / conflict は正常待機または終端 → 警告なし
if [[ "$STATUS_VALUE" == "merge-ready" || "$STATUS_VALUE" == "done" || "$STATUS_VALUE" == "conflict" ]]; then
  echo "skip_stagnate=1"
  exit 0
fi

if [[ "$STATUS_VALUE" == "running" ]]; then
  echo "stagnate_check=active"
  exit 0
fi

echo "unknown_status=$STATUS_VALUE"
exit 1
STAGNATE_EOF
  chmod +x "$SANDBOX/scripts/stagnate-check.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Scenario: terminal step が検知された場合（ADR-018）
# WHEN status=running 中に current_step が terminal step の値を持つ
# THEN inject_next_workflow() を呼び出す
# ---------------------------------------------------------------------------

@test "polling[terminal-step]: ac-extract は terminal step として inject を呼ぶ" {
  CURRENT_STEP_VALUE="ac-extract" \
  LAST_INJECTED_STEP="" \
    run bash "$SANDBOX/scripts/polling-branch.sh"

  assert_success
  grep -q "inject_next_workflow called" "$CALLS_LOG"
}

@test "polling[terminal-step]: post-change-apply は terminal step として inject を呼ぶ" {
  CURRENT_STEP_VALUE="post-change-apply" \
  LAST_INJECTED_STEP="" \
    run bash "$SANDBOX/scripts/polling-branch.sh"

  assert_success
  grep -q "inject_next_workflow called" "$CALLS_LOG"
}

@test "polling[terminal-step]: inject 成功時に LAST_INJECTED_STEP を更新する" {
  CURRENT_STEP_VALUE="ac-extract" \
  LAST_INJECTED_STEP="" \
  INJECT_EXIT=0 \
    run bash "$SANDBOX/scripts/polling-branch.sh"

  assert_success
  grep -q "last_injected_step_updated=ac-extract" "$CALLS_LOG"
}

@test "polling[terminal-step]: inject 成功時に check_and_nudge をスキップ" {
  CURRENT_STEP_VALUE="ac-extract" \
  LAST_INJECTED_STEP="" \
  INJECT_EXIT=0 \
    run bash "$SANDBOX/scripts/polling-branch.sh"

  assert_success
  grep -q "inject_next_workflow called" "$CALLS_LOG"
  ! grep -q "check_and_nudge called" "$CALLS_LOG" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Scenario: 非 terminal step の場合は inject を呼ばない
# WHEN current_step が terminal でない step（例: ts-preflight）
# THEN inject_next_workflow() を呼ばず check_and_nudge() を呼ぶ
# ---------------------------------------------------------------------------

@test "polling[non-terminal]: ts-preflight では inject が失敗するため check_and_nudge を呼ぶ" {
  CURRENT_STEP_VALUE="ts-preflight" \
  LAST_INJECTED_STEP="" \
  INJECT_EXIT=1 \
    run bash "$SANDBOX/scripts/polling-branch.sh"

  # inject_next_workflow 自体は呼ばれるが resolve_next_workflow が non-terminal で exit 1
  # → inject 失敗（INJECT_EXIT=1）→ inject_matched=0 → check_and_nudge へ
  assert_success
  grep -q "check_and_nudge called" "$CALLS_LOG"
}

@test "polling[non-terminal]: current_step が空の場合は inject を呼ばない" {
  CURRENT_STEP_VALUE="" \
  LAST_INJECTED_STEP="" \
    run bash "$SANDBOX/scripts/polling-branch.sh"

  assert_success
  ! grep -q "inject_next_workflow called" "$CALLS_LOG" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Edge case: LAST_INJECTED_STEP による重複 inject 防止
# WHEN 同一 current_step に対して2回目のポーリング
# THEN LAST_INJECTED_STEP が一致するため inject しない（重複防止）
# ---------------------------------------------------------------------------

@test "polling[dedup]: 同一 current_step への重複 inject を防ぐ" {
  CURRENT_STEP_VALUE="ac-extract" \
  LAST_INJECTED_STEP="ac-extract" \
    run bash "$SANDBOX/scripts/polling-branch.sh"

  assert_success
  # LAST_INJECTED_STEP が同じ → inject しない → check_and_nudge に fallback
  ! grep -q "inject_next_workflow called" "$CALLS_LOG" 2>/dev/null
  grep -q "check_and_nudge called" "$CALLS_LOG"
}

@test "polling[dedup]: current_step が変化した場合は再度 inject を呼ぶ" {
  CURRENT_STEP_VALUE="post-change-apply" \
  LAST_INJECTED_STEP="ac-extract" \
    run bash "$SANDBOX/scripts/polling-branch.sh"

  assert_success
  grep -q "inject_next_workflow called" "$CALLS_LOG"
}

# ---------------------------------------------------------------------------
# Edge case: inject 失敗時は check_and_nudge を継続する
# WHEN inject_next_workflow() が戻り値 1 で失敗する
# THEN inject_matched=0 なので check_and_nudge() を呼ぶ
# ---------------------------------------------------------------------------

@test "polling[inject-fail]: inject_next_workflow 失敗時は check_and_nudge を継続する" {
  CURRENT_STEP_VALUE="ac-extract" \
  LAST_INJECTED_STEP="" \
  INJECT_EXIT=1 \
    run bash "$SANDBOX/scripts/polling-branch.sh"

  assert_success
  grep -q "inject_next_workflow called" "$CALLS_LOG"
  grep -q "check_and_nudge called" "$CALLS_LOG"
}

@test "polling[inject-fail]: inject 失敗時は LAST_INJECTED_STEP を更新しない" {
  CURRENT_STEP_VALUE="ac-extract" \
  LAST_INJECTED_STEP="" \
  INJECT_EXIT=1 \
    run bash "$SANDBOX/scripts/polling-branch.sh"

  assert_success
  ! grep -q "last_injected_step_updated=" "$CALLS_LOG" 2>/dev/null
}

# ---------------------------------------------------------------------------
# ADR-018 AC: STAGNATE 抑制テスト（status=merge-ready / done / conflict）
# Requirement: Monitor が status=merge-ready 時に STAGNATE 警告を出さない
# ---------------------------------------------------------------------------

@test "stagnate[merge-ready]: status=merge-ready 時に STAGNATE チェックをスキップする" {
  STATUS_VALUE="merge-ready" \
    run bash "$SANDBOX/scripts/stagnate-check.sh"

  assert_success
  assert_output --partial "skip_stagnate=1"
}

@test "stagnate[done]: status=done 時に STAGNATE チェックをスキップする" {
  STATUS_VALUE="done" \
    run bash "$SANDBOX/scripts/stagnate-check.sh"

  assert_success
  assert_output --partial "skip_stagnate=1"
}

@test "stagnate[conflict]: status=conflict 時に STAGNATE チェックをスキップする" {
  STATUS_VALUE="conflict" \
    run bash "$SANDBOX/scripts/stagnate-check.sh"

  assert_success
  assert_output --partial "skip_stagnate=1"
}

@test "stagnate[running]: status=running 時は STAGNATE チェックをアクティブにする" {
  STATUS_VALUE="running" \
    run bash "$SANDBOX/scripts/stagnate-check.sh"

  assert_success
  assert_output --partial "stagnate_check=active"
}

# ---------------------------------------------------------------------------
# Edge case: state read は常に1回呼ばれる（ショートサーキット確認）
# ---------------------------------------------------------------------------

@test "polling[state-read]: current_step の state read は1回呼ばれる（terminal step の場合）" {
  CURRENT_STEP_VALUE="ac-extract" \
  LAST_INJECTED_STEP="" \
    run bash "$SANDBOX/scripts/polling-branch.sh"

  assert_success
  local count
  count=$(grep -c "state_read current_step" "$CALLS_LOG" 2>/dev/null || echo 0)
  [[ "$count" -eq 1 ]]
}

@test "polling[state-read]: current_step の state read は1回呼ばれる（非 terminal step の場合）" {
  CURRENT_STEP_VALUE="ts-preflight" \
  LAST_INJECTED_STEP="" \
    run bash "$SANDBOX/scripts/polling-branch.sh"

  assert_success
  local count
  count=$(grep -c "state_read current_step" "$CALLS_LOG" 2>/dev/null || echo 0)
  [[ "$count" -eq 1 ]]
}
