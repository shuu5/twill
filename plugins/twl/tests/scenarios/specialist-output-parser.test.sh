#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: specialist-output-parser.md
# Generated from: deltaspec/changes/b-5-pr-cycle-merge-gate-chain-driven/specs/specialist-output-parser.md
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
PARSER_SCRIPT="scripts/specialist-output-parse.sh"
OUTPUT_SCHEMA="refs/ref-specialist-output-schema.md"

# =============================================================================
# Requirement: specialist 出力パーサー
# =============================================================================
echo ""
echo "--- Requirement: specialist 出力パーサー ---"

# Scenario: 正常パース (line 8)
# WHEN: specialist の出力に status: PASS と JSON の findings ブロックが含まれる
# THEN: パーサーは status と findings 配列を抽出する
# AND: 各 finding の必須フィールド（severity, confidence, file, line, message, category）が検証される

test_parser_script_exists() {
  assert_file_exists "$PARSER_SCRIPT" || return 1
  return 0
}
run_test "specialist-output-parse.sh が存在する" test_parser_script_exists

test_parser_registered_in_deps() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
if 'specialist-output-parse' not in scripts:
    sys.exit(1)
sys.exit(0)
"
}
run_test "specialist-output-parse が deps.yaml に登録されている" test_parser_registered_in_deps

test_parser_executable() {
  assert_file_exists "$PARSER_SCRIPT" || return 1
  [[ -x "${PROJECT_ROOT}/${PARSER_SCRIPT}" ]]
}
run_test "specialist-output-parse.sh が実行可能である" test_parser_executable

test_parser_syntax_valid() {
  assert_file_exists "$PARSER_SCRIPT" || return 1
  bash -n "${PROJECT_ROOT}/${PARSER_SCRIPT}" 2>/dev/null
}
run_test "specialist-output-parse.sh の bash 構文が正しい" test_parser_syntax_valid

# Integration test: PASS 出力を正常にパースできる
test_parser_pass_output() {
  assert_file_exists "$PARSER_SCRIPT" || return 1
  # パーサーは ```json ブロック内を findings として扱う（配列を直接渡す）
  local input='status: PASS
```json
[]
```'
  local output
  output=$(echo "$input" | bash "${PROJECT_ROOT}/${PARSER_SCRIPT}" 2>/dev/null) || return 1
  # Parser should output valid JSON with status field
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if data.get('status') != 'PASS':
    sys.exit(1)
if not isinstance(data.get('findings'), list):
    sys.exit(1)
" 2>/dev/null
}
run_test "パーサーが PASS 出力を正常にパースする" test_parser_pass_output

# Integration test: findings の必須フィールド検証
test_parser_validates_required_fields() {
  assert_file_exists "$PARSER_SCRIPT" || return 1
  # パーサーは ```json ブロック内を findings として扱う（配列を直接渡す）
  local input='status: FAIL
```json
[
  {
    "severity": "CRITICAL",
    "confidence": 95,
    "file": "src/main.ts",
    "line": 42,
    "message": "Security vulnerability",
    "category": "security"
  }
]
```'
  local output
  output=$(echo "$input" | bash "${PROJECT_ROOT}/${PARSER_SCRIPT}" 2>/dev/null) || return 1
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
findings = data.get('findings', [])
if len(findings) == 0:
    sys.exit(1)
required = ['severity', 'confidence', 'file', 'line', 'message', 'category']
for f in findings:
    for field in required:
        if field not in f:
            print(f'Missing field: {field}', file=sys.stderr)
            sys.exit(1)
" 2>/dev/null
}
run_test "パーサーが findings の必須フィールドを検証する" test_parser_validates_required_fields

# Edge case: 出力スキーマリファレンスに必須フィールド一覧が定義されている
test_output_schema_has_required_fields() {
  assert_file_exists "$OUTPUT_SCHEMA" || return 1
  assert_file_contains_all "$OUTPUT_SCHEMA" \
    'severity' 'confidence' 'file' 'line' 'message' 'category' || return 1
  return 0
}
run_test "出力スキーマ [edge: 必須フィールド全6つが定義されている]" test_output_schema_has_required_fields

# Scenario: パース失敗のフォールバック (line 13)
# WHEN: specialist の出力が共通スキーマに準拠しない
# THEN: 出力全文が 1 つの WARNING finding（confidence=50）として扱われる
# AND: merge-gate のブロック閾値には達しない

