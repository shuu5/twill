#!/usr/bin/env bats
# auto-merge-898-safety-net-false-positive.bats
#
# Issue #1393: #898 safety net が他セッション同名 window を誤検知する問題
#
# 修正前の問題: post-kill check が `list-windows -a -F '#{window_name}'`（全セッション）を
# 使うため、対象 Worker window を kill 後も別セッションに同名 window が存在すると
# kill 失敗と誤判定して exit 1 する（false positive）。
#
# 修正方針: kill 前に Worker window が属するセッションを解決し、
# post-kill check を `list-windows -t <session>` に切り替えて session-scoped にする。
#
# tmux stub の -F 引数検出:
#   -F '#{session_name}:#{window_index} #{window_name}' → TMUX_ALL_WINDOWS（session:index 形式）
#   -F '#{window_name}' + no -t         → TMUX_ALL_WINDOW_NAMES（window 名のみ、旧チェック用）
#   -F '#{window_name}' + has -t        → TMUX_SESSION_WINDOWS（session-scoped、新チェック用）
#
# RED/GREEN summary:
#   AC-1: 修正前 → exit 1（false positive）   修正後 → exit 0 ✓
#   AC-2: 修正前後とも → exit 1（true positive 維持）✓

load '../helpers/common'

setup() {
  common_setup

  # python3 stub: non-autopilot 経路
  WINDOW_FIELD_OUT="${WINDOW_FIELD_OUT:-ap-#1393}"
  export WINDOW_FIELD_OUT

  cat > "$STUB_BIN/python3" <<'PYSTUB'
#!/usr/bin/env bash
case "$*" in
  *"state read"*"--field status"*)       echo "done" ;;
  *"state read"*"--field is_quick"*)     echo "false" ;;
  *"state read"*"--field current_step"*) echo "" ;;
  *"state read"*"--field window"*)       echo "${WINDOW_FIELD_OUT:-ap-#1393}" ;;
  *"state write"*)                       exit 0 ;;
  *)                                     exit 0 ;;
esac
PYSTUB
  chmod +x "$STUB_BIN/python3"

  stub_command "gh" '
    case "$*" in
      *"pr merge"*"--squash"*)        exit 0 ;;
      *"pr view"*"mergeStateStatus"*) echo "CLEAN" ;;
      *)                              exit 0 ;;
    esac
  '

  cat > "$STUB_BIN/git" <<GITSTUB
#!/usr/bin/env bash
case "\$*" in
  "rev-parse --git-dir")
    echo "$SANDBOX/.bare/worktrees/feat1393" ;;
  "rev-parse --show-toplevel")
    echo "$SANDBOX" ;;
  "worktree list --porcelain")
    cat <<PORCELAIN
worktree $SANDBOX/main
branch refs/heads/main

worktree $SANDBOX/worktrees/feat1393
branch refs/heads/feat/1393-test

PORCELAIN
    ;;
  "worktree remove --force "*)
    [[ "\${WORKTREE_REMOVE_FAIL:-false}" == "true" ]] && exit 1 || exit 0 ;;
  "checkout main"|"pull origin main")
    exit 0 ;;
  "push origin --delete "*|"branch -D "*)
    exit 0 ;;
  *)
    exit 0 ;;
esac
GITSTUB
  chmod +x "$STUB_BIN/git"

  TMUX_KILL_WINDOW_LOG="$SANDBOX/tmux-kill-window.log"
  export TMUX_KILL_WINDOW_LOG
  : > "$TMUX_KILL_WINDOW_LOG"

  # tmux stub: -F 引数と -t の有無で 3 種類の list-windows 呼び出しを区別する
  #
  # TMUX_ALL_WINDOWS      = "session:index window_name" 形式
  #                          safe_kill_window + 事前セッション解決用
  # TMUX_ALL_WINDOW_NAMES = window 名のみ（1行1名）
  #                          旧 post-kill check 用（-a -F '#{window_name}'）
  # TMUX_SESSION_WINDOWS  = window 名のみ
  #                          新 session-scoped post-kill check 用（-t session -F '#{window_name}'）
  TMUX_ALL_WINDOWS="${TMUX_ALL_WINDOWS:-worker-session:0 ap-#1393}"
  TMUX_ALL_WINDOW_NAMES="${TMUX_ALL_WINDOW_NAMES:-ap-#1393}"
  TMUX_SESSION_WINDOWS="${TMUX_SESSION_WINDOWS:-}"
  export TMUX_ALL_WINDOWS TMUX_ALL_WINDOW_NAMES TMUX_SESSION_WINDOWS

  cat > "$STUB_BIN/tmux" <<'TMUXSTUB'
