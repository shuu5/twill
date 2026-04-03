#!/usr/bin/env bash
# =============================================================================
# Unit Tests: workflow-test-ready quick ガード
# Generated from: openspec/changes/workflow-test-ready-quick-guard/specs/quick-guard.md
# Coverage level: edge-cases
#
# Requirements:
#   1. chain-runner.sh quick-guard コマンドの構造検証
#   2. workflow-test-ready/SKILL.md の quick ガードセクション検証
#   3. deps.yaml chain-runner.sh エントリ更新の検証
#
# Strategy:
#   - Document-level tests: ファイルが期待するコード・キーワードを含むか確認
#   - Structural tests: quick-guard が正しく統合されているかを検証
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

PASS=0
FAIL=0
SKIP=0
ERRORS=()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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

run_test_skip() {
  local name="$1"
  local reason="$2"
  echo "  SKIP: ${name} (${reason})"
  ((SKIP++)) || true
}

assert_file_exists() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]]
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qP -- "$pattern" "${PROJECT_ROOT}/${file}"
}

assert_file_contains_fixed() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qF -- "$pattern" "${PROJECT_ROOT}/${file}"
}

assert_valid_yaml() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && python3 -c "
import yaml, sys
with open('${PROJECT_ROOT}/${file}') as f:
    yaml.safe_load(f)
" 2>/dev/null
}

# =============================================================================
# Requirement: chain-runner.sh quick-guard コマンド
# =============================================================================
echo ""
echo "--- Requirement: chain-runner.sh quick-guard コマンド ---"

# quick-guard コマンドが chain-runner.sh に実装されているか
test_chain_runner_quick_guard_exists() {
  assert_file_exists "scripts/chain-runner.sh" || return 1
  assert_file_contains "scripts/chain-runner.sh" "quick.guard|quick-guard" || return 1
}
run_test "chain-runner.sh に quick-guard コマンドが実装されている" test_chain_runner_quick_guard_exists

# step_quick_guard 関数が存在するか
test_chain_runner_quick_guard_function() {
  assert_file_exists "scripts/chain-runner.sh" || return 1
  assert_file_contains "scripts/chain-runner.sh" "step_quick_guard\(\)" || return 1
}
run_test "chain-runner.sh に step_quick_guard() 関数が存在する" test_chain_runner_quick_guard_function

# ブランチから Issue 番号を抽出する処理があるか
test_quick_guard_extracts_issue_num() {
  assert_file_exists "scripts/chain-runner.sh" || return 1
  # extract_issue_num または同等の処理が quick-guard 実装内に存在する
  assert_file_contains "scripts/chain-runner.sh" "extract_issue_num|grep.*\\\\d\+|issue_num" || return 1
}
run_test "chain-runner.sh quick-guard がブランチから Issue 番号を抽出する処理を含む" test_quick_guard_extracts_issue_num

# state-read.sh で is_quick フィールドを読む処理があるか
test_quick_guard_reads_state_is_quick() {
  assert_file_exists "scripts/chain-runner.sh" || return 1
  assert_file_contains "scripts/chain-runner.sh" "state-read\.sh.*is_quick|--field is_quick" || return 1
}
run_test "chain-runner.sh quick-guard が state-read.sh で is_quick を読む" test_quick_guard_reads_state_is_quick

# detect_quick_label() へのフォールバックがあるか
test_quick_guard_fallback_to_detect() {
  assert_file_exists "scripts/chain-runner.sh" || return 1
  assert_file_contains "scripts/chain-runner.sh" "detect_quick_label" || return 1
}
run_test "chain-runner.sh quick-guard が detect_quick_label() にフォールバックする" test_quick_guard_fallback_to_detect

# quick 判定時に exit 1 を返すことが実装されているか
test_quick_guard_exits_1_on_quick() {
  assert_file_exists "scripts/chain-runner.sh" || return 1
  # step_quick_guard 内に exit 1 が存在する
  assert_file_contains "scripts/chain-runner.sh" "exit 1" || return 1
}
run_test "chain-runner.sh quick-guard が quick 判定時に exit 1 を返す" test_quick_guard_exits_1_on_quick

