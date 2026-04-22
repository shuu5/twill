#!/usr/bin/env bats
# spec-review-session-init.bats
#
# Tests for plugins/twl/scripts/spec-review-session-init.sh
#
# Spec: deltaspec/changes/issue-446/specs/pretooluse-gate/spec.md
#   Requirement: セッション初期化スクリプト（spec-review-session-init.sh）
#
# Scenarios:
#   1. 正常初期化: spec-review-session-init.sh 3 → state ファイルが {"total":3,"completed":0,"issues":{}} で作成される
#   2. 既存 state 上書き: 既存ファイル存在 + spec-review-session-init.sh 5 → {"total":5,"completed":0,"issues":{}} に上書き
#   3. edge: 引数なし → exit 非 0
#   4. edge: 引数が非数値 → exit 非 0
#   5. edge: 引数が 0 → exit 0 かつ total=0 で作成される
#   6. edge: 引数が負数 → exit 非 0 または total<0 で拒否
#   7. hash がプロジェクトルートから算出される
#   8. 複数回実行でも state ファイルが同じパスに作成される

load '../helpers/common'

SCRIPT_SRC=""

setup() {
  common_setup

  SCRIPT_SRC="$(cd "$REPO_ROOT" && pwd)/scripts/spec-review-session-init.sh"

  # Override CLAUDE_PROJECT_ROOT to a known value for predictable hash
  export CLAUDE_PROJECT_ROOT="$SANDBOX"

  # Compute expected hash the same way the script does:
  # printf '%s' "${CLAUDE_PROJECT_ROOT:-$PWD}" | cksum | awk '{print $1}'
  EXPECTED_HASH=$(printf '%s' "$SANDBOX" | cksum | awk '{print $1}')
  export EXPECTED_HASH
  EXPECTED_STATE_FILE="/tmp/.spec-review-session-${EXPECTED_HASH}.json"
  export EXPECTED_STATE_FILE
}

teardown() {
  rm -f "$EXPECTED_STATE_FILE" 2>/dev/null || true
  common_teardown
}

# ---------------------------------------------------------------------------
# Scenario 1: 正常初期化
# WHEN spec-review-session-init.sh 3 を実行する
# THEN /tmp/.spec-review-session-{hash}.json が {"total":3,"completed":0,"issues":{}} で作成される
# ---------------------------------------------------------------------------
@test "正常初期化: total=3 で state ファイルが作成される" {
  run bash "$SCRIPT_SRC" 3
  [ "$status" -eq 0 ]
  [ -f "$EXPECTED_STATE_FILE" ]

  local total completed issues_keys
  total=$(jq -r '.total' "$EXPECTED_STATE_FILE")
  completed=$(jq -r '.completed' "$EXPECTED_STATE_FILE")
  issues_keys=$(jq -r '.issues | keys | length' "$EXPECTED_STATE_FILE")

  [ "$total" = "3" ]
  [ "$completed" = "0" ]
  [ "$issues_keys" = "0" ]
}

# ---------------------------------------------------------------------------
# Scenario 2: 既存 state 上書き
# WHEN 既存の state ファイルが存在する状態で spec-review-session-init.sh 5 を実行する
# THEN state ファイルが {"total":5,"completed":0,"issues":{}} に上書きされる
# ---------------------------------------------------------------------------
@test "既存 state ファイルを上書き初期化する" {
  # Pre-create a state file with old values
  printf '{"total":10,"completed":7,"issues":{"123":"done"}}' > "$EXPECTED_STATE_FILE"

  run bash "$SCRIPT_SRC" 5
  [ "$status" -eq 0 ]
  [ -f "$EXPECTED_STATE_FILE" ]

  local total completed issues_keys
  total=$(jq -r '.total' "$EXPECTED_STATE_FILE")
  completed=$(jq -r '.completed' "$EXPECTED_STATE_FILE")
  issues_keys=$(jq -r '.issues | keys | length' "$EXPECTED_STATE_FILE")

  [ "$total" = "5" ]
  [ "$completed" = "0" ]
  [ "$issues_keys" = "0" ]
}

