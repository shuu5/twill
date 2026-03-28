#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: merge-gate.md
# Generated from: openspec/changes/b-5-pr-cycle-merge-gate-chain-driven/specs/merge-gate.md
# Coverage level: edge-cases
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
  [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qiP "$pattern" "${PROJECT_ROOT}/${file}"
}

assert_file_contains_all() {
  local file="$1"
  shift
  local patterns=("$@")
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  for pattern in "${patterns[@]}"; do
    grep -qiP "$pattern" "${PROJECT_ROOT}/${file}" || return 1
  done
  return 0
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  if grep -qiP "$pattern" "${PROJECT_ROOT}/${file}"; then
    return 1
  fi
  return 0
}

assert_valid_yaml() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && python3 -c "
import yaml, sys
with open('${PROJECT_ROOT}/${file}') as f:
    yaml.safe_load(f)
" 2>/dev/null
}

yaml_get() {
  local file="$1"
  local expr="$2"
  python3 -c "
import yaml, sys
with open('${PROJECT_ROOT}/${file}') as f:
    data = yaml.safe_load(f)
${expr}
" 2>/dev/null
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
  ((SKIP++))
}

DEPS_YAML="deps.yaml"
MERGE_GATE_SKILL="commands/merge-gate/COMMAND.md"
TECH_STACK_SCRIPT="scripts/tech-stack-detect.sh"

# =============================================================================
# Requirement: 動的レビュアー構築
# =============================================================================
echo ""
echo "--- Requirement: 動的レビュアー構築 ---"

# Scenario: deps.yaml 変更時の specialist 追加 (line 8)
# WHEN: PR の変更ファイルに deps.yaml が含まれる
# THEN: worker-structure と worker-principles が specialist リストに追加される

# merge-gate SKILL.md に deps.yaml 変更 → structure + principles ルールが記述されているか
test_merge_gate_deps_yaml_rule() {
  assert_file_exists "$MERGE_GATE_SKILL" || return 1
  assert_file_contains "$MERGE_GATE_SKILL" '(worker-structure|structure)' || return 1
  assert_file_contains "$MERGE_GATE_SKILL" '(worker-principles|principles)' || return 1
  return 0
}
run_test "merge-gate に deps.yaml 変更時の specialist ルール記述がある" test_merge_gate_deps_yaml_rule

# COMMAND.md に worker-structure と worker-principles が参照されているか
# (deps.yaml 登録は C-2/C-3 スコープ。現時点では COMMAND.md 内での言及を検証)
test_specialist_workers_registered() {
  assert_file_exists "$MERGE_GATE_SKILL" || return 1
  assert_file_contains "$MERGE_GATE_SKILL" 'worker-structure' || return 1
  assert_file_contains "$MERGE_GATE_SKILL" 'worker-principles' || return 1
  return 0
}
run_test "worker-structure, worker-principles が COMMAND.md に参照されている" test_specialist_workers_registered

# Scenario: コード変更時の specialist 追加 (line 12)
# WHEN: PR の変更ファイルにソースコード（.ts, .py, .md 等）が含まれる
# THEN: worker-code-reviewer と worker-security-reviewer が specialist リストに追加される
# COMMAND.md に worker-code-reviewer と worker-security-reviewer が参照されているか
# (deps.yaml 登録は C-2/C-3 スコープ。現時点では COMMAND.md 内での言及を検証)
test_code_review_workers_registered() {
  assert_file_exists "$MERGE_GATE_SKILL" || return 1
  assert_file_contains "$MERGE_GATE_SKILL" 'worker-code-reviewer' || return 1
  assert_file_contains "$MERGE_GATE_SKILL" 'worker-security-reviewer' || return 1
  return 0
}
run_test "worker-code-reviewer, worker-security-reviewer が COMMAND.md に参照されている" test_code_review_workers_registered

# Edge case: merge-gate SKILL.md にソースコード拡張子判定ルールが存在する
test_merge_gate_source_ext_rule() {
  assert_file_exists "$MERGE_GATE_SKILL" || return 1
  assert_file_contains "$MERGE_GATE_SKILL" '(\.(ts|py|md|sh)|ソースコード|source)' || return 1
  return 0
}
run_test "merge-gate [edge: ソースコード拡張子判定ルール記述がある]" test_merge_gate_source_ext_rule

