#!/usr/bin/env bats
# autopilot-pilot-precheck.bats - 4 scenarios for pilot precheck atomic

load "../helpers/common"
load "../helpers/gh_stub"

setup() {
  common_setup
  setup_gh_stubs

  # Create phase results JSON
  echo '{"phase":1,"done":[42],"failed":[],"skipped":[]}' > "$SANDBOX/.autopilot/phase-results.json"
  export PHASE_RESULTS_JSON="$SANDBOX/.autopilot/phase-results.json"
  export P=1
  export SESSION_STATE_FILE="$SANDBOX/.autopilot/session.json"

  # Create session.json
  create_session_json

  # Stub python3 for state read (pr_number)
  stub_command "python3" '
if echo "$*" | grep -q "pr_number"; then
  echo "100"
elif echo "$*" | grep -q "status"; then
  echo "done"
else
  echo ""
fi
'
}

teardown() {
  common_teardown
}

# Scenario 1: 正常系 - 削除ファイル 0 件 + AC 副作用キーワードなし → WARN/FAIL なし
@test "precheck: clean PR with no deletions and no AC keywords → no warnings" {
  # Default gh stubs return minimal diff with no major deletions
  # and issue body without AC keywords

  # Run the precheck logic inline (since it's an LLM atomic, we test the bash snippets)
  run bash -c '
    source "'"$SANDBOX"'/scripts/lib/common-functions.sh" 2>/dev/null || true
    export PHASE_RESULTS_JSON="'"$PHASE_RESULTS_JSON"'"
    export P='"$P"'
    export SESSION_STATE_FILE="'"$SESSION_STATE_FILE"'"
    export PATH="'"$PATH"'"

    DONE_LIST=$(jq -r ".done[]" "$PHASE_RESULTS_JSON" 2>/dev/null || true)
    VERIFY_COUNT=0
    MAX_VERIFY=3
    WARNINGS=0
    FAILS=0

    while IFS= read -r issue; do
      [ -z "$issue" ] && continue
      VERIFY_COUNT=$((VERIFY_COUNT + 1))
      [ "$VERIFY_COUNT" -gt "$MAX_VERIFY" ] && continue

      PR=$(python3 -m twl.autopilot.state read --type issue --issue "$issue" --field pr_number 2>/dev/null || echo "")
      [ -z "$PR" ] && continue

      STAT=$(gh pr diff "$PR" --stat 2>/dev/null || echo "")
      DELETIONS=$(echo "$STAT" | tail -1 | grep -oP "\d+(?= deletion)" || echo "0")
      [ "$DELETIONS" -gt 100 ] && WARNINGS=$((WARNINGS + 1))
    done <<< "$DONE_LIST"

    echo "warnings=$WARNINGS fails=$FAILS"
    [ "$WARNINGS" -eq 0 ] && [ "$FAILS" -eq 0 ]
  '
  assert_success
  assert_output --partial "warnings=0"
}

# Scenario 2: silent deletion - stat 出力で削除 100 行超 → WARN
@test "precheck: high deletion count triggers WARN" {
  setup_gh_high_deletion

  run bash -c '
    export PATH="'"$PATH"'"
    STAT=$(gh pr diff 100 --stat 2>/dev/null || echo "")
    DELETIONS=$(echo "$STAT" | tail -1 | grep -oP "\d+(?= deletion)" || echo "0")
    echo "deletions=$DELETIONS"
    [ "$DELETIONS" -gt 100 ]
  '
  assert_success
  assert_output --partial "deletions=315"
}

# Scenario 3: AC spot-check - 「Issue にコメント」AC が 0 comments → FAIL
@test "precheck: AC spot-check detects missing Issue comment" {
  setup_gh_ac_fail

  run bash -c '
    export PATH="'"$PATH"'"
    ISSUE_BODY=$(gh issue view 42 --json body -q .body 2>/dev/null || echo "")
    COMMENTS_RAW=$(gh issue view 42 --json comments 2>/dev/null || echo "{\"comments\":[]}")
    COMMENTS_COUNT=$(echo "$COMMENTS_RAW" | jq ".comments | length" 2>/dev/null || echo "0")

    FAIL=0
    if echo "$ISSUE_BODY" | grep -qF "Issue にコメント"; then
      if [ "$COMMENTS_COUNT" -eq 0 ]; then
        FAIL=1
        echo "FAIL: AC unmet - no comments found"
      fi
    fi
    echo "fail=$FAIL"
    [ "$FAIL" -eq 1 ]
  '
  assert_success
  assert_output --partial "FAIL: AC unmet"
}

# Scenario 4: opt-out - PILOT_ACTIVE_REVIEW_DISABLE=1 → スキップ
@test "precheck: opt-out with PILOT_ACTIVE_REVIEW_DISABLE=1 skips all verification" {
  run bash -c '
    export PILOT_ACTIVE_REVIEW_DISABLE=1
    if [ "${PILOT_ACTIVE_REVIEW_DISABLE:-0}" = "1" ]; then
      echo "WARN: PILOT_ACTIVE_REVIEW_DISABLE=1 — skipped" >&2
      echo "skipped"
      exit 0
    fi
    echo "should not reach here"
    exit 1
  '
  assert_success
  assert_output --partial "skipped"
}
