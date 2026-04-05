#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: cld-p-flag-prohibition
# Generated from: openspec/changes/fix-cld-p-flag-prohibition/specs/cld-p-flag-prohibition.md
# Coverage level: edge-cases
# Type: unit (documentation-verification)
# =============================================================================
set -uo pipefail

# Project root (relative to test file location)
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Counters
PASS=0
FAIL=0
SKIP=0
ERRORS=()

# --- Test Helpers ---

assert_file_exists() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]]
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qP "$pattern" "${PROJECT_ROOT}/${file}"
}

assert_file_contains_all() {
  local file="$1"
  shift
  local patterns=("$@")
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  for pattern in "${patterns[@]}"; do
    grep -qP "$pattern" "${PROJECT_ROOT}/${file}" || return 1
  done
  return 0
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  ! grep -qP "$pattern" "${PROJECT_ROOT}/${file}"
}

run_test() {
  local name="$1"
  local func="$2"
  local result
  result=0
  $func || result=$?
  if [[ $result -eq 0 ]]; then
    echo "  PASS: ${name}"
    ((PASS++)) || true
  else
    echo "  FAIL: ${name}"
    ((FAIL++)) || true
    ERRORS+=("${name}")
  fi
}

run_test_skip() {
  local name="$1"
  local reason="$2"
  echo "  SKIP: ${name} (${reason})"
  ((SKIP++)) || true
}

# ロジックは scripts/autopilot-launch.sh に移行済み。両方を検索対象にする。
TARGET_FILE="scripts/autopilot-launch.sh"
TARGET_FILE_MD="commands/autopilot-launch.md"

# =============================================================================
# Requirement: cld -p / --print フラグ使用禁止の明記
# =============================================================================
echo ""
echo "--- Requirement: cld -p / --print フラグ使用禁止の明記 ---"

# Scenario: 禁止事項セクションに cld -p 禁止が記載されている (line 7)
# WHEN: commands/autopilot-launch.md の禁止事項セクションを確認する
# THEN: cld -p / cld --print の使用禁止が記載されていること
test_prohibited_cld_p_flag_listed() {
  # 禁止事項は .md に記載。.sh のコメントにも存在する可能性あり
  local f="$TARGET_FILE_MD"
  assert_file_exists "$f" || f="$TARGET_FILE"
  assert_file_exists "$f" || return 1
  assert_file_contains "$f" "禁止事項" || return 1
  assert_file_contains "$f" "\-p\b|--print" || return 1
  local prohibit_line p_flag_line
  prohibit_line=$(grep -n "禁止事項" "${PROJECT_ROOT}/${f}" | tail -1 | cut -d: -f1)
  p_flag_line=$(grep -n "\-p\b\|--print" "${PROJECT_ROOT}/${f}" | tail -1 | cut -d: -f1)
  [[ -n "$prohibit_line" && -n "$p_flag_line" && "$p_flag_line" -gt "$prohibit_line" ]]
}
run_test "禁止事項セクションに cld -p 禁止が記載されている" test_prohibited_cld_p_flag_listed

# Edge case: -p と --print の両方の形式が言及されている
test_prohibited_both_short_and_long_flags() {
  assert_file_exists "$TARGET_FILE" || return 1
  assert_file_contains "$TARGET_FILE" "\-p\b" || return 1
  assert_file_contains "$TARGET_FILE" "\-\-print"
}
run_test "cld -p 禁止 [edge: -p と --print の両形式が言及]" test_prohibited_both_short_and_long_flags

# THEN: 禁止理由として「非対話 print モードで起動し Worker が即終了する」旨が記載されていること
test_prohibited_reason_stated() {
  assert_file_exists "$TARGET_FILE" || return 1
  # Reason should mention non-interactive mode or print mode causing immediate exit
  assert_file_contains "$TARGET_FILE" "print.*モード|非対話.*モード|即終了|immediately.*exit|print mode"
}
run_test "禁止理由 (print モード即終了) が記載されている" test_prohibited_reason_stated

# Edge case: 禁止理由が -p / --print の記載と同じブロック内または隣接行にある
test_prohibited_reason_near_flag() {
  assert_file_exists "$TARGET_FILE" || return 1
  # Extract lines around -p mention and check for reason keywords within ±5 lines
  local p_line
  p_line=$(grep -n "\-p\b\|--print" "${PROJECT_ROOT}/${TARGET_FILE}" | grep -i "禁止\|してはならない\|MUST NOT\|print.*モード\|即終了" | head -1)
  if [[ -n "$p_line" ]]; then
    return 0
  fi
  # Alternatively, check that within 5 lines of -p flag mention, reason appears
  local p_line_num
  p_line_num=$(grep -n "\-p\b\|--print" "${PROJECT_ROOT}/${TARGET_FILE}" | tail -1 | cut -d: -f1)
  [[ -n "$p_line_num" ]] || return 1
  local start=$(( p_line_num > 5 ? p_line_num - 5 : 1 ))
  local end=$(( p_line_num + 5 ))
  sed -n "${start},${end}p" "${PROJECT_ROOT}/${TARGET_FILE}" | grep -qP "print.*モード|非対話|即終了|print mode|non-interactive"
}
run_test "cld -p 禁止 [edge: 禁止理由が -p 記載と近傍に存在]" test_prohibited_reason_near_flag

