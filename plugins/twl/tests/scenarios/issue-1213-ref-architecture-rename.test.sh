#!/usr/bin/env bash
# =============================================================================
# TDD RED Tests: Issue #1213 ref-architecture.md -> ref-skill-arch-patterns.md
# Tests are intentionally written to FAIL before implementation.
# =============================================================================
set -uo pipefail

# Project root (relative to this test file location)
PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Counters
PASS=0
FAIL=0
SKIP=0
ERRORS=()

# --- Test Helpers ---

assert_file_exists() {
  local file="$1"
  [[ -f "${PLUGIN_ROOT}/${file}" ]]
}

assert_file_not_exists() {
  local file="$1"
  [[ ! -f "${PLUGIN_ROOT}/${file}" ]]
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PLUGIN_ROOT}/${file}" ]] && grep -qP "$pattern" "${PLUGIN_ROOT}/${file}"
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PLUGIN_ROOT}/${file}" ]] || return 1
  if grep -qP "$pattern" "${PLUGIN_ROOT}/${file}"; then
    return 1
  fi
  return 0
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

# =============================================================================
# AC1: git mv でリネーム — ref-skill-arch-patterns.md が存在し、ref-architecture.md が不在
# =============================================================================
echo ""
echo "--- AC1: git mv リネーム検証 ---"

# AC1a: ref-skill-arch-patterns.md が存在する
test_ac1_new_file_exists() {
  # RED: 実装前は ref-skill-arch-patterns.md が存在しないため fail する
  assert_file_exists "refs/ref-skill-arch-patterns.md"
}
run_test "AC1: refs/ref-skill-arch-patterns.md が存在する" test_ac1_new_file_exists

# AC1b: ref-architecture.md が存在しない（git mv で削除済み）
test_ac1_old_file_gone() {
  # RED: 実装前は ref-architecture.md が残っているため fail する
  assert_file_not_exists "refs/ref-architecture.md"
}
run_test "AC1: refs/ref-architecture.md が不在（git mv 済み）" test_ac1_old_file_gone

# AC1c: ref-architecture-spec.md は不変（不在にならない）
test_ac1_spec_file_preserved() {
  # spec ファイルは変更しない — 実装前から存在するため PASS するはずだが RED テストの整合性確認用
  assert_file_exists "refs/ref-architecture-spec.md"
}
run_test "AC1: refs/ref-architecture-spec.md は不変（存在する）" test_ac1_spec_file_preserved

# =============================================================================
# AC2: deps.yaml の component key 変更
# =============================================================================
echo ""
echo "--- AC2: deps.yaml component key 変更検証 ---"

DEPS_YAML="deps.yaml"

# AC2a: deps.yaml に ref-skill-arch-patterns キーが存在する
test_ac2_new_key_exists() {
  # RED: 実装前は ref-skill-arch-patterns キーがないため fail する
  assert_file_contains "$DEPS_YAML" "^  ref-skill-arch-patterns:"
}
run_test "AC2: deps.yaml に ref-skill-arch-patterns キーが存在する" test_ac2_new_key_exists

# AC2b: deps.yaml の path が refs/ref-skill-arch-patterns.md を指す
test_ac2_path_updated() {
  # RED: 実装前は path が ref-architecture.md のままのため fail する
  assert_file_contains "$DEPS_YAML" "path: refs/ref-skill-arch-patterns\.md"
}
run_test "AC2: deps.yaml の path が refs/ref-skill-arch-patterns.md を指す" test_ac2_path_updated

# AC2c: deps.yaml に ref-architecture の単独キー（ref-architecture-spec 以外）が残っていない
test_ac2_old_key_gone() {
  # RED: 実装前は ref-architecture キーが残っているため fail する
  # ref-architecture-spec は保護するため除外パターンを使用
  if grep -P "^  ref-architecture:" "${PLUGIN_ROOT}/${DEPS_YAML}" 2>/dev/null; then
    return 1
  fi
  return 0
}
run_test "AC2: deps.yaml から ref-architecture キー（単独）が削除されている" test_ac2_old_key_gone