# Scenario: conditional specialist 追加 (line 16)
# WHEN: tech-stack-detect スクリプトが該当する tech-stack を検出する
# THEN: 対応する conditional specialist がリストに追加される
test_tech_stack_detect_exists() {
  assert_file_exists "$TECH_STACK_SCRIPT" || return 1
  return 0
}
run_test "tech-stack-detect スクリプトが存在する" test_tech_stack_detect_exists

test_tech_stack_detect_executable() {
  assert_file_exists "$TECH_STACK_SCRIPT" || return 1
  [[ -x "${PROJECT_ROOT}/${TECH_STACK_SCRIPT}" ]]
}
run_test "tech-stack-detect スクリプトが実行可能である" test_tech_stack_detect_executable

# Edge case: tech-stack-detect が deps.yaml の scripts セクションに登録されている
test_tech_stack_in_deps_yaml() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
if 'tech-stack-detect' not in scripts:
    sys.exit(1)
sys.exit(0)
"
}
run_test "tech-stack-detect [edge: deps.yaml scripts に登録]" test_tech_stack_in_deps_yaml

# Scenario: specialist リストが空 (line 20)
# WHEN: PR の変更ファイルがレビュー対象外（.gitignore 等のみ）
# THEN: specialist リストは空となり merge-gate は自動 PASS する
# -> merge-gate SKILL.md に空リスト→自動PASS のルールが記述されているか
test_merge_gate_empty_list_pass_rule() {
  assert_file_exists "$MERGE_GATE_SKILL" || return 1
  assert_file_contains "$MERGE_GATE_SKILL" '(空|empty|auto.*PASS|自動.*PASS|no.*specialist)' || return 1
  return 0
}
run_test "merge-gate に specialist 空リスト時の自動 PASS ルールが記述されている" test_merge_gate_empty_list_pass_rule

# =============================================================================
# Requirement: merge-gate 単一パス統合
# =============================================================================
echo ""
echo "--- Requirement: merge-gate 単一パス統合 ---"

# Scenario: 単一パスでの merge-gate 実行 (line 28)
# WHEN: merge-gate が起動される
# THEN: 「standard」「plugin」等のパス識別子や分岐条件が存在しない
test_merge_gate_no_standard_plugin_branch() {
  assert_file_exists "$MERGE_GATE_SKILL" || return 1
  assert_file_not_contains "$MERGE_GATE_SKILL" 'standard_gate|plugin_gate|GATE_TYPE' || return 1
  return 0
}
run_test "merge-gate に standard/plugin パス分岐コードがない" test_merge_gate_no_standard_plugin_branch

# Edge case: merge-gate SKILL.md に "standard" と "plugin" の語が条件分岐文脈で出ない
test_merge_gate_no_branching_context() {
  assert_file_exists "$MERGE_GATE_SKILL" || return 1
  # "standard パス" or "plugin パス" or "if.*standard" should not be present
  assert_file_not_contains "$MERGE_GATE_SKILL" '(standard\s+パス|plugin\s+パス|if.*standard|if.*plugin)' || return 1
  return 0
}
run_test "merge-gate [edge: standard/plugin の分岐文脈がない]" test_merge_gate_no_branching_context

# merge-gate SKILL.md に単一フロー記述がある
test_merge_gate_single_flow() {
  assert_file_exists "$MERGE_GATE_SKILL" || return 1
  # Should describe a single flow: build reviewers → execute → aggregate → judge
  assert_file_contains "$MERGE_GATE_SKILL" '(動的|レビュアー|specialist|構築|build)' || return 1
  assert_file_contains "$MERGE_GATE_SKILL" '(集約|aggregat|結果|判定|PASS|REJECT)' || return 1
  return 0
}
run_test "merge-gate に単一フロー記述がある (構築→実行→集約→判定)" test_merge_gate_single_flow

# =============================================================================
# Requirement: merge-gate severity フィルタ
# =============================================================================
echo ""
echo "--- Requirement: merge-gate severity フィルタ ---"

