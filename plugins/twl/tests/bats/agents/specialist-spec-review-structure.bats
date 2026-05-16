#!/usr/bin/env bats
# specialist-spec-review-structure.bats - agent .md 静的検証 (11 test cases、C7)
# Phase F 軸 2 (構造整合性) for tool-architect 7-phase multi-agent PR cycle、opus 固定 (R-13)

load '../helpers/common'

setup() {
  common_setup
  AGENT_MD="$REPO_ROOT/agents/specialist-spec-review-structure.md"
}

teardown() {
  common_teardown
}

@test "specialist-spec-review-structure file exists" {
  [ -f "$AGENT_MD" ]
}

@test "specialist-spec-review-structure frontmatter has type=specialist" {
  FRONTMATTER="$(sed -n '/^---$/,/^---$/p' "$AGENT_MD")"
  echo "$FRONTMATTER" | grep -qE '^type:\s*specialist'
}

@test "specialist-spec-review-structure frontmatter name has twl: prefix" {
  FRONTMATTER="$(sed -n '/^---$/,/^---$/p' "$AGENT_MD")"
  echo "$FRONTMATTER" | grep -qE '^name:\s*twl:specialist-spec-review-structure'
}

@test "specialist-spec-review-structure frontmatter model=opus (R-13)" {
  FRONTMATTER="$(sed -n '/^---$/,/^---$/p' "$AGENT_MD")"
  echo "$FRONTMATTER" | grep -qE '^model:\s*opus'
}

@test "specialist-spec-review-structure no Edit/Write in tools" {
  FRONTMATTER="$(sed -n '/^---$/,/^---$/p' "$AGENT_MD")"
  TOOLS_SECTION="$(echo "$FRONTMATTER" | awk '/^tools:/{flag=1; next} /^[a-z]/{flag=0} flag')"
  ! echo "$TOOLS_SECTION" | grep -qE '^\s*-\s*(Edit|Write)'
}

@test "specialist-spec-review-structure mentions cross-ref" {
  grep -qE 'cross-ref' "$AGENT_MD"
}

@test "specialist-spec-review-structure mentions R-1" {
  grep -qE 'R-1\b' "$AGENT_MD"
}

@test "specialist-spec-review-structure mentions R-2" {
  grep -qE 'R-2\b' "$AGENT_MD"
}

@test "specialist-spec-review-structure mentions confidence >= 80 filter" {
  grep -qE 'confidence.*80|80.*confidence' "$AGENT_MD"
}

@test "specialist-spec-review-structure mentions Phase F 軸 2" {
  grep -qE 'Phase F.*2|2.*Phase F|軸 2' "$AGENT_MD"
}

@test "specialist-spec-review-structure output category is spec-structure" {
  grep -qE 'spec-structure' "$AGENT_MD"
}
