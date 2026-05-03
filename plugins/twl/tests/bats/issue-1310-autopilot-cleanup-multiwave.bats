#!/usr/bin/env bats
# issue-1310-autopilot-cleanup-multiwave.bats
#
# Issue #1310 P0 incident: autopilot-cleanup.sh が並列 Wave の worktree/branch を誤削除
#
# AC-1: autopilot-cleanup.sh が ${PROJECT_DIR}/.autopilot*/issues/ を再帰的スキャンし、
#       全 active branches を尊重する
# AC-2: git push origin --delete 直前に gh pr list --head <branch> で active PR がないことを確認、
#       ある場合は skip + WARN
# AC-3: regression test: parallel Wave fixture (.autopilot/issues/issue-A.json +
#       .autopilot-w2/issues/issue-B.json) で --autopilot-dir .autopilot-w2 実行時
#       issue-A の worktree が削除されないこと
# AC-4: 既存単一 Wave 動作（孤立 worktree 削除）には影響なし
#
# RED 形式: 現状 FAIL → 実装後 PASS

load 'helpers/common'

SCRIPT=""

# ---------------------------------------------------------------------------
# Shared fixture helpers
# ---------------------------------------------------------------------------

# _make_issue_json <dir> <issue_label> <branch> <status>
_make_issue_json() {
  local dir="$1"
  local label="$2"
  local branch="$3"
  local status="$4"
  mkdir -p "$dir"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq -n \
    --arg status "$status" \
    --arg branch "$branch" \
    --arg started_at "$now" \
    '{issue: 0, status: $status, branch: $branch, pr: null, window: "",
      started_at: $started_at, current_step: "", retry_count: 0,
      fix_instructions: null, merged_at: null, files_changed: [], failure: null}' \
    > "$dir/issue-${label}.json"
}

