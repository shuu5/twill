#!/usr/bin/env bats
# specialist-spec-review-temporal.bats - Phase F 軸 4 agent 静的検証 (C10)
# change 001-spec-purify Specialist phase 4 (b)

load '../helpers/common'

setup() {
  common_setup
  AGENT_MD="$REPO_ROOT/agents/specialist-spec-review-temporal.md"
}

teardown() {
  common_teardown
}

@test "agent file exists" {
  [ -f "$AGENT_MD" ]
}

@test "frontmatter name=twl:specialist-spec-review-temporal" {
  FRONTMATTER="$(extract_frontmatter "$AGENT_MD")"
  echo "$FRONTMATTER" | grep -qE '^name: twl:specialist-spec-review-temporal'
}

@test "frontmatter type=specialist" {
  FRONTMATTER="$(extract_frontmatter "$AGENT_MD")"
  echo "$FRONTMATTER" | grep -qE '^type: specialist'
}

@test "frontmatter model=opus (R-13)" {
  FRONTMATTER="$(extract_frontmatter "$AGENT_MD")"
  echo "$FRONTMATTER" | grep -qE '^model: opus'
}

@test "frontmatter tools includes Read and Grep" {
  FRONTMATTER="$(extract_frontmatter "$AGENT_MD")"
  echo "$FRONTMATTER" | grep -qE '\- Read'
  echo "$FRONTMATTER" | grep -qE '\- Grep'
}

@test "frontmatter skills references ref-specialist-output-schema" {
  FRONTMATTER="$(extract_frontmatter "$AGENT_MD")"
  echo "$FRONTMATTER" | grep -q "ref-specialist-output-schema"
}

@test "content mentions Phase F 軸 4" {
  grep -qE '軸 4' "$AGENT_MD"
}

@test "content uses category spec-temporal" {
  grep -q "spec-temporal" "$AGENT_MD"
}

@test "content mentions R-14 R-15 R-18" {
  grep -q "R-14" "$AGENT_MD"
  grep -q "R-15" "$AGENT_MD"
  grep -q "R-18" "$AGENT_MD"
}

@test "Task tool 使用禁止 mentioned" {
  grep -q "Task tool" "$AGENT_MD"
}

@test "confidence threshold 80 mentioned" {
  grep -qE 'confidence (≥|>=) ?80' "$AGENT_MD"
}
