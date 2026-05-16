#!/usr/bin/env bats
# specialist-spec-architect.bats - agent .md 静的検証 (10 test cases、C7)
# Phase D agent for tool-architect 7-phase multi-agent PR cycle

load '../helpers/common'

setup() {
  common_setup
  AGENT_MD="$REPO_ROOT/agents/specialist-spec-architect.md"
}

teardown() {
  common_teardown
}

@test "specialist-spec-architect file exists" {
  [ -f "$AGENT_MD" ]
}

@test "specialist-spec-architect frontmatter has type=specialist" {
  FRONTMATTER="$(extract_frontmatter "$AGENT_MD")"
  echo "$FRONTMATTER" | grep -qE '^type:\s*specialist'
}

@test "specialist-spec-architect frontmatter name has twl: prefix" {
  FRONTMATTER="$(extract_frontmatter "$AGENT_MD")"
  echo "$FRONTMATTER" | grep -qE '^name:\s*twl:specialist-spec-architect'
}

@test "specialist-spec-architect frontmatter model=sonnet" {
  FRONTMATTER="$(extract_frontmatter "$AGENT_MD")"
  echo "$FRONTMATTER" | grep -qE '^model:\s*sonnet'
}

@test "specialist-spec-architect no Edit/Write in tools" {
  FRONTMATTER="$(extract_frontmatter "$AGENT_MD")"
  TOOLS_SECTION="$(echo "$FRONTMATTER" | awk '/^tools:/{flag=1; next} /^[a-z]/{flag=0} flag')"
  ! echo "$TOOLS_SECTION" | grep -qE '^\s*-\s*(Edit|Write)'
}

@test "specialist-spec-architect mentions minimal blueprint option" {
  grep -qE 'minimal' "$AGENT_MD"
}

@test "specialist-spec-architect mentions clean blueprint option" {
  grep -qE 'clean' "$AGENT_MD"
}

@test "specialist-spec-architect mentions pragmatic blueprint option" {
  grep -qE 'pragmatic' "$AGENT_MD"
}

@test "specialist-spec-architect mentions Phase D context" {
  grep -qE 'Phase D' "$AGENT_MD"
}

@test "specialist-spec-architect skills includes ref-specialist-output-schema" {
  FRONTMATTER="$(extract_frontmatter "$AGENT_MD")"
  echo "$FRONTMATTER" | grep -qE 'ref-specialist-output-schema'
}
