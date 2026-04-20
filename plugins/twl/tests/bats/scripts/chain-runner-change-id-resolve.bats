#!/usr/bin/env bats
# chain-runner-change-id-resolve.bats
# Unit tests for Issue #753: step_change_id_resolve() の mtime-latest fallback 修正
#
# Spec: Issue #753 — Worker change_id 誤継承バグ
#
# Coverage:
#   (a) issue-748/ 存在 + ISSUE_NUM=748 → change-id-resolve が issue-748 を echo (exit 0)
#   (b) issue-748/ 不在 + ISSUE_NUM=748 (strict default) → exit 1 + stderr に「issue-748/ が存在しない」
#   (c) issue-748/ 不在 + ISSUE_NUM=748 + CHANGE_ID_FALLBACK_LATEST=1
#       → legacy mtime-latest fallback で issue-707 を echo

load '../helpers/common'

setup() {
  common_setup

  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/748-fix" ;;
      *"rev-parse --show-toplevel"*)
        echo "$SANDBOX" ;;
      *"rev-parse --git-dir"*)
        echo "$SANDBOX/.git" ;;
      *"worktree list"*)
        echo "worktree $SANDBOX"
        echo "HEAD abc123"
        echo "branch refs/heads/main" ;;
      *)
        exit 0 ;;
    esac
  '

  stub_command "gh" 'exit 0'

  # minimal deltaspec root
  mkdir -p "$SANDBOX/deltaspec/changes"
  echo "version: 1" > "$SANDBOX/deltaspec/config.yaml"

  # issue-707: mtime 最新（fallback テスト用）
  mkdir -p "$SANDBOX/deltaspec/changes/issue-707"
  echo "name: issue-707" > "$SANDBOX/deltaspec/changes/issue-707/.deltaspec.yaml"
  touch "$SANDBOX/deltaspec/changes/issue-707"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# (a) ISSUE_NUM=748, issue-748/ 存在 → issue-748 を echo (exit 0)
# WHEN: ISSUE_NUM=748 で issue-748/ が deltaspec/changes/ に存在する
# THEN: change-id-resolve は "issue-748" を stdout に出力し exit 0
# ---------------------------------------------------------------------------
@test "change-id-resolve: ISSUE_NUM=748, issue-748/ 存在 → issue-748 を echo" {
  mkdir -p "$SANDBOX/deltaspec/changes/issue-748"
  echo "name: issue-748" > "$SANDBOX/deltaspec/changes/issue-748/.deltaspec.yaml"

  export ISSUE_NUM=748
  run bash "$SANDBOX/scripts/chain-runner.sh" change-id-resolve
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "issue-748"
  ! echo "$output" | grep -qi "issue-707"
}

# ---------------------------------------------------------------------------
# (b) ISSUE_NUM=748, issue-748/ 不在, strict mode → exit 1 + エラーメッセージ
# WHEN: ISSUE_NUM=748 で issue-748/ が存在せず CHANGE_ID_FALLBACK_LATEST 未設定
# THEN: change-id-resolve は exit 1 し stderr に「issue-748/ が存在しない」を含む
# ---------------------------------------------------------------------------
@test "change-id-resolve: ISSUE_NUM=748, issue-748/ 不在 (strict) → exit 1 + error" {
  export ISSUE_NUM=748
  unset CHANGE_ID_FALLBACK_LATEST
  run bash "$SANDBOX/scripts/chain-runner.sh" change-id-resolve
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "issue-748"
}

# ---------------------------------------------------------------------------
# (c) ISSUE_NUM=748, issue-748/ 不在 + CHANGE_ID_FALLBACK_LATEST=1
#     → legacy mtime-latest fallback で issue-707 を echo
# WHEN: CHANGE_ID_FALLBACK_LATEST=1 の opt-in で issue-748/ 不在
# THEN: change-id-resolve は ls -td fallback で mtime 最新の issue-707 を echo
# ---------------------------------------------------------------------------
@test "change-id-resolve: CHANGE_ID_FALLBACK_LATEST=1 + issue-748/ 不在 → legacy fallback で issue-707" {
  export ISSUE_NUM=748
  export CHANGE_ID_FALLBACK_LATEST=1
  run bash "$SANDBOX/scripts/chain-runner.sh" change-id-resolve
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "issue-707"
}
