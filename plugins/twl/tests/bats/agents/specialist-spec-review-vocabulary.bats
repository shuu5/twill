#!/usr/bin/env bats
# specialist-spec-review-vocabulary.bats - agent .md 静的検証 (11 test cases、C7)
# Phase F 軸 1 (用語整合性) for tool-architect 7-phase multi-agent PR cycle、opus 固定 (R-13)

load '../helpers/common'

setup() {
  common_setup
  AGENT_MD="$REPO_ROOT/agents/specialist-spec-review-vocabulary.md"
}

teardown() {
  common_teardown
}

@test "specialist-spec-review-vocabulary file exists" {
  [ -f "$AGENT_MD" ]
}

@test "specialist-spec-review-vocabulary frontmatter has type=specialist" {
  FRONTMATTER="$(extract_frontmatter "$AGENT_MD")"
  echo "$FRONTMATTER" | grep -qE '^type:\s*specialist'
}

@test "specialist-spec-review-vocabulary frontmatter name has twl: prefix" {
  FRONTMATTER="$(extract_frontmatter "$AGENT_MD")"
  echo "$FRONTMATTER" | grep -qE '^name:\s*twl:specialist-spec-review-vocabulary'
}

@test "specialist-spec-review-vocabulary frontmatter model=opus (R-13)" {
  FRONTMATTER="$(extract_frontmatter "$AGENT_MD")"
  echo "$FRONTMATTER" | grep -qE '^model:\s*opus'
}

@test "specialist-spec-review-vocabulary no Edit/Write in tools" {
  FRONTMATTER="$(extract_frontmatter "$AGENT_MD")"
  TOOLS_SECTION="$(echo "$FRONTMATTER" | awk '/^tools:/{flag=1; next} /^[a-z]/{flag=0} flag')"
  ! echo "$TOOLS_SECTION" | grep -qE '^\s*-\s*(Edit|Write)'
}

@test "specialist-spec-review-vocabulary mentions vocabulary term" {
  grep -qE 'vocabulary' "$AGENT_MD"
}

@test "specialist-spec-review-vocabulary mentions forbidden synonym" {
  grep -qE 'forbidden' "$AGENT_MD"
}

@test "specialist-spec-review-vocabulary mentions glossary §11" {
  grep -qE 'glossary.*§11|§11.*glossary|deprecated' "$AGENT_MD"
}

@test "specialist-spec-review-vocabulary mentions confidence >= 80 filter" {
  grep -qE 'confidence.*80|80.*confidence' "$AGENT_MD"
}

@test "specialist-spec-review-vocabulary mentions Phase F 軸 1" {
  grep -qE 'Phase F.*1|1.*Phase F|軸 1' "$AGENT_MD"
}

@test "specialist-spec-review-vocabulary output category is spec-vocabulary" {
  grep -qE 'spec-vocabulary' "$AGENT_MD"
}