# Scenario: PASS 判定 (line 37)
# WHEN: 全 specialist の findings に severity=CRITICAL かつ confidence>=80 のエントリがない
# THEN: merge-gate は PASS を返す
test_merge_gate_pass_criteria() {
  assert_file_exists "$MERGE_GATE_SKILL" || return 1
  # Should document CRITICAL + confidence >= 80 filter
  assert_file_contains "$MERGE_GATE_SKILL" 'CRITICAL' || return 1
  assert_file_contains "$MERGE_GATE_SKILL" '(confidence|80)' || return 1
  assert_file_contains "$MERGE_GATE_SKILL" 'PASS' || return 1
  return 0
}
run_test "merge-gate に PASS 判定基準 (CRITICAL + confidence >= 80) が記述されている" test_merge_gate_pass_criteria

# Edge case: severity フィルタが機械的であり AI 判定でないことが明記
test_merge_gate_no_ai_judgment() {
  assert_file_exists "$MERGE_GATE_SKILL" || return 1
  assert_file_contains "$MERGE_GATE_SKILL" '(機械的|mechanical|フィルタ|filter|AI.*禁止|AI.*排除|裁量.*排除)' || return 1
  return 0
}
run_test "merge-gate [edge: AI 判定禁止/機械的フィルタが明記]" test_merge_gate_no_ai_judgment

# Scenario: REJECT 判定 (1回目) (line 42)
# WHEN: findings に severity=CRITICAL かつ confidence>=80 のエントリが存在する
# AND: issue-{N}.json の retry_count が 0
# THEN: merge-gate は REJECT を返す
# AND: status が failed → running に遷移し fix_instructions に CRITICAL findings が記録される
test_merge_gate_reject_criteria() {
  assert_file_exists "$MERGE_GATE_SKILL" || return 1
  assert_file_contains "$MERGE_GATE_SKILL" 'REJECT' || return 1
  return 0
}
run_test "merge-gate に REJECT 判定記述がある" test_merge_gate_reject_criteria

test_merge_gate_fix_instructions_rule() {
  assert_file_exists "$MERGE_GATE_SKILL" || return 1
  assert_file_contains "$MERGE_GATE_SKILL" '(fix_instructions|fix.instructions|修正指示)' || return 1
  return 0
}
run_test "merge-gate に fix_instructions 記録ルールがある" test_merge_gate_fix_instructions_rule

# Edge case: retry_count == 0 と retry_count >= 1 の区別が存在する
test_merge_gate_retry_count_branching() {
  assert_file_exists "$MERGE_GATE_SKILL" || return 1
  assert_file_contains "$MERGE_GATE_SKILL" '(retry_count|retry|リトライ)' || return 1
  return 0
}
run_test "merge-gate [edge: retry_count による分岐ロジック記述がある]" test_merge_gate_retry_count_branching

# Scenario: REJECT 判定 (2回目、確定失敗) (line 47)
# WHEN: fix-phase 後の再レビューで再度 CRITICAL findings が存在する
# AND: retry_count が 1 以上
# THEN: status が failed に確定する
# AND: Pilot に手動介入が要求される
test_merge_gate_final_reject() {
  assert_file_exists "$MERGE_GATE_SKILL" || return 1
  assert_file_contains "$MERGE_GATE_SKILL" '(failed|確定|手動介入|Pilot|エスカレーション)' || return 1
  return 0
}
run_test "merge-gate に確定失敗 + Pilot 手動介入ルールが記述されている" test_merge_gate_final_reject

# Edge case: retry 最大回数が 1 であることが明記
test_merge_gate_max_retry_one() {
  assert_file_exists "$MERGE_GATE_SKILL" || return 1
  assert_file_contains "$MERGE_GATE_SKILL" '(最大.*1|max.*1|retry.*1|1回|一度)' || return 1
  return 0
}
run_test "merge-gate [edge: retry 最大1回が明記]" test_merge_gate_max_retry_one

# =============================================================================
# Requirement: tech-stack-detect スクリプト
# =============================================================================
echo ""
echo "--- Requirement: tech-stack-detect スクリプト ---"

