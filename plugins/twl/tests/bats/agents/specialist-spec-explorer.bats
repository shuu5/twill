#!/usr/bin/env bats
# specialist-spec-explorer.bats - agent .md 静的検証 (12 test cases、C7)
# Phase B agent for tool-architect 7-phase multi-agent PR cycle

load '../helpers/common'

setup() {
  common_setup
  AGENT_MD="$REPO_ROOT/agents/specialist-spec-explorer.md"
}

teardown() {
  common_teardown
}

@test "specialist-spec-explorer file exists" {
  [ -f "$AGENT_MD" ]
}

@test "specialist-spec-explorer frontmatter has type=specialist" {
  FRONTMATTER="$(extract_frontmatter "$AGENT_MD")"
  echo "$FRONTMATTER" | grep -qE '^type:\s*specialist'
}

@test "specialist-spec-explorer frontmatter name has twl: prefix" {
  FRONTMATTER="$(extract_frontmatter "$AGENT_MD")"
  echo "$FRONTMATTER" | grep -qE '^name:\s*twl:specialist-spec-explorer'
}

@test "specialist-spec-explorer frontmatter model=sonnet" {
  FRONTMATTER="$(extract_frontmatter "$AGENT_MD")"
  echo "$FRONTMATTER" | grep -qE '^model:\s*sonnet'
}

@test "specialist-spec-explorer frontmatter tools field exists" {
  FRONTMATTER="$(extract_frontmatter "$AGENT_MD")"
  echo "$FRONTMATTER" | grep -q '^tools:'
}

@test "specialist-spec-explorer no Edit in tools (Read-only enforcement)" {
  FRONTMATTER="$(extract_frontmatter "$AGENT_MD")"
  TOOLS_SECTION="$(echo "$FRONTMATTER" | awk '/^tools:/{flag=1; next} /^[a-z]/{flag=0} flag')"
  ! echo "$TOOLS_SECTION" | grep -qE '^\s*-\s*Edit'
}

@test "specialist-spec-explorer no Write in tools (Read-only enforcement)" {
  FRONTMATTER="$(extract_frontmatter "$AGENT_MD")"
  TOOLS_SECTION="$(echo "$FRONTMATTER" | awk '/^tools:/{flag=1; next} /^[a-z]/{flag=0} flag')"
  ! echo "$TOOLS_SECTION" | grep -qE '^\s*-\s*Write'
}

@test "specialist-spec-explorer body is non-empty" {
  BODY_LINES="$(awk 'BEGIN{c=0} /^---$/{c++; next} c==2{print}' "$AGENT_MD" | wc -l)"
  [ "$BODY_LINES" -ge 50 ]
}

@test "specialist-spec-explorer NotebookRead in tools" {
  FRONTMATTER="$(extract_frontmatter "$AGENT_MD")"
  echo "$FRONTMATTER" | grep -qE 'NotebookRead'
}

@test "specialist-spec-explorer output mentions key files listing" {
  grep -qE '5-10 key files|files_to_inspect' "$AGENT_MD"
}

@test "specialist-spec-explorer mentions Phase B context" {
  grep -qE 'Phase B' "$AGENT_MD"
}

@test "specialist-spec-explorer skills includes ref-specialist-output-schema" {
  FRONTMATTER="$(extract_frontmatter "$AGENT_MD")"
  echo "$FRONTMATTER" | grep -qE 'ref-specialist-output-schema'
}
