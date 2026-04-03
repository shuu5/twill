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

# パターン検査 → 次コマンド決定（orchestrator 実装と同一の if-elif 構造）
if echo "$pane_output" | grep -qP "setup chain 完了"; then
  echo "/dev:workflow-test-ready #${issue}"
elif echo "$pane_output" | grep -qP ">>> 提案完了"; then
  echo ""
elif echo "$pane_output" | grep -qP "テスト準備.*完了"; then
  echo "/dev:workflow-pr-cycle #${issue}"
elif echo "$pane_output" | grep -qP "PR サイクル.*完了"; then
  echo ""
elif echo "$pane_output" | grep -qP "workflow-test-ready.*で次に進めます"; then
  echo "/dev:workflow-test-ready #${issue}"
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
@test "nudge: 'setup chain 完了' → /dev:workflow-test-ready #N" {
  run bash "$SANDBOX/scripts/nudge-dispatch.sh" "129" "ap-#129" "setup chain 完了"

  assert_success
  assert_output "/dev:workflow-test-ready #129"
}

# Scenario: chain 内遷移パターン（提案完了）→ 空コマンド
@test "nudge: '>>> 提案完了' → 空（chain 内遷移）" {
  run bash "$SANDBOX/scripts/nudge-dispatch.sh" "129" "ap-#129" ">>> 提案完了: orchestrator-nudge-command"

  assert_success
  assert_output ""
}

# Scenario: テスト準備完了パターン → workflow-pr-cycle コマンド送信
@test "nudge: 'テスト準備.*完了' → /dev:workflow-pr-cycle #N" {
  run bash "$SANDBOX/scripts/nudge-dispatch.sh" "135" "ap-#135" "テスト準備が完了しました"

  assert_success
  assert_output "/dev:workflow-pr-cycle #135"
}

# Scenario: PR サイクル完了パターン → 空コマンド（chain 終端）
@test "nudge: 'PR サイクル.*完了' → 空（chain 終端）" {
  run bash "$SANDBOX/scripts/nudge-dispatch.sh" "135" "ap-#135" "PR サイクルが完了しました"

  assert_success
  assert_output ""
}

# Scenario: workflow-test-ready 案内パターン → workflow-test-ready コマンド送信
@test "nudge: 'workflow-test-ready.*で次に進めます' → /dev:workflow-test-ready #N" {
  run bash "$SANDBOX/scripts/nudge-dispatch.sh" "42" "ap-#42" "workflow-test-ready で次に進めます"

  assert_success
  assert_output "/dev:workflow-test-ready #42"
}

# Scenario: issue 番号の置換（#N → 実際の番号）
@test "nudge: #N を issue 番号で正しく置換する" {
  run bash "$SANDBOX/scripts/nudge-dispatch.sh" "99" "ap-#99" "setup chain 完了"

  assert_success
  assert_output "/dev:workflow-test-ready #99"
}

# Scenario: パターンマッチなし → 空文字を返す
@test "nudge: マッチしないテキストには空文字を返す" {
  run bash "$SANDBOX/scripts/nudge-dispatch.sh" "1" "ap-#1" "通常のログ出力"

  assert_success
  assert_output ""
}
