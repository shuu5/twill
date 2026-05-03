#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: reference-migration
# Generated from: deltaspec/changes/c-3-specialist-reference-migration/specs/reference-migration/spec.md
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

# --- Reference 一覧 ---

# 12 new references to migrate
NEW_REFS=(
  ref-types
  ref-practices
  ref-deps-format
  ref-skill-arch-patterns
  ref-architecture-spec
  ref-project-model
  ref-issue-quality-criteria
  ref-dci
  self-improve-format
  baseline-coding-style
  baseline-security-checklist
  baseline-input-validation
)

# 4 twl sync targets
SYNC_REFS=(
  ref-types
  ref-practices
  ref-deps-format
  ref-skill-arch-patterns
)

# 4 plugin-specific refs
PLUGIN_REFS=(
  ref-architecture-spec
  ref-project-model
  ref-dci
  self-improve-format
)

# 3 baseline refs
BASELINE_REFS=(
  baseline-coding-style
  baseline-security-checklist
  baseline-input-validation
)

# 4 existing refs (already in deps.yaml before this change)
EXISTING_REFS=(
  ref-specialist-output-schema
  ref-specialist-few-shot
  ref-issue-template-bug
  ref-issue-template-feature
)

SYNC_MARKER="<!-- Synced from twl docs/ — do not edit directly -->"

# =============================================================================
# Requirement: twl sync 対象 reference の移植
# =============================================================================
echo ""
echo "--- Requirement: twl sync 対象 reference の移植 ---"

# Scenario: twl sync 対象ファイルの作成 (line 7)
# WHEN: ref-types を移植する
# THEN: refs/ref-types.md が作成され、先頭に同期マーカーが存在し、frontmatter に type: reference が宣言されている
test_ref_types_exists_with_marker() {
  assert_file_exists "refs/ref-types.md" || return 1
  # Check sync marker in first 5 lines
  if ! head -15 "${PROJECT_ROOT}/refs/ref-types.md" | grep -qF "Synced from twl docs/"; then
    echo "Sync marker not found in first 5 lines" >&2
    return 1
  fi
  assert_file_contains "refs/ref-types.md" "^type:\s*reference"
}
run_test "ref-types.md が作成され、同期マーカーと type: reference が存在" test_ref_types_exists_with_marker

# 全 4 sync refs が存在する
test_all_sync_refs_exist() {
  local missing=()
  for name in "${SYNC_REFS[@]}"; do
    if ! assert_file_exists "refs/${name}.md"; then
      missing+=("${name}")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing sync refs: ${missing[*]}" >&2
    return 1
  fi
  return 0
}
run_test "twl sync 対象 4 ファイル全て存在" test_all_sync_refs_exist

# 全 4 sync refs に同期マーカーがある
test_all_sync_refs_have_marker() {
  local failed=()
  for name in "${SYNC_REFS[@]}"; do
    local file="refs/${name}.md"
    if ! assert_file_exists "$file"; then
      failed+=("${name}: file not found")
      continue
    fi
    if ! head -15 "${PROJECT_ROOT}/${file}" | grep -qF "Synced from twl docs/"; then
      failed+=("${name}: sync marker not found")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    for f in "${failed[@]}"; do
      echo "  ${f}" >&2
    done
    return 1
  fi
  return 0
}
run_test "twl sync 対象 4 ファイル全てに同期マーカー" test_all_sync_refs_have_marker

# Edge case: 同期マーカーがファイルの先頭行（1行目または frontmatter 直後）にある
test_sync_marker_position() {
  local failed=()
  for name in "${SYNC_REFS[@]}"; do
    local file="refs/${name}.md"
    if ! assert_file_exists "$file"; then
      continue
    fi
    # マーカーは先頭 5 行以内にあるべき
    if ! head -15 "${PROJECT_ROOT}/${file}" | grep -qF "Synced from twl docs/"; then
      failed+=("${name}: marker not in first 5 lines")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    for f in "${failed[@]}"; do
      echo "  ${f}" >&2
    done
    return 1
  fi
  return 0
}
run_test "同期マーカーがファイル先頭付近 [edge: 先頭 5 行以内]" test_sync_marker_position

