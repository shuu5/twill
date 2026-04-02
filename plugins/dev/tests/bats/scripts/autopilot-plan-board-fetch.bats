#!/usr/bin/env bats
# autopilot-plan-board-fetch.bats - Board Issue 取得 + 排他バリデーション
#
# Spec: openspec/changes/110-autopilot-board-mode/specs/board-mode.md
# Scenarios: Board取得, Done除外, 空Board, Draft/PRフィルタ, 排他バリデーション

load '../helpers/common'
load './autopilot-plan-board-helpers'

setup() { common_setup; }
teardown() { common_teardown; }

# ---------------------------------------------------------------------------
# Requirement: Board Issue 取得モード
# ---------------------------------------------------------------------------

@test "autopilot-plan --board fetches Todo and In Progress issues and generates plan.yaml" {
  _write_board_items '{"items": [
    {"content": {"number": 42, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Todo",        "title": "Issue 42"},
    {"content": {"number": 43, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "In Progress", "title": "Issue 43"},
    {"content": {"number": 44, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Done",        "title": "Issue 44"}
  ]}'
  _stub_gh_single_project

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --board --project-dir "$SANDBOX" --repo-mode "worktree"

  assert_success
  assert_output --partial "plan.yaml 生成完了"
  [ -f "$SANDBOX/.autopilot/plan.yaml" ]
  grep -q "42" "$SANDBOX/.autopilot/plan.yaml"
  grep -q "43" "$SANDBOX/.autopilot/plan.yaml"
  run grep -qE "\b44\b" "$SANDBOX/.autopilot/plan.yaml"
  assert_failure
}

@test "autopilot-plan --board exits 1 when all board issues are Done" {
  _write_board_items '{"items": [
    {"content": {"number": 10, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Done", "title": "Issue 10"},
    {"content": {"number": 11, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Done", "title": "Issue 11"}
  ]}'
  _stub_gh_single_project

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --board --project-dir "$SANDBOX" --repo-mode "worktree"

  assert_failure
  assert_output --partial "Board に未完了の Issue がありません"
}

@test "autopilot-plan --board exits 1 when board has no items at all" {
  _write_board_items '{"items": []}'
  _stub_gh_single_project

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --board --project-dir "$SANDBOX" --repo-mode "worktree"

  assert_failure
  assert_output --partial "Board に未完了の Issue がありません"
}

@test "autopilot-plan --board skips items where content.type is not Issue" {
  _write_board_items '{"items": [
    {"content": {"number": 99,  "repository": "shuu5/loom-plugin-dev", "type": "PullRequest"}, "status": "Todo", "title": "PR 99"},
    {"content": {"number": 100, "repository": "shuu5/loom-plugin-dev", "type": "DraftIssue"},  "status": "Todo", "title": "Draft 100"},
    {"content": {"number": 42,  "repository": "shuu5/loom-plugin-dev", "type": "Issue"},       "status": "Todo", "title": "Issue 42"}
  ]}'
  _stub_gh_single_project

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --board --project-dir "$SANDBOX" --repo-mode "worktree"

  assert_success
  [ -f "$SANDBOX/.autopilot/plan.yaml" ]
  grep -q "42" "$SANDBOX/.autopilot/plan.yaml"
  run grep -qE "\b99\b" "$SANDBOX/.autopilot/plan.yaml"
  assert_failure
  run grep -qE "\b100\b" "$SANDBOX/.autopilot/plan.yaml"
  assert_failure
}

@test "autopilot-plan --board exits 1 when all items are non-Issue types" {
  _write_board_items '{"items": [
    {"content": {"number": 1, "repository": "shuu5/loom-plugin-dev", "type": "PullRequest"}, "status": "Todo", "title": "PR 1"},
    {"content": {"number": 2, "repository": "shuu5/loom-plugin-dev", "type": "DraftIssue"},  "status": "Todo", "title": "Draft 2"}
  ]}'
  _stub_gh_single_project

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --board --project-dir "$SANDBOX" --repo-mode "worktree"

  assert_failure
  assert_output --partial "Board に未完了の Issue がありません"
}

# ---------------------------------------------------------------------------
# Requirement: 排他バリデーション
# ---------------------------------------------------------------------------

@test "autopilot-plan --board with --issues exits 1 with exclusivity error" {
  stub_command "uuidgen" 'echo "test-uuid-excl-0001"'
  stub_command "gh" 'echo "{}"'

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --board --issues "42 43" --project-dir "$SANDBOX" --repo-mode "worktree"

  assert_failure
  assert_output --partial "--explicit/--issues/--board は同時に指定できません"
}

@test "autopilot-plan --board with --explicit exits 1 with exclusivity error" {
  stub_command "uuidgen" 'echo "test-uuid-excl-0002"'
  stub_command "gh" 'echo "{}"'

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --board --explicit "1 → 2" --project-dir "$SANDBOX" --repo-mode "worktree"

  assert_failure
  assert_output --partial "--explicit/--issues/--board は同時に指定できません"
}
