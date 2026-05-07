#!/usr/bin/env bash
# =============================================================================
# Unit Tests: Issue #1503 — auto-merge.sh READY_ERR_RAW トークンマスキング
# 対象: plugins/twl/scripts/auto-merge.sh
# AC:
#   AC1: READY_ERR_RAW が ghs_ トークンをマスクする
#   AC2: READY_ERR_RAW が ghu_ トークンをマスクする
#   AC3: ERROR_RAW が ghs_ トークンをマスクする
#   AC4: ERROR_RAW が ghu_ トークンをマスクする
#   AC5: マスキングパターンが gh[a-z]_ の汎用パターンを使用している
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

PASS=0
FAIL=0
SKIP=0
ERRORS=()

run_test() {
  local name="$1"
  local func="$2"
  local result=0
  "$func" || result=$?
  if [[ $result -eq 0 ]]; then
    echo "  PASS: ${name}"
    ((PASS++)) || true
  else
    echo "  FAIL: ${name}"
    ((FAIL++)) || true
    ERRORS+=("${name}")
  fi
}

TARGET_SCRIPT="scripts/auto-merge.sh"
TARGET_FILE="${PROJECT_ROOT}/${TARGET_SCRIPT}"

# =============================================================================
# AC5: マスキングパターン構造検証
# =============================================================================
echo ""
echo "--- AC5: マスキングパターン構造検証 ---"

test_ac5_generic_pattern_ready_err_raw() {
  # READY_ERR_RAW の sed パターンが gh[a-z]_ 汎用パターンを含む（ghp_ 単独ではない）
  grep 'READY_ERR_RAW=\$(sed' "$TARGET_FILE" | grep -qE 'gh\[a-z\]_|ghs_|ghu_'
}
run_test "AC5: READY_ERR_RAW の sed パターンが gh[a-z]_ 汎用形式または ghs_/ghu_ を含む" test_ac5_generic_pattern_ready_err_raw

test_ac5_generic_pattern_error_raw() {
  # ERROR_RAW の sed パターンが gh[a-z]_ 汎用パターンを含む（ghp_ 単独ではない）
  grep 'ERROR_RAW=\$(sed' "$TARGET_FILE" | grep -qE 'gh\[a-z\]_|ghs_|ghu_'
}
run_test "AC5: ERROR_RAW の sed パターンが gh[a-z]_ 汎用形式または ghs_/ghu_ を含む" test_ac5_generic_pattern_error_raw

# =============================================================================
# AC1: READY_ERR_RAW が ghs_ トークンをマスクする（機能テスト）
# =============================================================================
echo ""
echo "--- AC1/AC2: READY_ERR_RAW sed パターン機能テスト ---"

_extract_ready_err_sed_cmd() {
  # auto-merge.sh から READY_ERR_RAW の sed パターンを抽出する
  grep 'READY_ERR_RAW=\$(sed' "$TARGET_FILE" \
    | sed -E "s/.*-E '([^']*)'.*/\1/"
}

test_ac1_ghs_masked_in_ready_err() {
  local sed_pattern
  sed_pattern=$(_extract_ready_err_sed_cmd)
  [[ -z "$sed_pattern" ]] && return 1

  local input="error: authentication failed ghs_AbCdEfGhIj0123456789 not authorized"
  local output
  output=$(echo "$input" | sed -E "$sed_pattern")
  # ghs_ トークンが出力に残っていないこと
  ! echo "$output" | grep -qE "ghs_[a-zA-Z0-9_]+"
}
run_test "AC1: READY_ERR_RAW sed パターンが ghs_ トークンをマスクする" test_ac1_ghs_masked_in_ready_err

test_ac2_ghu_masked_in_ready_err() {
  local sed_pattern
  sed_pattern=$(_extract_ready_err_sed_cmd)
  [[ -z "$sed_pattern" ]] && return 1

  local input="error: authentication failed ghu_XyZaBcDeFgH9876543210 not authorized"
  local output
  output=$(echo "$input" | sed -E "$sed_pattern")
  ! echo "$output" | grep -qE "ghu_[a-zA-Z0-9_]+"
}
run_test "AC2: READY_ERR_RAW sed パターンが ghu_ トークンをマスクする" test_ac2_ghu_masked_in_ready_err