# Edge case: sync 対象でないファイルに同期マーカーがない
test_non_sync_refs_no_marker() {
  local non_sync=("${PLUGIN_REFS[@]}" "${BASELINE_REFS[@]}")
  local failed=()
  for name in "${non_sync[@]}"; do
    local file="refs/${name}.md"
    if ! assert_file_exists "$file"; then
      continue
    fi
    if head -15 "${PROJECT_ROOT}/${file}" | grep -qF "Synced from twl docs/"; then
      failed+=("${name}: has sync marker but should not")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    for f in "${failed[@]}"; do
      echo "  ${f}" >&2
    done
    return 1
  fi
  return 0
}
run_test "sync 対象外ファイルに同期マーカーがない [edge]" test_non_sync_refs_no_marker

# Scenario: twl --check の通過（ファイル存在検証）
# twl sync-docs はフラグ形式 (--sync-docs TARGET_DIR)。--check で全依存ファイル存在を検証
test_twl_check_passes() {
  if ! command -v twl &>/dev/null; then
    return 1
  fi
  local output exit_code
  output=$(cd "${PROJECT_ROOT}" && twl --check 2>&1)
  exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    echo "$output" >&2
    return 1
  fi
  return 0
}

if command -v twl &>/dev/null; then
  run_test "twl --check がエラーなしで通過（refs ファイル存在検証）" test_twl_check_passes
else
  run_test_skip "twl --check がエラーなしで通過" "twl command not found"
fi

# =============================================================================
# Requirement: プラグイン固有 reference の移植
# =============================================================================
echo ""
echo "--- Requirement: プラグイン固有 reference の移植 ---"

# Scenario: プラグイン固有 reference の作成 (line 20)
# WHEN: ref-dci を移植する
# THEN: refs/ref-dci.md が作成され、frontmatter に name: twl:ref-dci, type: reference が宣言されている
test_ref_dci_frontmatter() {
  assert_file_exists "refs/ref-dci.md" || return 1
  assert_file_contains "refs/ref-dci.md" "^name:\s*twl:ref-dci" || return 1
  assert_file_contains "refs/ref-dci.md" "^type:\s*reference"
}
run_test "ref-dci.md に name: twl:ref-dci と type: reference" test_ref_dci_frontmatter

# 全 plugin-specific refs が存在
test_all_plugin_refs_exist() {
  local missing=()
  for name in "${PLUGIN_REFS[@]}"; do
    if ! assert_file_exists "refs/${name}.md"; then
      missing+=("${name}")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing plugin refs: ${missing[*]}" >&2
    return 1
  fi
  return 0
}
run_test "プラグイン固有 4 reference 全て存在" test_all_plugin_refs_exist

# Edge case: プラグイン固有 refs の frontmatter に type: reference がある
test_plugin_refs_type_reference() {
  local failed=()
  for name in "${PLUGIN_REFS[@]}"; do
    local file="refs/${name}.md"
    if ! assert_file_exists "$file"; then
      continue
    fi
    if ! grep -qP "^type:\s*reference" "${PROJECT_ROOT}/${file}"; then
      failed+=("${name}: missing type: reference")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    for f in "${failed[@]}"; do
      echo "  ${f}" >&2
    done
    return 1
  fi
  return 0
}
run_test "プラグイン固有 refs 全てに type: reference [edge]" test_plugin_refs_type_reference

# =============================================================================
# Requirement: Baseline reference の移植
# =============================================================================
echo ""
echo "--- Requirement: Baseline reference の移植 ---"

