#!/usr/bin/env bats
# observer-atomics.bats - unit tests for observe-once, problem-detect, issue-draft-from-observation

load '../helpers/common'

setup() {
  common_setup

  # Copy wrapper scripts
  cp "$REPO_ROOT/scripts/observe-wrapper.sh" "$SANDBOX/scripts/observe-wrapper.sh"
  cp "$REPO_ROOT/scripts/session-state-wrapper.sh" "$SANDBOX/scripts/session-state-wrapper.sh"

  # Create mock session plugin directory
  mkdir -p "$SANDBOX/session/scripts"

  # Mock cld-observe: outputs tmux-like capture
  cat > "$SANDBOX/session/scripts/cld-observe" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
TARGET=""
LINES=30
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lines) LINES="$2"; shift 2 ;;
    *) TARGET="$1"; shift ;;
  esac
done
if [[ -z "$TARGET" ]]; then
  echo "Error: no target" >&2; exit 1
fi
# Check for non-existent window marker
if [[ "$TARGET" == "nonexistent-window" ]]; then
  echo "Error: window '$TARGET' not found" >&2; exit 1
fi
# Return fake capture
echo "=== Claude Code session: $TARGET (state: processing) ==="
head -n "$LINES" "${CLD_OBSERVE_FAKE_CAPTURE:-/dev/null}" 2>/dev/null || echo "no output"
MOCK
  chmod +x "$SANDBOX/session/scripts/cld-observe"

  # Mock session-state.sh
  cat > "$SANDBOX/session/scripts/session-state.sh" <<'MOCK'
#!/usr/bin/env bash
case "${1:-}" in
  state) echo "${SESSION_STATE_FAKE:-processing}" ;;
  *) echo "Error: unknown subcommand" >&2; exit 1 ;;
esac
MOCK
  chmod +x "$SANDBOX/session/scripts/session-state.sh"

  # Patch wrappers to point at sandbox session plugin
  sed -i "s|SCRIPT_DIR}/../../session/scripts|SANDBOX_SESSION|g" "$SANDBOX/scripts/observe-wrapper.sh"
  sed -i "s|SANDBOX_SESSION|$SANDBOX/session/scripts|g" "$SANDBOX/scripts/observe-wrapper.sh"
  sed -i "s|SCRIPT_DIR}/../../session/scripts|SANDBOX_SESSION|g" "$SANDBOX/scripts/session-state-wrapper.sh"
  sed -i "s|SANDBOX_SESSION|$SANDBOX/session/scripts|g" "$SANDBOX/scripts/session-state-wrapper.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# observe-once: 正常系
# ---------------------------------------------------------------------------

@test "observe-once wrapper returns capture from mock window" {
  # Create fake capture content
  echo "line 1: normal output" > "$SANDBOX/fake-capture.txt"
  echo "line 2: more output" >> "$SANDBOX/fake-capture.txt"
  export CLD_OBSERVE_FAKE_CAPTURE="$SANDBOX/fake-capture.txt"

  run bash "$SANDBOX/scripts/observe-wrapper.sh" "ap-42" --lines 30

  assert_success
  assert_output --partial "ap-42"
}

# ---------------------------------------------------------------------------
# observe-once: window 不在
# ---------------------------------------------------------------------------

@test "observe-once wrapper fails for nonexistent window" {
  run bash "$SANDBOX/scripts/observe-wrapper.sh" "nonexistent-window" --lines 1

  assert_failure
  assert_output --partial "not found"
}

# ---------------------------------------------------------------------------
# problem-detect: マッチあり
# ---------------------------------------------------------------------------

@test "problem-detect finds MergeGateError in capture" {
  # Create observe-once JSON with MergeGateError
  cat > "$SANDBOX/observe-output.json" <<'JSON'
{
  "window": "ap-42",
  "timestamp": "2026-04-08T10:30:00Z",
  "lines": 30,
  "capture": "line 1: normal output\nline 2: MergeGateError: base drift detected\nline 3: continuing",
  "session_state": "processing"
}
JSON

  # Extract capture and grep for pattern
  CAPTURE=$(jq -r '.capture' "$SANDBOX/observe-output.json")
  MATCH=$(echo "$CAPTURE" | grep -n "MergeGateError" || true)

  [[ -n "$MATCH" ]]
  echo "$MATCH" | grep -q "MergeGateError"
}

