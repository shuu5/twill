#!/usr/bin/env bats
# auto-merge-worker-kill.bats - #898 Worker window kill safety net
#
# Spec: Issue #898 — auto-merge.sh に Worker window kill safety net (cwd 消失事故防止)
#
# Coverage (3 scenario per AC, 1 edge case):
#   (a) Worker window 生存 + kill 成功 → worktree 削除続行
#   (b) Worker window 不在 (tmux list に無い) → safety net skip、通常動作
#   (c) Worker window kill 失敗 → exit 1 で abort (worktree 削除せず)
#   (d) state.window 空 (Pilot 既に cleanup 済) → safety net skip、通常動作
#
# 不変条件 B の defensive 実装を検証する。呼び手 (_cleanup_worker 等) が
# Worker window kill を skip していた場合でも auto-merge.sh 自身が安全側に倒す。

load '../helpers/common'

setup() {
  common_setup

  # 非 autopilot 経路に誘導するための python3 stub
  # --field status → "done" (IS_AUTOPILOT=false)
  # --field is_quick → "false"
  # --field current_step → ""
  # --field window → デフォルトは "ap-#898" (テストで override 可能)
  WINDOW_FIELD_OUT="${WINDOW_FIELD_OUT:-ap-#898}"
  export WINDOW_FIELD_OUT

  cat > "$STUB_BIN/python3" <<'PYSTUB'
#!/usr/bin/env bash
# auto-merge.sh から呼ばれる `python3 -m twl.autopilot.state` の mock
case "$*" in
  *"state read"*"--field status"*)       echo "done" ;;
  *"state read"*"--field is_quick"*)     echo "false" ;;
  *"state read"*"--field current_step"*) echo "" ;;
  *"state read"*"--field window"*)       echo "${WINDOW_FIELD_OUT}" ;;
  *"state write"*)                       exit 0 ;;
  *)                                     exit 0 ;;
esac
PYSTUB
  chmod +x "$STUB_BIN/python3"

  # gh stub: pr merge --squash を成功させる
  stub_command "gh" '
    case "$*" in
      *"pr merge"*"--squash"*) exit 0 ;;
      *"pr view"*"mergeStateStatus"*) echo "CLEAN" ;;
      *) exit 0 ;;
    esac
  '

  # git stub: worktree 判定に必要な最小限を提供
  # - rev-parse --git-dir → worktree モード (".git" 以外を返す)
  # - worktree list --porcelain → resolve_autopilot_dir 用 (main branch) +
  #   WORKTREE_PATH 計算用 (feature branch)
  # - worktree remove --force → 成功
  # - checkout main / pull origin main / push origin --delete → 成功
  cat > "$STUB_BIN/git" <<GITSTUB
#!/usr/bin/env bash
case "\$*" in
  "rev-parse --git-dir")
    # worktree モードにするため絶対パスを返す (".git" 以外)
    echo "$SANDBOX/.bare/worktrees/feat898" ;;
  "rev-parse --show-toplevel")
    echo "$SANDBOX" ;;
  "worktree list --porcelain")
    cat <<PORCELAIN
worktree $SANDBOX/main
branch refs/heads/main

worktree $SANDBOX/worktrees/feat898
branch refs/heads/feat/898-test

PORCELAIN
    ;;
  "worktree remove --force "*)
    # WORKTREE_REMOVE_FAIL=true のときは失敗
    if [[ "\${WORKTREE_REMOVE_FAIL:-false}" == "true" ]]; then exit 1; fi
    exit 0 ;;
  "checkout main"|"pull origin main")
    exit 0 ;;
  "push origin --delete "*|"branch -D "*)
    exit 0 ;;
  *)
    exit 0 ;;
esac
GITSTUB
  chmod +x "$STUB_BIN/git"

  # tmux stub: display-message / list-windows / kill-window を mock
  # TMUX_KILL_WINDOW_LOG に kill-window 呼出履歴を記録
  # TMUX_ALL_WINDOWS     : "session:index window_name" 形式（safe_kill_window + 事前セッション解決用）
  # TMUX_SESSION_WINDOWS : window 名のみ（post-kill session-scoped check 用、#1393 修正後）
  # TMUX_KILL_FAIL=true のときは kill-window を失敗させる
  TMUX_KILL_WINDOW_LOG="$SANDBOX/tmux-kill-window.log"
  export TMUX_KILL_WINDOW_LOG
  : > "$TMUX_KILL_WINDOW_LOG"

  TMUX_ALL_WINDOWS="${TMUX_ALL_WINDOWS:-sess1:0 ap-#898}"
  TMUX_SESSION_WINDOWS="${TMUX_SESSION_WINDOWS:-}"
  export TMUX_ALL_WINDOWS TMUX_SESSION_WINDOWS

  cat > "$STUB_BIN/tmux" <<'TMUXSTUB'
