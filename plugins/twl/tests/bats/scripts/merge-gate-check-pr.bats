#!/usr/bin/env bats
# merge-gate-check-pr.bats - unit tests for scripts/merge-gate-check-pr.sh
# Generated from: deltaspec/changes/issue-680/specs/merge-gate-refactor.md
# Requirement: PR 存在確認スクリプト抽出
# Coverage: unit + edge-cases

load '../helpers/common'

setup() {
  common_setup
  export CLAUDE_PLUGIN_ROOT="$SANDBOX"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: PR 存在確認スクリプト抽出
# ---------------------------------------------------------------------------

@test "merge-gate-check-pr.sh が存在する" {
  [[ -f "$SANDBOX/scripts/merge-gate-check-pr.sh" ]]
}

@test "merge-gate-check-pr.sh が実行可能である" {
  [[ -x "$SANDBOX/scripts/merge-gate-check-pr.sh" ]]
}

@test "merge-gate-check-pr.sh が bash 構文チェック pass" {
  bash -n "$SANDBOX/scripts/merge-gate-check-pr.sh"
}

# ---------------------------------------------------------------------------
# Scenario: PR 存在確認スクリプト実行 — PR が存在しない場合は exit 1 を返し REJECT checkpoint を書き込む
# WHEN: bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-check-pr.sh" が呼び出される
# THEN: PR が存在しない場合は exit 1 を返し、REJECT checkpoint を書き込むこと
# ---------------------------------------------------------------------------

@test "PR が存在しない場合 exit 1 を返す" {
  stub_command "gh" '
    case "$*" in
      *"pr view"*)
        echo ""
        exit 1 ;;
      *)
        exit 1 ;;
    esac
  '
  stub_command "python3" 'exit 0'

  run bash "$SANDBOX/scripts/merge-gate-check-pr.sh"

  assert_failure
}

@test "PR が存在しない場合 REJECT メッセージを stderr に出力する" {
  stub_command "gh" '
    case "$*" in
      *"pr view"*)
        echo ""
        exit 1 ;;
      *)
        exit 1 ;;
    esac
  '
  stub_command "python3" 'exit 0'

  run bash "$SANDBOX/scripts/merge-gate-check-pr.sh" 2>&1

  assert_output --partial "REJECT"
}

@test "PR が存在する場合は exit 0 を返す" {
  stub_command "gh" '
    case "$*" in
      *"pr view"*)
        echo "42"
        exit 0 ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-check-pr.sh"

  assert_success
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "[edge] PR_NUM が空文字列の場合も exit 1 を返す" {
  stub_command "gh" '
    case "$*" in
      *"pr view"*)
        printf ""
        exit 0 ;;
      *)
        exit 0 ;;
    esac
  '
  stub_command "python3" 'exit 0'

  run bash "$SANDBOX/scripts/merge-gate-check-pr.sh"

  assert_failure
}

@test "[edge] PR_NUM が 'none' の場合も exit 1 を返す" {
  stub_command "gh" '
    case "$*" in
      *"pr view"*)
        echo "none"
        exit 0 ;;
      *)
        exit 0 ;;
    esac
  '
  stub_command "python3" 'exit 0'

  run bash "$SANDBOX/scripts/merge-gate-check-pr.sh"

  assert_failure
}

@test "[edge] スクリプトに checkpoint write 呼び出し（REJECT 時）が含まれる" {
  grep -qP '(checkpoint|write.*REJECT|python3.*checkpoint)' "$SANDBOX/scripts/merge-gate-check-pr.sh"
}

@test "[edge] スクリプトが REJECT severity CRITICAL の findings を書き込む" {
  grep -qP '(CRITICAL|severity.*CRITICAL|chain-integrity)' "$SANDBOX/scripts/merge-gate-check-pr.sh"
}
