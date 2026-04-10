#!/usr/bin/env bats
# inject-next-workflow.bats
# Requirement: inject_next_workflow() — Orchestrator の Pilot 駆動 workflow 遷移
# Spec: deltaspec/changes/orchestrator-inject-next-workflow/specs/orchestrator/spec.md
#
# inject_next_workflow() は autopilot-orchestrator.sh に追加される新関数。
# tmux pane の入力待ち確認 → workflow skill inject → 後処理を担う。
#
# test double: inject-next-workflow-dispatch.sh
#   Usage: inject-next-workflow-dispatch.sh <issue> <window_name>
#   Env:
#     NEXT_WORKFLOW  - resolve_next_workflow の返り値（デフォルト: "/twl:workflow-pr-verify"）
#     RESOLVE_EXIT   - resolve_next_workflow の終了コード（デフォルト: 0）
#     PANE_OUTPUT    - tmux capture-pane の出力（デフォルト: "> " でプロンプトあり）
#     CALLS_LOG      - 呼び出し記録ファイル
#     STATE_FILE     - state 書き込み先ファイル

load '../../bats/helpers/common.bash'

# ---------------------------------------------------------------------------
# setup: inject_next_workflow テスト double を生成
# ---------------------------------------------------------------------------

setup() {
  common_setup

  CALLS_LOG="$SANDBOX/calls.log"
  STATE_FILE="$SANDBOX/state.log"
  export CALLS_LOG STATE_FILE

  # テスト double: inject_next_workflow ロジック
  cat > "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" << 'DISPATCH_EOF'
#!/usr/bin/env bash
# inject-next-workflow-dispatch.sh
# inject_next_workflow() の test double
# Usage: <issue> <window_name>
# Env:
#   NEXT_WORKFLOW  - resolve_next_workflow の返り値
#   RESOLVE_EXIT   - resolve_next_workflow の終了コード（デフォルト: 0）
#   PANE_OUTPUT    - tmux capture-pane の出力（デフォルト: "> "）
#   CALLS_LOG      - 呼び出し記録ファイル
#   STATE_FILE     - state write の記録ファイル
set -uo pipefail

issue="$1"
window_name="$2"

NEXT_WORKFLOW="${NEXT_WORKFLOW:-/twl:workflow-pr-verify}"
RESOLVE_EXIT="${RESOLVE_EXIT:-0}"
PANE_OUTPUT="${PANE_OUTPUT:-"> "}"
CALLS_LOG="${CALLS_LOG:-/dev/null}"
STATE_FILE="${STATE_FILE:-/dev/null}"
declare -A NUDGE_COUNTS=()

# --- resolve_next_workflow 呼び出し ---
echo "resolve_next_workflow --issue $issue" >> "$CALLS_LOG"
if [[ "$RESOLVE_EXIT" -ne 0 ]]; then
  echo "[orchestrator] WARNING: resolve_next_workflow 失敗 — issue $issue" >&2
  exit 1
fi
next_skill="$NEXT_WORKFLOW"

# --- allow-list バリデーション（コマンドインジェクション防止） ---
_skill_safe="${next_skill//$'\n'/}"  # 改行除去
if [[ "$_skill_safe" == "pr-merge" || "$_skill_safe" == "/twl:workflow-pr-merge" ]]; then
  echo "[orchestrator] Issue #${issue}: pr-merge 検出 — inject スキップ、merge-gate フローに委譲" >&2
  echo "state_write workflow_done=null" >> "$STATE_FILE"
  exit 0
fi
if [[ ! "$_skill_safe" =~ ^/twl:workflow-[a-z][a-z0-9-]*$ ]]; then
  echo "[orchestrator] WARNING: 不正な workflow skill '${_skill_safe}' — inject スキップ" >&2
  exit 1
fi

# --- tmux pane 入力待ち確認（最大3回、2秒間隔） ---
_prompt_re='[>$][[:space:]]*$'
prompt_found=0
for i in 1 2 3; do
  echo "tmux capture-pane -p -t $window_name" >> "$CALLS_LOG"
  pane_tail=$(echo "$PANE_OUTPUT" | tail -1)
  if [[ "$pane_tail" =~ $_prompt_re ]]; then
    prompt_found=1
    break
  fi
  sleep 0.01  # テスト環境では短縮（実装は 2 秒）
done

if [[ "$prompt_found" -eq 0 ]]; then
  echo "[orchestrator] WARNING: inject タイムアウト — 10秒後に再チェック (issue=$issue)" >&2
  exit 1
fi

# --- inject 実行（バリデーション済み _skill_safe を使用） ---
echo "tmux send-keys -t $window_name $_skill_safe" >> "$CALLS_LOG"
echo "[orchestrator] Issue #${issue}: inject_next_workflow — $_skill_safe" >&2

# --- workflow_done クリア ---
echo "state_write workflow_done=null" >> "$STATE_FILE"

# --- inject 履歴記録 ---
echo "state_write workflow_injected=$_skill_safe" >> "$STATE_FILE"
echo "state_write injected_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$STATE_FILE"

# --- NUDGE_COUNTS リセット ---
NUDGE_COUNTS[$issue]=0
echo "nudge_counts_reset issue=$issue" >> "$CALLS_LOG"

exit 0
DISPATCH_EOF
  chmod +x "$SANDBOX/scripts/inject-next-workflow-dispatch.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Scenario: 正常な inject フロー
# WHEN inject_next_workflow() が呼ばれ resolve_next_workflow が非 pr-merge を返す
# THEN pane 確認 → inject → workflow_done クリア → 履歴記録 → NUDGE_COUNTS リセット
# ---------------------------------------------------------------------------

@test "inject_next_workflow: 正常フローで tmux send-keys を実行する" {
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_success
  grep -q "tmux send-keys -t ap-#340 /twl:workflow-pr-verify" "$CALLS_LOG"
}

@test "inject_next_workflow: 正常フローで [orchestrator] inject ログを出力する" {
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_success
  assert_output --partial "[orchestrator] Issue #340: inject_next_workflow — /twl:workflow-pr-verify"
}

@test "inject_next_workflow: inject 成功後に workflow_done をクリアする" {
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_success
  grep -q "state_write workflow_done=null" "$STATE_FILE"
}

@test "inject_next_workflow: inject 成功後に workflow_injected を state に記録する" {
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_success
  grep -q "state_write workflow_injected=/twl:workflow-pr-verify" "$STATE_FILE"
}

@test "inject_next_workflow: inject 成功後に injected_at を state に記録する" {
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_success
  grep -q "state_write injected_at=" "$STATE_FILE"
}

@test "inject_next_workflow: inject 成功後に NUDGE_COUNTS をリセットする" {
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_success
  grep -q "nudge_counts_reset issue=340" "$CALLS_LOG"
}

# ---------------------------------------------------------------------------
# Scenario: pr-merge terminal workflow
# WHEN resolve_next_workflow が pr-merge を返す
# THEN inject せず workflow_done のみクリアして戻る
# ---------------------------------------------------------------------------

@test "inject_next_workflow[pr-merge]: inject をスキップする" {
  NEXT_WORKFLOW="pr-merge" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_success
  ! grep -q "tmux send-keys" "$CALLS_LOG" 2>/dev/null
}

@test "inject_next_workflow[pr-merge]: workflow_done をクリアする" {
  NEXT_WORKFLOW="pr-merge" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_success
  grep -q "state_write workflow_done=null" "$STATE_FILE"
}

@test "inject_next_workflow[pr-merge]: merge-gate フロー委譲ログを出力する" {
  NEXT_WORKFLOW="pr-merge" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_success
  assert_output --partial "merge-gate フローに委譲"
}

# ---------------------------------------------------------------------------
# Scenario: 3回リトライ後もプロンプト未検出
# WHEN tmux capture-pane が3回ともプロンプトなし出力を返す
# THEN WARNING ログを出力し戻り値 1 で終了する
# ---------------------------------------------------------------------------

@test "inject_next_workflow[timeout]: プロンプト未検出時に戻り値 1 を返す" {
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  PANE_OUTPUT="Working..." \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_failure
}

@test "inject_next_workflow[timeout]: プロンプト未検出時に WARNING ログを出力する" {
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  PANE_OUTPUT="Working..." \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_failure
  assert_output --partial "WARNING: inject タイムアウト"
}

@test "inject_next_workflow[timeout]: プロンプト未検出時に tmux send-keys を呼ばない" {
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  PANE_OUTPUT="Working..." \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_failure
  ! grep -q "tmux send-keys" "$CALLS_LOG" 2>/dev/null
}

@test "inject_next_workflow[timeout]: プロンプト未検出時に workflow_done をクリアしない" {
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  PANE_OUTPUT="Working..." \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_failure
  ! grep -q "state_write workflow_done=null" "$STATE_FILE" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Scenario: resolve_next_workflow 失敗
# WHEN resolve_next_workflow がエラーを返す
# THEN WARNING ログを出力し inject せず戻り値 1 で終了する
# ---------------------------------------------------------------------------

@test "inject_next_workflow[resolve-fail]: resolve 失敗時に戻り値 1 を返す" {
  RESOLVE_EXIT=1 \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_failure
}

@test "inject_next_workflow[resolve-fail]: resolve 失敗時に WARNING ログを出力する" {
  RESOLVE_EXIT=1 \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_failure
  assert_output --partial "WARNING: resolve_next_workflow 失敗"
}

@test "inject_next_workflow[resolve-fail]: resolve 失敗時に tmux send-keys を呼ばない" {
  RESOLVE_EXIT=1 \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_failure
  ! grep -q "tmux send-keys" "$CALLS_LOG" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Edge case: $ プロンプトでも inject が実行される
# ---------------------------------------------------------------------------

@test "inject_next_workflow: '\$ ' プロンプトでも inject を実行する" {
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  PANE_OUTPUT="$ " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_success
  grep -q "tmux send-keys -t ap-#340 /twl:workflow-pr-verify" "$CALLS_LOG"
}

# ---------------------------------------------------------------------------
# Edge case: resolve_next_workflow が呼ばれていること
# ---------------------------------------------------------------------------

@test "inject_next_workflow: resolve_next_workflow を必ず呼び出す" {
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_success
  grep -q "resolve_next_workflow --issue 340" "$CALLS_LOG"
}

# ---------------------------------------------------------------------------
# Security: allow-list バリデーション
# ---------------------------------------------------------------------------

@test "inject_next_workflow[security]: 不正な skill 名は inject されない" {
  NEXT_WORKFLOW="malicious; rm -rf /" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_failure
  ! grep -q "tmux send-keys" "$CALLS_LOG" 2>/dev/null
}

@test "inject_next_workflow[security]: 不正 skill に WARNING ログを出力する" {
  NEXT_WORKFLOW="malicious; rm -rf /" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_failure
  assert_output --partial "WARNING: 不正な workflow skill"
}

@test "inject_next_workflow[security]: /twl:workflow- プレフィックスなしは拒否" {
  NEXT_WORKFLOW="workflow-pr-verify" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_failure
  ! grep -q "tmux send-keys" "$CALLS_LOG" 2>/dev/null
}

@test "inject_next_workflow[security]: セミコロンを含む skill 名は拒否される" {
  NEXT_WORKFLOW="/twl:workflow-pr-verify; rm -rf /" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_failure
  ! grep -q "tmux send-keys" "$CALLS_LOG" 2>/dev/null
}

@test "inject_next_workflow[security]: 有効な /twl:workflow-<kebab> は許可される" {
  NEXT_WORKFLOW="/twl:workflow-pr-fix" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_success
  grep -q "tmux send-keys -t ap-#340 /twl:workflow-pr-fix" "$CALLS_LOG"
}