# AC2d: deps.yaml の reference エントリで ref-architecture(-spec 以外)が残っていない
test_ac2_references_updated() {
  # RED: 実装前は "reference: ref-architecture" 行が残っているため fail する
  # ref-architecture-spec は除外
  if grep -P "reference: ref-architecture([^-]|$)" "${PLUGIN_ROOT}/${DEPS_YAML}" 2>/dev/null; then
    return 1
  fi
  return 0
}
run_test "AC2: deps.yaml の reference エントリで ref-architecture（非spec）が残っていない" test_ac2_references_updated

# AC2e: deps.yaml の ref-architecture-spec キーは不変
test_ac2_spec_key_preserved() {
  # spec キーは変更しない — 実装前から存在するため確認用
  assert_file_contains "$DEPS_YAML" "^  ref-architecture-spec:"
}
run_test "AC2: deps.yaml の ref-architecture-spec キーは不変（保護）" test_ac2_spec_key_preserved

# =============================================================================
# AC3: 参照ファイル内の ref-architecture 置換（-spec 以外）
# =============================================================================
echo ""
echo "--- AC3: 参照ファイル内の ref-architecture 置換検証 ---"

# AC3a: agents/worker-architecture.md で ref-architecture(-spec 以外) が ref-skill-arch-patterns に置換されている
test_ac3_worker_architecture_updated() {
  local file="agents/worker-architecture.md"
  # RED: 実装前は ref-architecture 参照が残っているため fail する
  assert_file_not_contains "$file" "ref-architecture([^-]|$)"
}
run_test "AC3: agents/worker-architecture.md の ref-architecture 参照が置換されている" test_ac3_worker_architecture_updated

# AC3b: agents/worker-architecture.md に ref-skill-arch-patterns 参照が存在する
test_ac3_worker_architecture_has_new_ref() {
  local file="agents/worker-architecture.md"
  # RED: 実装前は ref-skill-arch-patterns が存在しないため fail する
  assert_file_contains "$file" "ref-skill-arch-patterns"
}
run_test "AC3: agents/worker-architecture.md に ref-skill-arch-patterns 参照が存在する" test_ac3_worker_architecture_has_new_ref

# AC3c: architecture/domain/contexts/twill-integration.md で ref-architecture(-spec 以外)が置換されている
test_ac3_twill_integration_updated() {
  local file="architecture/domain/contexts/twill-integration.md"
  # RED: 実装前は ref-architecture 参照が残っているため fail する
  # ただし ref-architecture-spec は保護
  assert_file_not_contains "$file" "ref-architecture([^-]|$)"
}
run_test "AC3: architecture/domain/contexts/twill-integration.md の ref-architecture 参照が置換されている" test_ac3_twill_integration_updated

# AC3d: commands/plugin-diagnose.md で ref-architecture(-spec 以外)が置換されている
test_ac3_plugin_diagnose_updated() {
  local file="commands/plugin-diagnose.md"
  # RED: 実装前は ref-architecture 参照が残っているため fail する
  assert_file_not_contains "$file" "ref-architecture([^-]|$)"
}
run_test "AC3: commands/plugin-diagnose.md の ref-architecture 参照が置換されている" test_ac3_plugin_diagnose_updated

# AC3e: commands/evaluate-architecture.md で ref-architecture(-spec 以外)が置換されている
test_ac3_evaluate_architecture_updated() {
  local file="commands/evaluate-architecture.md"
  # RED: 実装前は ref-architecture 参照が残っているため fail する
  assert_file_not_contains "$file" "ref-architecture([^-]|$)"
}
run_test "AC3: commands/evaluate-architecture.md の ref-architecture 参照が置換されている" test_ac3_evaluate_architecture_updated

# AC3f: refs/ref-practices.md で ref-architecture(-spec 以外)が置換されている
test_ac3_ref_practices_updated() {
  local file="refs/ref-practices.md"
  # RED: 実装前は ref-architecture 参照が残っているため fail する
  assert_file_not_contains "$file" "ref-architecture([^-]|$)"
}
run_test "AC3: refs/ref-practices.md の ref-architecture 参照が置換されている" test_ac3_ref_practices_updated

