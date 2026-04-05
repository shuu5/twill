#!/usr/bin/env bats
# orchestrator-nudge.bats
# Requirement: CHAIN_NUDGE_COMMANDS パターン → 次コマンドマッピング
#
# check_and_nudge() はオーケストレーター本体に埋め込まれているため、
# 関数ロジックのみを抽出した test double スクリプトで動作を検証する。

load '../helpers/common'

# ---------------------------------------------------------------------------
# setup: test double スクリプトを生成
# ---------------------------------------------------------------------------
# nudge-dispatch.sh: check_and_nudge() の停止検知 + コマンド送信ロジックのみを抽出
# 引数: <issue> <window> <pane_output>
# 出力: tmux send-keys に渡されるコマンド文字列を stdout へ出力
# ---------------------------------------------------------------------------

setup() {
  common_setup

  # テスト用 nudge ディスパッチスクリプトを生成
  cat > "$SANDBOX/scripts/nudge-dispatch.sh" << 'DISPATCH_EOF'
#!/usr/bin/env bash
# nudge-dispatch.sh - check_and_nudge() のコマンド選択ロジック test double
# Usage: nudge-dispatch.sh <issue> <window_name> <pane_output>
# stdout: tmux send-keys に渡すコマンド文字列（空文字 = 空 Enter）
set -euo pipefail

issue="$1"
pane_output="$3"

AUTOPILOT_DIR="${AUTOPILOT_DIR:-}"

# is_quick 取得: state ファイルから一次取得
is_quick=""
if [[ -n "$AUTOPILOT_DIR" ]]; then
  state_file="$AUTOPILOT_DIR/issues/issue-${issue}.json"
  if [[ -f "$state_file" ]]; then
    is_quick=$(jq -r '.is_quick // empty' "$state_file" 2>/dev/null || true)
  fi
fi

# test-ready 系パターン: quick Issue の場合はスキップ（return 1 相当 = exit 1）
if echo "$pane_output" | grep -qP "setup chain 完了|workflow-test-ready.*で次に進めます"; then
  if [[ "$is_quick" == "true" ]]; then
    exit 1
  fi
fi

# パターン検査 → 次コマンド決定（orchestrator 実装と同一の if-elif 構造）
if echo "$pane_output" | grep -qP "setup chain 完了"; then
  echo "/twl:workflow-test-ready #${issue}"
elif echo "$pane_output" | grep -qP ">>> 提案完了"; then
  echo ""
elif echo "$pane_output" | grep -qP "テスト準備.*完了"; then
  echo "/twl:workflow-pr-cycle #${issue}"
elif echo "$pane_output" | grep -qP "PR サイクル.*完了"; then
  echo ""
elif echo "$pane_output" | grep -qP "workflow-test-ready.*で次に進めます"; then
  echo "/twl:workflow-test-ready #${issue}"
else
  echo ""
fi
DISPATCH_EOF
  chmod +x "$SANDBOX/scripts/nudge-dispatch.sh"

  # tmux send-keys のキャプチャ用ファイル
  SENT_FILE="$SANDBOX/tmux-sent.txt"
  export SENT_FILE

  stub_command "tmux" "
    case \"\$*\" in
      *capture-pane*)
        echo 'dummy output' ;;
      *send-keys*)
        # 引数から送信テキストを抽出して記録
        shift; shift; shift  # tmux send-keys -t <window>
        echo \"\$*\" >> '$SENT_FILE' ;;
    esac
  "
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: CHAIN_NUDGE_COMMANDS パターン → 次コマンドマッピング
# ---------------------------------------------------------------------------

# Scenario: setup chain 完了パターン → workflow-test-ready コマンド送信
@test "nudge: 'setup chain 完了' → /twl:workflow-test-ready #N" {
  run bash "$SANDBOX/scripts/nudge-dispatch.sh" "129" "ap-#129" "setup chain 完了"

  assert_success
  assert_output "/twl:workflow-test-ready #129"
}

# Scenario: chain 内遷移パターン（提案完了）→ 空コマンド
@test "nudge: '>>> 提案完了' → 空（chain 内遷移）" {
  run bash "$SANDBOX/scripts/nudge-dispatch.sh" "129" "ap-#129" ">>> 提案完了: orchestrator-nudge-command"

  assert_success
  assert_output ""
}

# Scenario: テスト準備完了パターン → workflow-pr-cycle コマンド送信
@test "nudge: 'テスト準備.*完了' → /twl:workflow-pr-cycle #N" {
  run bash "$SANDBOX/scripts/nudge-dispatch.sh" "135" "ap-#135" "テスト準備が完了しました"

  assert_success
  assert_output "/twl:workflow-pr-cycle #135"
}

