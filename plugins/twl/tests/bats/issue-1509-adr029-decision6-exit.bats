#!/usr/bin/env bats
# issue-1509-adr029-decision6-exit.bats
#
# Issue #1509: ADR-029 Decision 6 追記 + exit code 誤記修正
#
# RED: 実装前は全テスト fail（Decision 6 未追記 / exit 2 誤記残存）
# GREEN: 実装後に PASS

load 'helpers/common'

ADR029=""
MIGRATION_STRATEGY=""

setup() {
  common_setup
  ADR029="${REPO_ROOT}/architecture/decisions/ADR-029-twl-mcp-integration-strategy.md"
  MIGRATION_STRATEGY="${REPO_ROOT}/architecture/migrations/tier-2-caller/migration-strategy.md"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: ADR-029 に Decision 6 セクション追記
# ===========================================================================

@test "ac1: ADR-029 に Decision 6 セクションが存在する" {
  # AC: ADR-029 に Decision 6 (Tier 1+ Strategy) を追記
  # RED: Decision 6 未追記のため fail
  grep -qF '### Decision 6' "$ADR029"
}

@test "ac1: ADR-029 Decision 6 に Tier 1+ Strategy の言及がある" {
  # AC: 6 tool の設計方針・shadow rollout pattern・既存実装との差分を記述
  # RED: Decision 6 未追記のため fail
  grep -qF 'Tier 1+' "$ADR029"
}

# ===========================================================================
# AC2: ADR-029 内 exit 2 表記を exit 1 に修正
# ===========================================================================

@test "ac2: ADR-029 の mcp-shadow-compare.sh 記述が exit 1 を使用している" {
  # AC: exit 2 表記を exit 1 に修正（実装と整合）
  # RED: 現在 exit 2 が残存しているため fail
  # mcp-shadow-compare.sh は exit 1 を返す（L26,33,38,49,85）
  grep -qF 'exit 1 = mismatch あり' "$ADR029"
}

@test "ac2: ADR-029 に exit 2 = mismatch あり の誤記が残っていない" {
  # AC: exit 2 表記を exit 1 に修正
  # RED: exit 2 が残存しているため run は success → assert_failure で fail
  run grep -qF 'exit 2 = mismatch あり' "$ADR029"
  assert_failure
}

# ===========================================================================
# AC3: migration-strategy.md §2.3 の exit code 誤記修正
# ===========================================================================

@test "ac3: migration-strategy.md §2.3 が exit 1 = mismatch あり を使用している" {
  # AC: plugins/twl/architecture/migrations/tier-2-caller/migration-strategy.md §2.3 の同様誤記を修正
  # RED: 現在 exit 2 が残存しているため fail
  grep -qF 'exit 1 = mismatch あり' "$MIGRATION_STRATEGY"
}

@test "ac3: migration-strategy.md §2.3 に exit 2 = mismatch あり の誤記が残っていない" {
  # AC: §2.3 の誤記修正
  # RED: exit 2 が残存しているため run は success → assert_failure で fail
  run grep -qF 'exit 2 = mismatch あり' "$MIGRATION_STRATEGY"
  assert_failure
}

# ===========================================================================
# AC4: epic #1271 AC3 達成証明 PR description diff link
# ===========================================================================

@test "ac4: PR description に epic #1271 AC3 証明の diff link が含まれる（手動確認）" {
  # AC: epic #1271 AC3 達成証明として PR description に diff link を貼る
  # RED: プロセス AC のため自動検証不可。PR 作成後に手動確認が必要
  # Worker: PR description に ADR-029 diff link を追加してからこのテストを GREEN にすること
  false
}