# AC3g: ref-architecture-spec 参照はいずれのファイルにも残っている（不変確認）
test_ac3_spec_ref_preserved_in_twill_integration() {
  local file="architecture/domain/contexts/twill-integration.md"
  # spec 参照は変更しない
  assert_file_contains "$file" "ref-architecture-spec"
}
run_test "AC3: architecture/domain/contexts/twill-integration.md の ref-architecture-spec 参照は不変" test_ac3_spec_ref_preserved_in_twill_integration

# =============================================================================
# AC4: twl update-readme による dot ファイル自動更新
# =============================================================================
echo ""
echo "--- AC4: dot ファイル自動更新検証 ---"

DOT_FILES=(
  "docs/deps.dot"
  "docs/deps-co-architect.dot"
  "docs/deps-workflow-plugin-diagnose.dot"
)

# AC4a: docs/deps.dot に ref-skill-arch-patterns が含まれる
test_ac4_deps_dot_has_new_name() {
  local file="docs/deps.dot"
  # RED: 実装前は ref-skill-arch-patterns が存在しないため fail する
  assert_file_contains "$file" "ref-skill-arch-patterns"
}
run_test "AC4: docs/deps.dot に ref-skill-arch-patterns が含まれる" test_ac4_deps_dot_has_new_name

# AC4b: docs/deps.dot に ref-architecture(-spec 以外)が残っていない
test_ac4_deps_dot_old_name_gone() {
  local file="docs/deps.dot"
  # RED: 実装前は ref-architecture が残っているため fail する
  assert_file_not_contains "$file" "ref-architecture([^-]|$)"
}
run_test "AC4: docs/deps.dot に ref-architecture（非spec）が残っていない" test_ac4_deps_dot_old_name_gone

# AC4c: docs/deps-co-architect.dot に ref-skill-arch-patterns が含まれる
test_ac4_co_architect_dot_has_new_name() {
  local file="docs/deps-co-architect.dot"
  # RED: 実装前は ref-skill-arch-patterns が存在しないため fail する
  assert_file_contains "$file" "ref-skill-arch-patterns"
}
run_test "AC4: docs/deps-co-architect.dot に ref-skill-arch-patterns が含まれる" test_ac4_co_architect_dot_has_new_name

# AC4d: docs/deps-co-architect.dot に ref-architecture(-spec 以外)が残っていない
test_ac4_co_architect_dot_old_name_gone() {
  local file="docs/deps-co-architect.dot"
  # RED: 実装前は ref-architecture が残っているため fail する
  assert_file_not_contains "$file" "ref-architecture([^-]|$)"
}
run_test "AC4: docs/deps-co-architect.dot に ref-architecture（非spec）が残っていない" test_ac4_co_architect_dot_old_name_gone

# AC4e: docs/deps-workflow-plugin-diagnose.dot に ref-skill-arch-patterns が含まれる
test_ac4_plugin_diagnose_dot_has_new_name() {
  local file="docs/deps-workflow-plugin-diagnose.dot"
  # RED: 実装前は ref-skill-arch-patterns が存在しないため fail する
  assert_file_contains "$file" "ref-skill-arch-patterns"
}
run_test "AC4: docs/deps-workflow-plugin-diagnose.dot に ref-skill-arch-patterns が含まれる" test_ac4_plugin_diagnose_dot_has_new_name

# AC4f: docs/deps-workflow-plugin-diagnose.dot に ref-architecture(-spec 以外)が残っていない
test_ac4_plugin_diagnose_dot_old_name_gone() {
  local file="docs/deps-workflow-plugin-diagnose.dot"
  # RED: 実装前は ref-architecture が残っているため fail する
  assert_file_not_contains "$file" "ref-architecture([^-]|$)"
}
run_test "AC4: docs/deps-workflow-plugin-diagnose.dot に ref-architecture（非spec）が残っていない" test_ac4_plugin_diagnose_dot_old_name_gone

# =============================================================================
# AC5: twl check と reference-migration.test.sh が PASS
# =============================================================================
echo ""
echo "--- AC5: twl check および reference-migration.test.sh PASS 検証 ---"

# AC5a: twl check が PASS する
test_ac5_twl_check_passes() {
  if ! command -v twl &>/dev/null; then
    # twl コマンドが存在しない場合は fail（RED）
    echo "twl command not found" >&2
    return 1
  fi
  local output exit_code
  output=$(cd "${PLUGIN_ROOT}" && twl check 2>&1)
  exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    echo "$output" >&2
    return 1
  fi
  return 0
}
run_test "AC5: twl check が PASS する" test_ac5_twl_check_passes