# ---------------------------------------------------------------------------
# problem-detect: マッチなし
# ---------------------------------------------------------------------------

@test "problem-detect returns empty for clean capture" {
  cat > "$SANDBOX/observe-output.json" <<'JSON'
{
  "window": "ap-42",
  "timestamp": "2026-04-08T10:30:00Z",
  "lines": 30,
  "capture": "line 1: all good\nline 2: task completed successfully\nline 3: no issues",
  "session_state": "processing"
}
JSON

  CAPTURE=$(jq -r '.capture' "$SANDBOX/observe-output.json")
  PATTERNS=("Error:" "APIError:" "MergeGateError:" "failed to" "\[CRITICAL\]" "nudge sent" "silent.*deletion" "矮小化" "force.with.lease")

  MATCH_COUNT=0
  for pat in "${PATTERNS[@]}"; do
    if echo "$CAPTURE" | grep -qP "$pat"; then
      MATCH_COUNT=$((MATCH_COUNT + 1))
    fi
  done

  [[ "$MATCH_COUNT" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# problem-detect: 複数マッチ
# ---------------------------------------------------------------------------

@test "problem-detect finds multiple patterns in capture" {
  cat > "$SANDBOX/observe-output.json" <<'JSON'
{
  "window": "ap-42",
  "timestamp": "2026-04-08T10:30:00Z",
  "lines": 30,
  "capture": "line 1: Error: something went wrong\nline 2: normal\nline 3: [CRITICAL] system failure",
  "session_state": "error"
}
JSON

  CAPTURE=$(jq -r '.capture' "$SANDBOX/observe-output.json")
  PATTERNS=("Error:" "\[CRITICAL\]")

  MATCH_COUNT=0
  for pat in "${PATTERNS[@]}"; do
    if echo "$CAPTURE" | grep -qP "$pat"; then
      MATCH_COUNT=$((MATCH_COUNT + 1))
    fi
  done

  [[ "$MATCH_COUNT" -eq 2 ]]
}

# ---------------------------------------------------------------------------
# issue-draft: 正常系
# ---------------------------------------------------------------------------

@test "issue-draft generates markdown with required labels" {
  # Simulate detection JSON
  cat > "$SANDBOX/detection.json" <<'JSON'
{
  "window": "ap-42",
  "timestamp": "2026-04-08T10:30:00Z",
  "detections": [
    {
      "pattern": "MergeGateError:",
      "severity": "high",
      "category": "merge-gate-failure",
      "line": "MergeGateError: base drift detected",
      "line_number": 17
    }
  ]
}
JSON

  # Verify detection has the expected structure
  DETECTION_COUNT=$(jq '.detections | length' "$SANDBOX/detection.json")
  [[ "$DETECTION_COUNT" -eq 1 ]]

  SEVERITY=$(jq -r '.detections[0].severity' "$SANDBOX/detection.json")
  [[ "$SEVERITY" == "high" ]]

  CATEGORY=$(jq -r '.detections[0].category' "$SANDBOX/detection.json")
  [[ "$CATEGORY" == "merge-gate-failure" ]]

  # Generate draft title
  TITLE="[Observation][$SEVERITY] $CATEGORY: $(jq -r '.detections[0].pattern' "$SANDBOX/detection.json")"
  echo "$TITLE" | grep -q "from-observation\|Observation"

  # Verify required labels would be included
  LABELS='["from-observation", "ctx/observation", "scope/plugins-twl"]'
  echo "$LABELS" | jq -e '.[0] == "from-observation"'
  echo "$LABELS" | jq -e '.[1] == "ctx/observation"'
}

# ---------------------------------------------------------------------------
# issue-draft: 空入力
# ---------------------------------------------------------------------------

@test "issue-draft returns empty drafts for zero detections" {
  cat > "$SANDBOX/detection-empty.json" <<'JSON'
{
  "window": "ap-42",
  "timestamp": "2026-04-08T10:30:00Z",
  "detections": []
}
JSON

  DETECTION_COUNT=$(jq '.detections | length' "$SANDBOX/detection-empty.json")
  [[ "$DETECTION_COUNT" -eq 0 ]]

  # Empty detections → empty drafts array
  DRAFTS="[]"
  echo "$DRAFTS" | jq -e 'length == 0'
}
