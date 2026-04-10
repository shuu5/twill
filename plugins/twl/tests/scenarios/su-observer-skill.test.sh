#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: su-observer SKILL.md
# Generated from: deltaspec/changes/issue-356/specs/su-observer/spec.md
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

assert_dir_exists() {
  local dir="$1"
  [[ -d "${PROJECT_ROOT}/${dir}" ]]
}

assert_dir_not_exists() {
  local dir="$1"
  [[ ! -d "${PROJECT_ROOT}/${dir}" ]]
}

assert_file_not_exists() {
  local file="$1"
  [[ ! -f "${PROJECT_ROOT}/${file}" ]]
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qiP -- "$pattern" "${PROJECT_ROOT}/${file}"
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  if grep -qiP -- "$pattern" "${PROJECT_ROOT}/${file}"; then
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

SU_OBSERVER_SKILL="skills/su-observer/SKILL.md"
CO_OBSERVER_DIR="skills/co-observer"
DEPS_YAML="deps.yaml"

# =============================================================================
# Requirement: su-observer ディレクトリ作成
# Scenario: ディレクトリリネーム完了 (line 7)
# WHEN: plugins/twl/skills/ ディレクトリを確認する
# THEN: co-observer/ が存在せず、su-observer/ が存在する
# =============================================================================
echo ""
echo "--- Requirement: su-observer ディレクトリ作成 ---"

# Test: su-observer/ ディレクトリが存在する
test_su_observer_dir_exists() {
  assert_dir_exists "skills/su-observer"
}
run_test "su-observer/ ディレクトリが存在する" test_su_observer_dir_exists

# Test: co-observer/ ディレクトリが存在しない
test_co_observer_dir_not_exists() {
  assert_dir_not_exists "skills/co-observer"
}
run_test "co-observer/ ディレクトリが存在しない" test_co_observer_dir_not_exists

# Edge case: su-observer/SKILL.md が存在する（ディレクトリだけでなくファイルも）
test_su_observer_skillmd_exists() {
  assert_file_exists "$SU_OBSERVER_SKILL"
}
run_test "su-observer [edge: SKILL.md が存在する]" test_su_observer_skillmd_exists

# Edge case: co-observer/SKILL.md が存在しない
test_co_observer_skillmd_not_exists() {
  assert_file_not_exists "skills/co-observer/SKILL.md"
}
run_test "co-observer [edge: SKILL.md が存在しない]" test_co_observer_skillmd_not_exists

# Edge case: skills/ 配下に co-observer 文字列を含むディレクトリが存在しない
test_no_co_observer_any() {
  if ls "${PROJECT_ROOT}/skills/" 2>/dev/null | grep -q "co-observer"; then
    return 1
  fi
  return 0
}
run_test "skills/ [edge: co-observer を含むディレクトリが一切存在しない]" test_no_co_observer_any

# =============================================================================
# Requirement: su-observer SKILL.md の frontmatter
# Scenario: supervisor 型 frontmatter (line 15)
# WHEN: su-observer/SKILL.md の frontmatter を参照する
# THEN: type: supervisor、name: twl:su-observer、spawnable_by: [user] が定義されている
# =============================================================================
echo ""
echo "--- Requirement: su-observer SKILL.md の frontmatter ---"

# Test: type: supervisor が定義されている
test_frontmatter_type_supervisor() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "^type:\s*supervisor"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "frontmatter type: supervisor が定義されている" test_frontmatter_type_supervisor
else
  run_test_skip "frontmatter type: supervisor" "skills/su-observer/SKILL.md not yet created"
fi

# Test: name: twl:su-observer が定義されている
test_frontmatter_name() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "^name:\s*twl:su-observer"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "frontmatter name: twl:su-observer が定義されている" test_frontmatter_name
else
  run_test_skip "frontmatter name: twl:su-observer" "skills/su-observer/SKILL.md not yet created"
fi

# Test: spawnable_by に user が含まれている
test_frontmatter_spawnable_by_user() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "spawnable_by:.*\[.*user.*\]|spawnable_by:\s*\n\s*-\s*user"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "frontmatter spawnable_by: [user] が定義されている" test_frontmatter_spawnable_by_user
else
  run_test_skip "frontmatter spawnable_by: [user]" "skills/su-observer/SKILL.md not yet created"
fi

# Edge case: frontmatter が YAML フェンス（---）で囲まれている
test_frontmatter_yaml_fence() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  head -1 "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" | grep -q "^---"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "frontmatter [edge: YAML フェンス --- で始まる]" test_frontmatter_yaml_fence
else
  run_test_skip "frontmatter [edge: YAML フェンス]" "skills/su-observer/SKILL.md not yet created"
fi

# Edge case: type が observer や controller など誤った値でない
test_frontmatter_type_not_observer() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_not_contains "$SU_OBSERVER_SKILL" "^type:\s*observer" || return 1
  assert_file_not_contains "$SU_OBSERVER_SKILL" "^type:\s*controller" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "frontmatter [edge: type が observer/controller でない]" test_frontmatter_type_not_observer
else
  run_test_skip "frontmatter [edge: type が observer/controller でない]" "skills/su-observer/SKILL.md not yet created"
fi

# Edge case: name が twl:co-observer など旧名称でない
test_frontmatter_name_not_co_observer() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_not_contains "$SU_OBSERVER_SKILL" "^name:\s*twl:co-observer"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "frontmatter [edge: name が twl:co-observer でない]" test_frontmatter_name_not_co_observer
else
  run_test_skip "frontmatter [edge: name が twl:co-observer でない]" "skills/su-observer/SKILL.md not yet created"
fi

# =============================================================================
# Requirement: Step 0〜7 の基本構造定義
# Scenario: Step 0〜7 の全ステップ存在 (line 22)
# WHEN: su-observer/SKILL.md の見出し構造を確認する
# THEN: Step 0 から Step 7 まで全てのステップが定義されている
# =============================================================================
echo ""
echo "--- Requirement: Step 0〜7 の基本構造定義 ---"

# Test: Step 0 が存在する
test_step0_exists() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "Step\s*0"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "Step 0 が定義されている" test_step0_exists
else
  run_test_skip "Step 0" "skills/su-observer/SKILL.md not yet created"
fi

# Test: Step 1 が存在する
test_step1_exists() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "Step\s*1"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "Step 1 が定義されている" test_step1_exists
else
  run_test_skip "Step 1" "skills/su-observer/SKILL.md not yet created"
fi

# Test: Step 2 が存在する
test_step2_exists() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "Step\s*2"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "Step 2 が定義されている" test_step2_exists
else
  run_test_skip "Step 2" "skills/su-observer/SKILL.md not yet created"
fi

# Test: Step 3 が存在する
test_step3_exists() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "Step\s*3"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "Step 3 が定義されている" test_step3_exists
else
  run_test_skip "Step 3" "skills/su-observer/SKILL.md not yet created"
fi

# Test: Step 4 が存在する
test_step4_exists() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "Step\s*4"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "Step 4 が定義されている" test_step4_exists
else
  run_test_skip "Step 4" "skills/su-observer/SKILL.md not yet created"
fi

# Test: Step 5 が存在する
test_step5_exists() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "Step\s*5"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "Step 5 が定義されている" test_step5_exists
else
  run_test_skip "Step 5" "skills/su-observer/SKILL.md not yet created"
fi

# Test: Step 6 が存在する
test_step6_exists() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "Step\s*6"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "Step 6 が定義されている" test_step6_exists
else
  run_test_skip "Step 6" "skills/su-observer/SKILL.md not yet created"
fi

# Test: Step 7 が存在する
test_step7_exists() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "Step\s*7"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "Step 7 が定義されている" test_step7_exists
else
  run_test_skip "Step 7" "skills/su-observer/SKILL.md not yet created"
fi

# Edge case: Step 8 以上が存在しない（0〜7 のみ）
test_no_step_8_or_above() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_not_contains "$SU_OBSERVER_SKILL" "Step\s*8" || return 1
  assert_file_not_contains "$SU_OBSERVER_SKILL" "Step\s*9" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "Step 構造 [edge: Step 8 以上が存在しない]" test_no_step_8_or_above
else
  run_test_skip "Step 構造 [edge: Step 8 以上なし]" "skills/su-observer/SKILL.md not yet created"
fi

# =============================================================================
# Requirement: Step 0〜7 の基本構造定義
# Scenario: Step 4〜7 はプレースホルダー (line 26)
# WHEN: Step 4〜7 の内容を参照する
# THEN: 後続 Issue で詳細化される旨のプレースホルダーが記載されている
# =============================================================================
echo ""
echo "--- Requirement: Step 4〜7 プレースホルダー確認 ---"

# Test: Step 4〜7 にプレースホルダー記述が存在する
test_steps_4to7_placeholder() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "後続.*Issue|詳細化|placeholder|TBD|TODO|以降.*Issue|将来.*実装"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "Step 4〜7 プレースホルダー記述が存在する" test_steps_4to7_placeholder
else
  run_test_skip "Step 4〜7 プレースホルダー" "skills/su-observer/SKILL.md not yet created"
fi

# Edge case: Step 0〜3 に「後続 Issue」「TBD」等のプレースホルダー記述が存在しない（実装済みであること）
test_steps_0to3_not_placeholder() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  # Step 0〜3 セクションだけ抽出して確認（Step 4 より前の部分）
  # ヘッダー行が Step 0 から始まりStep 4 の前まで
  python3 - "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" <<'PYEOF'
import re, sys

with open(sys.argv[1]) as f:
    content = f.read()

# Step 4 以降を除いた前半部分を抽出（大雑把に Step 4 見出し行の前まで）
# "Step 4" が現れる位置を探す
step4_match = re.search(r'(##+ Step\s*4|Step\s*4[:\s])', content, re.IGNORECASE)
if step4_match:
    before_step4 = content[:step4_match.start()]
else:
    before_step4 = content

# 前半部分に「後続 Issue / TBD / TODO / placeholder」が含まれていないか確認
placeholder_pattern = re.compile(r'後続.*Issue|placeholder|TBD\b|TODO\b|将来.*実装', re.IGNORECASE)
if placeholder_pattern.search(before_step4):
    print("Step 0-3 section contains placeholder text", file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PYEOF
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "Step 0〜3 [edge: プレースホルダーでなく実装済み記述]" test_steps_0to3_not_placeholder
else
  run_test_skip "Step 0〜3 [edge: プレースホルダーなし]" "skills/su-observer/SKILL.md not yet created"
fi

# =============================================================================
# Requirement: deps.yaml の co-observer 参照更新
# Scenario: deps.yaml 参照更新 (line 35)
# WHEN: plugins/twl/deps.yaml を参照する
# THEN: co-observer キーが存在せず、su-observer キーが type: supervisor で定義されている
# =============================================================================
echo ""
echo "--- Requirement: deps.yaml の co-observer 参照更新 ---"

# Test: deps.yaml に co-observer キーが存在しない（スキルエントリとして）
test_deps_no_co_observer_key() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
if 'co-observer' in skills:
    print('co-observer key still exists in skills', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に co-observer スキルキーが存在しない" test_deps_no_co_observer_key

# Test: deps.yaml に su-observer キーが存在する
test_deps_su_observer_key_exists() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
if 'su-observer' not in skills:
    print('su-observer key missing from skills', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に su-observer スキルキーが存在する" test_deps_su_observer_key_exists

# Test: deps.yaml の su-observer エントリが type: supervisor である
test_deps_su_observer_type_supervisor() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
su = skills.get('su-observer', {})
t = su.get('type')
if t != 'supervisor':
    print(f'su-observer type={t!r}, expected supervisor', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml su-observer type: supervisor で定義されている" test_deps_su_observer_type_supervisor

# Edge case: deps.yaml の su-observer path が skills/su-observer/SKILL.md を指している
test_deps_su_observer_path() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
su = skills.get('su-observer', {})
path = su.get('path', '')
if 'su-observer' not in path:
    print(f'su-observer path={path!r}, expected to contain su-observer', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml su-observer [edge: path が su-observer/SKILL.md を指す]" test_deps_su_observer_path

# Edge case: deps.yaml に co-observer を参照している文字列が残っていない
test_deps_no_co_observer_reference_string() {
  assert_file_exists "$DEPS_YAML" || return 1
  # "controller: co-observer" や "skills/co-observer/" のような参照が残っていないか
  if grep -qP "skills/co-observer/|controller:\s*co-observer|:\s*co-observer\b" "${PROJECT_ROOT}/${DEPS_YAML}"; then
    echo "co-observer reference string still exists in deps.yaml" >&2
    return 1
  fi
  return 0
}
run_test "deps.yaml [edge: co-observer 参照文字列が残っていない]" test_deps_no_co_observer_reference_string

# Edge case: deps.yaml が valid YAML である
test_deps_valid_yaml() {
  assert_valid_yaml "$DEPS_YAML"
}
run_test "deps.yaml [edge: YAML として有効]" test_deps_valid_yaml

# =============================================================================
# Requirement: co-observer SKILL.md の削除
# Scenario: co-observer 削除確認 (line 44)
# WHEN: plugins/twl/skills/co-observer/ の存在を確認する
# THEN: ディレクトリが存在しない
# =============================================================================
echo ""
echo "--- Requirement: co-observer SKILL.md の削除 ---"

# Test: co-observer/ ディレクトリが存在しない（再確認）
test_co_observer_dir_deleted() {
  assert_dir_not_exists "skills/co-observer"
}
run_test "co-observer/ ディレクトリが削除されている" test_co_observer_dir_deleted

# Edge case: co-observer/SKILL.md が存在しない（ファイル単体も確認）
test_co_observer_skillmd_deleted() {
  assert_file_not_exists "skills/co-observer/SKILL.md"
}
run_test "co-observer [edge: SKILL.md が存在しない]" test_co_observer_skillmd_deleted

# Edge case: git ls-files で co-observer が追跡されていない
test_co_observer_not_tracked() {
  if git -C "${PROJECT_ROOT}" ls-files --error-unmatch "skills/co-observer/SKILL.md" 2>/dev/null; then
    echo "co-observer/SKILL.md is still tracked by git" >&2
    return 1
  fi
  return 0
}
run_test "co-observer [edge: git で追跡されていない]" test_co_observer_not_tracked

# =============================================================================
# Requirement: twl validate の PASS
# Scenario: validate 通過 (line 52)
# WHEN: twl validate を実行する
# THEN: エラーなしで PASS する（supervisor 型が types.yaml に定義済みであることが前提）
# =============================================================================
echo ""
echo "--- Requirement: twl validate の PASS ---"

# Test: types.yaml に supervisor 型が定義されている（validate の前提条件）
test_types_yaml_supervisor() {
  local types_yaml
  # types.yaml は cli/twl/ または plugins/twl/ にある可能性
  for candidate in "${PROJECT_ROOT}/../../cli/twl/types.yaml" "${PROJECT_ROOT}/types.yaml"; do
    if [[ -f "$candidate" ]] && grep -qP "supervisor" "$candidate"; then
      return 0
    fi
  done
  return 1
}
run_test "types.yaml に supervisor 型が定義されている（validate 前提）" test_types_yaml_supervisor

# Test: twl validate が実行可能（コマンドの存在確認）
test_twl_validate_available() {
  command -v twl >/dev/null 2>&1 || \
    [[ -x "${PROJECT_ROOT}/../../cli/twl/twl" ]] || \
    python3 -m twl --help >/dev/null 2>&1
}
run_test "twl コマンドが実行可能" test_twl_validate_available

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
