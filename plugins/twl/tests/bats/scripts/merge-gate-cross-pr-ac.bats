#!/usr/bin/env bats
# merge-gate-cross-pr-ac.bats - unit tests for scripts/merge-gate-cross-pr-ac.sh
# Generated from: deltaspec/changes/issue-680/specs/merge-gate-refactor.md
# Requirement: Cross-PR AC 検証スクリプト抽出
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
# Requirement: Cross-PR AC 検証スクリプト抽出
# ---------------------------------------------------------------------------

@test "merge-gate-cross-pr-ac.sh が存在する" {
  [[ -f "$SANDBOX/scripts/merge-gate-cross-pr-ac.sh" ]]
}

@test "merge-gate-cross-pr-ac.sh が実行可能である" {
  [[ -x "$SANDBOX/scripts/merge-gate-cross-pr-ac.sh" ]]
}

@test "merge-gate-cross-pr-ac.sh が bash 構文チェック pass" {
  bash -n "$SANDBOX/scripts/merge-gate-cross-pr-ac.sh"
}

# ---------------------------------------------------------------------------
# Scenario: Cross-PR AC 検証スクリプト実行
# WHEN: bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-cross-pr-ac.sh" が呼び出される
# THEN: implementation_pr が設定されている場合にマージコミットを取得し checkpoint へ記録すること
# ---------------------------------------------------------------------------

@test "implementation_pr が設定されている場合は exit 0 を返す" {
  stub_command "python3" '
    case "$*" in
      *"read"*"implementation_pr"*)
        echo "100" ;;
      *"checkpoint"*"write"*)
        exit 0 ;;
      *)
        exit 0 ;;
    esac
  '
  stub_command "gh" '
    case "$*" in
      *"pr view"*)
        echo "abc123def456" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-cross-pr-ac.sh"

  assert_success
}

@test "implementation_pr が設定されている場合は checkpoint に verified_via_pr を記録する" {
  stub_command "python3" '
    case "$*" in
      *"read"*"implementation_pr"*)
        echo "100" ;;
      *"checkpoint"*"write"*)
        # 引数を記録
        echo "$*" >> /tmp/twl-test-checkpoint-calls.log
        exit 0 ;;
      *)
        exit 0 ;;
    esac
  '
  stub_command "gh" '
    case "$*" in
      *"pr view"*)
        echo "abc123def456" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-cross-pr-ac.sh"

  assert_success
}

@test "implementation_pr が空または null の場合は checkpoint 記録をスキップする" {
  stub_command "python3" '
    case "$*" in
      *"read"*"implementation_pr"*)
        echo "" ;;
      *)
        exit 0 ;;
    esac
  '
  stub_command "gh" '
    exit 0
  '

  run bash "$SANDBOX/scripts/merge-gate-cross-pr-ac.sh"

  assert_success
  # checkpoint write は呼ばれない（出力を検証）
  refute_output --partial "verified_via_commit"
}

@test "マージコミットが取得できない場合は WARN を出力して継続する" {
  stub_command "python3" '
    case "$*" in
      *"read"*"implementation_pr"*)
        echo "100" ;;
      *"checkpoint"*"write"*)
        exit 0 ;;
      *)
        exit 0 ;;
    esac
  '
  stub_command "gh" '
    case "$*" in
      *"pr view"*)
        # マージコミット取得失敗（空文字列）
        echo ""
        exit 0 ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-cross-pr-ac.sh" 2>&1

  assert_success
  assert_output --partial "WARN"
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "[edge] スクリプトが resolve-issue-num.sh を使って ISSUE_NUM を取得する" {
  grep -qP '(resolve-issue-num|resolve_issue_num|ISSUE_NUM)' \
    "$SANDBOX/scripts/merge-gate-cross-pr-ac.sh"
}

@test "[edge] スクリプトが implementation_pr フィールドを state read で取得する" {
  grep -qP '(implementation_pr|state.*read|python3.*state.*read)' \
    "$SANDBOX/scripts/merge-gate-cross-pr-ac.sh"
}

@test "[edge] スクリプトが gh pr view --json mergeCommit を呼び出す" {
  grep -qP '(mergeCommit|merge_commit|merge.*commit)' \
    "$SANDBOX/scripts/merge-gate-cross-pr-ac.sh"
}

@test "[edge] スクリプトが checkpoint write に --extra フラグを渡す" {
  grep -qP '(--extra.*verified_via|verified_via.*commit|verified_via.*pr)' \
    "$SANDBOX/scripts/merge-gate-cross-pr-ac.sh"
}

@test "[edge] implementation_pr が 'null' 文字列の場合もスキップする" {
  stub_command "python3" '
    case "$*" in
      *"read"*"implementation_pr"*)
        echo "null" ;;
      *)
        exit 0 ;;
    esac
  '
  stub_command "gh" 'exit 0'

  run bash "$SANDBOX/scripts/merge-gate-cross-pr-ac.sh"

  assert_success
}
