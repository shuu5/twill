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

# ---------------------------------------------------------------------------
# Requirement: クロスリポジトリ Board シナリオテスト
# Spec: openspec/changes/fix-buildcrossrepojson-board-subshell/specs/fix-subshell-propagation.md
# ---------------------------------------------------------------------------

# Scenario: クロスリポジトリ Issue が plan.yaml に repos セクション付きで出力される
# WHEN: Board に shuu5/loom-plugin-dev#42, #43 と shuu5/other-repo#56 が存在する場合
# THEN: plan.yaml に repos セクションが出力され、other-repo の owner/name が含まれる
#
# このテストは _build_cross_repo_json() がサブシェル内で呼ばれた場合に FAIL し、
# グローバル変数経由（BUILD_RESULT）で呼ばれた場合に PASS する。
@test "autopilot-plan --board cross-repo generates plan.yaml with repos section containing other-repo" {
  _write_cross_repo_board_items
  _stub_gh_cross_repo_project

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --board --project-dir "$SANDBOX" --repo-mode "worktree"

  assert_success
  assert_output --partial "plan.yaml 生成完了"
  [ -f "$SANDBOX/.autopilot/plan.yaml" ]
  # repos セクションが存在すること（CROSS_REPO が伝搬していなければ出力されない）
  grep -q "^repos:" "$SANDBOX/.autopilot/plan.yaml"
  # other-repo の owner と name が含まれること
  grep -q "other-repo" "$SANDBOX/.autopilot/plan.yaml"
  grep -q "shuu5" "$SANDBOX/.autopilot/plan.yaml"
}

# Scenario: クロスリポジトリ Issue が plan.yaml に repos セクション付きで出力される（issue 番号検証）
# WHEN: Board に shuu5/loom-plugin-dev#42, #43 と shuu5/other-repo#56 が存在する場合
# THEN: plan.yaml に 42, 43（ローカル）と 56（other-repo）が全て含まれる
#
# このテストは CROSS_REPO が false のまま parse_issues() が呼ばれた場合に FAIL する。
# （other-repo#56 が "other-repo#56" 形式で issue_list に入るが、
#   CROSS_REPO=false のまま resolve_issue_ref() が呼ばれると不明な repo_id エラーになる）
@test "autopilot-plan --board cross-repo plan.yaml includes both local issues 42 43 and cross-repo issue 56" {
  _write_cross_repo_board_items
  _stub_gh_cross_repo_project

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --board --project-dir "$SANDBOX" --repo-mode "worktree"

  assert_success
  [ -f "$SANDBOX/.autopilot/plan.yaml" ]
  # ローカル Issue 42, 43 が含まれること
  grep -qE "\b42\b" "$SANDBOX/.autopilot/plan.yaml"
  grep -qE "\b43\b" "$SANDBOX/.autopilot/plan.yaml"
  # クロスリポジトリ Issue 56 が含まれること
  grep -qE "\b56\b" "$SANDBOX/.autopilot/plan.yaml"
}

# Scenario: クロスリポジトリ Board で CROSS_REPO が伝搬する（REPO_OWNERS/REPO_NAMES の検証）
# WHEN: --board モードで異なるリポジトリの Issue を含む Board を処理した場合
# THEN: CROSS_REPO が true に設定され、REPO_OWNERS/REPO_NAMES が parse_issues() に正しく伝搬し、
#       plan.yaml の repos セクションに owner: "shuu5", name: "other-repo" が出力される
#
# このテストはサブシェルバグにより CROSS_REPO が伝搬しない場合に FAIL する。
@test "autopilot-plan --board cross-repo repos section has correct owner and name for other-repo" {
  _write_cross_repo_board_items
  _stub_gh_cross_repo_project

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --board --project-dir "$SANDBOX" --repo-mode "worktree"

  assert_success
  [ -f "$SANDBOX/.autopilot/plan.yaml" ]
  grep -q "^repos:" "$SANDBOX/.autopilot/plan.yaml"
  # owner: "shuu5" が repos セクションに含まれること
  grep -q 'owner:.*shuu5' "$SANDBOX/.autopilot/plan.yaml"
  # name: "other-repo" が repos セクションに含まれること
  grep -q 'name:.*other-repo' "$SANDBOX/.autopilot/plan.yaml"
}

# Scenario: クロスリポジトリのみの Board（ローカル Issue なし）
# WHEN: Board に shuu5/other-repo の Issue のみが存在する場合（ローカル Issue なし）
# THEN: plan.yaml が生成され、repos セクションに other-repo が含まれる
#
# エッジケース: issue_list がクロスリポジトリ Issue のみの場合の動作確認。
@test "autopilot-plan --board with only cross-repo issues generates plan.yaml with repos section" {
  _write_board_items '{"items": [
    {"content": {"number": 56, "repository": "shuu5/other-repo", "type": "Issue"}, "status": "Todo", "title": "Issue other-repo#56"}
  ]}'
  _stub_gh_cross_repo_project

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --board --project-dir "$SANDBOX" --repo-mode "worktree"

  assert_success
  assert_output --partial "plan.yaml 生成完了"
  [ -f "$SANDBOX/.autopilot/plan.yaml" ]
  grep -q "^repos:" "$SANDBOX/.autopilot/plan.yaml"
  grep -q "other-repo" "$SANDBOX/.autopilot/plan.yaml"
  grep -qE "\b56\b" "$SANDBOX/.autopilot/plan.yaml"
}

# Scenario: 単一リポジトリ Board の回帰なし
# WHEN: --board モードで現在のリポジトリのみの Issue を含む Board を処理した場合
# THEN: 既存と同一の plan.yaml が生成され、repos セクションは存在しない
#
# 修正後も単一リポジトリの動作が壊れないことを確認する回帰テスト。
@test "autopilot-plan --board single-repo does not produce repos section after cross-repo fix" {
  _write_board_items '{"items": [
    {"content": {"number": 42, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Todo",        "title": "Issue 42"},
    {"content": {"number": 43, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "In Progress", "title": "Issue 43"}
  ]}'
  _stub_gh_single_project

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --board --project-dir "$SANDBOX" --repo-mode "worktree"

  assert_success
  assert_output --partial "plan.yaml 生成完了"
  [ -f "$SANDBOX/.autopilot/plan.yaml" ]
  # 単一リポジトリでは repos セクションが出力されないこと
  run grep -q "^repos:" "$SANDBOX/.autopilot/plan.yaml"
  assert_failure
  grep -qE "\b42\b" "$SANDBOX/.autopilot/plan.yaml"
  grep -qE "\b43\b" "$SANDBOX/.autopilot/plan.yaml"
}
