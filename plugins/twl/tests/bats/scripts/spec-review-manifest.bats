#!/usr/bin/env bats
# spec-review-manifest.bats - unit tests for scripts/spec-review-manifest.sh

load '../helpers/common'

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# ===========================================================================
# Requirement: spec-review-manifest.sh が正確に3行出力すること
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: specialist リスト出力
# WHEN spec-review-manifest.sh を実行する
# THEN 正確に3行出力される
# ---------------------------------------------------------------------------

@test "spec-review-manifest outputs exactly 3 lines" {
  run bash "$SANDBOX/scripts/spec-review-manifest.sh"

  assert_success
  assert [ "$(echo "$output" | wc -l)" -eq 3 ]
}

# ---------------------------------------------------------------------------
# Scenario: issue-critic が含まれる
# WHEN spec-review-manifest.sh を実行する
# THEN "twl:twl:issue-critic" が出力に含まれる
# ---------------------------------------------------------------------------

@test "spec-review-manifest includes twl:twl:issue-critic" {
  run bash "$SANDBOX/scripts/spec-review-manifest.sh"

  assert_success
  assert_output --partial "twl:twl:issue-critic"
}

# ---------------------------------------------------------------------------
# Scenario: issue-feasibility が含まれる
# WHEN spec-review-manifest.sh を実行する
# THEN "twl:twl:issue-feasibility" が出力に含まれる
# ---------------------------------------------------------------------------

@test "spec-review-manifest includes twl:twl:issue-feasibility" {
  run bash "$SANDBOX/scripts/spec-review-manifest.sh"

  assert_success
  assert_output --partial "twl:twl:issue-feasibility"
}

# ---------------------------------------------------------------------------
# Scenario: worker-codex-reviewer が含まれる
# WHEN spec-review-manifest.sh を実行する
# THEN "twl:twl:worker-codex-reviewer" が出力に含まれる
# ---------------------------------------------------------------------------

@test "spec-review-manifest includes twl:twl:worker-codex-reviewer" {
  run bash "$SANDBOX/scripts/spec-review-manifest.sh"

  assert_success
  assert_output --partial "twl:twl:worker-codex-reviewer"
}

# ===========================================================================
# Requirement: 出力の各行が有効な agent type であること
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: 各行が agents/ ディレクトリに存在する agent type を指す
# WHEN spec-review-manifest.sh の各行を確認する
# THEN twl/twl/ プレフィックスを除いた agent 名が agents/ に存在する
# ---------------------------------------------------------------------------

@test "spec-review-manifest each line corresponds to an existing agent file" {
  # REPO_ROOT は common_setup で設定される（sandbox/scripts/../ = sandbox）
  # 実際の agents/ ディレクトリはリポジトリルートにある
  HELPERS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../helpers" && pwd)"
  BATS_TEST_DIR="$(cd "$HELPERS_DIR/.." && pwd)"
  TESTS_DIR="$(cd "$BATS_TEST_DIR/.." && pwd)"
  ACTUAL_REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

  run bash "$SANDBOX/scripts/spec-review-manifest.sh"
  assert_success

  while IFS= read -r agent_type; do
    # "twl:twl:foo" → "foo"
    agent_name="${agent_type##*:}"
    agent_file="$ACTUAL_REPO_ROOT/agents/${agent_name}.md"
    assert [ -f "$agent_file" ] \
      "agent file not found: $agent_file (from agent type: $agent_type)"
  done <<< "$output"
}
