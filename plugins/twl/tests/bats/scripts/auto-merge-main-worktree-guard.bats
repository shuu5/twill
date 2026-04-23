#!/usr/bin/env bats
# auto-merge-main-worktree-guard.bats - #924 main worktree 保護 guard
#
# Spec: Issue #924 — auto-merge.sh が main worktree を誤削除する事故の再発防止
#
# Coverage (3 scenarios per AC):
#   (a) branch=main → guard 発火、worktree 削除スキップ（sanity check 1）
#   (b) feat branch だが target path == main worktree path → guard 発火（sanity check 2）
#   (c) 通常 feat branch（別 worktree パス）→ guard 非発火、正常削除（regression）

load '../helpers/common'

setup() {
  common_setup

  # 非 autopilot 経路に誘導するための python3 stub
  # --field status → "done" (IS_AUTOPILOT=false)
  # --field is_quick → "false"
  # --field current_step → ""
  # --field window → "" (Worker window なし)
  cat > "$STUB_BIN/python3" <<'PYSTUB'
#!/usr/bin/env bash
case "$*" in
  *"state read"*"--field status"*)       echo "done" ;;
  *"state read"*"--field is_quick"*)     echo "false" ;;
  *"state read"*"--field current_step"*) echo "" ;;
  *"state read"*"--field window"*)       echo "" ;;
  *"state write"*)                        exit 0 ;;
  *)                                      exit 0 ;;
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

  # git stub: 基本構造（各テストで GITSTUB_PORCELAIN_EXTRA を上書き可能）
  # worktree list --porcelain の出力は GITSTUB_PORCELAIN_OUT で制御
  GITSTUB_PORCELAIN_OUT="${GITSTUB_PORCELAIN_OUT:-}"
  export GITSTUB_PORCELAIN_OUT

  WORKTREE_REMOVE_LOG="$SANDBOX/worktree-remove.log"
  : > "$WORKTREE_REMOVE_LOG"
  export WORKTREE_REMOVE_LOG

  cat > "$STUB_BIN/git" <<GITSTUB
#!/usr/bin/env bash
case "\$*" in
  "rev-parse --git-dir")
    echo "$SANDBOX/.bare/worktrees/feat924" ;;
  "rev-parse --show-toplevel")
    echo "$SANDBOX" ;;
  "worktree list --porcelain")
    printf '%s' "\${GITSTUB_PORCELAIN_OUT:-}" ;;
  "worktree remove --force "*)
    printf '%s\n' "\$*" >> "\${WORKTREE_REMOVE_LOG}"
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

  # tmux stub: Layer 3 guard 回避 (非 ap-# window を返す)
  stub_command "tmux" '
    case "$1" in
      display-message) echo "main" ;;
      list-windows)    echo "" ;;
      *) exit 0 ;;
    esac
  '

  # issue-N.json が存在しないことを保証 (Layer 4 フォールバックガード回避)
  rm -f "$SANDBOX/.autopilot/issues/issue-924.json"

  # CWD を sandbox の main worktree に移動 (Layer 2 CWD ガード回避)
  mkdir -p "$SANDBOX/main"
  cd "$SANDBOX/main"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Scenario (a): branch=main → guard 発火、worktree 削除スキップ
# ---------------------------------------------------------------------------

@test "#924 (a): branch=main のとき worktree 削除をスキップする" {
  export GITSTUB_PORCELAIN_OUT="worktree $SANDBOX/main
branch refs/heads/main

worktree $SANDBOX/worktrees/feat924
branch refs/heads/feat/924-fix

"

  run bash "$SANDBOX/scripts/auto-merge.sh" --issue 924 --pr 925 --branch main

  assert_success
  # guard メッセージが出力されていること
  echo "$output" | grep -qF "GUARD: branch=main の worktree 削除をスキップ"
  # worktree remove が呼ばれていないこと
  [ ! -s "$WORKTREE_REMOVE_LOG" ]
}

# ---------------------------------------------------------------------------
# Scenario (b): feat branch だが target path == main worktree path → guard 発火
# ---------------------------------------------------------------------------

@test "#924 (b): 削除対象パスが main worktree と一致するとき削除をスキップする" {
  # feat/phase-z-core-removal が main worktree でチェックアウトされていた事故を再現
  export GITSTUB_PORCELAIN_OUT="worktree $SANDBOX/main
branch refs/heads/feat/phase-z-core-removal

"

  run bash "$SANDBOX/scripts/auto-merge.sh" --issue 924 --pr 925 --branch feat/phase-z-core-removal

  assert_success
  # guard メッセージが出力されていること（path 一致 guard）
  echo "$output" | grep -qF "GUARD: 削除対象が main worktree"
  # worktree remove が呼ばれていないこと
  [ ! -s "$WORKTREE_REMOVE_LOG" ]
}

# ---------------------------------------------------------------------------
# Scenario (c): 通常 feat branch（別 worktree パス）→ guard 非発火、正常削除
# ---------------------------------------------------------------------------

@test "#924 (c): 通常の feat worktree は guard なしで正常削除される (regression)" {
  export GITSTUB_PORCELAIN_OUT="worktree $SANDBOX/main
branch refs/heads/main

worktree $SANDBOX/worktrees/feat924
branch refs/heads/fix/924-auto-merge-main-worktree-guard

"

  run bash "$SANDBOX/scripts/auto-merge.sh" --issue 924 --pr 925 --branch fix/924-auto-merge-main-worktree-guard

  assert_success
  # guard メッセージが出力されていないこと
  run echo "$output"
  refute_output --partial "GUARD:"
  # worktree remove が呼ばれていること
  grep -qF "worktree remove --force $SANDBOX/worktrees/feat924" "$WORKTREE_REMOVE_LOG"
}