# ---------------------------------------------------------------------------
# edge: 引数なし → exit 非 0
# ---------------------------------------------------------------------------
@test "引数なしは exit 非 0 で終了する" {
  run bash "$SCRIPT_SRC"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# edge: 引数が非数値 → exit 非 0
# ---------------------------------------------------------------------------
@test "非数値引数は exit 非 0 で終了する" {
  run bash "$SCRIPT_SRC" "abc"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# edge: 引数が 0 → total=0 で作成
# ---------------------------------------------------------------------------
@test "引数 0 で total=0 の state ファイルが作成される" {
  run bash "$SCRIPT_SRC" 0
  [ "$status" -eq 0 ]
  [ -f "$EXPECTED_STATE_FILE" ]
  local total
  total=$(jq -r '.total' "$EXPECTED_STATE_FILE")
  [ "$total" = "0" ]
}

# ---------------------------------------------------------------------------
# edge: hash がプロジェクトルートから算出される
# ---------------------------------------------------------------------------
@test "hash は CLAUDE_PROJECT_ROOT から算出される" {
  run bash "$SCRIPT_SRC" 1
  [ "$status" -eq 0 ]
  # The state file must exist at the expected hash path
  [ -f "$EXPECTED_STATE_FILE" ]
}

# ---------------------------------------------------------------------------
# edge: 複数回実行でも同じパスに上書き
# ---------------------------------------------------------------------------
@test "同じプロジェクトルートなら複数回実行でも同じパスに出力される" {
  run bash "$SCRIPT_SRC" 2
  [ "$status" -eq 0 ]
  [ -f "$EXPECTED_STATE_FILE" ]

  run bash "$SCRIPT_SRC" 4
  [ "$status" -eq 0 ]
  # Still the same file, now total=4
  [ -f "$EXPECTED_STATE_FILE" ]
  local total
  total=$(jq -r '.total' "$EXPECTED_STATE_FILE")
  [ "$total" = "4" ]
}

# ---------------------------------------------------------------------------
# Cleanup: co-issue 終了時クリーンアップ（AC #832 §1）
# WHEN spec-review session state ファイルが存在する状態でクリーンアップ snippet を実行する
# THEN state ファイルが削除される
# ---------------------------------------------------------------------------
@test "cleanup: spec-review session state ファイルが削除される" {
  # 初期化してファイルを作成
  run bash "$SCRIPT_SRC" 1
  [ "$status" -eq 0 ]
  [ -f "$EXPECTED_STATE_FILE" ]

  # co-issue SKILL.md の cleanup snippet と同等の処理
  SPEC_REVIEW_HASH=$(printf '%s' "${CLAUDE_PROJECT_ROOT:-$PWD}" | cksum | awk '{print $1}')
  SPEC_REVIEW_STATE_FILE="/tmp/.spec-review-session-${SPEC_REVIEW_HASH}.json"
  rm -f "$SPEC_REVIEW_STATE_FILE"

  [ ! -f "$EXPECTED_STATE_FILE" ]
}

# ---------------------------------------------------------------------------
# Cleanup: ファイルが存在しない場合も cleanup が冪等である
# WHEN spec-review session state ファイルが存在しない状態でクリーンアップ snippet を実行する
# THEN エラーなく終了する
# ---------------------------------------------------------------------------
@test "cleanup: state ファイルが存在しなくても冪等に終了する" {
  [ ! -f "$EXPECTED_STATE_FILE" ]

  # rm -f は対象ファイルが存在しなくても exit 0
  run bash -c '
    SPEC_REVIEW_HASH=$(printf "%s" "${CLAUDE_PROJECT_ROOT:-$PWD}" | cksum | awk "{print \$1}")
    SPEC_REVIEW_STATE_FILE="/tmp/.spec-review-session-${SPEC_REVIEW_HASH}.json"
    rm -f "$SPEC_REVIEW_STATE_FILE"
  '
  [ "$status" -eq 0 ]
}
