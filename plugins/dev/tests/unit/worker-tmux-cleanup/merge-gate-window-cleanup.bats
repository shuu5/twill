#!/usr/bin/env bats
# merge-gate-window-cleanup.bats
# Requirement: merge-gate-execute.sh reject 時の window cleanup
# Spec: openspec/changes/worker-tmux-cleanup/specs/merge-gate-cleanup/spec.md
#
# NOTE: --reject / --reject-final での tmux kill-window は worker-tmux-cleanup
#       spec で追加される変更。現行の merge-gate-execute.sh には未実装のため、
#       実装確認テスト（Scenario 1-2）は実装後に通るよう設計されている。
#       window-不在・ISSUE未設定などのエッジケースは既存実装でも動作する。

load '../../bats/helpers/common'

setup() {
  common_setup

  # デフォルト stubs
  stub_command "git" '
    case "$*" in
      *"rev-parse --git-dir"*)
        echo "/tmp/.git/worktrees/test" ;;
      *"worktree list"*)
        echo "" ;;
      *"worktree remove"*)
        exit 0 ;;
      *"push origin --delete"*)
        exit 0 ;;
      *"branch -D"*)
        exit 0 ;;
      *)
        exit 0 ;;
    esac
  '
  stub_command "gh" '
    case "$*" in
      *"pr merge"*)
        exit 0 ;;
      *)
        echo "" ;;
    esac
  '

  # tmux: 呼び出しを記録
  TMUX_LOG="$SANDBOX/tmux-calls.log"
  export TMUX_LOG

  stub_command "tmux" "
    case \"\$*\" in
      *'display-message'*)
        echo '' ;;
      *)
        echo \"tmux \$*\" >> '$TMUX_LOG'
        exit 0 ;;
    esac
  "
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: merge-gate-execute.sh reject 時の window cleanup
# （実装確認テスト: worker-tmux-cleanup 実装後に通る）
# ---------------------------------------------------------------------------

# Scenario: --reject モードの window cleanup
# WHEN merge-gate-execute.sh --reject が実行される
# THEN state-write.sh で status=failed を設定した後に
#      tmux kill-window -t "ap-#${ISSUE}" 2>/dev/null || true を実行する
@test "merge-gate-execute --reject: status=failed 設定後に tmux kill-window を実行する" {
  create_issue_json 1 "merge-ready"
  export ISSUE=1 PR_NUMBER=42 BRANCH="feat/1-test"
  export FINDING_SUMMARY="Critical bug found"
  export FIX_INSTRUCTIONS="Fix the issue"

  run bash "$SANDBOX/scripts/merge-gate-execute.sh" --reject

  assert_success

  # status が failed に変換されていること（既存動作）
  local status
  status=$(jq -r '.status' "$SANDBOX/.autopilot/issues/issue-1.json")
  [ "$status" = "failed" ]

  # tmux kill-window が呼ばれていること（worker-tmux-cleanup 実装後に通る）
  [ -f "$TMUX_LOG" ]
  grep -q "kill-window" "$TMUX_LOG"
  grep -q "ap-#1" "$TMUX_LOG"
}

# Scenario: --reject-final モードの window cleanup
# WHEN merge-gate-execute.sh --reject-final が実行される
# THEN state-write.sh で status=failed を設定した後に
#      tmux kill-window -t "ap-#${ISSUE}" 2>/dev/null || true を実行する
@test "merge-gate-execute --reject-final: status=failed 設定後に tmux kill-window を実行する" {
  create_issue_json 1 "merge-ready"
  export ISSUE=1 PR_NUMBER=42 BRANCH="feat/1-test"
  export FINDING_SUMMARY="Critical bug again"

  run bash "$SANDBOX/scripts/merge-gate-execute.sh" --reject-final

  assert_success

  # status が failed に変換されていること（既存動作）
  local status
  status=$(jq -r '.status' "$SANDBOX/.autopilot/issues/issue-1.json")
  [ "$status" = "failed" ]

  # tmux kill-window が呼ばれていること（worker-tmux-cleanup 実装後に通る）
  [ -f "$TMUX_LOG" ]
  grep -q "kill-window" "$TMUX_LOG"
  grep -q "ap-#1" "$TMUX_LOG"
}

