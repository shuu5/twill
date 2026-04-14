#!/usr/bin/env bats
# merge-gate-check-phase-review.bats - unit tests for scripts/merge-gate-check-phase-review.sh
# Generated from: deltaspec/changes/issue-680/specs/merge-gate-refactor.md
# Requirement: phase-review 必須チェックスクリプト抽出
# Coverage: unit + edge-cases

load '../helpers/common'

setup() {
  common_setup
  export CLAUDE_PLUGIN_ROOT="$SANDBOX"
  # デフォルト環境変数
  export PHASE_REVIEW_STATUS="PASS"
  export ISSUE_NUM="42"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: phase-review 必須チェックスクリプト抽出
# ---------------------------------------------------------------------------

@test "merge-gate-check-phase-review.sh が存在する" {
  [[ -f "$SANDBOX/scripts/merge-gate-check-phase-review.sh" ]]
}

@test "merge-gate-check-phase-review.sh が実行可能である" {
  [[ -x "$SANDBOX/scripts/merge-gate-check-phase-review.sh" ]]
}

@test "merge-gate-check-phase-review.sh が bash 構文チェック pass" {
  bash -n "$SANDBOX/scripts/merge-gate-check-phase-review.sh"
}

# ---------------------------------------------------------------------------
# Scenario: phase-review チェックスクリプト実行
# WHEN: bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-check-phase-review.sh" が呼び出される
#       (PHASE_REVIEW_STATUS, ISSUE_NUM が環境変数で渡される)
# THEN: phase-review が不在かつ scope/direct / quick ラベルがない場合は REJECT を返し、
#       ラベルがある場合はスキップすること
# ---------------------------------------------------------------------------

@test "PHASE_REVIEW_STATUS=PASS の場合は exit 0 を返す" {
  export PHASE_REVIEW_STATUS="PASS"
  stub_command "gh" '
    case "$*" in
      *"issue view"*)
        echo '"'"'["code-review"]'"'"' ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-check-phase-review.sh"

  assert_success
}

@test "PHASE_REVIEW_STATUS=MISSING かつラベルなしの場合は exit 1 (REJECT) を返す" {
  export PHASE_REVIEW_STATUS="MISSING"
  stub_command "gh" '
    case "$*" in
      *"issue view"*)
        echo '"'"'["bug"]'"'"' ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-check-phase-review.sh"

  assert_failure
}

@test "PHASE_REVIEW_STATUS=MISSING かつラベルなしの場合は REJECT メッセージを出力する" {
  export PHASE_REVIEW_STATUS="MISSING"
  stub_command "gh" '
    case "$*" in
      *"issue view"*)
        echo '"'"'["bug"]'"'"' ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-check-phase-review.sh" 2>&1

  assert_output --partial "REJECT"
}

@test "PHASE_REVIEW_STATUS=MISSING かつ scope/direct ラベルの場合はスキップして exit 0" {
  export PHASE_REVIEW_STATUS="MISSING"
  stub_command "gh" '
    case "$*" in
      *"issue view"*)
        echo '"'"'["scope/direct"]'"'"' ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-check-phase-review.sh"

  assert_success
}

@test "PHASE_REVIEW_STATUS=MISSING かつ quick ラベルの場合はスキップして exit 0" {
  export PHASE_REVIEW_STATUS="MISSING"
  stub_command "gh" '
    case "$*" in
      *"issue view"*)
        echo '"'"'["quick"]'"'"' ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-check-phase-review.sh"

  assert_success
}

@test "scope/direct ラベルでスキップした場合はスキップメッセージを出力する" {
  export PHASE_REVIEW_STATUS="MISSING"
  stub_command "gh" '
    case "$*" in
      *"issue view"*)
        echo '"'"'["scope/direct"]'"'"' ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-check-phase-review.sh" 2>&1

  assert_success
  # スキップした理由が出力に含まれること
  assert_output --partial "skip"
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "[edge] ISSUE_NUM が未設定の場合は適切にエラー処理する" {
  unset ISSUE_NUM
  stub_command "gh" 'exit 1'

  run bash "$SANDBOX/scripts/merge-gate-check-phase-review.sh"

  # crash しないこと（exit 0 or 1）
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

@test "[edge] PHASE_REVIEW_STATUS が未設定の場合は MISSING として扱う" {
  unset PHASE_REVIEW_STATUS
  stub_command "gh" '
    case "$*" in
      *"issue view"*)
        echo '"'"'["bug"]'"'"' ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-check-phase-review.sh"

  assert_failure
}

@test "[edge] --force フラグで MISSING でも WARNING を出して継続する" {
  export PHASE_REVIEW_STATUS="MISSING"
  stub_command "gh" '
    case "$*" in
      *"issue view"*)
        echo '"'"'["bug"]'"'"' ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-check-phase-review.sh" --force 2>&1

  assert_success
  assert_output --partial "WARNING"
}

@test "[edge] スクリプトが gh issue view --json labels を呼び出す" {
  grep -qP '(gh issue view.*labels|json labels|labels.*\[\]|\.labels)' \
    "$SANDBOX/scripts/merge-gate-check-phase-review.sh"
}

@test "[edge] スクリプトが scope/direct と quick の両方をスキップ条件として持つ" {
  grep -qP 'scope/direct' "$SANDBOX/scripts/merge-gate-check-phase-review.sh"
  grep -qP '"quick"' "$SANDBOX/scripts/merge-gate-check-phase-review.sh"
}

@test "[edge] PHASE_REVIEW_STATUS=MISSING かつラベルなしの REJECT で checkpoint を書き込む" {
  grep -qP '(checkpoint.*write|python3.*checkpoint)' \
    "$SANDBOX/scripts/merge-gate-check-phase-review.sh"
}
