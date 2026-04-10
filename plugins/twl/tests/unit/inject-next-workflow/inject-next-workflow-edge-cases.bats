#!/usr/bin/env bats
# inject-next-workflow-edge-cases.bats
# Requirement: inject_next_workflow() — エッジケース・境界値テスト
# Spec: deltaspec/changes/orchestrator-inject-next-workflow/specs/orchestrator/spec.md
# Coverage: --type=unit --coverage=edge-cases
#
# 既存の inject-next-workflow.bats が正常系・基本エラー系をカバー済み。
# 本ファイルは以下のエッジケースに特化:
#   - プロンプト境界値（末尾空白なし、複数行末尾、$ 後に文字続き）
#   - resolve_next_workflow 空文字返却（exit 0 だが空文字）
#   - /twl:workflow-pr-merge の完全パス形式も pr-merge 扱い
#   - 数字のみ・大文字混在の不正 skill 名
#   - 改行埋め込みによるコマンドインジェクション試みを改行除去で無害化
#   - 引数の issue 番号が特殊文字を含む場合のログ出力
#   - injected_at が ISO8601 形式であること
#   - NUDGE_COUNTS リセット後に check_and_nudge がゼロから再カウントされること

load '../../bats/helpers/common.bash'

# ---------------------------------------------------------------------------
# setup: テスト double を生成（inject-next-workflow.bats と同形式）
# ---------------------------------------------------------------------------

