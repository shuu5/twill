#!/usr/bin/env bats
# tool-architect-temporal.bats - R-14〜R-20 spec content semantic 規律静的検証 (C10)
# change 001-spec-purify Specialist phase 4 (b)

load '../helpers/common'

setup() {
  common_setup
  RULES_MD="$REPO_ROOT/skills/tool-architect/refs/spec-management-rules.md"
  SKILL_MD="$REPO_ROOT/skills/tool-architect/SKILL.md"
}

teardown() {
  common_teardown
}

@test "spec-management-rules.md has R-14 heading (現在形 declarative)" {
  grep -qE '^## R-14:' "$RULES_MD"
}

@test "spec-management-rules.md has R-15 heading (code block 制限)" {
  grep -qE '^## R-15:' "$RULES_MD"
}

@test "spec-management-rules.md has R-16 heading (archive 移動)" {
  grep -qE '^## R-16:' "$RULES_MD"
}

@test "spec-management-rules.md has R-17 heading (changes/ lifecycle)" {
  grep -qE '^## R-17:' "$RULES_MD"
}

@test "spec-management-rules.md has R-18 heading (ReSpec markup)" {
  grep -qE '^## R-18:' "$RULES_MD"
}

@test "spec-management-rules.md has R-19 heading (hook chain)" {
  grep -qE '^## R-19:' "$RULES_MD"
}

@test "spec-management-rules.md has R-20 heading (MCP tool 統合)" {
  grep -qE '^## R-20:' "$RULES_MD"
}

@test "SKILL.md mentions R-14 and R-20" {
  grep -q "R-14" "$SKILL_MD"
  grep -q "R-20" "$SKILL_MD"
}

@test "SKILL.md Phase F is 4 並列固定 (R-12 + 4 軸目 update)" {
  grep -qE "4 並列固定" "$SKILL_MD"
}

@test "SKILL.md mentions specialist-spec-review-temporal" {
  grep -q "specialist-spec-review-temporal" "$SKILL_MD"
}

@test "SKILL.md mentions twl_spec_content_check (R-20)" {
  grep -q "twl_spec_content_check" "$SKILL_MD"
}

@test "spec-management-rules.md ReSpec markup in HTML template (R-18)" {
  grep -qE 'class="(normative|informative)"' "$RULES_MD"
}