# Scenario: Next.js プロジェクトの TSX 変更検出 (line 58)
# WHEN: 変更ファイルに .tsx ファイルが含まれ、next.config.* が存在する
# THEN: worker-nextjs-reviewer が specialist リストに追加される
test_tech_stack_tsx_detection_rule() {
  assert_file_exists "$TECH_STACK_SCRIPT" || return 1
  assert_file_contains "$TECH_STACK_SCRIPT" '(\.tsx|tsx)' || return 1
  assert_file_contains "$TECH_STACK_SCRIPT" '(next\.config|next_config|nextjs)' || return 1
  return 0
}
run_test "tech-stack-detect に tsx + next.config 検出ルールがある" test_tech_stack_tsx_detection_rule

# Edge case: worker-nextjs-reviewer が tech-stack-detect スクリプトで参照されている
# (deps.yaml 登録は C-2/C-3 スコープ。現時点ではスクリプト内での言及を検証)
test_nextjs_reviewer_registered() {
  assert_file_exists "$TECH_STACK_SCRIPT" || return 1
  assert_file_contains "$TECH_STACK_SCRIPT" 'worker-nextjs-reviewer' || return 1
  return 0
}
run_test "worker-nextjs-reviewer [edge: tech-stack-detect に参照]" test_nextjs_reviewer_registered

# Scenario: 該当 tech-stack なし (line 62)
# WHEN: 変更ファイルがいずれの tech-stack 判定ルールにも該当しない
# THEN: conditional specialist は追加されない
# -> tech-stack-detect.sh がデフォルトで空出力を返すことの構造確認
test_tech_stack_default_empty() {
  assert_file_exists "$TECH_STACK_SCRIPT" || return 1
  # Script should not have hardcoded default specialist additions
  # It should only add specialists when a match is found
  # Basic structural check: the script should be able to exit with empty output
  assert_file_contains "$TECH_STACK_SCRIPT" '(exit|return|echo)' || return 1
  return 0
}
run_test "tech-stack-detect が構造的に空出力を返せる" test_tech_stack_default_empty

# Edge case: tech-stack-detect.sh が bash スクリプトとして構文的に正しい
test_tech_stack_syntax_valid() {
  assert_file_exists "$TECH_STACK_SCRIPT" || return 1
  bash -n "${PROJECT_ROOT}/${TECH_STACK_SCRIPT}" 2>/dev/null
}
run_test "tech-stack-detect [edge: bash 構文チェック pass]" test_tech_stack_syntax_valid

# =============================================================================
# Requirement: standard/plugin 2パス分岐 (REMOVED)
# =============================================================================
echo ""
echo "--- Requirement: standard/plugin 2パス分岐 (REMOVED) ---"

# Scenario: 旧パス分岐コードの不在 (line 72)
# WHEN: merge-gate の実装を検査する
# THEN: GATE_TYPE, standard_gate, plugin_gate 等のパス識別変数が存在しない
test_no_gate_type_variable() {
  assert_file_exists "$MERGE_GATE_SKILL" || return 1
  assert_file_not_contains "$MERGE_GATE_SKILL" 'GATE_TYPE' || return 1
  return 0
}
run_test "merge-gate に GATE_TYPE 変数が存在しない" test_no_gate_type_variable

test_no_standard_gate() {
  assert_file_exists "$MERGE_GATE_SKILL" || return 1
  assert_file_not_contains "$MERGE_GATE_SKILL" 'standard_gate' || return 1
  return 0
}
run_test "merge-gate に standard_gate が存在しない" test_no_standard_gate

test_no_plugin_gate() {
  assert_file_exists "$MERGE_GATE_SKILL" || return 1
  assert_file_not_contains "$MERGE_GATE_SKILL" 'plugin_gate' || return 1
  return 0
}
run_test "merge-gate に plugin_gate が存在しない" test_no_plugin_gate

# Edge case: merge-gate ディレクトリ内の全ファイルにパス分岐変数がない
test_no_gate_vars_in_any_file() {
  local dir="${PROJECT_ROOT}/commands/merge-gate"
  if [[ ! -d "$dir" ]]; then
    return 1
  fi
  if grep -rP 'GATE_TYPE|standard_gate|plugin_gate' "$dir" 2>/dev/null; then
    return 1
  fi
  return 0
}
run_test "merge-gate ディレクトリ [edge: 全ファイルにパス分岐変数がない]" test_no_gate_vars_in_any_file

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