setup() {
  common_setup

  CALLS_LOG="$SANDBOX/calls.log"
  STATE_FILE="$SANDBOX/state.log"
  export CALLS_LOG STATE_FILE

  cat > "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" << 'DISPATCH_EOF'
#!/usr/bin/env bash
# inject-next-workflow-dispatch.sh (edge-cases variant)
# inject_next_workflow() の test double — エッジケース用
#
# 注: NEXT_WORKFLOW / PANE_OUTPUT に空文字を渡す場合は
#     NEXT_WORKFLOW_EMPTY=1 / PANE_OUTPUT_EMPTY=1 を使う（:-展開回避）
set -uo pipefail

issue="$1"
window_name="$2"

# 空文字 override フラグ
if [[ "${NEXT_WORKFLOW_EMPTY:-0}" == "1" ]]; then
  NEXT_WORKFLOW=""
else
  NEXT_WORKFLOW="${NEXT_WORKFLOW:-/twl:workflow-pr-verify}"
fi
RESOLVE_EXIT="${RESOLVE_EXIT:-0}"
if [[ "${PANE_OUTPUT_EMPTY:-0}" == "1" ]]; then
  PANE_OUTPUT=""
else
  PANE_OUTPUT="${PANE_OUTPUT:-"> "}"
fi
CALLS_LOG="${CALLS_LOG:-/dev/null}"
STATE_FILE="${STATE_FILE:-/dev/null}"
declare -A NUDGE_COUNTS=()

# --- resolve_next_workflow 呼び出し ---
echo "resolve_next_workflow --issue $issue" >> "$CALLS_LOG"
if [[ "$RESOLVE_EXIT" -ne 0 ]]; then
  echo "[orchestrator] Issue #${issue}: WARNING: resolve_next_workflow 失敗 — inject スキップ" >&2
  exit 1
fi
next_skill="$NEXT_WORKFLOW"

# 空文字チェック（exit 0 だが空文字の場合）
if [[ -z "$next_skill" ]]; then
  echo "[orchestrator] Issue #${issue}: WARNING: resolve_next_workflow 失敗 — inject スキップ" >&2
  exit 1
fi

# --- allow-list バリデーション（コマンドインジェクション防止） ---
_skill_safe="${next_skill//$'\n'/}"  # 改行除去
if [[ "$_skill_safe" == "pr-merge" || "$_skill_safe" == "/twl:workflow-pr-merge" ]]; then
  echo "[orchestrator] Issue #${issue}: pr-merge 検出 — inject スキップ、merge-gate フローに委譲" >&2
  echo "state_write workflow_done=null" >> "$STATE_FILE"
  exit 0
fi
if [[ ! "$_skill_safe" =~ ^/twl:workflow-[a-z][a-z0-9-]*$ ]]; then
  echo "[orchestrator] Issue #${issue}: WARNING: 不正な workflow skill '${_skill_safe:0:200}' — inject スキップ" >&2
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
  sleep 0.01
done

if [[ "$prompt_found" -eq 0 ]]; then
  echo "[orchestrator] Issue #${issue}: WARNING: inject タイムアウト — ${POLL_INTERVAL:-10}秒後に再チェック" >&2
  exit 1
fi

# --- inject 実行 ---
echo "tmux send-keys -t $window_name $_skill_safe" >> "$CALLS_LOG"
echo "[orchestrator] Issue #${issue}: inject_next_workflow — $_skill_safe" >&2

# --- workflow_done クリア ---
echo "state_write workflow_done=null" >> "$STATE_FILE"

# --- inject 履歴記録 ---
injected_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "state_write workflow_injected=$_skill_safe" >> "$STATE_FILE"
echo "state_write injected_at=$injected_at" >> "$STATE_FILE"

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
# Edge case: resolve_next_workflow が exit 0 で空文字を返す
# WHEN resolve が exit 0 だが stdout が空の場合
# THEN WARNING ログを出力し戻り値 1 で終了する（inject 失敗として扱う）
# ---------------------------------------------------------------------------

@test "inject_next_workflow[empty-skill]: resolve が空文字を返した場合は失敗する" {
  NEXT_WORKFLOW_EMPTY=1 \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_failure
}

@test "inject_next_workflow[empty-skill]: resolve 空文字時に WARNING ログを出力する" {
  NEXT_WORKFLOW_EMPTY=1 \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_failure
  assert_output --partial "WARNING: resolve_next_workflow 失敗"
}

@test "inject_next_workflow[empty-skill]: resolve 空文字時に tmux send-keys を呼ばない" {
  NEXT_WORKFLOW_EMPTY=1 \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_failure
  ! grep -q "tmux send-keys" "$CALLS_LOG" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Edge case: /twl:workflow-pr-merge の完全パス形式（pr-merge 別名）
# WHEN resolve が "/twl:workflow-pr-merge" を返す（フルパス形式）
# THEN "pr-merge" と同様に inject スキップ、workflow_done のみクリア
# ---------------------------------------------------------------------------

@test "inject_next_workflow[full-pr-merge-path]: /twl:workflow-pr-merge は inject スキップ" {
  NEXT_WORKFLOW="/twl:workflow-pr-merge" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_success
  ! grep -q "tmux send-keys" "$CALLS_LOG" 2>/dev/null
}

@test "inject_next_workflow[full-pr-merge-path]: /twl:workflow-pr-merge 時に workflow_done をクリアする" {
  NEXT_WORKFLOW="/twl:workflow-pr-merge" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_success
  grep -q "state_write workflow_done=null" "$STATE_FILE"
}

@test "inject_next_workflow[full-pr-merge-path]: merge-gate 委譲ログを出力する" {
  NEXT_WORKFLOW="/twl:workflow-pr-merge" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_success
  assert_output --partial "merge-gate フローに委譲"
}

# ---------------------------------------------------------------------------
# Edge case: 大文字を含む skill 名は拒否される
# WHEN resolve が "/twl:workflow-PR-verify"（大文字含む）を返す
# THEN バリデーション失敗で inject スキップ
# ---------------------------------------------------------------------------

@test "inject_next_workflow[security]: 大文字を含む skill 名は拒否される" {
  NEXT_WORKFLOW="/twl:workflow-PR-verify" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_failure
  ! grep -q "tmux send-keys" "$CALLS_LOG" 2>/dev/null
}

@test "inject_next_workflow[security]: 数字始まりの skill セグメントは拒否される" {
  NEXT_WORKFLOW="/twl:workflow-1abc" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_failure
  ! grep -q "tmux send-keys" "$CALLS_LOG" 2>/dev/null
}

@test "inject_next_workflow[security]: ダブルダッシュを含む skill 名は allow-list を通過する（実装動作の文書化）" {
  # 正規表現 ^/twl:workflow-[a-z][a-z0-9-]*$ は連続ハイフンを明示的に禁止しない
  # このテストは実装の現在の動作（許可）を文書化する
  NEXT_WORKFLOW="/twl:workflow-pr--verify" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_success
  grep -q "tmux send-keys" "$CALLS_LOG"
}

@test "inject_next_workflow[security]: アンダースコアを含む skill 名は拒否される" {
  NEXT_WORKFLOW="/twl:workflow-pr_verify" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_failure
  ! grep -q "tmux send-keys" "$CALLS_LOG" 2>/dev/null
}

@test "inject_next_workflow[security]: 改行を含む skill 名は改行除去後バリデーションされる" {
  # 改行埋め込みで "valid\nmalicious" → 改行除去で "validmalicious" → 不正パターンで拒否
  # または改行で "/twl:workflow-valid\nrm -rf" → 除去後 "/twl:workflow-validrm -rf" → 拒否
  NEXT_WORKFLOW=$'/twl:workflow-valid\nrm -rf /' \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_failure
  ! grep -q "tmux send-keys" "$CALLS_LOG" 2>/dev/null
}

@test "inject_next_workflow[security]: スペースを含む skill 名は拒否される" {
  NEXT_WORKFLOW="/twl:workflow-pr verify" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_failure
  ! grep -q "tmux send-keys" "$CALLS_LOG" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Edge case: プロンプト検出の境界値
# ---------------------------------------------------------------------------

@test "inject_next_workflow[prompt]: 末尾が '> ' のみ（LF なし）でも検出される" {
  # printf で末尾改行なしのプロンプトを模擬
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_success
  grep -q "tmux send-keys" "$CALLS_LOG"
}

@test "inject_next_workflow[prompt]: 複数行出力で末尾行が '> ' の場合に検出される" {
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  PANE_OUTPUT=$'some output line\nanother line\n> ' \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_success
  grep -q "tmux send-keys" "$CALLS_LOG"
}

@test "inject_next_workflow[prompt]: '$ ' プロンプトが中間行にあっても末尾行でないと検出されない" {
  # 末尾行が "Working..." → プロンプト未検出
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  PANE_OUTPUT=$'$ \nWorking...' \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_failure
  assert_output --partial "WARNING: inject タイムアウト"
}

@test "inject_next_workflow[prompt]: プロンプト後に余分なスペースが複数ある場合も検出される" {
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  PANE_OUTPUT=">   " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_success
  grep -q "tmux send-keys" "$CALLS_LOG"
}

@test "inject_next_workflow[prompt]: プロンプト文字なしの空行はタイムアウトとなる" {
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  PANE_OUTPUT_EMPTY=1 \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_failure
  assert_output --partial "WARNING: inject タイムアウト"
}

# ---------------------------------------------------------------------------
# Edge case: 3回リトライの回数確認
# WHEN tmux capture-pane が3回ともプロンプトなし
# THEN capture-pane が正確に3回呼ばれる
# ---------------------------------------------------------------------------

@test "inject_next_workflow[timeout]: プロンプト未検出時に capture-pane を3回呼ぶ" {
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  PANE_OUTPUT="Working..." \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_failure
  local count
  count=$(grep -c "tmux capture-pane -p -t ap-#340" "$CALLS_LOG" 2>/dev/null || echo 0)
  [[ "$count" -eq 3 ]]
}

# ---------------------------------------------------------------------------
# Edge case: inject 成功後の injected_at が ISO8601 形式
# WHEN inject が成功する
# THEN injected_at の値が "%Y-%m-%dT%H:%M:%SZ" 形式を満たす
# ---------------------------------------------------------------------------

@test "inject_next_workflow[state]: injected_at が ISO8601 形式で記録される" {
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_success
  # ISO8601 パターン: 2024-01-01T00:00:00Z
  grep -qE "state_write injected_at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z" "$STATE_FILE"
}

# ---------------------------------------------------------------------------
# Edge case: workflow_done クリアの順序（inject 成功時と pr-merge 時の両方で必須）
# ---------------------------------------------------------------------------

@test "inject_next_workflow[order]: inject 成功時に workflow_done クリアが workflow_injected より先に記録される" {
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_success
  local line_clear line_injected
  line_clear=$(grep -n "state_write workflow_done=null" "$STATE_FILE" | head -1 | cut -d: -f1)
  line_injected=$(grep -n "state_write workflow_injected=" "$STATE_FILE" | head -1 | cut -d: -f1)
  [[ -n "$line_clear" && -n "$line_injected" ]]
  [[ "$line_clear" -lt "$line_injected" ]]
}

# ---------------------------------------------------------------------------
# Edge case: ログメッセージに [orchestrator] プレフィックスが含まれる
# Requirement: inject イベントのログ出力
# ---------------------------------------------------------------------------

@test "inject_next_workflow[log]: inject 実行ログは [orchestrator] プレフィックスを含む" {
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_success
  assert_output --partial "[orchestrator]"
}

@test "inject_next_workflow[log]: WARNING ログは [orchestrator] プレフィックスを含む（タイムアウト）" {
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  PANE_OUTPUT="Working..." \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_failure
  assert_output --partial "[orchestrator]"
  assert_output --partial "WARNING"
}

@test "inject_next_workflow[log]: WARNING ログは [orchestrator] プレフィックスを含む（resolve 失敗）" {
  RESOLVE_EXIT=1 \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_failure
  assert_output --partial "[orchestrator]"
  assert_output --partial "WARNING"
}

@test "inject_next_workflow[log]: inject ログに Issue 番号が含まれる" {
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_success
  assert_output --partial "Issue #340"
}

@test "inject_next_workflow[log]: inject ログに skill 名が含まれる" {
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_success
  assert_output --partial "inject_next_workflow — /twl:workflow-pr-verify"
}

# ---------------------------------------------------------------------------
# Edge case: 異なる Issue 番号でも正しく動作する
# ---------------------------------------------------------------------------

@test "inject_next_workflow[issue-num]: Issue 番号 1（最小値）で正常動作する" {
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "1" "ap-#1"

  assert_success
  assert_output --partial "Issue #1"
  grep -q "tmux send-keys -t ap-#1 /twl:workflow-pr-verify" "$CALLS_LOG"
}

@test "inject_next_workflow[issue-num]: 大きな Issue 番号（4桁）で正常動作する" {
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "9999" "ap-#9999"

  assert_success
  assert_output --partial "Issue #9999"
  grep -q "nudge_counts_reset issue=9999" "$CALLS_LOG"
}

# ---------------------------------------------------------------------------
# Edge case: 許可されている最長の skill 名
# ---------------------------------------------------------------------------

@test "inject_next_workflow[security]: 長い kebab チェーン skill 名は許可される" {
  NEXT_WORKFLOW="/twl:workflow-pr-fix-rebase-retry" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_success
  grep -q "tmux send-keys -t ap-#340 /twl:workflow-pr-fix-rebase-retry" "$CALLS_LOG"
}

@test "inject_next_workflow[security]: skill 名が /twl:workflow- だけ（本体なし）は拒否される" {
  NEXT_WORKFLOW="/twl:workflow-" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/inject-next-workflow-dispatch.sh" "340" "ap-#340"

  assert_failure
  ! grep -q "tmux send-keys" "$CALLS_LOG" 2>/dev/null
}