setup() {
  common_setup
  SCRIPT="${REPO_ROOT}/scripts/autopilot-cleanup.sh"

  # session.json（SESSION_ID に合法な値）
  printf '{"session_id":"test1234","plan_path":".autopilot/plan.yaml","current_phase":1,"phase_count":2,"started_at":"2026-01-01T00:00:00Z","cross_issue_warnings":[],"phase_insights":[],"patterns":{},"self_improve_issues":[]}' \
    > "$SANDBOX/.autopilot/session.json"

  # worktree-delete.sh スタブ（sandbox/scripts/ 配下に配置）
  local wt_delete_log="$SANDBOX/wt-delete-calls.log"
  cat > "$SANDBOX/scripts/worktree-delete.sh" <<WTEOF
#!/usr/bin/env bash
echo "CALLED: \$*" >> "$wt_delete_log"
exit 0
WTEOF
  chmod +x "$SANDBOX/scripts/worktree-delete.sh"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC-1: ${PROJECT_DIR}/.autopilot*/issues/ の再帰スキャンで active branches 尊重
#
# RED: 現実装は --project-dir オプションを持たない。
#      --project-dir を渡すと "不明なオプション" エラーで exit 1。
#      assert_success → 現状 FAIL（exit 1）、実装後 PASS（exit 0）。
# ===========================================================================
@test "ac1: --project-dir を受け取り別 Wave の active branch を保護する" {
  # AC: autopilot-cleanup.sh が ${PROJECT_DIR}/.autopilot*/issues/ を再帰的スキャンし、
  #     全 active branches を尊重する

  # Fixture: Wave 1 (.autopilot) に issue-1266 が in_progress（branch=feat/1266-wave1）
  _make_issue_json "$SANDBOX/.autopilot/issues" "1266" "feat/1266-wave1" "in_progress"

  # Fixture: Wave 2 (.autopilot-w2) に issue-1275 が done（cleanup 対象 wave）
  mkdir -p "$SANDBOX/.autopilot-w2/issues"
  printf '{"session_id":"test-w2"}' > "$SANDBOX/.autopilot-w2/session.json"
  _make_issue_json "$SANDBOX/.autopilot-w2/issues" "1275" "feat/1275-wave2" "done"

  # git stub: feat/1266-wave1 の worktree が存在する
  local wt_path="$SANDBOX/worktrees/feat-1266"
  mkdir -p "$wt_path"
  stub_command "git" "
if [[ \"\$*\" == *'worktree list'* ]]; then
  printf 'worktree %s\nHEAD abc1234\nbranch refs/heads/feat/1266-wave1\n\nworktree %s\nHEAD def5678\nbranch refs/heads/main\n' '$wt_path' '$SANDBOX'
  exit 0
fi
exit 0
"
  stub_command "gh" "exit 0"

  # RED: --project-dir は未実装 → exit 1 → assert_success が失敗する
  # GREEN（実装後）: exit 0 で成功し、feat/1266-wave1 が削除対象にならない
  run bash "$SANDBOX/scripts/autopilot-cleanup.sh" \
    --autopilot-dir "$SANDBOX/.autopilot-w2" \
    --project-dir "$SANDBOX" \
    --dry-run

  assert_success
}

# ===========================================================================
# AC-2: git push origin --delete 直前の gh pr list --head <branch> チェック
#
# RED: 現実装は gh pr list チェックを行わない。
#      gh pr list が呼ばれないため gh-calls.log に "pr list" が記録されない。
#      assert_success for grep → 現状 FAIL、実装後 PASS。
# ===========================================================================
@test "ac2: active PR がある branch への remote 削除を skip し WARN を出す" {
  # AC: git push origin --delete 直前に gh pr list --head <branch> で
  #     active PR がないことを確認、ある場合は skip + WARN

  # Fixture: .autopilot に worktree 付きの孤立 branch（issues にも archive にも state なし）
  # → active_branches に入らず「孤立」と判定される（session.json も最小限）
  local branch="feat/1292-has-open-pr"
  # session.json を上書き: issues が全 done のため SESSION_COMPLETED=true のシナリオを回避
  printf '{"session_id":"sess2","plan_path":".autopilot/plan.yaml","current_phase":1,"phase_count":1,"started_at":"2026-01-01T00:00:00Z","cross_issue_warnings":[],"phase_insights":[],"patterns":{},"self_improve_issues":[]}' \
    > "$SANDBOX/.autopilot/session.json"
  mkdir -p "$SANDBOX/.autopilot/archive/sess1"

  local wt_path="$SANDBOX/worktrees/feat-1292"
  mkdir -p "$wt_path"

  local gh_calls_log="$SANDBOX/gh-calls.log"

  # git stub: feat/1292-has-open-pr の worktree が存在する
  stub_command "git" "
if [[ \"\$*\" == *'worktree list'* ]]; then
  printf 'worktree %s\nHEAD aaa1111\nbranch refs/heads/feat/1292-has-open-pr\n\nworktree %s\nHEAD bbb2222\nbranch refs/heads/main\n' '$wt_path' '$SANDBOX'
  exit 0
fi
exit 0
"

  # gh stub: pr list --head feat/1292-has-open-pr → OPEN PR 1 件
  cat > "$STUB_BIN/gh" <<GHEOF
#!/usr/bin/env bash
echo "\$@" >> "$gh_calls_log"
if [[ "\$*" == *"pr list"* && "\$*" == *"$branch"* ]]; then
  printf '%s\tOPEN\t%s\n' "1292" "$branch"
  exit 0
fi
exit 0
GHEOF
  chmod +x "$STUB_BIN/gh"

  # RED: 現実装は gh pr list を呼ばない → gh_calls_log に "pr list" が記録されない
  # GREEN（実装後）: gh pr list --head branch が呼ばれ、OPEN PR があれば WARN を出して push をスキップ
  run bash "$SANDBOX/scripts/autopilot-cleanup.sh" \
    --autopilot-dir "$SANDBOX/.autopilot"

  assert_success

  # RED: 現状 gh pr list が呼ばれない → grep が失敗 → assert_success が FAIL
  # GREEN: gh pr list が呼ばれ → log に "pr list" が含まれる → assert_success が PASS
  run grep "pr list" "$gh_calls_log" 2>/dev/null
  assert_success
}

# ===========================================================================
# AC-3: regression test — parallel Wave fixture での動作検証
#
# RED: 現実装は --project-dir を受け付けないため exit 1。
#      assert_success → 現状 FAIL、実装後 PASS。
#      実装後は feat/1266-wa1-active が削除対象にならない。
# ===========================================================================
@test "ac3: --autopilot-dir .autopilot-w2 実行時 .autopilot/ 側 issue-A の worktree が削除されない" {
  # AC: parallel Wave fixture で --autopilot-dir .autopilot-w2 実行時
  #     issue-A (.autopilot/ 側) の worktree が削除されないこと

  # Fixture: Wave 1 (.autopilot) の issue-A が in_progress（branch=feat/1266-wa1-active）
  _make_issue_json "$SANDBOX/.autopilot/issues" "A" "feat/1266-wa1-active" "in_progress"
  printf '{"session_id":"session-wa1"}' > "$SANDBOX/.autopilot/session.json"

  # Fixture: Wave 2 (.autopilot-w2) の issues は空（cleanup 対象、active issues なし）
  mkdir -p "$SANDBOX/.autopilot-w2/issues"
  mkdir -p "$SANDBOX/.autopilot-w2/archive/session-w2"
  printf '{"session_id":"session-w2"}' > "$SANDBOX/.autopilot-w2/session.json"

  # git stub: feat/1266-wa1-active の worktree が存在する
  local wt_path="$SANDBOX/worktrees/feat-1266-wa1"
  mkdir -p "$wt_path"
  stub_command "git" "
if [[ \"\$*\" == *'worktree list'* ]]; then
  printf 'worktree %s\nHEAD ccc3333\nbranch refs/heads/feat/1266-wa1-active\n\nworktree %s\nHEAD ddd4444\nbranch refs/heads/main\n' '$wt_path' '$SANDBOX'
  exit 0
fi
exit 0
"
  stub_command "gh" "exit 0"

  # RED: --project-dir 未実装 → exit 1 → assert_success が失敗する
  # GREEN（実装後）: exit 0 で成功し、feat/1266-wa1-active が [dry-run] ログに出ない
  run bash "$SANDBOX/scripts/autopilot-cleanup.sh" \
    --autopilot-dir "$SANDBOX/.autopilot-w2" \
    --project-dir "$SANDBOX" \
    --dry-run

  assert_success
  # feat/1266-wa1-active が削除対象として出力されないこと
  refute_output --partial "feat/1266-wa1-active"
}

# ===========================================================================
# AC-4: 既存単一 Wave 動作（孤立 worktree 削除）には影響なし
#
# このテストは GREEN（実装前後ともに PASS）であること。
# 修正後に regression が入った場合 FAIL する。
# ===========================================================================
@test "ac4: 単一 Wave 動作 - 真の孤立 worktree（state file なし）は削除される" {
  # AC: 既存単一 Wave 動作（孤立 worktree 削除）には影響なし

  # Fixture: .autopilot に done issue 1 件（feat/999-single-wave は active_branches に入る）
  _make_issue_json "$SANDBOX/.autopilot/issues" "999" "feat/999-single-wave" "done"

  # 孤立 worktree: どの Wave の issues にも記録されていないブランチ
  local orphan_branch="feat/888-orphan-no-state"
  local wt_path="$SANDBOX/worktrees/feat-888-orphan"
  mkdir -p "$wt_path"

  local wt_delete_log="$SANDBOX/wt-delete-calls.log"

  stub_command "git" "
if [[ \"\$*\" == *'worktree list'* ]]; then
  printf 'worktree %s\nHEAD eee5555\nbranch refs/heads/feat/888-orphan-no-state\n\nworktree %s\nHEAD fff6666\nbranch refs/heads/main\n' '$wt_path' '$SANDBOX'
  exit 0
fi
exit 0
"
  stub_command "gh" "exit 0"

  # 単一 Wave で実行（--project-dir なし）
  run bash "$SANDBOX/scripts/autopilot-cleanup.sh" \
    --autopilot-dir "$SANDBOX/.autopilot"

  # 既存動作: exit 0 で完了すること
  assert_success
  # worktree-delete.sh が orphan_branch で呼ばれること
  run grep -q "feat/888-orphan-no-state" "$wt_delete_log"
  assert_success
}