# Scenario: baseline のフラット配置 (line 27)
# WHEN: baseline/coding-style.md を移植する
# THEN: refs/baseline-coding-style.md として作成され、サブディレクトリは使用されていない
test_baseline_flat_placement() {
  assert_file_exists "refs/baseline-coding-style.md" || return 1
  # サブディレクトリが存在しないこと
  if [[ -d "${PROJECT_ROOT}/refs/baseline" ]]; then
    echo "refs/baseline/ subdirectory exists (should be flat)" >&2
    return 1
  fi
  return 0
}
run_test "baseline-coding-style.md がフラット配置（サブディレクトリなし）" test_baseline_flat_placement

# 全 baseline refs が存在
test_all_baseline_refs_exist() {
  local missing=()
  for name in "${BASELINE_REFS[@]}"; do
    if ! assert_file_exists "refs/${name}.md"; then
      missing+=("${name}")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing baseline refs: ${missing[*]}" >&2
    return 1
  fi
  return 0
}
run_test "baseline 3 reference 全て存在" test_all_baseline_refs_exist

# Edge case: refs/baseline/ サブディレクトリが存在しない
test_no_baseline_subdirectory() {
  if [[ -d "${PROJECT_ROOT}/refs/baseline" ]]; then
    echo "refs/baseline/ subdirectory should not exist" >&2
    return 1
  fi
  return 0
}
run_test "refs/baseline/ サブディレクトリが存在しない [edge: フラット配置強制]" test_no_baseline_subdirectory

# Edge case: baseline refs のファイル名パターンが refs/baseline-*.md
test_baseline_naming_pattern() {
  local failed=()
  for name in "${BASELINE_REFS[@]}"; do
    if [[ ! "$name" =~ ^baseline- ]]; then
      failed+=("${name}: does not start with baseline-")
    fi
    if ! assert_file_exists "refs/${name}.md"; then
      failed+=("${name}: file not found")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    for f in "${failed[@]}"; do
      echo "  ${f}" >&2
    done
    return 1
  fi
  return 0
}
run_test "baseline refs が baseline-*.md 命名パターン [edge]" test_baseline_naming_pattern

# Scenario: specialist からの baseline 参照が有効 (line 31)
# WHEN: worker-code-reviewer が baseline-coding-style を参照する
# THEN: Glob パターン **/refs/baseline-coding-style.md で参照可能である
test_baseline_glob_reachable() {
  local result
  result=$(find "${PROJECT_ROOT}" -path "*/refs/baseline-coding-style.md" -type f 2>/dev/null | wc -l)
  if [[ "$result" -lt 1 ]]; then
    echo "baseline-coding-style.md not found via glob" >&2
    return 1
  fi
  return 0
}
run_test "baseline-coding-style.md が glob パターンで参照可能" test_baseline_glob_reachable

# =============================================================================
# Requirement: deps.yaml refs セクション登録
# =============================================================================
echo ""
echo "--- Requirement: deps.yaml refs セクション登録 ---"

# 全 12 new refs が存在
test_all_12_new_refs_exist() {
  local missing=()
  for name in "${NEW_REFS[@]}"; do
    if ! assert_file_exists "refs/${name}.md"; then
      missing+=("${name}")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing refs: ${missing[*]}" >&2
    return 1
  fi
  return 0
}
run_test "全 12 new reference ファイルが refs/ に存在" test_all_12_new_refs_exist

# 全 reference に frontmatter type: reference がある
test_all_refs_have_type_reference() {
  local all_refs=("${NEW_REFS[@]}")
  local failed=()
  for name in "${all_refs[@]}"; do
    local file="refs/${name}.md"
    if ! assert_file_exists "$file"; then
      continue
    fi
    if ! grep -qP "^type:\s*reference" "${PROJECT_ROOT}/${file}"; then
      failed+=("${name}: missing type: reference")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    for f in "${failed[@]}"; do
      echo "  ${f}" >&2
    done
    return 1
  fi
  return 0
}
run_test "全 12 new reference に type: reference frontmatter" test_all_refs_have_type_reference

