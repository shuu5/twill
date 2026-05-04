#!/usr/bin/env bats
# issue-1352-autopilot-cleanup-dot-branch.bats
#
# Issue #1352: autopilot-cleanup.sh のブランチ名 regex にドット（.）を追加
#
# AC-1: plugins/twl/scripts/autopilot-cleanup.sh の regex を
#       ^[a-zA-Z0-9_/.-]+$ に変更（ハイフンを文字クラス末尾に移動してリテラル扱い、ドットを追加）
# AC-2: ドットを含むブランチ名（例: feat/auto.1234）に対して該当 if ブロックが評価され、
#       リモートブランチ削除パスが実行されること
#
# RED フォーマット: 実装前は FAIL → 実装後 PASS

load 'helpers/common'

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC-1: regex が ^[a-zA-Z0-9_/.-]+$ に変更されていること
#
# RED: 現 regex は ^[a-zA-Z0-9_/\-]+$ でドット不在
#      → grep -qF がマッチしない → assert_success FAIL
# GREEN: regex 修正後 ^[a-zA-Z0-9_/.-]+$ が含まれる → PASS
# ===========================================================================
@test "ac1: autopilot-cleanup.sh の branch regex がドット（.）を含む ^[a-zA-Z0-9_/.-]+\$ になっている" {
  # AC: plugins/twl/scripts/autopilot-cleanup.sh の regex を ^[a-zA-Z0-9_/.-]+$ に変更

  # RED: 現在は ^[a-zA-Z0-9_/\-]+$ (ドットなし) → grep FAIL
  # GREEN: 修正後 ^[a-zA-Z0-9_/.-]+$ が含まれる → grep PASS
  run grep -qF '^[a-zA-Z0-9_/.-]+$' "$SANDBOX/scripts/autopilot-cleanup.sh"
  assert_success
}

# ===========================================================================
# AC-2: ドット含みブランチ名が regex を通過し git push --delete に到達する
#
# RED: 現 regex がドットを許容しない → if が false → git push 呼ばれない
#      → git_calls_log に "push" なし → grep FAIL → assert_success FAIL
# GREEN: regex 修正後 → if が true → git push origin --delete feat/auto.1234 呼ばれる → PASS
# ===========================================================================
@test "ac2: ドット含みブランチ名（feat/auto.1234）が regex を通過してリモートブランチ削除に到達する" {
  # AC: ドットを含むブランチ名に対して if ブロックが評価され、リモートブランチ削除パスが実行される

  local branch="feat/auto.1234"
  local wt_path="$SANDBOX/worktrees/feat-auto-1234"
  mkdir -p "$wt_path"

  # session.json: active issues なし（SESSION_COMPLETED=false、Phase 2 の孤立検出のみ実行）
  printf '{"session_id":"sess-dot","plan_path":".autopilot/plan.yaml","current_phase":1,"phase_count":1,"started_at":"2026-01-01T00:00:00Z","cross_issue_warnings":[],"phase_insights":[],"patterns":{},"self_improve_issues":[]}\n' \
    > "$SANDBOX/.autopilot/session.json"

  local git_calls_log="$SANDBOX/git-calls.log"

  # git stub: feat/auto.1234 の worktree を返し、全呼び出しを記録
  cat > "$STUB_BIN/git" <<GITEOF
#!/usr/bin/env bash
echo "\$@" >> "$git_calls_log"
if [[ "\$*" == *"worktree list"* ]]; then
  printf 'worktree %s\nHEAD aaa1111\nbranch refs/heads/%s\n\nworktree %s\nHEAD bbb2222\nbranch refs/heads/main\n' "$wt_path" "$branch" "$SANDBOX"
  exit 0
fi
exit 0
GITEOF
  chmod +x "$STUB_BIN/git"

  # gh stub: OPEN PR なし（空を返す）
  stub_command "gh" 'exit 0'

  # worktree-delete.sh: 常に成功するスタブで上書き（実際の git 操作を回避）
  cat > "$SANDBOX/scripts/worktree-delete.sh" <<WTEOF
#!/usr/bin/env bash
exit 0
WTEOF
  chmod +x "$SANDBOX/scripts/worktree-delete.sh"

  run bash "$SANDBOX/scripts/autopilot-cleanup.sh" \
    --autopilot-dir "$SANDBOX/.autopilot"

  assert_success

  # RED: 現 regex はドット不可 → git push が呼ばれない → grep FAIL
  # GREEN: 修正後 → git push origin --delete feat/auto.1234 が呼ばれる → PASS
  run grep -qF "push" "$git_calls_log" 2>/dev/null
  assert_success
}
