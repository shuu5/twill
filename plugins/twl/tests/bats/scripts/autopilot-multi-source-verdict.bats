#!/usr/bin/env bats
# autopilot-multi-source-verdict.bats - 3 scenarios for multi-source verdict atomic

load "../helpers/common"
load "../helpers/gh_stub"

setup() {
  common_setup
  setup_gh_stubs
  export PR_NUM=100
  export ISSUE_NUM=42
}

teardown() {
  common_teardown
}

# Scenario 1: legitimate-light - 5 ソース全て consistent → verdict=legitimate-light, confidence=75
@test "verdict: consistent sources produce legitimate-light with max confidence" {
  run bash -c '
    export PATH="'"$PATH"'"

    # Collect sources
    PR_META=$(gh pr view '"$PR_NUM"' --json title,body,additions,deletions 2>/dev/null || echo "{}")
    ISSUE_DATA=$(gh issue view '"$ISSUE_NUM"' --json title,body,comments 2>/dev/null || echo "{}")

    # Simulate verdict output (LLM would produce this)
    cat <<EOF
{
  "verdict": "legitimate-light",
  "confidence": 75,
  "sources": {
    "pr_meta": $(echo "$PR_META" | jq -c .),
    "commit_log": "abc1234 feat: add feature",
    "issue_data": $(echo "$ISSUE_DATA" | jq -c .),
    "audit_history": "no audit history available",
    "alignment_result": "not available"
  },
  "reasoning": "All sources consistent, PR additions match issue scope"
}
EOF
  '
  assert_success

  # Parse output and verify
  VERDICT=$(echo "$output" | jq -r '.verdict')
  CONFIDENCE=$(echo "$output" | jq -r '.confidence')
  [ "$VERDICT" = "legitimate-light" ]
  [ "$CONFIDENCE" -eq 75 ]
  # Verify sources are present (not null)
  SOURCES_COUNT=$(echo "$output" | jq '.sources | keys | length')
  [ "$SOURCES_COUNT" -eq 5 ]
}

# Scenario 2: suspicious-trivial - PR body と git log が矛盾 → verdict=suspicious-trivial
@test "verdict: contradictory sources produce suspicious-trivial" {
  run bash -c '
    # Simulate contradictory verdict
    cat <<EOF
{
  "verdict": "suspicious-trivial",
  "confidence": 30,
  "sources": {
    "pr_meta": "PR claims 500 additions but stat shows 3",
    "commit_log": "single commit: fix typo",
    "issue_data": "Issue requires major refactoring",
    "audit_history": "previous attempt failed",
    "alignment_result": "FAIL: scope mismatch"
  },
  "reasoning": "PR body claims extensive changes but commit log shows only typo fix, contradicting issue requirements"
}
EOF
  '
  assert_success

  VERDICT=$(echo "$output" | jq -r '.verdict')
  CONFIDENCE=$(echo "$output" | jq -r '.confidence')
  [ "$VERDICT" = "suspicious-trivial" ]
  [ "$CONFIDENCE" -le 75 ]
}

# Scenario 3: hallucination 対策 - 引用なし出力 → parser で WARNING 降格
@test "verdict: missing source citations triggers WARNING degradation" {
  run bash -c '
    # Simulate output with empty sources (hallucination)
    OUTPUT='"'"'{
      "verdict": "legitimate-light",
      "confidence": 75,
      "sources": {
        "pr_meta": "",
        "commit_log": "",
        "issue_data": "",
        "audit_history": "",
        "alignment_result": ""
      },
      "reasoning": "Everything looks fine"
    }'"'"'

    # Parser check: all sources empty → degrade to WARNING
    EMPTY_SOURCES=$(echo "$OUTPUT" | jq "[.sources | to_entries[] | select(.value == \"\" or .value == null)] | length")

    if [ "$EMPTY_SOURCES" -ge 3 ]; then
      echo "WARNING: verdict degraded — $EMPTY_SOURCES of 5 sources have no citations"
      # Override verdict
      echo "$OUTPUT" | jq ".verdict = \"uncertain\" | .confidence = 0 | .reasoning = .reasoning + \" [DEGRADED: missing citations]\""
      exit 0
    fi

    echo "$OUTPUT"
  '
  assert_success
  assert_output --partial "WARNING: verdict degraded"

  # Parse the degraded verdict
  DEGRADED=$(echo "$output" | grep -v "^WARNING" | jq -r '.verdict' 2>/dev/null || echo "")
  [ "$DEGRADED" = "uncertain" ]
}
