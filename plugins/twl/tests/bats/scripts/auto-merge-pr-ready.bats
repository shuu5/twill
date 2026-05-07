#!/usr/bin/env bats
# auto-merge-pr-ready.bats - #1497 workflow-pr-merge step の gh pr ready 呼び出し
#
# Spec: Issue #1497 — draft PR が squash merge 前に ready 化されていないバグの修正
#
# Coverage:
#   AC1: 非 autopilot path で gh pr merge --squash 直前に gh pr ready が呼ばれる
#   AC2: gh pr ready 失敗時に "draft" / "ready" を含む明確なエラーメッセージが出力される
#   AC3a: draft PR を ready 化してから merge する動作を verify
#   AC3b: 既に ready の PR を idempotent に処理する（ready 化は no-op、merge は続行）
#   AC4: pitfalls-catalog.md に "merge_failed: draft" 解釈ガイドが存在する

load '../helpers/common'

# ---------------------------------------------------------------------------
# setup / teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  # 非 autopilot 経路に誘導するための python3 stub
  # --field status → "done" (IS_AUTOPILOT=false)
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

  # gh stub: 呼び出しをログに記録する（各テストで PR_READY_FAIL / PR_ALREADY_READY を override 可能）
  # PR_READY_FAIL=true  → gh pr ready が失敗する
  # PR_ALREADY_READY=true → gh pr ready が "already ready" 系の exit 0 を返す（idempotent 検証用）
  GH_CALL_LOG="$SANDBOX/gh-calls.log"
  : > "$GH_CALL_LOG"
  export GH_CALL_LOG

  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
echo "gh $*" >> "${GH_CALL_LOG}"
case "$*" in
  *"pr ready "*)
    if [[ "${PR_READY_FAIL:-false}" == "true" ]]; then
      echo "failed to mark PR as ready for review: PR is not a draft" >&2
      exit 1
    fi
    exit 0 ;;
  *"pr merge"*"--squash"*)
    exit 0 ;;
  *"pr view"*"mergeStateStatus"*)
    echo "CLEAN" ;;
  *)
    exit 0 ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  # git stub: worktree モードで動作させる
  cat > "$STUB_BIN/git" <<GITSTUB
#!/usr/bin/env bash
case "\$*" in
  "rev-parse --git-dir")
    echo "$SANDBOX/.bare/worktrees/feat1497" ;;
  "rev-parse --show-toplevel")
    echo "$SANDBOX" ;;
  "worktree list --porcelain")
    cat <<PORCELAIN
worktree $SANDBOX/main
branch refs/heads/main

worktree $SANDBOX/worktrees/feat1497
branch refs/heads/fix/1497-draft-ready

PORCELAIN
    ;;
  "worktree remove --force "*)
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
  cat > "$STUB_BIN/tmux" <<'TMUXSTUB'
#!/usr/bin/env bash
case "$1" in
  display-message) echo "main" ;;
  list-windows)    echo "" ;;
  *)               exit 0 ;;
esac
TMUXSTUB
  chmod +x "$STUB_BIN/tmux"

  # issue-N.json が存在しないことを保証 (Layer 4 フォールバックガード回避)
  rm -f "$SANDBOX/.autopilot/issues/issue-1497.json"

  # CWD を sandbox の main worktree に移動 (Layer 2 CWD ガード回避)
  mkdir -p "$SANDBOX/main"
  cd "$SANDBOX/main"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC1: 非 autopilot path で gh pr ready が squash merge 直前に呼ばれる
# ---------------------------------------------------------------------------

@test "ac1: 非 autopilot path で gh pr ready が gh pr merge --squash より前に呼ばれる" {
  # AC: workflow-pr-merge step が merge 前に gh pr ready を実行する
  # RED: 現在 auto-merge.sh に gh pr ready 呼び出しがないため fail する

  run bash "$SANDBOX/scripts/auto-merge.sh" --issue 1497 --pr 1498 --branch fix/1497-draft-ready

  assert_success

  # gh pr ready <PR> が呼ばれていること
  grep -qF "gh pr ready 1498" "$GH_CALL_LOG" || {
    echo "FAIL: gh pr ready 1498 が gh-calls.log に記録されていない"
    echo "--- gh-calls.log ---"
    cat "$GH_CALL_LOG"
    false
  }

  # gh pr ready が gh pr merge より先に呼ばれていること（行番号で順序確認）
  READY_LINE=$(grep -n "pr ready" "$GH_CALL_LOG" | head -1 | cut -d: -f1)
  MERGE_LINE=$(grep -n "pr merge" "$GH_CALL_LOG" | head -1 | cut -d: -f1)
  [[ -n "$READY_LINE" && -n "$MERGE_LINE" && "$READY_LINE" -lt "$MERGE_LINE" ]] || {
    echo "FAIL: gh pr ready (line ${READY_LINE:-N/A}) が gh pr merge (line ${MERGE_LINE:-N/A}) より前に呼ばれていない"
    false
  }
}

# ---------------------------------------------------------------------------
# AC2: gh pr ready 失敗時に明確なエラーメッセージが出力される
# ---------------------------------------------------------------------------

