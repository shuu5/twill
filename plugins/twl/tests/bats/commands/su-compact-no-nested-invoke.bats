#!/usr/bin/env bats
# su-compact-no-nested-invoke.bats
# Issue #1120: su-compact.md から externalize-state.md への nested invoke を削除する
# RED phase: 実装前は FAIL することを確認するテスト

load '../helpers/common'

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC-1: su-compact.md に externalize-state.md への Read + 実行記述がないこと
# 現状: Line 82 に記述が存在するため FAIL（RED フェーズ正常）
# ---------------------------------------------------------------------------

@test "ac1: su-compact.md に externalize-state.md を Read する execute 形式がないこと" {
  local cmd_md="$REPO_ROOT/commands/su-compact.md"

  # ファイルが存在すること
  [ -f "$cmd_md" ]

  # Issue #1120 AC-6 で指定されたパターン: "Read し" + "externalize-state" の行が存在しないこと
  # 注釈・設計意図セクション内での参照（MUST NOT 等）は許容（Issue #1120 仕様）
  run bash -c "grep -F 'Read し' '$cmd_md' | grep -F 'externalize-state'"

  # マッチが 0 件（exit 1）であることを期待
  assert_failure
}

@test "ac1: su-compact.md に externalize-state.md を引数として実行する記述がないこと" {
  local cmd_md="$REPO_ROOT/commands/su-compact.md"

  [ -f "$cmd_md" ]

  # "externalize-state.md を Read し、...を引数として実行する" 形式がないこと
  # 注釈・禁止事項セクションでの文言は許容
  run bash -c "grep -F 'externalize-state.md' '$cmd_md' | grep -F 'を引数として実行する'"

  assert_failure
}

@test "ac1: Issue 番号誤記 'Issue #NN1119' が存在しないこと" {
  local cmd_md="$REPO_ROOT/commands/su-compact.md"

  [ -f "$cmd_md" ]

  # 'Issue #NN1119' という placeholder 誤記がないこと
  # RED: 実装前にこの誤記が存在していれば FAIL
  run bash -c "grep -q 'Issue #NN1119' '$cmd_md'"

  assert_failure
}

# ---------------------------------------------------------------------------
# AC-2: externalize-state.md 自体が変更されていないこと
# 現状でも変更なし → PASS する可能性があるが TDD 記録として残す
# ---------------------------------------------------------------------------

@test "ac2: externalize-state.md が変更されていないこと（git diff が空）" {
  local ext_md="$REPO_ROOT/commands/externalize-state.md"

  [ -f "$ext_md" ]

  # worktree root から git diff で確認
  local worktree_root
  worktree_root="$(cd "$REPO_ROOT" && git rev-parse --show-toplevel 2>/dev/null)"

  run bash -c "cd '$worktree_root' && git diff HEAD -- plugins/twl/commands/externalize-state.md"

  # diff が空であること（exit 0 かつ stdout 空）
  assert_success
  assert_output ""
}

# ---------------------------------------------------------------------------
# AC-4: MUST NOT セクションに nested invoke 禁止文言が追記されていること
# RED: 現状 MUST NOT セクションに該当文言が存在しないため FAIL
# ---------------------------------------------------------------------------

@test "ac4: MUST NOT セクションに nested invoke 禁止文言が追記されていること" {
  local cmd_md="$REPO_ROOT/commands/su-compact.md"

  [ -f "$cmd_md" ]

  # MUST NOT セクションに "nested invoke" 禁止の文言があること
  # RED: 現状 MUST NOT セクションにこの文言が存在しないため FAIL
  run bash -c "grep -q 'nested invoke' '$cmd_md'"

  assert_success
}

@test "ac4: MUST NOT セクションに Issue #1120 の参照が含まれること" {
  local cmd_md="$REPO_ROOT/commands/su-compact.md"

  [ -f "$cmd_md" ]

  # MUST NOT セクションに "Issue #1120" の参照があること
  # RED: 現状この参照が存在しないため FAIL
  run bash -c "grep -q 'Issue #1120' '$cmd_md'"

  assert_success
}

# ---------------------------------------------------------------------------
# AC-5: pitfalls-catalog.md §8 末尾に su-compact inline 実装サブセクションが追加されていること
# RED: 現状 §8 に su-compact に関するサブセクションが存在しないため FAIL
# ---------------------------------------------------------------------------

@test "ac5: pitfalls-catalog.md に su-compact inline 実装サブセクションが存在すること" {
  local catalog_md="$REPO_ROOT/skills/su-observer/refs/pitfalls-catalog.md"

  [ -f "$catalog_md" ]

  # §8 内に su-compact に関するサブセクション（### レベル）が存在すること
  # RED: 現状 §8 に su-compact 関連の記述がないため FAIL
  run bash -c "
    sed -n '/^## 8\./,/^## 9\./p' '$catalog_md' | grep -q 'su-compact'
  "

  assert_success
}

# ---------------------------------------------------------------------------
# AC-6: su-compact.md 本文中に externalize-state.md を Read + 実行する形式の記述がないこと
# これが最重要テスト（Issue body に明示）
# RED: 現状 Line 82 に記述が存在するため FAIL
# ---------------------------------------------------------------------------

@test "ac6: su-compact.md 本文に externalize-state.md の Read + execute 形式の記述がないこと" {
  local cmd_md="$REPO_ROOT/commands/su-compact.md"

  [ -f "$cmd_md" ]

  # Issue #1120 指定パターン: "Read し" + "externalize-state" の行が存在しないこと
  # 注釈・MUST NOT セクションでの参照は許容（Issue #1120 仕様）
  run bash -c "grep -F 'Read し' '$cmd_md' | grep -F 'externalize-state'"

  assert_failure
}

@test "ac6: su-compact.md Step 3 に externalize-state.md の execute 命令がないこと" {
  local cmd_md="$REPO_ROOT/commands/su-compact.md"

  [ -f "$cmd_md" ]

  # Step 3 セクション内に "externalize-state.md を Read し" の execute 命令がないこと
  # 注釈・説明文内での参照（「nested invoke は行わない」等）は許容
  run bash -c "
    sed -n '/### Step 3:/,/### Step 4:/p' '$cmd_md' \
      | grep -F 'Read し' | grep -F 'externalize-state'
  "

  assert_failure
}