#!/usr/bin/env bash
case "$1" in
  display-message)
    echo "main" ;;
  list-windows)
    # -t が引数に含まれる → session-scoped（post-kill check 用）
    HAS_T=false
    for arg in "$@"; do [[ "$arg" == "-t" ]] && HAS_T=true; done
    if $HAS_T; then
      printf '%s\n' "${TMUX_SESSION_WINDOWS:-}"
    else
      # global (-a): session:index 形式（safe_kill_window + 事前セッション解決用）
      printf '%s\n' "${TMUX_ALL_WINDOWS:-}"
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

  # twl stub (DeltaSpec archive をスキップさせる)
  stub_command "twl" 'exit 0'

  # auto-merge.sh を sandbox に配置 (common_setup でコピー済みのはずだが念のため確認)
  if [[ ! -f "$SANDBOX/scripts/auto-merge.sh" ]]; then
    mkdir -p "$SANDBOX/scripts/lib"
    cp "$REPO_ROOT/scripts/auto-merge.sh" "$SANDBOX/scripts/auto-merge.sh"
    cp "$REPO_ROOT/scripts/lib/python-env.sh" "$SANDBOX/scripts/lib/python-env.sh" 2>/dev/null || true
  fi

  # issue-N.json が存在しないことを保証 (フォールバックガード回避)
  rm -f "$SANDBOX/.autopilot/issues/issue-898.json"

  # CWD を sandbox の main worktree に移動 (Layer 2 CWD ガード回避)
  # bats 自体が worktrees/ 配下で実行される場合があるため必須
  mkdir -p "$SANDBOX/main"
  cd "$SANDBOX/main"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Scenario (a): Worker window 生存 + kill 成功 → worktree 削除続行
# ---------------------------------------------------------------------------

@test "#898 (a): Worker window 生存 + kill 成功で worktree 削除続行" {
  export WINDOW_FIELD_OUT="ap-#898"
  # TMUX_ALL_WINDOWS: session:index 形式（safe_kill_window + 事前セッション解決用）
  export TMUX_ALL_WINDOWS="sess1:0 ap-#898
sess1:1 main
sess1:2 other-window"
  # TMUX_SESSION_WINDOWS: kill 後 worker session は空（kill 成功）
  export TMUX_SESSION_WINDOWS=""

  run bash "$SANDBOX/scripts/auto-merge.sh" --issue 898 --pr 899 --branch feat/898-test

  assert_success
  # safety net 発火確認
  assert_output --partial "Worker window (ap-#898) kill"
  # kill-window が session-scoped target（sess1:0）で呼ばれている
  [ -f "$TMUX_KILL_WINDOW_LOG" ]
  grep -qF "kill-window -t sess1:0" "$TMUX_KILL_WINDOW_LOG"
  # worktree 削除成功メッセージ
  assert_output --partial "worktree 削除成功"
}

# ---------------------------------------------------------------------------
# Scenario (b): Worker window 不在 (tmux list に無い) → safety net skip
# ---------------------------------------------------------------------------

@test "#898 (b): Worker window 不在 (既 cleanup 済) でも通常動作継続" {
  export WINDOW_FIELD_OUT="ap-#898"
  # ap-#898 を含まない（worker window は既に cleanup 済み）
  export TMUX_ALL_WINDOWS="sess1:0 main
sess1:1 other-window"
  export TMUX_SESSION_WINDOWS=""

  run bash "$SANDBOX/scripts/auto-merge.sh" --issue 898 --pr 899 --branch feat/898-test

  assert_success
  # kill-window は呼ばれていない（window が存在しないため）
  if [[ -s "$TMUX_KILL_WINDOW_LOG" ]]; then
    ! grep -qF "kill-window" "$TMUX_KILL_WINDOW_LOG"
  fi
  # worktree 削除は成功
  assert_output --partial "worktree 削除成功"
}

# ---------------------------------------------------------------------------
# Scenario (c): Worker window kill 失敗 → exit 1 で abort
# ---------------------------------------------------------------------------

@test "#898 (c): Worker window kill 失敗で exit 1、worktree 削除せず abort" {
  export WINDOW_FIELD_OUT="ap-#898"
  # Worker session に ap-#898 が存在（WORKER_SESSION="sess1" として解決される）
  export TMUX_ALL_WINDOWS="sess1:0 ap-#898
sess1:1 main"
  # post-kill session-scoped check: window が残存（kill 失敗を模擬）
  export TMUX_SESSION_WINDOWS="ap-#898"

  run bash "$SANDBOX/scripts/auto-merge.sh" --issue 898 --pr 899 --branch feat/898-test

  assert_failure
  assert_output --partial "ERROR: Worker window kill 失敗"
  assert_output --partial "unsafe state"
  refute_output --partial "worktree 削除成功"
}

# ---------------------------------------------------------------------------
# Scenario (d): state.window 空 (Pilot 既に cleanup 済) → safety net skip
# ---------------------------------------------------------------------------

@test "#898 (d): state.window 空のときは safety net skip (Pilot 通常経路)" {
  # WINDOW_FIELD_OUT を明示的に空文字に（python3 stub は ${WINDOW_FIELD_OUT} を直接出力）
  export WINDOW_FIELD_OUT=""
  export TMUX_ALL_WINDOWS="sess1:0 main
sess1:1 other-window"
  export TMUX_SESSION_WINDOWS=""

  run bash "$SANDBOX/scripts/auto-merge.sh" --issue 898 --pr 899 --branch feat/898-test

  assert_success
  # WORKER_WINDOW が空のため safety net は発火しない
  refute_output --partial "Worker window"
  # kill-window は呼ばれていない
  if [[ -s "$TMUX_KILL_WINDOW_LOG" ]]; then
    ! grep -qF "kill-window" "$TMUX_KILL_WINDOW_LOG"
  fi
  assert_output --partial "worktree 削除成功"
}
