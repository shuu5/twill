#!/usr/bin/env bats
# externalize-state-exit-gate.bats — unit tests for scripts/externalize-state-exit-gate.sh
#
# Spec: Issue #829 — externalize-state.md に exit gate 追加
#
# Coverage:
#   1. session.json 不在 → exit 2
#   2. externalization_log なし → exit 1 + WARN
#   3. pitfall_declaration 未設定 → exit 1 + WARN
#   4. pitfall_declaration="none" (0件宣言) → exit 0
#   5. pitfall_declaration="2-items" (ハッシュ付き) → exit 0

load '../helpers/common'

SCRIPT_NAME="externalize-state-exit-gate.sh"

setup() {
  common_setup
  cp "$REPO_ROOT/scripts/${SCRIPT_NAME}" "$SANDBOX/scripts/"
  chmod +x "$SANDBOX/scripts/${SCRIPT_NAME}"
  SCRIPT="$SANDBOX/scripts/${SCRIPT_NAME}"
  SESSION_JSON="$SANDBOX/.autopilot/session.json"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Test 1: session.json 不在 → exit 2
# ---------------------------------------------------------------------------

@test "session.json 不在のとき exit 2 を返す" {
  run bash "$SCRIPT" "test-session" "${SANDBOX}/.autopilot/nonexistent.json"
  assert_failure 2
  assert_output --partial "見つかりません"
}

# ---------------------------------------------------------------------------
# Test 2: externalization_log が空 → exit 1 + WARN
# ---------------------------------------------------------------------------

@test "externalization_log が空のとき exit 1 と WARN を返す" {
  jq -n '{
    session_id: "test1234",
    externalization_log: []
  }' > "$SESSION_JSON"

  run bash "$SCRIPT" "test-session" "$SESSION_JSON"
  assert_failure 1
  assert_output --partial "pitfall_declaration"
}

# ---------------------------------------------------------------------------
# Test 3: pitfall_declaration フィールドなし → exit 1 + WARN
# ---------------------------------------------------------------------------

@test "pitfall_declaration が未設定のとき exit 1 と WARN を返す" {
  jq -n '{
    session_id: "test1234",
    externalization_log: [
      {
        externalized_at: "2026-04-22T00:00:00Z",
        trigger: "manual",
        output_path: "/tmp/test.md"
      }
    ]
  }' > "$SESSION_JSON"

  run bash "$SCRIPT" "test-session" "$SESSION_JSON"
  assert_failure 1
  assert_output --partial "pitfall_declaration"
}

# ---------------------------------------------------------------------------
# Test 4: pitfall_declaration="none" (0 件宣言) → exit 0
# ---------------------------------------------------------------------------

@test "pitfall_declaration=none のとき exit 0 を返す" {
  jq -n '{
    session_id: "test1234",
    externalization_log: [
      {
        externalized_at: "2026-04-22T00:00:00Z",
        trigger: "wave_complete",
        output_path: "/tmp/wave-1-summary.md",
        new_pitfall_hashes: [],
        pitfall_declaration: "none"
      }
    ]
  }' > "$SESSION_JSON"

  run bash "$SCRIPT" "test-session" "$SESSION_JSON"
  assert_success
  assert_output --partial "記録済"
}

# ---------------------------------------------------------------------------
# Test 5: pitfall_declaration="2-items" (ハッシュ付き) → exit 0
# ---------------------------------------------------------------------------

@test "pitfall_declaration=2-items のとき exit 0 と hash を返す" {
  jq -n '{
    session_id: "test1234",
    externalization_log: [
      {
        externalized_at: "2026-04-22T00:00:00Z",
        trigger: "wave_complete",
        output_path: "/tmp/wave-1-summary.md",
        new_pitfall_hashes: ["abc123", "def456"],
        pitfall_declaration: "2-items"
      }
    ]
  }' > "$SESSION_JSON"

  run bash "$SCRIPT" "test-session" "$SESSION_JSON"
  assert_success
  assert_output --partial "記録済"
  assert_output --partial "2-items"
}
