#!/usr/bin/env bats
# merge-gate-checkpoint-merge.bats - unit tests for scripts/merge-gate-checkpoint-merge.sh
# Generated from: deltaspec/changes/issue-680/specs/merge-gate-refactor.md
# Requirement: checkpoint 統合スクリプト抽出
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
# Requirement: checkpoint 統合スクリプト抽出
# ---------------------------------------------------------------------------

@test "merge-gate-checkpoint-merge.sh が存在する" {
  [[ -f "$SANDBOX/scripts/merge-gate-checkpoint-merge.sh" ]]
}

@test "merge-gate-checkpoint-merge.sh が実行可能である" {
  [[ -x "$SANDBOX/scripts/merge-gate-checkpoint-merge.sh" ]]
}

@test "merge-gate-checkpoint-merge.sh が bash 構文チェック pass" {
  bash -n "$SANDBOX/scripts/merge-gate-checkpoint-merge.sh"
}

# ---------------------------------------------------------------------------
# Scenario: checkpoint 統合スクリプト実行
# WHEN: COMBINED_FINDINGS=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-checkpoint-merge.sh" "$FINDINGS") が呼び出される
# THEN: ac-verify, phase-review の findings を統合した JSON を stdout に出力すること
# ---------------------------------------------------------------------------

@test "空の findings を渡した場合は有効な JSON 配列を stdout に出力する" {
  stub_command "python3" '
    case "$*" in
      *"checkpoint"*"read"*"ac-verify"*)
        echo "[]" ;;
      *"checkpoint"*"read"*"phase-review"*)
        echo "[]" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-checkpoint-merge.sh" "[]"

  assert_success
  # 出力が JSON 配列であること
  echo "$output" | python3 -c "import json,sys; data=json.load(sys.stdin); assert isinstance(data, list)"
}

@test "specialist findings を引数で渡すと統合 JSON に含まれる" {
  local specialist_findings='[{"severity":"WARNING","message":"test finding","confidence":90}]'

  stub_command "python3" '
    case "$*" in
      *"checkpoint"*"read"*"ac-verify"*)
        echo "[]" ;;
      *"checkpoint"*"read"*"phase-review"*)
        echo "[]" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-checkpoint-merge.sh" "$specialist_findings"

  assert_success
  assert_output --partial "test finding"
}

@test "ac-verify findings が統合 JSON に含まれる" {
  stub_command "python3" '
    case "$*" in
      *"checkpoint"*"read"*"ac-verify"*)
        echo '"'"'[{"severity":"CRITICAL","message":"ac-verify finding","confidence":85}]'"'"' ;;
      *"checkpoint"*"read"*"phase-review"*)
        echo "[]" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-checkpoint-merge.sh" "[]"

  assert_success
  assert_output --partial "ac-verify finding"
}

@test "phase-review findings が統合 JSON に含まれる" {
  stub_command "python3" '
    case "$*" in
      *"checkpoint"*"read"*"ac-verify"*)
        echo "[]" ;;
      *"checkpoint"*"read"*"phase-review"*)
        echo '"'"'[{"severity":"WARNING","message":"phase-review finding","confidence":75}]'"'"' ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-checkpoint-merge.sh" "[]"

  assert_success
  assert_output --partial "phase-review finding"
}

@test "全 findings が統合されて出力される" {
  stub_command "python3" '
    case "$*" in
      *"checkpoint"*"read"*"ac-verify"*)
        echo '"'"'[{"severity":"WARNING","message":"ac finding","confidence":70}]'"'"' ;;
      *"checkpoint"*"read"*"phase-review"*)
        echo '"'"'[{"severity":"CRITICAL","message":"phase finding","confidence":95}]'"'"' ;;
      *)
        exit 0 ;;
    esac
  '
  local specialist_findings='[{"severity":"INFO","message":"specialist finding","confidence":60}]'

  run bash "$SANDBOX/scripts/merge-gate-checkpoint-merge.sh" "$specialist_findings"

  assert_success
  assert_output --partial "ac finding"
  assert_output --partial "phase finding"
  assert_output --partial "specialist finding"
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "[edge] ac-verify checkpoint が存在しない場合は空配列 [] として扱う" {
  stub_command "python3" '
    case "$*" in
      *"checkpoint"*"read"*"ac-verify"*)
        # not found → empty
        echo "[]" ;;
      *"checkpoint"*"read"*"phase-review"*)
        echo "[]" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-checkpoint-merge.sh" "[]"

  assert_success
}