# Scenario: PR サイクル完了パターン → 空コマンド（chain 終端）
@test "nudge: 'PR サイクル.*完了' → 空（chain 終端）" {
  run bash "$SANDBOX/scripts/nudge-dispatch.sh" "135" "ap-#135" "PR サイクルが完了しました"

  assert_success
  assert_output ""
}

# Scenario: workflow-test-ready 案内パターン → workflow-test-ready コマンド送信
@test "nudge: 'workflow-test-ready.*で次に進めます' → /twl:workflow-test-ready #N" {
  run bash "$SANDBOX/scripts/nudge-dispatch.sh" "42" "ap-#42" "workflow-test-ready で次に進めます"

  assert_success
  assert_output "/twl:workflow-test-ready #42"
}

# Scenario: issue 番号の置換（#N → 実際の番号）
@test "nudge: #N を issue 番号で正しく置換する" {
  run bash "$SANDBOX/scripts/nudge-dispatch.sh" "99" "ap-#99" "setup chain 完了"

  assert_success
  assert_output "/twl:workflow-test-ready #99"
}

# Scenario: パターンマッチなし → 空文字を返す
@test "nudge: マッチしないテキストには空文字を返す" {
  run bash "$SANDBOX/scripts/nudge-dispatch.sh" "1" "ap-#1" "通常のログ出力"

  assert_success
  assert_output ""
}

# ---------------------------------------------------------------------------
# Requirement: quick Issue での test-ready nudge スキップ
# ---------------------------------------------------------------------------

# Scenario: quick Issue で setup chain 完了 → nudge しない
# WHEN: is_quick=true の Issue で pane_output が "setup chain 完了" を含む
# THEN: exit 1 を返し、/twl:workflow-test-ready を送信しない
@test "nudge: quick Issue + 'setup chain 完了' → exit 1 (no nudge)" {
  create_issue_json 152 "running" '. + {is_quick: true}'

  run bash "$SANDBOX/scripts/nudge-dispatch.sh" "152" "ap-#152" "setup chain 完了"

  assert_failure
  assert_output ""
}

# Scenario: quick Issue で "workflow-test-ready で次に進めます" → nudge しない
# WHEN: is_quick=true の Issue で pane_output が "workflow-test-ready で次に進めます" を含む
# THEN: exit 1 を返し、/twl:workflow-test-ready を送信しない
@test "nudge: quick Issue + 'workflow-test-ready で次に進めます' → exit 1 (no nudge)" {
  create_issue_json 152 "running" '. + {is_quick: true}'

  run bash "$SANDBOX/scripts/nudge-dispatch.sh" "152" "ap-#152" "workflow-test-ready で次に進めます"

  assert_failure
  assert_output ""
}

# Scenario: 通常 Issue は従来通り動作する
# WHEN: is_quick=false の Issue で pane_output が "setup chain 完了" を含む
# THEN: /twl:workflow-test-ready #N を返す
@test "nudge: normal Issue (is_quick=false) + 'setup chain 完了' → /twl:workflow-test-ready #N" {
  create_issue_json 153 "running" '. + {is_quick: false}'

  run bash "$SANDBOX/scripts/nudge-dispatch.sh" "153" "ap-#153" "setup chain 完了"

  assert_success
  assert_output "/twl:workflow-test-ready #153"
}

# Scenario: quick Issue で通常パターンは影響を受けない
# WHEN: is_quick=true の Issue で pane_output が "テスト準備が完了しました" を含む
# THEN: /twl:workflow-pr-cycle #N を返す（test-ready 以外のパターンは従来通り）
@test "nudge: quick Issue + 'テスト準備.*完了' → /twl:workflow-pr-cycle #N (unaffected)" {
  create_issue_json 152 "running" '. + {is_quick: true}'

  run bash "$SANDBOX/scripts/nudge-dispatch.sh" "152" "ap-#152" "テスト準備が完了しました"

  assert_success
  assert_output "/twl:workflow-pr-cycle #152"
}

# Scenario: state ファイルに is_quick が未記録 → 通常動作（nudge 送信）
# WHEN: state ファイルに is_quick フィールドがない
# THEN: test-ready パターンで /twl:workflow-test-ready #N を返す（fallback: is_quick 空 = false 扱い）
@test "nudge: is_quick フィールド未記録の Issue → 通常通り nudge 送信" {
  create_issue_json 200 "running"

  run bash "$SANDBOX/scripts/nudge-dispatch.sh" "200" "ap-#200" "setup chain 完了"

  assert_success
  assert_output "/twl:workflow-test-ready #200"
}
