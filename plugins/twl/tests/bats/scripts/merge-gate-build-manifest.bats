#!/usr/bin/env bats
# merge-gate-build-manifest.bats - unit tests for scripts/merge-gate-build-manifest.sh
# Generated from: deltaspec/changes/issue-680/specs/merge-gate-refactor.md
# Requirement: 動的レビュアー構築スクリプト抽出
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
# Requirement: 動的レビュアー構築スクリプト抽出
# ---------------------------------------------------------------------------

@test "merge-gate-build-manifest.sh が存在する" {
  [[ -f "$SANDBOX/scripts/merge-gate-build-manifest.sh" ]]
}

@test "merge-gate-build-manifest.sh が実行可能である" {
  [[ -x "$SANDBOX/scripts/merge-gate-build-manifest.sh" ]]
}

@test "merge-gate-build-manifest.sh が bash 構文チェック pass" {
  bash -n "$SANDBOX/scripts/merge-gate-build-manifest.sh"
}

# ---------------------------------------------------------------------------
# Scenario: マニフェスト構築スクリプト実行
# WHEN: bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-build-manifest.sh" が呼び出される
# THEN: MANIFEST_FILE と CONTEXT_ID と SPAWNED_FILE が設定され、specialists が書き込まれること
# ---------------------------------------------------------------------------

@test "スクリプトが MANIFEST_FILE 変数を出力する" {
  stub_command "git" '
    case "$*" in
      *"diff"*)
        echo "src/main.ts" ;;
      *"fetch"*)
        exit 0 ;;
      *)
        exit 0 ;;
    esac
  '
  stub_command "bash" '
    case "$*" in
      *"pr-review-manifest.sh"*)
        echo "twl:worker-code-reviewer" ;;
      *)
        bash "$@" ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-build-manifest.sh"

  assert_success
  assert_output --partial "MANIFEST_FILE="
}

@test "スクリプトが CONTEXT_ID 変数を出力する" {
  stub_command "git" '
    case "$*" in
      *"diff"*)
        echo "src/main.ts" ;;
      *"fetch"*)
        exit 0 ;;
      *)
        exit 0 ;;
    esac
  '
  stub_command "bash" '
    case "$*" in
      *"pr-review-manifest.sh"*)
        echo "twl:worker-code-reviewer" ;;
      *)
        bash "$@" ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-build-manifest.sh"

  assert_success
  assert_output --partial "CONTEXT_ID="
}

@test "スクリプトが SPAWNED_FILE 変数を出力する" {
  stub_command "git" '
    case "$*" in
      *"diff"*)
        echo "src/main.ts" ;;
      *"fetch"*)
        exit 0 ;;
      *)
        exit 0 ;;
    esac
  '
  stub_command "bash" '
    case "$*" in
      *"pr-review-manifest.sh"*)
        echo "twl:worker-code-reviewer" ;;
      *)
        bash "$@" ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-build-manifest.sh"

  assert_success
  assert_output --partial "SPAWNED_FILE="
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "[edge] スクリプトが pr-review-manifest.sh を --mode merge-gate で呼び出す" {
  grep -qP '(pr-review-manifest\.sh.*--mode merge-gate|--mode merge-gate.*pr-review-manifest\.sh)' \
    "$SANDBOX/scripts/merge-gate-build-manifest.sh"
}

@test "[edge] origin/main が解決できない場合に FETCH_HEAD フォールバックを持つ" {
  grep -qP '(FETCH_HEAD|fallback|fetch.*origin.*main)' \
    "$SANDBOX/scripts/merge-gate-build-manifest.sh"
}

@test "[edge] MANIFEST_FILE が /tmp/ 配下に作成される" {
  grep -qP '(mktemp.*/tmp|/tmp/.*specialist-manifest)' \
    "$SANDBOX/scripts/merge-gate-build-manifest.sh"
}

@test "[edge] MANIFEST_FILE のパーミッションが 600 に設定される" {
  grep -qP '(chmod 600|chmod.*600)' \
    "$SANDBOX/scripts/merge-gate-build-manifest.sh"
}

@test "[edge] specialists が MANIFEST_FILE に書き込まれる" {
  grep -qP '(echo.*MANIFEST_FILE|>.*MANIFEST_FILE|SPECIALISTS.*>)' \
    "$SANDBOX/scripts/merge-gate-build-manifest.sh"
}

@test "[edge] trap で MANIFEST_FILE と SPAWNED_FILE を削除する" {
  grep -qP '(trap.*rm|trap.*MANIFEST_FILE|trap.*SPAWNED_FILE)' \
    "$SANDBOX/scripts/merge-gate-build-manifest.sh"
}
