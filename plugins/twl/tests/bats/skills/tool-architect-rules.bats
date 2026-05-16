#!/usr/bin/env bats
# tool-architect-rules.bats - spec-management-rules.md R-1〜R-13 静的検証 (11 test cases、C7)

load '../helpers/common'

setup() {
  common_setup
  RULES_MD="$REPO_ROOT/skills/tool-architect/refs/spec-management-rules.md"
}

teardown() {
  common_teardown
}

@test "spec-management-rules.md exists" {
  [ -f "$RULES_MD" ]
}

@test "spec-management-rules.md has R-1 heading" {
  grep -qE '^## R-1:' "$RULES_MD"
}

@test "spec-management-rules.md has R-10 heading (existing baseline)" {
  grep -qE '^## R-10:' "$RULES_MD"
}

@test "spec-management-rules.md has R-11 heading (new)" {
  grep -qE '^## R-11:' "$RULES_MD"
}

@test "spec-management-rules.md has R-12 heading (new)" {
  grep -qE '^## R-12:' "$RULES_MD"
}

@test "spec-management-rules.md has R-13 heading (new)" {
  grep -qE '^## R-13:' "$RULES_MD"
}

@test "R-11 mentions specialist-spec-* prefix" {
  grep -A 30 '^## R-11:' "$RULES_MD" | grep -qE 'specialist-spec-\*'
}

@test "R-12 mentions Phase C and Phase F MUST NOT SKIP" {
  grep -A 30 '^## R-12:' "$RULES_MD" | grep -qE 'Phase C'
  grep -A 30 '^## R-12:' "$RULES_MD" | grep -qE 'Phase F'
  grep -A 30 '^## R-12:' "$RULES_MD" | grep -qE 'MUST NOT SKIP'
}

@test "R-12 mentions AskUserQuestion" {
  grep -A 50 '^## R-12:' "$RULES_MD" | grep -qE 'AskUserQuestion'
}

@test "R-13 mentions opus fixed and sonnet downgrade prohibition" {
  grep -A 30 '^## R-13:' "$RULES_MD" | grep -qE 'opus'
  grep -A 30 '^## R-13:' "$RULES_MD" | grep -qE 'sonnet.*downgrade|downgrade.*sonnet|sonnet.*禁止'
}

@test "All R-1 through R-13 headings present" {
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13; do
    grep -qE "^## R-$i:" "$RULES_MD"
  done
}
