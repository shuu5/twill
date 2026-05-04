#!/usr/bin/env bats
# issue-1385-tmux-window-kill.bats
#
# Issue #1385: safe_kill_window ヘルパー化（tmux kill-window direct call 排除）
# AC: plugins/twl/scripts/lib/tmux-window-kill.sh 新規作成 + 既存 18 箇所置換
#
# RED: 実装前は全テスト fail（lib 未存在 / 直接呼び出し 18 箇所残存）
# GREEN: 実装後に PASS

load 'helpers/common'

setup() {
  common_setup
  # common_setup が $REPO_ROOT/scripts/lib/* を $SANDBOX/scripts/lib/ にコピー済み
  SANDBOX_LIB="$SANDBOX/scripts/lib/tmux-window-kill.sh"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC-1: lib/tmux-window-kill.sh が存在し safe_kill_window が export されている
#
# RED: ファイル未存在 → source 失敗 → fail
# GREEN: 実装後 source 成功 + safe_kill_window が declare -F に現れる → PASS
# ===========================================================================
@test "ac1: plugins/twl/scripts/lib/tmux-window-kill.sh が存在し safe_kill_window を export している" {
  # AC: lib/tmux-window-kill.sh が存在し safe_kill_window 関数を export している
  # RED: lib 未実装のためファイルが存在せず source 失敗
  run bash -c "source \"$SANDBOX_LIB\" && declare -F safe_kill_window >/dev/null"
  assert_success
}

# ===========================================================================
# AC-2: plugins/twl/scripts/ の tmux kill-window -t 直接呼び出しがヘルパー定義 1 件のみ
#
# RED: 18 箇所の直接呼び出し残存 → count > 1 → fail
# GREEN: 全置換後 → ヘルパー定義 1 件のみ → PASS
# ===========================================================================
@test "ac2: plugins/twl/scripts/ の tmux kill-window -t 直接呼び出しがヘルパー定義 1 件のみ" {
  # AC: grep -rn 'tmux kill-window -t' plugins/twl/scripts/ の結果がヘルパー定義 1 件のみ
  # RED: 現在 18 箇所の直接呼び出しが存在するため count > 1
  local count
  count=$(grep -rn 'tmux kill-window -t' "$REPO_ROOT/scripts/" 2>/dev/null | wc -l)
  [[ "$count" -eq 1 ]]
}

# ===========================================================================
# AC-3: safe_kill_window が tmux list-windows -a -F 経由で target を解決している
#
# RED: lib 未存在 → grep 失敗 → fail
# GREEN: 実装後 list-windows -a -F パターン確認 → PASS
# ===========================================================================
@test "ac3: safe_kill_window が list-windows -a -F を経由して target を解決している" {
  # AC: safe_kill_window が '#{session_name}:#{window_index} #{window_name}' 経由で解決
  # RED: ファイル未存在のため grep 失敗
  run grep -qF 'list-windows -a -F' "$SANDBOX_LIB"
  assert_success
}

# ===========================================================================
# AC-4: 複数 session に同名 window が存在する場合に set -e 下でもエラー終了しない
#
# RED: lib 未存在 → source 失敗 → fail
# GREEN: 実装後 → tmux mock で複数 session 同名 window を返しても
#        awk 先頭 1 件取得 → kill → exit 0 → PASS
# ===========================================================================
@test "ac4: 同名 window が複数 session に存在する場合に set -e 下で safe_kill_window が継続する" {
  # AC: ambiguous target エラーで script が終了しない（set -e 下でも継続）
  # RED: lib 未実装のため source 失敗
  run bash <<EOF
set -euo pipefail

tmux() {
    case "\$1" in
        list-windows)
            printf 'sess1:0 my-window\nsess2:0 my-window\n'
            return 0
            ;;
        kill-window)
            return 0
            ;;
        *)
            return 0
            ;;
    esac
}
export -f tmux

source "$SANDBOX_LIB"
safe_kill_window "my-window"
echo "completed"
EOF
  assert_success
  assert_output --partial "completed"
}

# ===========================================================================
# AC-5: 主要ファイル（autopilot-orchestrator.sh）に tmux kill-window 直接呼び出しが残存しない
#
# RED: 未置換 → direct call が 2 件存在 → count > 0 → fail
# GREEN: 置換完了 → direct call なし → PASS
# ===========================================================================
@test "ac5: autopilot-orchestrator.sh の tmux kill-window -t 直接呼び出しが 0 件になっている" {
  # AC: 既存 e2e/integration テストが green（主要ファイルの置換完了確認）
  # RED: autopilot-orchestrator.sh に 2 件の直接呼び出しが残存
  local count=0
  count=$(grep -c 'tmux kill-window -t' "$SANDBOX/scripts/autopilot-orchestrator.sh" 2>/dev/null) || count=0
  [[ "$count" -eq 0 ]]
}
