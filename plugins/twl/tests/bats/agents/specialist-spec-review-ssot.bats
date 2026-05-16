#!/usr/bin/env bats
# specialist-spec-review-ssot.bats - agent .md 静的検証 (11 test cases、C7)
# Phase F 軸 3 (SSoT 整合性) for tool-architect 7-phase multi-agent PR cycle、opus 固定 (R-13)

load '../helpers/common'

setup() {
  common_setup
  AGENT_MD="$REPO_ROOT/agents/specialist-spec-review-ssot.md"
}

teardown() {
  common_teardown
}

@test "specialist-spec-review-ssot file exists" {
  [ -f "$AGENT_MD" ]
}

@test "specialist-spec-review-ssot frontmatter has type=specialist" {
  FRONTMATTER="$(sed -n '/^---$/,/^---$/p' "$AGENT_MD")"
  echo "$FRONTMATTER" | grep -qE '^type:\s*specialist'
}

@test "specialist-spec-review-ssot frontmatter name has twl: prefix" {
  FRONTMATTER="$(sed -n '/^---$/,/^---$/p' "$AGENT_MD")"
  echo "$FRONTMATTER" | grep -qE '^name:\s*twl:specialist-spec-review-ssot'
}

@test "specialist-spec-review-ssot frontmatter model=opus (R-13)" {
  FRONTMATTER="$(sed -n '/^---$/,/^---$/p' "$AGENT_MD")"
  echo "$FRONTMATTER" | grep -qE '^model:\s*opus'
}

@test "specialist-spec-review-ssot no Edit/Write in tools" {
  FRONTMATTER="$(sed -n '/^---$/,/^---$/p' "$AGENT_MD")"
  TOOLS_SECTION="$(echo "$FRONTMATTER" | awk '/^tools:/{flag=1; next} /^[a-z]/{flag=0} flag')"
  ! echo "$TOOLS_SECTION" | grep -qE '^\s*-\s*(Edit|Write)'
}

@test "specialist-spec-review-ssot mentions ADR" {
  grep -qE 'ADR' "$AGENT_MD"
}

@test "specialist-spec-review-ssot mentions 不変条件 (Invariant)" {
  grep -qE '不変条件|invariant' "$AGENT_MD"
}

@test "specialist-spec-review-ssot mentions EXP" {
  grep -qE 'EXP-?[0-9]|experiment-index' "$AGENT_MD"
}

@test "specialist-spec-review-ssot mentions registry-schema" {
  grep -qE 'registry-schema|registry\.yaml' "$AGENT_MD"
}

@test "specialist-spec-review-ssot mentions Phase F 軸 3" {
  grep -qE 'Phase F.*3|3.*Phase F|軸 3' "$AGENT_MD"
}

@test "specialist-spec-review-ssot output category is spec-ssot" {
  grep -qE 'spec-ssot' "$AGENT_MD"
}
