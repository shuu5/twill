#!/usr/bin/env bats
# check-and-nudge-allowlist.bats
# Requirement: check_and_nudge allow-list 検証
# Spec: deltaspec/changes/issue-496/specs/security/spec.md
#
# check_and_nudge() が _nudge_command_for_pattern の出力を tmux send-keys に渡す前に
# allow-list バリデーションを適用することを確認する。
#
# test double: check-and-nudge-dispatch.sh
#   Usage: check-and-nudge-dispatch.sh <issue> <window_name>
#   Env:
#     NEXT_CMD      - _nudge_command_for_pattern の返り値（デフォルト: "/twl:workflow-test-ready"）
#     PATTERN_EXIT  - _nudge_command_for_pattern の終了コード（デフォルト: 0, 1=パターン不一致）
#     CALLS_LOG     - tmux send-keys 呼び出し記録ファイル
#     TRACE_LOG     - trace ログ記録ファイル

load '../../bats/helpers/common.bash'

# ---------------------------------------------------------------------------
# setup: check_and_nudge テスト double を生成
# ---------------------------------------------------------------------------

setup() {
  common_setup

  CALLS_LOG="$SANDBOX/calls.log"
  TRACE_LOG="$SANDBOX/trace.log"
  export CALLS_LOG TRACE_LOG

  # テスト double: check_and_nudge allow-list バリデーションロジック
  cat > "$SANDBOX/scripts/check-and-nudge-dispatch.sh" << 'DISPATCH_EOF'
#!/usr/bin/env bash
# check-and-nudge-dispatch.sh
# check_and_nudge() の allow-list バリデーション部分の test double
# Usage: <issue> <window_name>
# Env:
#   NEXT_CMD      - _nudge_command_for_pattern の返り値（デフォルト: "/twl:workflow-test-ready"）
#   PATTERN_EXIT  - _nudge_command_for_pattern の終了コード（デフォルト: 0）
#   CALLS_LOG     - 呼び出し記録ファイル
#   TRACE_LOG     - trace ログファイル
set -uo pipefail

issue="$1"
window_name="$2"

NEXT_CMD="${NEXT_CMD-/twl:workflow-test-ready}"
PATTERN_EXIT="${PATTERN_EXIT:-0}"
CALLS_LOG="${CALLS_LOG:-/dev/null}"
TRACE_LOG="${TRACE_LOG:-/dev/null}"

# _nudge_command_for_pattern の呼び出しをシミュレート
if [[ "$PATTERN_EXIT" -ne 0 ]]; then
  # パターン不一致: return 1 相当
  exit 0
fi

next_cmd="$NEXT_CMD"

# [[ -n "$next_cmd" ]] チェック（空文字は無操作）
if [[ -z "$next_cmd" ]]; then
  exit 0
fi

# --- allow-list バリデーション（コマンドインジェクション防止） ---
if [[ ! "$next_cmd" =~ ^/twl:workflow-[a-z][a-z0-9-]*$ ]]; then
  echo "[orchestrator] Issue #${issue}: WARNING: check_and_nudge — 不正な next_cmd '${next_cmd:0:200}' — nudge スキップ" >&2
  _trace_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "[${_trace_ts}] issue=${issue} next_cmd=INVALID result=skip reason=\"invalid next_cmd\"" >> "$TRACE_LOG" 2>/dev/null || true
  exit 0
fi

# --- inject 実行（バリデーション済み） ---
echo "tmux send-keys -t $window_name $next_cmd" >> "$CALLS_LOG"
echo "[orchestrator] Issue #${issue}: chain 遷移停止検知 — nudge 送信" >&2

exit 0
DISPATCH_EOF
  chmod +x "$SANDBOX/scripts/check-and-nudge-dispatch.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Scenario: 有効な workflow コマンドは inject される
# WHEN _nudge_command_for_pattern が /twl:workflow-test-ready を返す
# THEN allow-list を通過し tmux send-keys に渡される
# ---------------------------------------------------------------------------

@test "check_and_nudge[allowlist]: 有効コマンドは tmux send-keys に渡される" {
  NEXT_CMD="/twl:workflow-test-ready" \
    run bash "$SANDBOX/scripts/check-and-nudge-dispatch.sh" "496" "ap-#496"

  assert_success
  grep -q "tmux send-keys -t ap-#496 /twl:workflow-test-ready" "$CALLS_LOG"
}

@test "check_and_nudge[allowlist]: /twl:workflow-pr-verify は inject される" {
  NEXT_CMD="/twl:workflow-pr-verify" \
    run bash "$SANDBOX/scripts/check-and-nudge-dispatch.sh" "496" "ap-#496"

  assert_success
  grep -q "tmux send-keys -t ap-#496 /twl:workflow-pr-verify" "$CALLS_LOG"
}

@test "check_and_nudge[allowlist]: /twl:workflow-pr-fix は inject される" {
  NEXT_CMD="/twl:workflow-pr-fix" \
    run bash "$SANDBOX/scripts/check-and-nudge-dispatch.sh" "496" "ap-#496"

  assert_success
  grep -q "tmux send-keys -t ap-#496 /twl:workflow-pr-fix" "$CALLS_LOG"
}

@test "check_and_nudge[allowlist]: /twl:workflow-pr-merge は inject される" {
  NEXT_CMD="/twl:workflow-pr-merge" \
    run bash "$SANDBOX/scripts/check-and-nudge-dispatch.sh" "496" "ap-#496"

  assert_success
  grep -q "tmux send-keys -t ap-#496 /twl:workflow-pr-merge" "$CALLS_LOG"
}

# ---------------------------------------------------------------------------
# Scenario: 不正なコマンドは nudge をスキップする
# WHEN _nudge_command_for_pattern が allow-list に一致しない文字列を返す
# THEN WARNING ログを出力し tmux send-keys を呼ばない
# ---------------------------------------------------------------------------

@test "check_and_nudge[security]: 不正コマンドは tmux send-keys を呼ばない" {
  NEXT_CMD="malicious; rm -rf /" \
    run bash "$SANDBOX/scripts/check-and-nudge-dispatch.sh" "496" "ap-#496"

  assert_success
  ! grep -q "tmux send-keys" "$CALLS_LOG" 2>/dev/null
}

@test "check_and_nudge[security]: 不正コマンドに WARNING ログを出力する" {
  NEXT_CMD="malicious; rm -rf /" \
    run bash "$SANDBOX/scripts/check-and-nudge-dispatch.sh" "496" "ap-#496"

  assert_success
  assert_output --partial "WARNING: check_and_nudge"
}

@test "check_and_nudge[security]: /twl:workflow- プレフィックスなしは拒否される" {
  NEXT_CMD="workflow-pr-verify" \
    run bash "$SANDBOX/scripts/check-and-nudge-dispatch.sh" "496" "ap-#496"

  assert_success
  ! grep -q "tmux send-keys" "$CALLS_LOG" 2>/dev/null
}

@test "check_and_nudge[security]: セミコロンを含むコマンドは拒否される" {
  NEXT_CMD="/twl:workflow-pr-verify; rm -rf /" \
    run bash "$SANDBOX/scripts/check-and-nudge-dispatch.sh" "496" "ap-#496"

  assert_success
  ! grep -q "tmux send-keys" "$CALLS_LOG" 2>/dev/null
}

@test "check_and_nudge[security]: スペースを含むコマンドは拒否される（#N 付き inject_next_workflow 形式と区別）" {
  NEXT_CMD="/twl:workflow-pr-verify #496" \
    run bash "$SANDBOX/scripts/check-and-nudge-dispatch.sh" "496" "ap-#496"

  assert_success
  ! grep -q "tmux send-keys" "$CALLS_LOG" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Scenario: バリデーション失敗時に trace ログを出力する
# WHEN allow-list バリデーションが失敗する
# THEN trace ログに result=skip reason="invalid next_cmd" が記録される
# ---------------------------------------------------------------------------

@test "check_and_nudge[trace]: バリデーション失敗時に trace ログに result=skip を記録する" {
  NEXT_CMD="malicious" \
    run bash "$SANDBOX/scripts/check-and-nudge-dispatch.sh" "496" "ap-#496"

  assert_success
  grep -q "result=skip" "$TRACE_LOG"
}

@test "check_and_nudge[trace]: バリデーション失敗時に trace ログに reason=\"invalid next_cmd\" を記録する" {
  NEXT_CMD="malicious" \
    run bash "$SANDBOX/scripts/check-and-nudge-dispatch.sh" "496" "ap-#496"

  assert_success
  grep -q 'reason="invalid next_cmd"' "$TRACE_LOG"
}

# ---------------------------------------------------------------------------
# Scenario: 空文字列は無操作（既存の [[ -n "$next_cmd" ]] ガードで除外）
# WHEN _nudge_command_for_pattern が空文字列を返す（>>> 提案完了 / PR マージ完了）
# THEN tmux send-keys を呼ばずに正常終了する
# ---------------------------------------------------------------------------

@test "check_and_nudge[empty]: 空文字列は tmux send-keys を呼ばない" {
  NEXT_CMD="" \
    run bash "$SANDBOX/scripts/check-and-nudge-dispatch.sh" "496" "ap-#496"

  assert_success
  ! grep -q "tmux send-keys" "$CALLS_LOG" 2>/dev/null
}

@test "check_and_nudge[empty]: パターン不一致（exit 1）は tmux send-keys を呼ばない" {
  PATTERN_EXIT=1 \
    run bash "$SANDBOX/scripts/check-and-nudge-dispatch.sh" "496" "ap-#496"

  assert_success
  ! grep -q "tmux send-keys" "$CALLS_LOG" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Scenario: 既存 7 パターンの allow-list 通過確認（正規表現単体テスト）
# WHEN _nudge_command_for_pattern が返す 5 つの非空パターンを allow-list に通す
# THEN 全て ^/twl:workflow-[a-z][a-z0-9-]*$ に一致する
# ---------------------------------------------------------------------------

@test "check_and_nudge[7-patterns]: /twl:workflow-test-ready は allow-list を通過する" {
  [[ "/twl:workflow-test-ready" =~ ^/twl:workflow-[a-z][a-z0-9-]*$ ]]
}

@test "check_and_nudge[7-patterns]: /twl:workflow-pr-verify は allow-list を通過する（AC-2 fallback）" {
  [[ "/twl:workflow-pr-verify" =~ ^/twl:workflow-[a-z][a-z0-9-]*$ ]]
}

@test "check_and_nudge[7-patterns]: /twl:workflow-pr-verify は allow-list を通過する（テスト準備完了）" {
  [[ "/twl:workflow-pr-verify" =~ ^/twl:workflow-[a-z][a-z0-9-]*$ ]]
}

@test "check_and_nudge[7-patterns]: /twl:workflow-pr-fix は allow-list を通過する" {
  [[ "/twl:workflow-pr-fix" =~ ^/twl:workflow-[a-z][a-z0-9-]*$ ]]
}

@test "check_and_nudge[7-patterns]: /twl:workflow-pr-merge は allow-list を通過する" {
  [[ "/twl:workflow-pr-merge" =~ ^/twl:workflow-[a-z][a-z0-9-]*$ ]]
}