@test "[edge] phase-review checkpoint が存在しない場合は空配列 [] として扱う" {
  stub_command "python3" '
    case "$*" in
      *"checkpoint"*"read"*"ac-verify"*)
        echo "[]" ;;
      *"checkpoint"*"read"*"phase-review"*)
        echo "[]" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-checkpoint-merge.sh" "[]"

  assert_success
}

@test "[edge] スクリプトが jq -s 'add' または同等の JSON 統合コマンドを使用する" {
  grep -qP "(jq.*-s.*add|jq_merge|jq.*add|python3.*json)" \
    "$SANDBOX/scripts/merge-gate-checkpoint-merge.sh"
}

# ---------------------------------------------------------------------------
# #748: post-fix-verify precedence over phase-review
# ---------------------------------------------------------------------------

@test "[#748] phase-review CRITICAL あり + post-fix-verify 不在 → phase-review findings が COMBINED に含まれる（回帰保護）" {
  stub_command "python3" '
    case "$*" in
      *"checkpoint"*"read"*"ac-verify"*)
        echo "[]" ;;
      *"checkpoint"*"read"*"post-fix-verify"*)
        exit 1 ;;
      *"checkpoint"*"read"*"phase-review"*)
        echo '"'"'[{"severity":"CRITICAL","message":"stale-phase-review-critical","confidence":90}]'"'"' ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-checkpoint-merge.sh" "[]"

  assert_success
  assert_output --partial "stale-phase-review-critical"
}

@test "[#748] phase-review CRITICAL あり + post-fix-verify PASS → phase-review CRITICAL が COMBINED から除外される" {
  stub_command "python3" '
    case "$*" in
      *"checkpoint"*"read"*"ac-verify"*)
        echo "[]" ;;
      *"checkpoint"*"read"*"post-fix-verify"*)
        echo "[]" ;;
      *"checkpoint"*"read"*"phase-review"*)
        echo '"'"'[{"severity":"CRITICAL","message":"stale-phase-review-critical","confidence":90}]'"'"' ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-checkpoint-merge.sh" "[]"

  assert_success
  refute_output --partial "stale-phase-review-critical"
}

@test "[#748] phase-review CRITICAL あり + post-fix-verify WARN → phase-review CRITICAL が除外され post-fix-verify WARNING が含まれる（最頻ケース）" {
  stub_command "python3" '
    case "$*" in
      *"checkpoint"*"read"*"ac-verify"*)
        echo "[]" ;;
      *"checkpoint"*"read"*"post-fix-verify"*)
        echo '"'"'[{"severity":"WARNING","message":"post-fix-verify-warning","confidence":75}]'"'"' ;;
      *"checkpoint"*"read"*"phase-review"*)
        echo '"'"'[{"severity":"CRITICAL","message":"stale-phase-review-critical","confidence":90}]'"'"' ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-checkpoint-merge.sh" "[]"

  assert_success
  assert_output --partial "post-fix-verify-warning"
  refute_output --partial "stale-phase-review-critical"
}

@test "[#748] phase-review CRITICAL あり + post-fix-verify FAIL → post-fix-verify findings が採用され CRITICAL が残る" {
  stub_command "python3" '
    case "$*" in
      *"checkpoint"*"read"*"ac-verify"*)
        echo "[]" ;;
      *"checkpoint"*"read"*"post-fix-verify"*)
        echo '"'"'[{"severity":"CRITICAL","message":"post-fix-verify-critical","confidence":85}]'"'"' ;;
      *"checkpoint"*"read"*"phase-review"*)
        echo '"'"'[{"severity":"CRITICAL","message":"stale-phase-review-critical","confidence":90}]'"'"' ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-checkpoint-merge.sh" "[]"

  assert_success
  assert_output --partial "post-fix-verify-critical"
  refute_output --partial "stale-phase-review-critical"
}

@test "[edge] スクリプトが stdout に結果を出力する（stderr ではない）" {
  stub_command "python3" '
    case "$*" in
      *"checkpoint"*"read"*)
        echo "[]" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-checkpoint-merge.sh" "[]"

  assert_success
  # stdout に JSON が出力されていること（refute empty output）
  [[ -n "$output" ]]
}

@test "[edge] 引数なしの場合は空配列または引数エラーで終了する" {
  stub_command "python3" '
    case "$*" in
      *"checkpoint"*"read"*)
        echo "[]" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-checkpoint-merge.sh"

  # 引数なしでも crash しない（exit 0 または exit 1 のどちらも許容、crash は禁止）
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
}