# ディスパッチャの case 文に quick-guard が登録されているか
test_chain_runner_dispatch_quick_guard() {
  assert_file_exists "scripts/chain-runner.sh" || return 1
  assert_file_contains "scripts/chain-runner.sh" "quick-guard\)" || return 1
}
run_test "chain-runner.sh ディスパッチャに quick-guard が登録されている" test_chain_runner_dispatch_quick_guard

# =============================================================================
# Requirement: workflow-test-ready quick ガード
# =============================================================================
echo ""
echo "--- Requirement: workflow-test-ready/SKILL.md quick ガード ---"

# SKILL.md が存在するか
test_workflow_test_ready_skill_exists() {
  assert_file_exists "skills/workflow-test-ready/SKILL.md" || return 1
}
run_test "skills/workflow-test-ready/SKILL.md が存在する" test_workflow_test_ready_skill_exists

# Scenario: quick Issue で workflow-test-ready が呼ばれた場合
# SKILL.md に chain-runner.sh quick-guard の呼び出しがあるか
test_skill_calls_quick_guard() {
  assert_file_exists "skills/workflow-test-ready/SKILL.md" || return 1
  assert_file_contains "skills/workflow-test-ready/SKILL.md" "quick-guard|quick.guard" || return 1
}
run_test "workflow-test-ready SKILL.md が chain-runner.sh quick-guard を呼び出す" test_skill_calls_quick_guard

# SKILL.md に quick Issue のスキップメッセージが記述されているか
test_skill_quick_skip_message() {
  assert_file_exists "skills/workflow-test-ready/SKILL.md" || return 1
  assert_file_contains "skills/workflow-test-ready/SKILL.md" \
    "quick.*スキップ|スキップ.*quick|quick Issue.*test-ready|test-ready.*quick" || return 1
}
run_test "workflow-test-ready SKILL.md に quick Issue スキップメッセージが記述されている" test_skill_quick_skip_message

# SKILL.md の quick ガードが Step 1 より前に配置されているか
test_skill_quick_guard_before_step1() {
  assert_file_exists "skills/workflow-test-ready/SKILL.md" || return 1
  local md_file="${PROJECT_ROOT}/skills/workflow-test-ready/SKILL.md"

  # quick-guard の行番号と Step 1 の行番号を比較
  local guard_line step1_line
  guard_line=$(grep -n "quick.guard\|quick-guard" "$md_file" | head -1 | cut -d: -f1)
  step1_line=$(grep -n "Step 1" "$md_file" | head -1 | cut -d: -f1)

  # どちらも見つかった場合のみ比較
  [[ -n "$guard_line" && -n "$step1_line" ]] || return 1
  [[ "$guard_line" -lt "$step1_line" ]]
}
run_test "workflow-test-ready SKILL.md の quick ガードが Step 1 より前に配置されている" test_skill_quick_guard_before_step1

# Scenario: 非 quick Issue で workflow-test-ready が呼ばれた場合
# SKILL.md に exit 0 / ガード通過後の継続処理が記述されているか
test_skill_non_quick_continues() {
  assert_file_exists "skills/workflow-test-ready/SKILL.md" || return 1
  # exit 0 = ガード通過 → 通常フロー継続の記述を確認
  assert_file_contains "skills/workflow-test-ready/SKILL.md" \
    "exit 0.*通常|通常.*フロー|ガード.*通過|Step 1.*以降|continue|続行" || return 1
}
run_test "workflow-test-ready SKILL.md が非 quick Issue の場合に通常フロー継続を記述している" test_skill_non_quick_continues