@test "ac2: gh pr ready 失敗時に draft/ready を含む明確なエラーメッセージが出力される" {
  # AC: gh pr ready 失敗時に Pilot へ明確なエラーを返す
  #     "draft のまま merge は不可、ready 切替を要" のメッセージを含む
  # RED: 現在 auto-merge.sh に gh pr ready 呼び出しがなく、エラーハンドリングも存在しないため fail する
  export PR_READY_FAIL=true

  run bash "$SANDBOX/scripts/auto-merge.sh" --issue 1497 --pr 1498 --branch fix/1497-draft-ready

  # gh pr ready 失敗時は abort（exit non-zero）
  assert_failure

  # "draft" と "ready" の両方を含むエラーメッセージが出力されていること
  echo "$output" | grep -qi "draft" || {
    echo "FAIL: 出力に 'draft' が含まれていない"
    echo "--- output ---"
    echo "$output"
    false
  }
  echo "$output" | grep -qi "ready" || {
    echo "FAIL: 出力に 'ready' が含まれていない"
    echo "--- output ---"
    echo "$output"
    false
  }
}

# ---------------------------------------------------------------------------
# AC3a: draft PR を ready 化してから merge する動作を verify
# ---------------------------------------------------------------------------

@test "ac3a: draft PR を ready 化してから squash merge する end-to-end 動作を verify" {
  # AC: draft PR を ready 化してから merge する動作を verify
  # RED: gh pr ready が呼ばれないため fail する

  run bash "$SANDBOX/scripts/auto-merge.sh" --issue 1497 --pr 1498 --branch fix/1497-draft-ready

  assert_success

  # 1) gh pr ready が呼ばれていること
  grep -qF "gh pr ready 1498" "$GH_CALL_LOG" || {
    echo "FAIL: gh pr ready 1498 が呼ばれていない"
    cat "$GH_CALL_LOG"
    false
  }

  # 2) gh pr merge --squash が呼ばれていること（ready 後に merge が続行される）
  grep -qF "gh pr merge 1498 --squash" "$GH_CALL_LOG" || {
    echo "FAIL: gh pr merge 1498 --squash が呼ばれていない"
    cat "$GH_CALL_LOG"
    false
  }

  # 3) merge 成功メッセージが出力されていること
  assert_output --partial "merge 成功"
}

# ---------------------------------------------------------------------------
# AC3b: 既に ready の PR を idempotent に処理する
# ---------------------------------------------------------------------------

@test "ac3b: 既に ready の PR に対して idempotent（no-op）に処理し merge を続行する" {
  # AC: 既に ready の場合は no-op（idempotent）
  # RED: gh pr ready 呼び出し自体が存在しないため、idempotent 確認以前に fail する
  # NOTE: PR_ALREADY_READY=true のとき gh pr ready は exit 0 を返す（already ready 模擬）
  export PR_ALREADY_READY=true

  run bash "$SANDBOX/scripts/auto-merge.sh" --issue 1497 --pr 1498 --branch fix/1497-draft-ready

  assert_success

  # gh pr ready が呼ばれていること（idempotent: 失敗しない）
  grep -qF "gh pr ready 1498" "$GH_CALL_LOG" || {
    echo "FAIL: gh pr ready 1498 が呼ばれていない（idempotent 呼び出しも未実装）"
    cat "$GH_CALL_LOG"
    false
  }

  # merge が続行されていること（idempotent ready 後も merge は中断されない）
  grep -qF "gh pr merge 1498 --squash" "$GH_CALL_LOG" || {
    echo "FAIL: gh pr merge 1498 --squash が呼ばれていない"
    cat "$GH_CALL_LOG"
    false
  }

  assert_output --partial "merge 成功"
}

# ---------------------------------------------------------------------------
# AC4: pitfalls-catalog.md に "merge_failed: draft" 解釈ガイドが存在する
# ---------------------------------------------------------------------------

@test "ac4: pitfalls-catalog.md に merge_failed_draft の解釈ガイドが存在する" {
  # AC: co-autopilot SKILL.md または pitfalls-catalog.md に
  #     "merge_failed: PR is still a draft" = chain workflow の bug という注記を追加する
  # RED: 現在 pitfalls-catalog.md に該当記述がないため fail する

  PITFALLS_CATALOG="$REPO_ROOT/skills/su-observer/refs/pitfalls-catalog.md"

  # ファイルが存在すること
  [ -f "$PITFALLS_CATALOG" ] || {
    echo "FAIL: pitfalls-catalog.md が存在しない: $PITFALLS_CATALOG"
    false
  }

  # "draft" に関する記述が存在すること
  grep -qi "draft" "$PITFALLS_CATALOG" || {
    echo "FAIL: pitfalls-catalog.md に 'draft' の記述がない"
    false
  }

  # "merge_failed" に関する記述が存在すること
  grep -qi "merge_failed\|merge.*draft\|draft.*merge" "$PITFALLS_CATALOG" || {
    echo "FAIL: pitfalls-catalog.md に 'merge_failed' / draft merge 関連の記述がない"
    false
  }
}
