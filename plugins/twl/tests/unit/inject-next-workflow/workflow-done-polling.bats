#!/usr/bin/env bats
# workflow-done-polling.bats
# Requirement: workflow_done フィールドの読み取り / check_and_nudge の条件付きスキップ
# Spec: deltaspec/changes/orchestrator-inject-next-workflow/specs/orchestrator/spec.md
# Coverage: --type=unit --coverage=edge-cases
#
# このファイルは polling ループ内での workflow_done 検知ロジックを単体テストする。
# autopilot-orchestrator.sh の poll_single() 内分岐を test double で再現し、
# 以下の境界値・エッジケースを検証する:
#
#   - workflow_done が非空の値 → inject_next_workflow() を呼ぶ
#   - workflow_done が空文字 → check_and_nudge() を呼ぶ（inject しない）
#   - workflow_done が "null" 文字列 → 空と同等として check_and_nudge() を呼ぶ
#   - inject_next_workflow() 成功（exit 0）→ inject_matched=1 → check_and_nudge スキップ
#   - inject_next_workflow() 失敗（exit 1）→ inject_matched=0 → check_and_nudge を継続
#   - workflow_done が設定済みで inject 失敗 → check_and_nudge を継続する

load '../../bats/helpers/common.bash'

# ---------------------------------------------------------------------------
# setup: polling ループの workflow_done 分岐を再現するテスト double を生成
# ---------------------------------------------------------------------------