#!/usr/bin/env bash
case "$1" in
  display-message)
    echo "main" ;;
  list-windows)
    # -t が引数に含まれるか確認（session-scoped query）
    HAS_T=false
    # -F の値を取得（次の引数）
    FORMAT_VAL=""
    prev=""
    for arg in "$@"; do
      [[ "$arg" == "-t" ]] && HAS_T=true
      [[ "$prev" == "-F" ]] && FORMAT_VAL="$arg"
      prev="$arg"
    done

    if $HAS_T; then
      # session-scoped: 新 post-kill check 用
      printf '%s\n' "${TMUX_SESSION_WINDOWS:-}"
    elif printf '%s' "$FORMAT_VAL" | grep -q 'session_name'; then
      # global + session:index 形式: safe_kill_window + 事前セッション解決用
      printf '%s\n' "${TMUX_ALL_WINDOWS:-}"
    else
      # global + window 名のみ: 旧 post-kill check 用
      printf '%s\n' "${TMUX_ALL_WINDOW_NAMES:-}"
    fi ;;
  kill-window)
    printf '%s\n' "$*" >> "${TMUX_KILL_WINDOW_LOG}"
    [[ "${TMUX_KILL_FAIL:-false}" == "true" ]] && exit 1
    exit 0 ;;
  *)
    exit 0 ;;
esac
TMUXSTUB
  chmod +x "$STUB_BIN/tmux"

  stub_command "twl" 'exit 0'

  mkdir -p "$SANDBOX/main"
  cd "$SANDBOX/main"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC-1: kill 成功 + 他セッションに同名 window 残存 → exit 0（false positive 解消）
#
# RED:   修正前: list-windows -a -F '#{window_name}' が other-session の ap-#1393 を
#        返すため grep が true → exit 1（false positive）
# GREEN: 修正後: list-windows -t worker-session が空を返すため exit 0
# ===========================================================================
@test "#1393 AC-1: kill 後に他セッションに同名 window が残存しても exit 0（false positive 解消）" {
  # Worker session に ap-#1393 が存在（kill 対象）、other-session にも存在
  export TMUX_ALL_WINDOWS="worker-session:0 ap-#1393
other-session:0 ap-#1393"

  # 旧 post-kill check 用: other-session が ap-#1393 を持つため global list に現れる
  export TMUX_ALL_WINDOW_NAMES="ap-#1393"

  # 新 session-scoped check 用: worker-session は kill 後に空
  export TMUX_SESSION_WINDOWS=""

  run bash "$SANDBOX/scripts/auto-merge.sh" --issue 1393 --pr 1394 --branch feat/1393-test

  assert_success
  assert_output --partial "Worker window (ap-#1393) kill"
  assert_output --partial "worktree 削除成功"
  # kill-window が実際に呼ばれた
  assert [ -s "$TMUX_KILL_WINDOW_LOG" ]
}

# ===========================================================================
# AC-2: kill 失敗（Worker session に window 残存）→ exit 1（true positive 維持）
#
# RED/GREEN どちらも: exit 1 を返すことを確認（regression guard）
# ===========================================================================
@test "#1393 AC-2: Worker session に window が残存する場合は exit 1（true positive 維持）" {
  # Worker session のみに ap-#1393 が存在
  export TMUX_ALL_WINDOWS="worker-session:0 ap-#1393"

  # 旧 post-kill check 用: worker session の window が global list に現れる
  export TMUX_ALL_WINDOW_NAMES="ap-#1393"

  # 新 session-scoped check 用: kill 後も worker-session に残存
  export TMUX_SESSION_WINDOWS="ap-#1393"

  run bash "$SANDBOX/scripts/auto-merge.sh" --issue 1393 --pr 1394 --branch feat/1393-test

  assert_failure
  assert_output --partial "ERROR: Worker window kill 失敗"
  assert_output --partial "unsafe state"
  refute_output --partial "worktree 削除成功"
}
