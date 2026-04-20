#!/usr/bin/env bats
# chain-runner-init.bats
# Unit tests for Issue #753: step_init() の mtime-latest fallback 修正
#
# Spec: Issue #753 — Worker change_id 誤継承バグ
#
# Coverage:
#   (a) issue-707/ (approved) 存在 + issue-748/ 不在 + ISSUE_NUM=748
#       → recommended_action=propose, change_id 不在
#   (b) issue-707/ (approved) 存在 + issue-748/ (pending) 存在 + ISSUE_NUM=748
#       → change_id=issue-748（issue-707 を参照しない）
#   (c) issue-707/ 存在 + ISSUE_NUM 未設定
#       → ls -td fallback で issue-707 採用（legacy 互換）
#   (d) issue-707/ 存在 + ISSUE_NUM=707 + .deltaspec.yaml=approved
#       → recommended_action=apply, change_id=issue-707

load '../helpers/common'

setup() {
  common_setup

  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/test-branch" ;;
      *"rev-parse --show-toplevel"*)
        echo "$SANDBOX" ;;
      *"rev-parse --git-dir"*)
        echo "$SANDBOX/.git" ;;
      *"status --porcelain"*)
        echo "" ;;
      *"diff"*"--name-only"*)
        # 実装コードを含む diff → retroactive 経路を回避
        echo "plugins/twl/scripts/chain-runner.sh" ;;
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

  # issue-707: approved (mtime 最新にする)
  mkdir -p "$SANDBOX/deltaspec/changes/issue-707"
  cat > "$SANDBOX/deltaspec/changes/issue-707/.deltaspec.yaml" <<'EOF'
name: issue-707
status: approved
EOF
  echo "# Proposal" > "$SANDBOX/deltaspec/changes/issue-707/proposal.md"
  # issue-707 を mtime 最新にする
  touch "$SANDBOX/deltaspec/changes/issue-707"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# (a) ISSUE_NUM=748, issue-748/ 不在 → propose (新規作成経路)
# WHEN: issue-707/ (approved) が mtime 最新で存在し、issue-748/ は不在
# THEN: ISSUE_NUM=748 で init を実行すると recommended_action=propose
# ---------------------------------------------------------------------------
@test "init: ISSUE_NUM=748, issue-748/ 不在 → recommended_action=propose (issue-707 を誤採用しない)" {
  # issue-707.json を作成してテスト
  jq -n '{issue: 748, status: "running", branch: "feat/748", current_step: "init"}' \
    > "$SANDBOX/.autopilot/issues/issue-748.json"

  export ISSUE_NUM=748
  run bash "$SANDBOX/scripts/chain-runner.sh" init 748
  [ "$status" -eq 0 ]
  # recommended_action が propose であること
  echo "$output" | grep -q '"recommended_action".*"propose"'
  # change_id が issue-707 でないこと
  ! echo "$output" | grep -q '"change_id".*"issue-707"'
}

# ---------------------------------------------------------------------------
# (b) ISSUE_NUM=748, issue-748/ (pending) 存在 → change_id=issue-748
# WHEN: issue-707/ (approved, mtime 最新) と issue-748/ (pending) が共存
# THEN: ISSUE_NUM=748 で init を実行すると change_id=issue-748 を返す
# ---------------------------------------------------------------------------
@test "init: ISSUE_NUM=748, issue-748/ (pending) 存在 → change_id=issue-748 (issue-707 を参照しない)" {
  # issue-748: pending (proposal あり、未承認)
  mkdir -p "$SANDBOX/deltaspec/changes/issue-748"
  cat > "$SANDBOX/deltaspec/changes/issue-748/.deltaspec.yaml" <<'EOF'
name: issue-748
status: pending
EOF
  echo "# Draft proposal" > "$SANDBOX/deltaspec/changes/issue-748/proposal.md"

  jq -n '{issue: 748, status: "running", branch: "feat/748", current_step: "init"}' \
    > "$SANDBOX/.autopilot/issues/issue-748.json"

  export ISSUE_NUM=748
  run bash "$SANDBOX/scripts/chain-runner.sh" init 748
  [ "$status" -eq 0 ]
  # change_id が issue-748 であること（issue-707 ではない）
  echo "$output" | grep -q '"change_id".*"issue-748"'
  ! echo "$output" | grep -q '"change_id".*"issue-707"'
}

# ---------------------------------------------------------------------------
# (c) ISSUE_NUM 未設定 → legacy mtime-latest fallback で issue-707 採用
# WHEN: issue-707/ (approved) が mtime 最新で存在、ISSUE_NUM は未設定
# THEN: init は既存挙動（ls -td fallback）で issue-707 を採用する
# ---------------------------------------------------------------------------
@test "init: ISSUE_NUM 未設定 → legacy fallback で mtime-latest (issue-707) を採用" {
  unset ISSUE_NUM
  run bash "$SANDBOX/scripts/chain-runner.sh" init
  [ "$status" -eq 0 ]
  # recommended_action=apply かつ change_id=issue-707
  echo "$output" | grep -q '"change_id".*"issue-707"'
  echo "$output" | grep -q '"recommended_action".*"apply"'
}

# ---------------------------------------------------------------------------
# (d) ISSUE_NUM=707, issue-707/ .deltaspec.yaml=approved → recommended_action=apply
# WHEN: issue-707/ が存在し .deltaspec.yaml=approved、ISSUE_NUM=707
# THEN: recommended_action=apply, change_id=issue-707
# ---------------------------------------------------------------------------
@test "init: ISSUE_NUM=707, issue-707/ (approved) → recommended_action=apply, change_id=issue-707" {
  jq -n '{issue: 707, status: "running", branch: "feat/707", current_step: "init"}' \
    > "$SANDBOX/.autopilot/issues/issue-707.json"

  export ISSUE_NUM=707
  run bash "$SANDBOX/scripts/chain-runner.sh" init 707
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"recommended_action".*"apply"'
  echo "$output" | grep -q '"change_id".*"issue-707"'
}