setup() {
  common_setup

  CALLS_LOG="$SANDBOX/calls.log"
  export CALLS_LOG

  # polling-branch.sh: poll_single() の workflow_done 分岐を独立再現
  # Env:
  #   WORKFLOW_DONE_VALUE  - state read の返り値（空文字 / "null" / スキル名 など）
  #   INJECT_EXIT          - inject_next_workflow() の終了コード（0=成功, 1=失敗）
  #   CALLS_LOG            - 呼び出し記録ファイル
  cat > "$SANDBOX/scripts/polling-branch.sh" << 'POLLING_EOF'
#!/usr/bin/env bash
# polling-branch.sh
# poll_single() の status=running ブランチの workflow_done 検知部分を再現
set -uo pipefail

WORKFLOW_DONE_VALUE="${WORKFLOW_DONE_VALUE:-}"
INJECT_EXIT="${INJECT_EXIT:-0}"
CALLS_LOG="${CALLS_LOG:-/dev/null}"

# --- simulate: state read --field workflow_done ---
workflow_done="$WORKFLOW_DONE_VALUE"
echo "state_read workflow_done" >> "$CALLS_LOG"

inject_matched=0

if [[ -n "$workflow_done" && "$workflow_done" != "null" ]]; then
  # inject_next_workflow() を呼ぶ
  echo "inject_next_workflow called" >> "$CALLS_LOG"
  if [[ "$INJECT_EXIT" -eq 0 ]]; then
    inject_matched=1
  fi
fi

if [[ "$inject_matched" -eq 0 ]]; then
  echo "check_and_nudge called" >> "$CALLS_LOG"
fi

exit 0
POLLING_EOF
  chmod +x "$SANDBOX/scripts/polling-branch.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Scenario: workflow_done が設定されている場合
# WHEN status=running 中に workflow_done が非空の値を持つ
# THEN inject_next_workflow() を呼び出す
# ---------------------------------------------------------------------------

@test "polling[workflow_done-set]: workflow_done が非空の場合に inject_next_workflow を呼ぶ" {
  WORKFLOW_DONE_VALUE="/twl:workflow-pr-verify" \
    run bash "$SANDBOX/scripts/polling-branch.sh"

  assert_success
  grep -q "inject_next_workflow called" "$CALLS_LOG"
}

@test "polling[workflow_done-set]: workflow_done が非空かつ inject 成功時に check_and_nudge をスキップ" {
  WORKFLOW_DONE_VALUE="/twl:workflow-pr-verify" \
  INJECT_EXIT=0 \
    run bash "$SANDBOX/scripts/polling-branch.sh"

  assert_success
  grep -q "inject_next_workflow called" "$CALLS_LOG"
  ! grep -q "check_and_nudge called" "$CALLS_LOG" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Scenario: workflow_done が未設定の場合
# WHEN status=running 中に workflow_done が空文字
# THEN inject_next_workflow() を呼ばず check_and_nudge() を継続する
# ---------------------------------------------------------------------------

@test "polling[workflow_done-empty]: workflow_done が空文字の場合に inject_next_workflow を呼ばない" {
  WORKFLOW_DONE_VALUE="" \
    run bash "$SANDBOX/scripts/polling-branch.sh"

  assert_success
  ! grep -q "inject_next_workflow called" "$CALLS_LOG" 2>/dev/null
}

@test "polling[workflow_done-empty]: workflow_done が空文字の場合に check_and_nudge を呼ぶ" {
  WORKFLOW_DONE_VALUE="" \
    run bash "$SANDBOX/scripts/polling-branch.sh"

  assert_success
  grep -q "check_and_nudge called" "$CALLS_LOG"
}

# ---------------------------------------------------------------------------
# Edge case: workflow_done が "null" 文字列の場合は未設定扱い
# WHEN workflow_done フィールドが "null" 文字列（JSON null の文字列表現）
# THEN 空文字と同等として check_and_nudge() を呼ぶ
# ---------------------------------------------------------------------------

@test "polling[workflow_done-null-string]: workflow_done が 'null' 文字列の場合に inject を呼ばない" {
  WORKFLOW_DONE_VALUE="null" \
    run bash "$SANDBOX/scripts/polling-branch.sh"

  assert_success
  ! grep -q "inject_next_workflow called" "$CALLS_LOG" 2>/dev/null
}

@test "polling[workflow_done-null-string]: workflow_done が 'null' 文字列の場合に check_and_nudge を呼ぶ" {
  WORKFLOW_DONE_VALUE="null" \
    run bash "$SANDBOX/scripts/polling-branch.sh"

  assert_success
  grep -q "check_and_nudge called" "$CALLS_LOG"
}

# ---------------------------------------------------------------------------
# Edge case: workflow_done が設定されているが inject が失敗した場合
# Requirement: check_and_nudge() の条件付きスキップ
# WHEN inject_next_workflow() が戻り値 1 で失敗する
# THEN inject_matched=0 なので check_and_nudge() を呼ぶ
# ---------------------------------------------------------------------------

@test "polling[inject-fail]: inject_next_workflow 失敗時は check_and_nudge を継続する" {
  WORKFLOW_DONE_VALUE="/twl:workflow-pr-verify" \
  INJECT_EXIT=1 \
    run bash "$SANDBOX/scripts/polling-branch.sh"

  assert_success
  grep -q "inject_next_workflow called" "$CALLS_LOG"
  grep -q "check_and_nudge called" "$CALLS_LOG"
}

# ---------------------------------------------------------------------------
# Edge case: state read は常に1回呼ばれる（ショートサーキット確認）
# ---------------------------------------------------------------------------

@test "polling[state-read]: workflow_done の state read は1回呼ばれる（非空の場合）" {
  WORKFLOW_DONE_VALUE="/twl:workflow-pr-verify" \
    run bash "$SANDBOX/scripts/polling-branch.sh"

  assert_success
  local count
  count=$(grep -c "state_read workflow_done" "$CALLS_LOG" 2>/dev/null || echo 0)
  [[ "$count" -eq 1 ]]
}

@test "polling[state-read]: workflow_done の state read は1回呼ばれる（空の場合）" {
  WORKFLOW_DONE_VALUE="" \
    run bash "$SANDBOX/scripts/polling-branch.sh"

  assert_success
  local count
  count=$(grep -c "state_read workflow_done" "$CALLS_LOG" 2>/dev/null || echo 0)
  [[ "$count" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# Edge case: workflow_done に whitespace のみの値は非空扱いになるか
# 実装: [[ -n "$workflow_done" ]] → スペースも非空として検知される
# WHEN workflow_done がスペース1文字
# THEN -n 条件で真になり inject を呼ぶ（実装の動作を文書化）
# ---------------------------------------------------------------------------

@test "polling[whitespace]: workflow_done がスペース1文字の場合は非空扱いで inject を呼ぶ" {
  WORKFLOW_DONE_VALUE=" " \
    run bash "$SANDBOX/scripts/polling-branch.sh"

  assert_success
  # スペースは -n で真になる（bash の動作として文書化）
  grep -q "inject_next_workflow called" "$CALLS_LOG"
}

# ---------------------------------------------------------------------------
# Edge case: workflow_done に "0" や "false" の場合も非空扱い
# ---------------------------------------------------------------------------

@test "polling[truthy-values]: workflow_done が '0' でも inject を呼ぶ（非空として扱う）" {
  WORKFLOW_DONE_VALUE="0" \
    run bash "$SANDBOX/scripts/polling-branch.sh"

  assert_success
  grep -q "inject_next_workflow called" "$CALLS_LOG"
}

@test "polling[truthy-values]: workflow_done が 'false' でも inject を呼ぶ（非空として扱う）" {
  WORKFLOW_DONE_VALUE="false" \
    run bash "$SANDBOX/scripts/polling-branch.sh"

  assert_success
  grep -q "inject_next_workflow called" "$CALLS_LOG"
}
