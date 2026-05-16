#!/usr/bin/env bats
# tool-architect-7phase.bats - SKILL.md 7-phase workflow 静的検証 (9 test cases、C7、R-12 enforcement)

load '../helpers/common'

setup() {
  common_setup
  SKILL_MD="$REPO_ROOT/skills/tool-architect/SKILL.md"
}

teardown() {
  common_teardown
}

@test "tool-architect SKILL.md exists" {
  [ -f "$SKILL_MD" ]
}

@test "tool-architect SKILL.md frontmatter name=twl:tool-architect" {
  FRONTMATTER="$(sed -n '/^---$/,/^---$/p' "$SKILL_MD")"
  echo "$FRONTMATTER" | grep -qE '^name:\s*twl:tool-architect'
}

@test "tool-architect SKILL.md frontmatter type=tool" {
  FRONTMATTER="$(sed -n '/^---$/,/^---$/p' "$SKILL_MD")"
  echo "$FRONTMATTER" | grep -qE '^type:\s*tool'
}

@test "tool-architect SKILL.md allowed-tools includes Agent" {
  FRONTMATTER="$(sed -n '/^---$/,/^---$/p' "$SKILL_MD")"
  echo "$FRONTMATTER" | grep -qE 'allowed-tools.*Agent|Agent.*allowed-tools'
}

@test "tool-architect SKILL.md has 7-phase section heading" {
  grep -qE '7-phase' "$SKILL_MD"
}

@test "tool-architect SKILL.md has Phase A (Discovery)" {
  grep -qE 'Phase A.*Discovery|Discovery.*Phase A' "$SKILL_MD"
}

@test "tool-architect SKILL.md has Phase B/C/D/E/F/G all" {
  # All 6 remaining phases should be present
  for phase in B C D E F G; do
    grep -qE "Phase $phase\b" "$SKILL_MD"
  done
}

@test "tool-architect SKILL.md mentions specialist-spec-explorer/architect/review-*" {
  grep -qE 'specialist-spec-explorer' "$SKILL_MD"
  grep -qE 'specialist-spec-architect' "$SKILL_MD"
  grep -qE 'specialist-spec-review-vocabulary' "$SKILL_MD"
  grep -qE 'specialist-spec-review-structure' "$SKILL_MD"
  grep -qE 'specialist-spec-review-ssot' "$SKILL_MD"
}

@test "tool-architect SKILL.md mentions MUST NOT SKIP for Phase C/F (R-12)" {
  grep -qE 'MUST NOT SKIP' "$SKILL_MD"
}