# ---------------------------------------------------------------------------
# Scenario: window が存在しない場合（エラー無視）
# ---------------------------------------------------------------------------

# Scenario: window が存在しない場合
# WHEN tmux kill-window の対象 window が既に存在しない
# THEN エラーを無視して処理を続行する
@test "merge-gate-execute --reject: tmux kill-window が失敗しても処理を続行する" {
  create_issue_json 1 "merge-ready"
  export ISSUE=1 PR_NUMBER=42 BRANCH="feat/1-test"
  export FINDING_SUMMARY="Critical bug"

  # tmux kill-window が常に失敗するよう stub を上書き
  stub_command "tmux" "
    case \"\$*\" in
      *'display-message'*)
        echo '' ;;
      *'kill-window'*)
        exit 1 ;;
      *)
        exit 0 ;;
    esac
  "

  run bash "$SANDBOX/scripts/merge-gate-execute.sh" --reject

  # tmux kill-window の失敗に関わらず正常終了すること
  assert_success

  # status が failed になっていること（window の kill 失敗は status 遷移に影響しない）
  local status
  status=$(jq -r '.status' "$SANDBOX/.autopilot/issues/issue-1.json")
  [ "$status" = "failed" ]
}

@test "merge-gate-execute --reject-final: tmux kill-window が失敗しても処理を続行する" {
  create_issue_json 1 "merge-ready"
  export ISSUE=1 PR_NUMBER=42 BRANCH="feat/1-test"
  export FINDING_SUMMARY="Critical bug again"

  stub_command "tmux" "
    case \"\$*\" in
      *'display-message'*)
        echo '' ;;
      *'kill-window'*)
        exit 1 ;;
      *)
        exit 0 ;;
    esac
  "

  run bash "$SANDBOX/scripts/merge-gate-execute.sh" --reject-final

  assert_success

  local status
  status=$(jq -r '.status' "$SANDBOX/.autopilot/issues/issue-1.json")
  [ "$status" = "failed" ]
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

# Edge case: --reject で正しい window 名（ap-#${ISSUE}）が kill される
# （worker-tmux-cleanup 実装後に通る）
@test "merge-gate-execute --reject: 正しい window 名 ap-#ISSUE を kill する" {
  create_issue_json 5 "merge-ready"
  export ISSUE=5 PR_NUMBER=10 BRANCH="feat/5-fix"
  export FINDING_SUMMARY="Bug found"

  run bash "$SANDBOX/scripts/merge-gate-execute.sh" --reject

  assert_success
  [ -f "$TMUX_LOG" ]
  grep -q "ap-#5" "$TMUX_LOG"
  # 別の番号は kill されていないこと
  ! grep -q "ap-#1" "$TMUX_LOG" 2>/dev/null
}

# Edge case: --reject-final で正しい window 名が kill される
# （worker-tmux-cleanup 実装後に通る）
@test "merge-gate-execute --reject-final: 正しい window 名 ap-#ISSUE を kill する" {
  create_issue_json 7 "merge-ready"
  export ISSUE=7 PR_NUMBER=20 BRANCH="feat/7-hotfix"
  export FINDING_SUMMARY="Serious issue"

  run bash "$SANDBOX/scripts/merge-gate-execute.sh" --reject-final

  assert_success
  [ -f "$TMUX_LOG" ]
  grep -q "ap-#7" "$TMUX_LOG"
}

# Edge case: ISSUE 未設定時はバリデーションで弾かれ tmux kill-window は呼ばれない
@test "merge-gate-execute --reject: ISSUE 未設定時は tmux kill-window を呼ばない" {
  unset ISSUE

  run bash "$SANDBOX/scripts/merge-gate-execute.sh" --reject

  assert_failure
  # tmux log が存在しないか、kill-window が記録されていないこと
  [ ! -f "$TMUX_LOG" ] || ! grep -q "kill-window" "$TMUX_LOG" 2>/dev/null
}