# AC5b: reference-migration.test.sh が PASS する
test_ac5_reference_migration_test_passes() {
  local test_script="${PLUGIN_ROOT}/tests/scenarios/reference-migration.test.sh"
  if [[ ! -f "$test_script" ]]; then
    echo "reference-migration.test.sh not found" >&2
    return 1
  fi
  local output exit_code
  output=$(bash "$test_script" 2>&1)
  exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    echo "$output" >&2
    return 1
  fi
  return 0
}
run_test "AC5: bash reference-migration.test.sh が PASS する" test_ac5_reference_migration_test_passes

# =============================================================================
# AC6: ネガティブ検証 — dot ファイルに旧名残骸なし
# =============================================================================
echo ""
echo "--- AC6: ネガティブ検証 — dot ファイルに ref-architecture（非spec）残骸なし ---"

# AC6a: deps*.dot ファイル全体で ref-architecture(-spec 以外)が出力空
test_ac6_no_old_name_in_all_dot_files() {
  local found
  # RED: 実装前は ref-architecture が残っているため fail する
  found=$(grep -rn "ref-architecture[^-]" "${PLUGIN_ROOT}/docs/deps"*.dot 2>/dev/null || true)
  # spec 参照のみ許可（ref-architecture-spec はヒットしない: [^-] で除外済み）
  if [[ -n "$found" ]]; then
    echo "旧名残骸が残っている:" >&2
    echo "$found" >&2
    return 1
  fi
  return 0
}
run_test "AC6: grep -rn 'ref-architecture[^-]' docs/deps*.dot の出力が空" test_ac6_no_old_name_in_all_dot_files

# AC6b: docs/deps.dot 単体でも ref-architecture(-spec 以外)が出力空
test_ac6_deps_dot_clean() {
  local found
  # RED: 実装前は ref-architecture が残っているため fail する
  found=$(grep -n "ref-architecture[^-]" "${PLUGIN_ROOT}/docs/deps.dot" 2>/dev/null || true)
  if [[ -n "$found" ]]; then
    echo "deps.dot に旧名残骸:" >&2
    echo "$found" >&2
    return 1
  fi
  return 0
}
run_test "AC6: docs/deps.dot に ref-architecture（非spec）残骸なし" test_ac6_deps_dot_clean

# =============================================================================
# AC7: archive ファイルは歴史資料として変更なし（旧名 ref-architecture を保持）
# =============================================================================
echo ""
echo "--- AC7: archive ファイル不変検証 ---"

ARCHIVE_FILE="architecture/archive/migration/component-mapping.md"

# AC7a: archive ファイルが存在する
test_ac7_archive_exists() {
  assert_file_exists "$ARCHIVE_FILE"
}
run_test "AC7: architecture/archive/migration/component-mapping.md が存在する" test_ac7_archive_exists

# AC7b: archive ファイルに旧名 ref-architecture が保持されている
test_ac7_archive_preserves_old_name() {
  # archive は歴史資料なので ref-architecture を保持しているはず
  # 実装前から存在するため PASS 可能 — archive が変更されたら FAIL になる RED テスト
  assert_file_contains "$ARCHIVE_FILE" "ref-architecture"
}
run_test "AC7: archive ファイルに旧名 ref-architecture が保持されている" test_ac7_archive_preserves_old_name

# AC7c: archive ファイルが ref-skill-arch-patterns に書き換えられていない（歴史資料保全）
test_ac7_archive_not_modified() {
  # archive に ref-skill-arch-patterns が混入していないことを確認
  # 実装後に archive を触った場合この RED テストが検知する
  if grep -qP "ref-skill-arch-patterns" "${PLUGIN_ROOT}/${ARCHIVE_FILE}" 2>/dev/null; then
    echo "archive ファイルが書き換えられています（歴史資料を変更禁止）" >&2
    return 1
  fi
  return 0
}
run_test "AC7: archive ファイルに ref-skill-arch-patterns が混入していない（歴史資料保全）" test_ac7_archive_not_modified

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