# Scenario: reference の deps.yaml 登録 (line 44)
# WHEN: 全 12 references の deps.yaml 登録が完了した
# THEN: refs セクションに 16 以上のエントリが存在する（既存 4 + 新規 12 が最小セット、その後の migration で追加あり）
test_deps_refs_count_at_least_16() {
  assert_file_exists "$DEPS_YAML" || return 1
  assert_valid_yaml "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
refs = data.get('refs', {})
count = len(refs)
if count < 16:
    print(f'Expected at least 16 refs, got {count}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml refs セクションに 16 以上のエントリ (既存 4 + 新規 12 が最小セット)" test_deps_refs_count_at_least_16

# 全 12 new refs が deps.yaml に登録されている
test_deps_all_new_refs_registered() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
import json
refs = data.get('refs', {})
new_refs = json.loads('$(printf '%s\n' "${NEW_REFS[@]}" | python3 -c "import sys, json; print(json.dumps([l.strip() for l in sys.stdin]))")')
missing = [r for r in new_refs if r not in refs]
if missing:
    for m in missing:
        print(f'Missing: {m}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に全 12 new references が登録されている" test_deps_all_new_refs_registered

# 既存 4 refs も残っている
test_deps_existing_refs_preserved() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
import json
refs = data.get('refs', {})
existing = json.loads('$(printf '%s\n' "${EXISTING_REFS[@]}" | python3 -c "import sys, json; print(json.dumps([l.strip() for l in sys.stdin]))")')
missing = [r for r in existing if r not in refs]
if missing:
    for m in missing:
        print(f'Missing existing ref: {m}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "既存 4 refs が deps.yaml に残っている [edge: 上書き防止]" test_deps_existing_refs_preserved

# Edge case: 全 refs エントリに必須フィールド (type, path, description) がある
test_deps_refs_required_fields() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
refs = data.get('refs', {})
required_keys = ['type', 'path', 'description']
errors = []
for name, entry in refs.items():
    if not isinstance(entry, dict):
        errors.append(f'{name}: not a dict')
        continue
    for key in required_keys:
        if key not in entry:
            errors.append(f'{name}: missing {key}')
if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml 全 refs エントリに必須フィールド (type, path, description) [edge]" test_deps_refs_required_fields

# Edge case: 全 refs の type が reference
test_deps_refs_type_all_reference() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
refs = data.get('refs', {})
errors = []
for name, entry in refs.items():
    if not isinstance(entry, dict):
        continue
    if entry.get('type') != 'reference':
        errors.append(f'{name}: type={entry.get(\"type\")}')
if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml 全 refs の type が reference [edge]" test_deps_refs_type_all_reference

# Edge case: 全 refs の path が refs/<name>.md または skills/*/refs/<name>.md と一致
# su-observer / co-autopilot などスキル固有 refs は skills/<skill>/refs/<name>.md パスを使用
test_deps_refs_path_consistency() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
import re
refs = data.get('refs', {})
errors = []
for name, entry in refs.items():
    if not isinstance(entry, dict):
        continue
    actual_path = entry.get('path', '')
    flat_path = f'refs/{name}.md'
    skill_pattern = re.compile(r'^skills/[^/]+/refs/' + re.escape(name) + r'\.md$')
    if actual_path != flat_path and not skill_pattern.match(actual_path):
        errors.append(f'{name}: path={actual_path}, expected refs/{name}.md or skills/*/refs/{name}.md')
if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml 全 refs の path が refs/<name>.md または skills/*/refs/<name>.md [edge: パス整合性]" test_deps_refs_path_consistency

# Scenario: twl --validate が通過 (line 48)
test_twl_validate_refs() {
  if ! command -v twl &>/dev/null; then
    return 1
  fi
  local output exit_code
  output=$(cd "${PROJECT_ROOT}" && twl --validate 2>&1)
  exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    echo "$output" >&2
    return 1
  fi
  return 0
}

if command -v twl &>/dev/null; then
  run_test "twl --validate がエラーなしで通過する (refs)" test_twl_validate_refs
else
  run_test_skip "twl --validate がエラーなしで通過する (refs)" "twl command not found"
fi

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
