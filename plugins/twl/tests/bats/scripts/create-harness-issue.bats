#!/usr/bin/env bats
# create-harness-issue.bats - unit tests for scripts/create-harness-issue.sh

load '../helpers/common'

setup() {
  common_setup
  stub_command "gh" '
    case "$*" in
      *"issue list"*)
        echo "[]" ;;
      *"label create"*)
        exit 0 ;;
      *"issue create"*)
        echo "https://github.com/shuu5/ubuntu-note-system/issues/999" ;;
      *"pr view"*)
        echo "42" ;;
      *)
        exit 0 ;;
    esac
  '
  stub_command "git" '
    case "$*" in
      *"rev-parse --show-toplevel"*)
        echo "/tmp/test-project" ;;
      *"rev-parse --short HEAD"*)
        echo "abc1234" ;;
      *"rev-parse --git-common-dir"*)
        echo "/tmp/test-project/.bare" ;;
      *)
        exit 0 ;;
    esac
  '
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: create-harness-issue
# ---------------------------------------------------------------------------

@test "create-harness-issue fails without snapshot-dir" {
  run bash "$SANDBOX/scripts/create-harness-issue.sh"

  assert_failure
  assert_output --partial "Usage"
}

@test "create-harness-issue rejects snapshot-dir outside /tmp/" {
  run bash "$SANDBOX/scripts/create-harness-issue.sh" "$SANDBOX/snapshot"

  assert_failure
  assert_output --partial "/tmp/"
}

@test "create-harness-issue skips non-harness classification" {
  local snap="$SANDBOX/test-harness-$$"
  mkdir -p "$snap"
  cat > "$snap/05.5-failure-classification.json" <<'JSON'
{"classification": "code", "confidence": 80, "component": "src/main.ts", "evidence": ["test error"], "issue_url": null}
JSON

  run bash "$SANDBOX/scripts/create-harness-issue.sh" "$snap"

  assert_success
  assert_output --partial "harness ではありません"

  rm -rf "$snap"
}

@test "create-harness-issue skips low confidence" {
  local snap="$SANDBOX/test-harness-$$"
  mkdir -p "$snap"
  cat > "$snap/05.5-failure-classification.json" <<'JSON'
{"classification": "harness", "confidence": 50, "component": "test.sh", "evidence": ["test error"], "issue_url": null}
JSON

  run bash "$SANDBOX/scripts/create-harness-issue.sh" "$snap"

  assert_success
  assert_output --partial "confidence不足"

  rm -rf "$snap"
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "create-harness-issue creates issue for high-confidence harness" {
  local snap="$SANDBOX/test-harness-$$"
  mkdir -p "$snap"
  cat > "$snap/05.5-failure-classification.json" <<'JSON'
{"classification": "harness", "confidence": 80, "component": "scripts/test.sh", "evidence": ["SKILL.md error"], "issue_url": null}
JSON

  run bash "$SANDBOX/scripts/create-harness-issue.sh" "$snap"

  assert_success
  assert_output --partial "Issue作成完了"

  # Verify issue_url was written back
  jq -e '.issue_url != null' "$snap/05.5-failure-classification.json" > /dev/null

  rm -rf "$snap"
}

@test "create-harness-issue skips if duplicate issue exists" {
  local snap="$SANDBOX/test-harness-$$"
  mkdir -p "$snap"
  cat > "$snap/05.5-failure-classification.json" <<'JSON'
{"classification": "harness", "confidence": 80, "component": "scripts/test.sh", "evidence": ["error"], "issue_url": null}
JSON

  stub_command "gh" '
    case "$*" in
      *"issue list"*)
        echo "[{\"number\": 100, \"url\": \"https://github.com/test/issues/100\"}]" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/create-harness-issue.sh" "$snap"

  assert_success
  assert_output --partial "重複Issue検出"

  rm -rf "$snap"
}

@test "create-harness-issue fails when classification file is missing" {
  local snap="$SANDBOX/test-harness-$$"
  mkdir -p "$snap"
  # No classification file

  run bash "$SANDBOX/scripts/create-harness-issue.sh" "$snap"

  assert_failure
  assert_output --partial "分類結果ファイルが見つかりません"

  rm -rf "$snap"
}
