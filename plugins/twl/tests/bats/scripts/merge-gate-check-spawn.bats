#!/usr/bin/env bats
# merge-gate-check-spawn.bats - unit tests for scripts/merge-gate-check-spawn.sh
# Generated from: deltaspec/changes/issue-680/specs/merge-gate-refactor.md
# Requirement: spawn 完了確認スクリプト抽出
# Coverage: unit + edge-cases

load '../helpers/common'

setup() {
  common_setup
  export CLAUDE_PLUGIN_ROOT="$SANDBOX"

  # Create temp files for MANIFEST_FILE and SPAWNED_FILE
  MANIFEST_FILE="$(mktemp /tmp/test-manifest-XXXXXXXX.txt)"
  SPAWNED_FILE="/tmp/.specialist-spawned-$(basename "$MANIFEST_FILE" .txt).txt"
  export MANIFEST_FILE
  export SPAWNED_FILE
}

teardown() {
  common_teardown
  rm -f "$MANIFEST_FILE" "$SPAWNED_FILE" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Requirement: spawn 完了確認スクリプト抽出
# ---------------------------------------------------------------------------

@test "merge-gate-check-spawn.sh が存在する" {
  [[ -f "$SANDBOX/scripts/merge-gate-check-spawn.sh" ]]
}

@test "merge-gate-check-spawn.sh が実行可能である" {
  [[ -x "$SANDBOX/scripts/merge-gate-check-spawn.sh" ]]
}

@test "merge-gate-check-spawn.sh が bash 構文チェック pass" {
  bash -n "$SANDBOX/scripts/merge-gate-check-spawn.sh"
}

# ---------------------------------------------------------------------------
# Scenario: spawn 確認スクリプト実行 — 全員完了の場合は成功メッセージを出力すること
# WHEN: bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-check-spawn.sh" が呼び出される
#       (MANIFEST_FILE と SPAWNED_FILE が環境変数で渡される)
# THEN: 未 spawn の specialist がある場合は ERROR を出力してスクリプトを終了し、
#       全員完了の場合は成功メッセージを出力すること
# ---------------------------------------------------------------------------

@test "全 specialist が spawn 済みの場合は exit 0 を返す" {
  echo "twl:worker-code-reviewer" > "$MANIFEST_FILE"
  echo "worker-code-reviewer" > "$SPAWNED_FILE"

  run bash "$SANDBOX/scripts/merge-gate-check-spawn.sh"

  assert_success
}

@test "全 specialist が spawn 済みの場合は成功メッセージを出力する" {
  echo "twl:worker-code-reviewer" > "$MANIFEST_FILE"
  echo "worker-code-reviewer" > "$SPAWNED_FILE"

  run bash "$SANDBOX/scripts/merge-gate-check-spawn.sh"

  assert_success
  # 成功確認メッセージの存在を検証
  assert_output --partial "✓"
}

@test "未 spawn の specialist がある場合は exit 1 を返す" {
  echo "twl:worker-code-reviewer" > "$MANIFEST_FILE"
  echo "twl:worker-security-reviewer" >> "$MANIFEST_FILE"
  # SPAWNED_FILE にはコードレビュアーのみ記録
  echo "worker-code-reviewer" > "$SPAWNED_FILE"

  run bash "$SANDBOX/scripts/merge-gate-check-spawn.sh"

  assert_failure
}

@test "未 spawn の specialist がある場合は ERROR を出力する" {
  echo "twl:worker-code-reviewer" > "$MANIFEST_FILE"
  echo "twl:worker-security-reviewer" >> "$MANIFEST_FILE"
  echo "worker-code-reviewer" > "$SPAWNED_FILE"

  run bash "$SANDBOX/scripts/merge-gate-check-spawn.sh" 2>&1

  assert_output --partial "ERROR"
}

@test "未 spawn の specialist 名が出力に含まれる" {
  echo "twl:worker-security-reviewer" > "$MANIFEST_FILE"
  # SPAWNED_FILE は空（未 spawn）
  touch "$SPAWNED_FILE"

  run bash "$SANDBOX/scripts/merge-gate-check-spawn.sh" 2>&1

  assert_output --partial "worker-security-reviewer"
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "[edge] MANIFEST_FILE が未設定の場合はエラーで終了する" {
  unset MANIFEST_FILE

  run bash "$SANDBOX/scripts/merge-gate-check-spawn.sh"

  assert_failure
}

@test "[edge] SPAWNED_FILE が存在しない場合は全員未 spawn として扱う" {
  echo "twl:worker-code-reviewer" > "$MANIFEST_FILE"
  rm -f "$SPAWNED_FILE"

  run bash "$SANDBOX/scripts/merge-gate-check-spawn.sh"

  assert_failure
}

@test "[edge] MANIFEST_FILE がコメント行（#）を含む場合も正しく処理する" {
  cat > "$MANIFEST_FILE" <<'EOF'
# This is a comment
twl:worker-code-reviewer
EOF
  echo "worker-code-reviewer" > "$SPAWNED_FILE"

  run bash "$SANDBOX/scripts/merge-gate-check-spawn.sh"

  assert_success
}

@test "[edge] MANIFEST_FILE が空行を含む場合も正しく処理する" {
  cat > "$MANIFEST_FILE" <<'EOF'

twl:worker-code-reviewer

EOF
  echo "worker-code-reviewer" > "$SPAWNED_FILE"

  run bash "$SANDBOX/scripts/merge-gate-check-spawn.sh"

  assert_success
}

@test "[edge] スクリプトが twl: プレフィックスを除去して比較する" {
  grep -qP '(twl:|sed.*twl|s\|.*twl)' \
    "$SANDBOX/scripts/merge-gate-check-spawn.sh"
}

@test "[edge] スクリプトが comm または diff でリストを比較する" {
  grep -qP '(comm|diff.*spawn|MISSING)' \
    "$SANDBOX/scripts/merge-gate-check-spawn.sh"
}