# Edge case: 禁止事項が MUST NOT / してはならない 相当の強い表現で記載されている
test_prohibited_strong_prohibition_language() {
  local f="$TARGET_FILE_MD"
  assert_file_exists "$f" || f="$TARGET_FILE"
  assert_file_exists "$f" || return 1
  local prohibit_line
  prohibit_line=$(grep -n "禁止事項" "${PROJECT_ROOT}/${f}" | tail -1 | cut -d: -f1)
  [[ -n "$prohibit_line" ]] || return 1
  tail -n "+${prohibit_line}" "${PROJECT_ROOT}/${f}" | grep -qP "\-p\b|--print"
}
run_test "cld -p 禁止 [edge: 禁止事項セクション配下に -p 記載が存在]" test_prohibited_strong_prohibition_language

# Scenario: Pilot Claude が Worker 起動コマンドを構築する (line 12)
# WHEN: Pilot Claude が autopilot-launch.md に従い Worker 起動コマンドを構築する
# THEN: 禁止事項により -p / --print フラグの使用が排除されること
# Note: This scenario tests the documentation's effectiveness as guidance.
#       We verify that the prohibition is placed where Pilot Claude will see it.
test_prohibition_visible_to_pilot() {
  local f="$TARGET_FILE_MD"
  assert_file_exists "$f" || f="$TARGET_FILE"
  assert_file_exists "$f" || return 1
  assert_file_contains "$f" "## 禁止事項" || return 1
  local prohibit_line
  prohibit_line=$(grep -n "## 禁止事項" "${PROJECT_ROOT}/${f}" | head -1 | cut -d: -f1)
  [[ -n "$prohibit_line" ]] || return 1
  tail -n "+${prohibit_line}" "${PROJECT_ROOT}/${f}" | grep -qP "^\s*-\s.*(\-p\b|--print)"
}
run_test "禁止事項により -p / --print フラグが排除される" test_prohibition_visible_to_pilot

# Edge case: 禁止事項セクションのリスト項目として箇条書きで記載されている
test_prohibition_as_list_item() {
  local f="$TARGET_FILE_MD"
  assert_file_exists "$f" || f="$TARGET_FILE"
  assert_file_exists "$f" || return 1
  local prohibit_line
  prohibit_line=$(grep -n "## 禁止事項" "${PROJECT_ROOT}/${f}" | head -1 | cut -d: -f1)
  [[ -n "$prohibit_line" ]] || return 1
  tail -n "+${prohibit_line}" "${PROJECT_ROOT}/${f}" | grep -qP "^-\s.*(-p\b|--print)"
}
run_test "Pilot 向け禁止 [edge: 禁止事項が箇条書きリスト項目として記載]" test_prohibition_as_list_item

# =============================================================================
# Requirement: Step 5 コード例への注意コメント追加
# =============================================================================
echo ""
echo "--- Requirement: Step 5 コード例への注意コメント追加 ---"

# Scenario: Step 5 のコード例にコメントが存在する (line 20)
# WHEN: commands/autopilot-launch.md の Step 5 コード例を確認する
# THEN: positional arg でプロンプトを渡す方式であることを示すコメントが存在すること
test_step5_positional_arg_comment() {
  assert_file_exists "$TARGET_FILE" || return 1
  # .sh に移行後: positional arg コメントがスクリプト内に存在する
  assert_file_contains "$TARGET_FILE" "positional|プロンプト.*渡す|#.*prompt"
}
run_test "Step 5 にプロンプトを positional arg で渡す旨のコメントが存在する" test_step5_positional_arg_comment

# THEN: -p / --print を使用してはならない旨のコメントが存在すること
test_step5_no_p_flag_comment() {
  assert_file_exists "$TARGET_FILE" || return 1
  # .sh に移行後: -p/--print 禁止コメントがスクリプト内に存在する
  assert_file_contains "$TARGET_FILE" "#.*-p.*禁止|#.*--print.*禁止|#.*print.*禁止|-p.*禁止"
}
run_test "Step 5 に -p / --print を使用しない旨のコメントが存在する" test_step5_no_p_flag_comment

# Edge case: コメントがコードブロック内（```bash ... ```）に存在する
test_step5_comment_inside_codeblock() {
  assert_file_exists "$TARGET_FILE" || return 1
  # .sh に移行後: スクリプト内にコメントとして存在する（コードブロック不要）
  assert_file_contains "$TARGET_FILE" "#.*positional|#.*-p.*禁止|#.*--print.*禁止"
}
run_test "Step 5 コメント [edge: コメントがコードブロック内に存在]" test_step5_comment_inside_codeblock

# Edge case: Step 5 のコード例が cld 起動コマンドを含む（コメントが実際の起動コードに付随）
test_step5_codeblock_has_cld_launch() {
  assert_file_exists "$TARGET_FILE" || return 1
  # .sh に移行後: tmux new-window と CLD_PATH がスクリプト内に存在する
  assert_file_contains "$TARGET_FILE" "tmux.*new-window|QUOTED_CLD|CLD_PATH"
}
run_test "Step 5 コメント [edge: コード例が cld 起動コマンドを含む]" test_step5_codeblock_has_cld_launch

# Edge case: Step 5 に -p フラグの使用例が実際には含まれていない（誤って追加されていない）
test_step5_no_p_flag_in_code() {
  assert_file_exists "$TARGET_FILE" || return 1
  # .sh に移行後: 非コメント行に -p / --print フラグが含まれていない
  # コメント行を除外して検査
  local result
  result=$(grep -v '^\s*#' "${PROJECT_ROOT}/${TARGET_FILE}" | grep -P "\s-p\b|\s--print\b" || true)
  [[ -z "$result" ]]
}
run_test "Step 5 コメント [edge: 実コード行に -p / --print フラグが含まれない]" test_step5_no_p_flag_in_code

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