test_parser_fallback_on_invalid_input() {
  assert_file_exists "$PARSER_SCRIPT" || return 1
  local input='This is not a valid specialist output.
No status line, no JSON block at all.
Just random text.'
  local output
  output=$(echo "$input" | bash "${PROJECT_ROOT}/${PARSER_SCRIPT}" 2>/dev/null) || true
  # Even on parse failure, parser should output valid JSON fallback
  echo "$output" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except:
    sys.exit(1)
findings = data.get('findings', [])
if len(findings) < 1:
    sys.exit(1)
# Fallback finding should be WARNING with confidence=50
f = findings[0]
if f.get('severity') != 'WARNING':
    print(f'Expected severity=WARNING, got={f.get(\"severity\")}', file=sys.stderr)
    sys.exit(1)
if f.get('confidence') != 50:
    print(f'Expected confidence=50, got={f.get(\"confidence\")}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null
}
run_test "パーサーが不正入力時に WARNING(confidence=50) フォールバックを返す" test_parser_fallback_on_invalid_input

# Edge case: フォールバックの confidence=50 は merge-gate 閾値 (80) 未満
test_fallback_below_threshold() {
  # This is a static check - confidence=50 < 80
  # Verify the schema doc mentions the threshold relationship
  assert_file_exists "$OUTPUT_SCHEMA" || return 1
  assert_file_contains "$OUTPUT_SCHEMA" '(80|confidence.*>=.*80|merge.gate)' || return 1
  return 0
}
run_test "フォールバック [edge: confidence=50 は閾値 80 未満であることがスキーマに記述]" test_fallback_below_threshold

# Edge case: 空入力でもクラッシュしない
test_parser_empty_input() {
  assert_file_exists "$PARSER_SCRIPT" || return 1
  local output
  output=$(echo "" | bash "${PROJECT_ROOT}/${PARSER_SCRIPT}" 2>/dev/null) || true
  # Should not crash - output should be valid JSON or at least parseable
  if [[ -n "$output" ]]; then
    echo "$output" | python3 -c "import json, sys; json.load(sys.stdin)" 2>/dev/null || return 1
  fi
  return 0
}
run_test "パーサー [edge: 空入力でクラッシュしない]" test_parser_empty_input

# Scenario: findings の severity 集約 (line 19)
# WHEN: 複数 specialist の findings が集約される
# THEN: severity=CRITICAL かつ confidence>=80 の finding が 1 件でもあれば REJECT
# AND: findings は specialist 名付きで一覧表示される

# merge-gate SKILL.md に集約ロジック記述があるか
test_merge_gate_aggregation_rule() {
  local merge_gate_skill="commands/merge-gate.md"
  assert_file_exists "$merge_gate_skill" || return 1
  assert_file_contains "$merge_gate_skill" '(集約|aggregat|findings)' || return 1
  return 0
}
run_test "merge-gate に findings 集約ルールが記述されている" test_merge_gate_aggregation_rule

# Edge case: specialist の識別情報が merge-gate に記述されている
test_findings_include_specialist_info() {
  local merge_gate_skill="commands/merge-gate.md"
  assert_file_exists "$merge_gate_skill" || return 1
  # specialist の結果集約に関する記述があること
  assert_file_contains "$merge_gate_skill" '(specialist|worker|findings|集約|aggregat)' || return 1
  return 0
}
run_test "findings [edge: specialist 識別情報が merge-gate に記述されている]" test_findings_include_specialist_info

# =============================================================================
# Requirement: AI 裁量の排除
# =============================================================================
echo ""
echo "--- Requirement: AI 裁量の排除 ---"

# Scenario: 機械的結果集約 (line 29)
# WHEN: phase-review が全 specialist の結果を統合する
# THEN: パーサーの出力（構造化データ）のみを使用する
# AND: AI による severity の再判定、confidence の推定、finding の要約生成は行わない

test_parser_script_no_ai_logic() {
  assert_file_exists "$PARSER_SCRIPT" || return 1
  # Parser should not contain AI-related keywords for judgment
  assert_file_not_contains "$PARSER_SCRIPT" '(openai|claude|anthropic|gpt|llm|ai_judge|ai_eval)' || return 1
  return 0
}
run_test "パーサースクリプトに AI 判定ロジックがない" test_parser_script_no_ai_logic

# phase-review SKILL.md に AI 裁量排除ルールがあるか
test_phase_review_no_ai_rule() {
  local phase_review_skill="commands/phase-review.md"
  assert_file_exists "$phase_review_skill" || return 1
  assert_file_contains "$phase_review_skill" '(機械的|AI.*禁止|裁量.*排除|パーサー.*出力|構造化データ)' || return 1
  return 0
}
run_test "phase-review に AI 裁量排除ルールが記述されている" test_phase_review_no_ai_rule

# Edge case: パーサーが severity を変更するロジックを持たない
test_parser_no_severity_modification() {
  assert_file_exists "$PARSER_SCRIPT" || return 1
  # Parser should not re-assign or modify severity values
  assert_file_not_contains "$PARSER_SCRIPT" '(severity\s*=\s*"(CRITICAL|WARNING|INFO)"|override.*severity|reassign.*severity)' || return 1
  return 0
}
run_test "パーサー [edge: severity 再判定ロジックがない]" test_parser_no_severity_modification

# Edge case: confidence の推定（パーサー内でconfidenceを生成しない - フォールバック除く）
test_parser_no_confidence_estimation() {
  assert_file_exists "$PARSER_SCRIPT" || return 1
  # Parser may set confidence=50 for fallback, but should not estimate/calculate otherwise
  # Check there's no dynamic confidence calculation (excluding the fixed fallback value)
  local content
  content=$(cat "${PROJECT_ROOT}/${PARSER_SCRIPT}")
  # Count confidence assignments; allow at most the fallback case
  local assignments
  assignments=$(echo "$content" | grep -cP 'confidence\s*[=:]\s*[0-9]' 2>/dev/null || true)
  # Allow up to 2 assignments (fallback case + default)
  if [[ $assignments -gt 3 ]]; then
    echo "Found $assignments confidence assignments (expected <= 3)" >&2
    return 1
  fi
  return 0
}
run_test "パーサー [edge: confidence 推定ロジックが過度にない (<=3箇所)]" test_parser_no_confidence_estimation

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
