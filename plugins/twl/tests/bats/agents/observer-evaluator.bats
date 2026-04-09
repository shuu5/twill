#!/usr/bin/env bats
# observer-evaluator.bats - agent .md の静的検証 (4 test cases)

load '../helpers/common'

setup() {
  common_setup
  AGENT_MD="$REPO_ROOT/agents/observer-evaluator.md"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# 1. frontmatter: type=specialist, model=sonnet
# ---------------------------------------------------------------------------

@test "observer-evaluator frontmatter has type=specialist and model=sonnet" {
  # Extract frontmatter (between --- markers)
  FRONTMATTER="$(sed -n '/^---$/,/^---$/p' "$AGENT_MD")"

  echo "$FRONTMATTER" | grep -qE '^type:\s*specialist'
  echo "$FRONTMATTER" | grep -qE '^model:\s*sonnet'
}

# ---------------------------------------------------------------------------
# 2. 入力スキーマ記載: --input (必須) + --context (optional)
# ---------------------------------------------------------------------------

@test "observer-evaluator documents --input as required and --context as optional" {
  CONTENT="$(cat "$AGENT_MD")"

  echo "$CONTENT" | grep -q '\-\-input'
  echo "$CONTENT" | grep -qi 'required\|必須'
  echo "$CONTENT" | grep -q '\-\-context'
  echo "$CONTENT" | grep -qi 'optional'
}

# ---------------------------------------------------------------------------
# 3. 引用 MUST 記載: quote field 必須
# ---------------------------------------------------------------------------

@test "observer-evaluator documents quote field as MUST" {
  CONTENT="$(cat "$AGENT_MD")"

  # Must contain "quote" AND "MUST" in the document
  echo "$CONTENT" | grep -qi 'quote.*must\|must.*quote'
}

# ---------------------------------------------------------------------------
# 4. confidence 上限記載: confidence <= 75
# ---------------------------------------------------------------------------

@test "observer-evaluator documents confidence upper limit of 75" {
  CONTENT="$(cat "$AGENT_MD")"

  # Must reference confidence cap at 75
  echo "$CONTENT" | grep -qE 'confidence.*75|75.*confidence'
}