test_ac1_ghs_masked_result_contains_marker() {
  local sed_pattern
  sed_pattern=$(_extract_ready_err_sed_cmd)
  [[ -z "$sed_pattern" ]] && return 1

  local input="error: ghs_AbCdEfGhIj0123456789 token"
  local output
  output=$(echo "$input" | sed -E "$sed_pattern")
  # マスク後にマーカーが含まれること
  echo "$output" | grep -qE "MASKED|\*\*\*"
}
run_test "AC1: READY_ERR_RAW で ghs_ マスク後に MASKED マーカーが含まれる" test_ac1_ghs_masked_result_contains_marker

test_ac2_ghu_masked_result_contains_marker() {
  local sed_pattern
  sed_pattern=$(_extract_ready_err_sed_cmd)
  [[ -z "$sed_pattern" ]] && return 1

  local input="error: ghu_XyZaBcDeFgH9876543210 token"
  local output
  output=$(echo "$input" | sed -E "$sed_pattern")
  echo "$output" | grep -qE "MASKED|\*\*\*"
}
run_test "AC2: READY_ERR_RAW で ghu_ マスク後に MASKED マーカーが含まれる" test_ac2_ghu_masked_result_contains_marker

# =============================================================================
# AC3/AC4: ERROR_RAW が ghs_/ghu_ トークンをマスクする（機能テスト）
# =============================================================================
echo ""
echo "--- AC3/AC4: ERROR_RAW sed パターン機能テスト ---"

_extract_error_raw_sed_cmd() {
  grep 'ERROR_RAW=\$(sed' "$TARGET_FILE" \
    | sed -E "s/.*-E '([^']*)'.*/\1/"
}

test_ac3_ghs_masked_in_error_raw() {
  local sed_pattern
  sed_pattern=$(_extract_error_raw_sed_cmd)
  [[ -z "$sed_pattern" ]] && return 1

  local input="merge failed: ghs_AbCdEfGhIj0123456789 bad credentials"
  local output
  output=$(echo "$input" | sed -E "$sed_pattern")
  ! echo "$output" | grep -qE "ghs_[a-zA-Z0-9_]+"
}
run_test "AC3: ERROR_RAW sed パターンが ghs_ トークンをマスクする" test_ac3_ghs_masked_in_error_raw

test_ac4_ghu_masked_in_error_raw() {
  local sed_pattern
  sed_pattern=$(_extract_error_raw_sed_cmd)
  [[ -z "$sed_pattern" ]] && return 1

  local input="merge failed: ghu_XyZaBcDeFgH9876543210 bad credentials"
  local output
  output=$(echo "$input" | sed -E "$sed_pattern")
  ! echo "$output" | grep -qE "ghu_[a-zA-Z0-9_]+"
}
run_test "AC4: ERROR_RAW sed パターンが ghu_ トークンをマスクする" test_ac4_ghu_masked_in_error_raw

test_ac3_ghs_masked_result_contains_marker() {
  local sed_pattern
  sed_pattern=$(_extract_error_raw_sed_cmd)
  [[ -z "$sed_pattern" ]] && return 1

  local input="error: ghs_AbCdEfGhIj0123456789 token"
  local output
  output=$(echo "$input" | sed -E "$sed_pattern")
  echo "$output" | grep -qE "MASKED|\*\*\*"
}
run_test "AC3: ERROR_RAW で ghs_ マスク後に MASKED マーカーが含まれる" test_ac3_ghs_masked_result_contains_marker

