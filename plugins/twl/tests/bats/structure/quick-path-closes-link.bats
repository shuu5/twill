#!/usr/bin/env bats
# quick-path-closes-link.bats - static checks for Issue #136
#
# Issue #136 受け入れ基準:
# - workflow-setup quick path セクション内に Closes # の記載があること
# - autopilot-launch.sh の QUICK_INSTRUCTION 文字列に Closes #${ISSUE} が含まれること
#
# Note: 本ファイルは bats-support/bats-assert 非依存。
# 環境にサブモジュール未初期化でも実行可能。

setup() {
  REPO_ROOT_REAL="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
}

# ---------------------------------------------------------------------------
# Scenario: workflow-setup SKILL.md quick path に Closes # 記載
# ---------------------------------------------------------------------------

@test "workflow-setup SKILL.md quick path mentions Closes #" {
  local skill_md="$REPO_ROOT_REAL/skills/workflow-setup/SKILL.md"
  [ -f "$skill_md" ]
  grep -E "IS_QUICK=true.*IS_AUTOPILOT=true" "$skill_md"
  grep -F "Closes #" "$skill_md"
}

@test "workflow-setup SKILL.md quick path references pr_create_with_closes helper" {
  local skill_md="$REPO_ROOT_REAL/skills/workflow-setup/SKILL.md"
  grep -F "pr_create_with_closes" "$skill_md"
}

# ---------------------------------------------------------------------------
# Scenario: autopilot-launch.sh QUICK_INSTRUCTION に Closes #${ISSUE}
# ---------------------------------------------------------------------------

@test "autopilot-launch.sh QUICK_INSTRUCTION contains Closes #\${ISSUE}" {
  local launch_sh="$REPO_ROOT_REAL/scripts/autopilot-launch.sh"
  [ -f "$launch_sh" ]
  local line
  line=$(grep -E '^\s*QUICK_INSTRUCTION=' "$launch_sh")
  [ -n "$line" ]
  [[ "$line" == *'Closes #${ISSUE}'* ]]
}

# ---------------------------------------------------------------------------
# Scenario: 共通ヘルパー存在確認
# ---------------------------------------------------------------------------

@test "scripts/lib/pr-create-helper.sh exists and defines pr_create_with_closes" {
  local helper="$REPO_ROOT_REAL/scripts/lib/pr-create-helper.sh"
  [ -f "$helper" ]
  grep -E "^pr_create_with_closes\(\)" "$helper"
}

@test "scripts/pr-link-issue.sh exists and is executable" {
  local script="$REPO_ROOT_REAL/scripts/pr-link-issue.sh"
  [ -f "$script" ]
  [ -x "$script" ]
}

@test "scripts/pr-link-issue.sh --help mentions auto-close caveat" {
  local script="$REPO_ROOT_REAL/scripts/pr-link-issue.sh"
  local out
  out=$(bash "$script" --help 2>&1)
  [[ "$out" == *"--close-issue"* ]]
  [[ "$out" == *"再評価"* ]] || [[ "$out" == *"merge 後"* ]] || [[ "$out" == *"再評価しない"* ]]
}