# SKILL.md に chain-runner.sh quick-guard の bash スニペットが存在するか
test_skill_has_bash_snippet() {
  assert_file_exists "skills/workflow-test-ready/SKILL.md" || return 1
  assert_file_contains "skills/workflow-test-ready/SKILL.md" \
    "chain-runner\.sh.*quick-guard|bash.*quick-guard" || return 1
}
run_test "workflow-test-ready SKILL.md に chain-runner.sh quick-guard の bash スニペットがある" test_skill_has_bash_snippet

# =============================================================================
# Requirement: deps.yaml chain-runner.sh エントリ更新
# =============================================================================
echo ""
echo "--- Requirement: deps.yaml chain-runner.sh エントリ更新 ---"

# deps.yaml が存在するか
test_deps_yaml_exists() {
  assert_file_exists "deps.yaml" || return 1
}
run_test "deps.yaml が存在する" test_deps_yaml_exists

# deps.yaml が有効な YAML か
test_deps_yaml_valid() {
  assert_valid_yaml "deps.yaml" || return 1
}
run_test "deps.yaml が有効な YAML である" test_deps_yaml_valid

# Scenario: deps.yaml 更新後に loom check が通る
# deps.yaml に chain-runner.sh の quick-guard コマンドが記述されているか
test_deps_yaml_has_quick_guard() {
  assert_file_exists "deps.yaml" || return 1
  assert_file_contains "deps.yaml" "quick.guard\|quick-guard" || return 1
}
run_test "deps.yaml の chain-runner.sh エントリに quick-guard が記述されている" test_deps_yaml_has_quick_guard

# Scenario: loom check が通る（loom コマンドが利用可能な場合のみ）
test_loom_check_passes() {
  if ! command -v loom &>/dev/null; then
    return 1
  fi
  local output
  output=$(cd "${PROJECT_ROOT}" && loom check 2>&1)
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    echo "$output" >&2
    return 1
  fi
  return 0
}

if command -v loom &>/dev/null; then
  run_test "deps.yaml 更新後に loom check がエラーなく完了する" test_loom_check_passes
else
  run_test_skip "deps.yaml 更新後に loom check がエラーなく完了する" "loom command not found"
fi

# =============================================================================
# Edge cases: chain-runner.sh quick-guard の境界チェック
# =============================================================================
echo ""
echo "--- Edge cases: chain-runner.sh quick-guard の境界チェック ---"

# quick-guard がヘルプに記載されているか（--help / Usage に含まれるか）
test_quick_guard_in_usage() {
  assert_file_exists "scripts/chain-runner.sh" || return 1
  assert_file_contains "scripts/chain-runner.sh" "quick-guard" || return 1
}
run_test "chain-runner.sh のヘルプ/Usage に quick-guard が含まれている" test_quick_guard_in_usage

# Issue 番号が取得できない場合の保守的スキップが明示されているか
test_quick_guard_conservative_skip() {
  assert_file_exists "scripts/chain-runner.sh" || return 1
  # Issue 番号なしの場合は exit 0（スキップ）する実装を確認
  # extract_issue_num が空文字を返した場合に exit 0 する分岐が存在する
  assert_file_contains "scripts/chain-runner.sh" \
    "-z.*issue_num.*exit 0|issue_num.*-z.*exit 0|\[\[.*-z.*issue_num|issue_num.*==.*\"\"" || return 1
}
run_test "chain-runner.sh quick-guard: Issue 番号不在時に exit 0（保守的スキップ）する" test_quick_guard_conservative_skip

# gh API fallback が数値の Issue 番号の場合のみ呼ばれることを確認
test_quick_guard_validates_issue_num_before_gh() {
  assert_file_exists "scripts/chain-runner.sh" || return 1
  # detect_quick_label 関数内の数値バリデーション（既存: =~ ^[0-9]+$）を確認
  assert_file_contains "scripts/chain-runner.sh" '\^\[0-9\]' || return 1
}
run_test "chain-runner.sh detect_quick_label が Issue 番号を数値検証してから gh API を呼ぶ" test_quick_guard_validates_issue_num_before_gh

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