test_ac4_ghu_masked_result_contains_marker() {
  local sed_pattern
  sed_pattern=$(_extract_error_raw_sed_cmd)
  [[ -z "$sed_pattern" ]] && return 1

  local input="error: ghu_XyZaBcDeFgH9876543210 token"
  local output
  output=$(echo "$input" | sed -E "$sed_pattern")
  echo "$output" | grep -qE "MASKED|\*\*\*"
}
run_test "AC4: ERROR_RAW で ghu_ マスク後に MASKED マーカーが含まれる" test_ac4_ghu_masked_result_contains_marker

# =============================================================================
# 既存パターン（回帰テスト）
# =============================================================================
echo ""
echo "--- 回帰テスト: 既存 ghp_ / Bearer マスキング維持 ---"

test_regression_ghp_still_masked_ready_err() {
  local sed_pattern
  sed_pattern=$(_extract_ready_err_sed_cmd)
  [[ -z "$sed_pattern" ]] && return 1

  local input="error: ghp_AbCdEfGhIj0123456789 bad credentials"
  local output
  output=$(echo "$input" | sed -E "$sed_pattern")
  ! echo "$output" | grep -qE "ghp_[a-zA-Z0-9_]+"
}
run_test "回帰: READY_ERR_RAW で既存 ghp_ も引き続きマスクされる" test_regression_ghp_still_masked_ready_err

test_regression_bearer_still_masked_ready_err() {
  local sed_pattern
  sed_pattern=$(_extract_ready_err_sed_cmd)
  [[ -z "$sed_pattern" ]] && return 1

  local token="eyJhbGciOiJIUzI1NiJ9.secret"
  local input="error: Bearer ${token}"
  local output
  output=$(echo "$input" | sed -E "$sed_pattern")
  # 元のトークン文字列が出力に残っていないこと
  ! echo "$output" | grep -qF "$token"
}
run_test "回帰: READY_ERR_RAW で既存 Bearer も引き続きマスクされる" test_regression_bearer_still_masked_ready_err

# =============================================================================
# github_pat_ Fine-grained PAT テスト（Issue #1503 明示対象）
# =============================================================================
echo ""
echo "--- github_pat_ Fine-grained PAT マスキング ---"

test_github_pat_masked_in_ready_err() {
  local sed_pattern
  sed_pattern=$(_extract_ready_err_sed_cmd)
  [[ -z "$sed_pattern" ]] && return 1

  local token="github_pat_AbCdEfGhIj0123456789XxYyZz"
  local input="error: ${token} bad credentials"
  local output
  output=$(echo "$input" | sed -E "$sed_pattern")
  ! echo "$output" | grep -qF "$token"
}
run_test "READY_ERR_RAW で github_pat_ Fine-grained PAT がマスクされる" test_github_pat_masked_in_ready_err

test_github_pat_masked_in_error_raw() {
  local sed_pattern
  sed_pattern=$(_extract_error_raw_sed_cmd)
  [[ -z "$sed_pattern" ]] && return 1

  local token="github_pat_AbCdEfGhIj0123456789XxYyZz"
  local input="merge failed: ${token} bad credentials"
  local output
  output=$(echo "$input" | sed -E "$sed_pattern")
  ! echo "$output" | grep -qF "$token"
}
run_test "ERROR_RAW で github_pat_ Fine-grained PAT がマスクされる" test_github_pat_masked_in_error_raw

test_github_pat_masked_result_contains_marker() {
  local sed_pattern
  sed_pattern=$(_extract_ready_err_sed_cmd)
  [[ -z "$sed_pattern" ]] && return 1

  local input="error: github_pat_AbCdEfGhIj0123456789XxYyZz token"
  local output
  output=$(echo "$input" | sed -E "$sed_pattern")
  echo "$output" | grep -qE "MASKED|\*\*\*"
}
run_test "READY_ERR_RAW で github_pat_ マスク後に MASKED マーカーが含まれる" test_github_pat_masked_result_contains_marker

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "==========================================="
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "==========================================="

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "Failed tests:"
  for err in "${ERRORS[@]}"; do
    echo "  - ${err}"
  done
fi

exit $FAIL
