#!/usr/bin/env bats
# autopilot-cleanup-1673-cross-wave.bats
#
# Issue #1673: autopilot-cleanup.sh の並列 Wave cross-wave 破壊バグ修正
#
# AC1: cleanup の対象範囲を自 Wave 内に限定 (option C: degrade mode)
# AC2: 並列 Wave 検出 — AUTOPILOT_DIR 親ディレクトリから .autopilot*/ を自動検出
# AC3: bats test — 並列 Wave 存在時は他 Wave worktree 保護、単一 Wave では既存挙動維持
# AC4: incident log — degrade mode 遷移時 stderr + audit JSON

load '../helpers/common'

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
  printf '{"session_id":"sess1673","plan_path":".autopilot-wave1/plan.yaml","current_phase":1,"phase_count":1,"started_at":"2026-01-01T00:00:00Z","cross_issue_warnings":[],"phase_insights":[],"patterns":{},"self_improve_issues":[]}' \
    > "$SANDBOX/.autopilot/session.json"

  # worktree-delete.sh スタブ（sandbox/scripts/ 配下に上書き配置）
  _WT_DELETE_LOG="$SANDBOX/wt-delete-calls.log"
  cat > "$SANDBOX/scripts/worktree-delete.sh" <<WTEOF
#!/usr/bin/env bash
echo "CALLED: \$*" >> "${_WT_DELETE_LOG}"
exit 0
WTEOF
  chmod +x "$SANDBOX/scripts/worktree-delete.sh"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1 + AC2: 並列 Wave 検出時に degrade mode が発動し orphan cleanup がスキップされる
#
# RED: 現実装は並列 Wave 自動検出・degrade mode を持たない。
#      他 Wave worktree が [dry-run] 孤立 worktree 削除: ... に含まれる。
# GREEN: degrade mode が発動し、他 Wave worktree が削除対象に出力されない。
# ===========================================================================
@test "ac1_ac2: 並列 Wave 検出時に degrade mode が発動し orphan cleanup がスキップされる" {
  # AC: AUTOPILOT_DIR の親ディレクトリで .autopilot*/ を自動検出し、
  #     複数存在する場合は degrade mode に切り替えて orphan 削除をスキップする

  # Fixture: SANDBOX 直下に2つの Wave ディレクトリを配置
  # Wave 1 (.autopilot) — 現在クリーンアップ対象（自 Wave）
  mkdir -p "$SANDBOX/.autopilot/issues"
  printf '{"session_id":"sess1673"}' > "$SANDBOX/.autopilot/session.json"

  # Wave 2 (.autopilot-wave2) — 並列実行中の別 Wave（保護対象）
  _make_issue_json "$SANDBOX/.autopilot-wave2/issues" "2000" "feat/2000-wave2-active" "in_progress"
  printf '{"session_id":"sess-wave2"}' > "$SANDBOX/.autopilot-wave2/session.json"

  # Wave 2 の active branch の worktree が存在する（これを保護すべき）
  local wt_path="$SANDBOX/worktrees/feat-2000-wave2"
  mkdir -p "$wt_path"

  # git stub: Wave 2 の feat/2000-wave2-active worktree を返す
  stub_command "git" "
if [[ \"\$*\" == *'worktree list'* ]]; then
  printf 'worktree %s\nHEAD aaa1111\nbranch refs/heads/feat/2000-wave2-active\n\nworktree %s\nHEAD bbb2222\nbranch refs/heads/main\n' '${wt_path}' '${SANDBOX}'
  exit 0
fi
exit 0
"
  stub_command "gh" "exit 0"

  # --project-dir 未指定で Wave 1 を cleanup 対象として実行
  # RED: 現実装では feat/2000-wave2-active が削除対象に表示される
  # GREEN: degrade mode が発動し、feat/2000-wave2-active が削除対象に出ない
  run bash "$SANDBOX/scripts/autopilot-cleanup.sh" \
    --autopilot-dir "$SANDBOX/.autopilot" \
    --dry-run

  assert_success
  refute_output --partial "孤立 worktree 削除: ${wt_path}"
}

# ===========================================================================
# AC3: 単一 Wave では既存の orphan 削除挙動が維持される
#
# このテストは GREEN（実装前後ともに PASS）であること。
# ===========================================================================
@test "ac3_single_wave: 単一 Wave では既存の orphan 削除挙動が維持される" {
  # AC: 並列 Wave が存在しない場合、degrade mode にならず既存 orphan 削除が動作する

  # Fixture: .autopilot のみ（並列 Wave なし）
  mkdir -p "$SANDBOX/.autopilot/issues"
  printf '{"session_id":"sess1673"}' > "$SANDBOX/.autopilot/session.json"

  # 孤立 worktree: issues にも archive にも state file がない branch
  local orphan_branch="feat/9900-orphan-single-wave"
  local wt_path="$SANDBOX/worktrees/feat-9900-orphan"
  mkdir -p "$wt_path"

  # git stub: orphan_branch の worktree を返す
  stub_command "git" "
if [[ \"\$*\" == *'worktree list'* ]]; then
  printf 'worktree %s\nHEAD ccc3333\nbranch refs/heads/feat/9900-orphan-single-wave\n\nworktree %s\nHEAD ddd4444\nbranch refs/heads/main\n' '${wt_path}' '${SANDBOX}'
  exit 0
fi
exit 0
"
  stub_command "gh" "exit 0"

  # 単一 Wave で cleanup 実行
  run bash "$SANDBOX/scripts/autopilot-cleanup.sh" \
    --autopilot-dir "$SANDBOX/.autopilot"

  # 既存挙動: exit 0 で完了
  assert_success
  # worktree-delete.sh が orphan_branch で呼ばれること
  run grep -q "feat/9900-orphan-single-wave" "$_WT_DELETE_LOG"
  assert_success
}

# ===========================================================================
# AC4: degrade mode 遷移が stderr に記録される
#
# RED: 現実装は degrade mode メッセージを出力しない。
# GREEN: "並列 Wave 検出" メッセージが stderr に出力される。
# ===========================================================================
@test "ac4_degrade_mode_log: degrade mode 遷移が stderr に記録される" {
  # AC: degrade mode 移行時に警告メッセージを stderr に出力する

  # Fixture: 2つの Wave ディレクトリ
  mkdir -p "$SANDBOX/.autopilot/issues"
  printf '{"session_id":"sess1673"}' > "$SANDBOX/.autopilot/session.json"

  _make_issue_json "$SANDBOX/.autopilot-wave3/issues" "3000" "feat/3000-wave3-active" "in_progress"
  printf '{"session_id":"sess-wave3"}' > "$SANDBOX/.autopilot-wave3/session.json"

  local wt_path="$SANDBOX/worktrees/feat-3000-wave3"
  mkdir -p "$wt_path"

  stub_command "git" "
if [[ \"\$*\" == *'worktree list'* ]]; then
  printf 'worktree %s\nHEAD eee5555\nbranch refs/heads/feat/3000-wave3-active\n\nworktree %s\nHEAD fff6666\nbranch refs/heads/main\n' '${wt_path}' '${SANDBOX}'
  exit 0
fi
exit 0
"
  stub_command "gh" "exit 0"

  # RED: 現実装では "並列 Wave 検出" メッセージが出力されない
  # GREEN: degrade mode 移行時に "並列 Wave 検出" が stderr に出力される
  run bash "$SANDBOX/scripts/autopilot-cleanup.sh" \
    --autopilot-dir "$SANDBOX/.autopilot" \
    --dry-run

  assert_success
  assert_output --partial "並列 Wave 検出"
}
