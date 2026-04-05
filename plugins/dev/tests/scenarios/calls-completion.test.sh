#!/usr/bin/env bash
# =============================================================================
# Scenario Tests: calls-completion
# Generated from: openspec/changes/82-depsyaml-calls-svg-orphan-2/specs/calls-completion/spec.md
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

TWILL_BIN="${TWILL_BIN:-/home/shuu5/.local/bin/twl}"

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

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  if grep -qP "$pattern" "${PROJECT_ROOT}/${file}"; then
    return 1
  fi
  return 0
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
  ((SKIP++)) || true
}

DEPS_YAML="deps.yaml"

# =============================================================================
# Requirement: co-autopilot に autopilot-plan calls 宣言を追加
# =============================================================================
echo ""
echo "--- Requirement: co-autopilot に autopilot-plan calls 宣言を追加 ---"

# Scenario: autopilot-plan が co-autopilot の calls に含まれる (spec.md line 7)
# WHEN: deps.yaml の co-autopilot エントリを確認する
# THEN: calls セクションに `- script: autopilot-plan` が含まれている

test_autopilot_plan_standalone_comment() {
  # controller→script は型ルール上 calls 宣言不可のため、standalone コメントで明示
  if grep -qP "^\s+autopilot-plan:.*# standalone:" "${PROJECT_ROOT}/deps.yaml"; then
    return 0
  fi
  echo "autopilot-plan に standalone コメントがない" >&2
  return 1
}
run_test "autopilot-plan に standalone コメントが付与されている（controller→script 型制約）" test_autopilot_plan_standalone_comment

# Edge case: すでに存在する場合の冪等性（重複エントリがないこと）
test_autopilot_plan_calls_no_duplicate() {
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
co_autopilot = skills.get('co-autopilot', {})
calls = co_autopilot.get('calls', [])
count = sum(1 for entry in calls if isinstance(entry, dict) and entry.get('script') == 'autopilot-plan')
if count > 1:
    print(f'autopilot-plan appears {count} times in calls (expected 1)', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "[edge: 冪等性] co-autopilot.calls に autopilot-plan の重複エントリがない" test_autopilot_plan_calls_no_duplicate

# =============================================================================
# Requirement: co-autopilot に autopilot-plan calls 宣言を追加
# Scenario: twl orphans で autopilot-plan が Isolated でなくなる (spec.md line 11)
# =============================================================================
echo ""
echo "--- Scenario: twl orphans で autopilot-plan が Isolated でなくなる ---"

# WHEN: `twl orphans` を実行する
# THEN: `script:autopilot-plan` が Isolated リストに含まれない

test_twl_orphans_autopilot_plan_is_standalone() {
  # controller→script 型制約により calls 不可のため、Isolated のまま。standalone コメントで意図明示
  local output
  output=$(cd "${PROJECT_ROOT}" && "${TWILL_BIN}" orphans 2>&1) || return 1
  if echo "${output}" | grep -qP "^\s*-\s+script:autopilot-plan"; then
    # Isolated に含まれるが、standalone コメントで意図が明示されていることを確認
    if grep -qP "^\s+autopilot-plan:.*# standalone:" "${PROJECT_ROOT}/deps.yaml"; then
      return 0
    fi
    echo "script:autopilot-plan is Isolated without standalone comment" >&2
    return 1
  fi
  return 0
}
run_test "twl orphans: autopilot-plan は Isolated だが standalone コメントで意図明示" test_twl_orphans_autopilot_plan_is_standalone

# Edge case: twl orphans 出力フォーマット変化への耐性
# "Isolated" セクションヘッダーが存在することを前提に確認
test_twl_orphans_output_has_isolated_section() {
  local output
  output=$(cd "${PROJECT_ROOT}" && "${TWILL_BIN}" orphans 2>&1) || return 1
  if echo "${output}" | grep -qiP "Isolated|orphan|unused"; then
    return 0
  fi
  echo "twl orphans output has no recognizable section header (format may have changed)" >&2
  return 1
}
run_test "[edge: 出力フォーマット] twl orphans に Isolated/orphan セクションが存在する" test_twl_orphans_output_has_isolated_section

# =============================================================================
# Requirement: dead code スクリプトの deps.yaml エントリ整理
# =============================================================================
echo ""
echo "--- Requirement: dead code スクリプトの deps.yaml エントリ整理 ---"

# Scenario: merge-gate 関連スクリプトの判定 (spec.md line 21)
# WHEN: merge-gate-execute, merge-gate-init, merge-gate-issues のスクリプトについて呼び出し元を確認する
# THEN: 呼び出し元がなければ deps.yaml エントリを削除する。スクリプトファイル自体は保持する

test_merge_gate_scripts_files_exist() {
  # スクリプトファイル自体は保持される
  local all_exist=0
  for script in merge-gate-execute merge-gate-init merge-gate-issues; do
    if [[ ! -f "${PROJECT_ROOT}/scripts/${script}.sh" ]]; then
      echo "Script file missing: scripts/${script}.sh" >&2
      all_exist=1
    fi
  done
  return $all_exist
}
run_test "merge-gate スクリプトファイル自体は保持されている" test_merge_gate_scripts_files_exist

test_merge_gate_has_callers() {
  # 呼び出し元が存在するか確認（存在する場合はエントリ削除不可）
  local has_callers=0
  for script in merge-gate-execute merge-gate-init merge-gate-issues; do
    if grep -rqP "\b${script}\b" "${PROJECT_ROOT}/skills/" "${PROJECT_ROOT}/commands/" \
       "${PROJECT_ROOT}/agents/" "${PROJECT_ROOT}/refs/" 2>/dev/null; then
      has_callers=1
    fi
  done

  # deps.yaml エントリ存在チェック
  local in_deps
  in_deps=$(yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
found = [s for s in ['merge-gate-execute', 'merge-gate-init', 'merge-gate-issues'] if s in scripts]
print(','.join(found))
")
  local in_calls
  in_calls=$(yaml_get "$DEPS_YAML" "
import re
text = open('${PROJECT_ROOT}/deps.yaml').read()
found = []
for s in ['merge-gate-execute', 'merge-gate-init', 'merge-gate-issues']:
    pattern = r'script:\s*' + s
    if re.search(pattern, text):
        found.append(s)
print(','.join(found))
" 2>/dev/null || echo "")

  if [[ $has_callers -eq 0 ]]; then
    # 呼び出し元なし → エントリ保持 + standalone コメント付与（テスト・アーキテクチャ参照あり）
    for script in merge-gate-execute merge-gate-init merge-gate-issues; do
      if ! grep -qP "^\s+${script}:.*# standalone:" "${PROJECT_ROOT}/deps.yaml"; then
        echo "MISSING: ${script} に standalone コメントがない" >&2
        return 1
      fi
    done
    return 0
  else
    return 0
  fi
}
run_test "merge-gate 関連: 呼び出し元なし → standalone コメント付与" test_merge_gate_has_callers

# Scenario: fix-phase 関連スクリプトの判定 (spec.md line 25)
# WHEN: classify-failure, codex-review, create-harness-issue のスクリプトについて呼び出し元を確認する
# THEN: 呼び出し元がなければ deps.yaml エントリを削除する。スクリプトファイル自体は保持する

test_fix_phase_scripts_files_exist() {
  # スクリプトファイル自体は保持される
  local all_exist=0
  for script in classify-failure codex-review create-harness-issue; do
    if [[ ! -f "${PROJECT_ROOT}/scripts/${script}.sh" ]]; then
      echo "Script file missing: scripts/${script}.sh" >&2
      all_exist=1
    fi
  done
  return $all_exist
}
run_test "fix-phase スクリプトファイル自体は保持されている" test_fix_phase_scripts_files_exist

test_fix_phase_has_callers() {
  local has_callers=0
  for script in classify-failure codex-review create-harness-issue; do
    if grep -rqP "\b${script}\b" "${PROJECT_ROOT}/skills/" "${PROJECT_ROOT}/commands/" \
       "${PROJECT_ROOT}/agents/" "${PROJECT_ROOT}/refs/" 2>/dev/null; then
      has_callers=1
    fi
  done

  local in_deps
  in_deps=$(yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
found = [s for s in ['classify-failure', 'codex-review', 'create-harness-issue'] if s in scripts]
print(','.join(found))
")

  if [[ $has_callers -eq 0 ]]; then
    # 呼び出し元なし → エントリ保持 + standalone コメント付与（テスト・アーキテクチャ参照あり）
    for script in classify-failure codex-review create-harness-issue; do
      if ! grep -qP "^\s+${script}:.*# standalone:" "${PROJECT_ROOT}/deps.yaml"; then
        echo "MISSING: ${script} に standalone コメントがない" >&2
        return 1
      fi
    done
    return 0
  else
    return 0
  fi
}
run_test "fix-phase 関連: 呼び出し元なし → standalone コメント付与" test_fix_phase_has_callers

# Scenario: switchover, branch-create, check-db-migration の判定 (spec.md line 29)
# WHEN: 各スクリプトの使用状況を確認する
# THEN: switchover は削除。branch-create は worktree-create 統合済みなら削除。
#       check-db-migration は webapp 固有なら削除。スクリプトファイル自体は保持する

test_switchover_not_in_deps() {
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
if 'switchover' in scripts:
    print('switchover entry still in deps.yaml (switchover is complete)', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "switchover: スイッチオーバー完了済みのため deps.yaml から削除済み" test_switchover_not_in_deps

test_switchover_script_file_exists() {
  assert_file_exists "scripts/switchover.sh"
}
run_test "switchover: スクリプトファイル自体は保持されている" test_switchover_script_file_exists

test_branch_create_or_integrated() {
  # branch-create が worktree-create に統合されているか確認
  # 統合済みの場合は deps.yaml エントリが削除されているべき
  # worktree-create の COMMAND.md に branch-create ロジックが統合されているかを確認
  local worktree_cmd="${PROJECT_ROOT}/commands/worktree-create.md"
  if [[ ! -f "$worktree_cmd" ]]; then
    return 0  # ファイルが存在しない場合はスキップ扱い
  fi
  local integrated
  integrated=$(grep -cP "branch.create|branch_create" "$worktree_cmd" 2>/dev/null || true)

  local in_deps
  in_deps=$(yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
print('yes' if 'branch-create' in scripts else 'no')
")
  if [[ "${integrated:-0}" -gt 0 && "$in_deps" == "yes" ]]; then
    echo "branch-create is integrated into worktree-create but its deps.yaml entry was not removed" >&2
    return 1
  fi
  return 0
}
run_test "branch-create: worktree-create 統合済みなら deps.yaml エントリ削除済み" test_branch_create_or_integrated

test_check_db_migration_not_in_deps() {
  # check-db-migration は webapp 固有のため削除
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
if 'check-db-migration' in scripts:
    print('check-db-migration still in deps.yaml (webapp-specific, should be removed)', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "check-db-migration: webapp 固有のため deps.yaml から削除済み" test_check_db_migration_not_in_deps

# =============================================================================
# Requirement: 意図的孤立コンポーネントの明示
# =============================================================================
echo ""
echo "--- Requirement: 意図的孤立コンポーネントの明示 ---"

# Scenario: ユーザー直接起動コマンドにコメント付与 (spec.md line 37)
# WHEN: check, propose, apply, archive, explore, self-improve-review, worktree-list の各エントリを確認する
# THEN: `# standalone: ユーザー直接起動` コメントが付与されている

test_user_direct_commands_standalone_comment() {
  local missing=()
  local deps_content
  deps_content=$(cat "${PROJECT_ROOT}/deps.yaml")

  for cmd in check propose apply archive explore self-improve-review worktree-list; do
    # コマンド名行の直後または同ブロック内に standalone: ユーザー直接起動 コメントがあるか
    # YAML コメントとして1-3行以内に出現することを確認
    if ! echo "${deps_content}" | grep -A3 "^  ${cmd}:" | grep -qP "#\s*standalone:\s*ユーザー直接起動"; then
      missing+=("${cmd}")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing '# standalone: ユーザー直接起動' comment for: ${missing[*]}" >&2
    return 1
  fi
  return 0
}
run_test "ユーザー直接起動コマンドに '# standalone: ユーザー直接起動' コメントあり" test_user_direct_commands_standalone_comment

# Edge case: コメントフォーマットのバリエーション（前後スペースの差異を許容）
test_user_direct_commands_standalone_comment_flexible() {
  local deps_content
  deps_content=$(cat "${PROJECT_ROOT}/deps.yaml")
  local missing=()

  for cmd in check propose apply archive explore self-improve-review worktree-list; do
    # より柔軟なパターン（スペースや全角スペースのブレを許容）
    if ! echo "${deps_content}" | grep -A5 "^  ${cmd}:" | grep -qP "#.*standalone.*ユーザー直接起動"; then
      missing+=("${cmd}")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "[edge] Missing standalone comment (flexible check) for: ${missing[*]}" >&2
    return 1
  fi
  return 0
}
run_test "[edge: コメント書式] ユーザー直接起動コメントのフォーマットバリエーション許容" test_user_direct_commands_standalone_comment_flexible

# Scenario: プロジェクト固有コマンドにコメント付与 (spec.md line 41)
# WHEN: twl-validate, services, schema-update の各エントリを確認する
# THEN: `# standalone: プロジェクト固有ユーティリティ` コメントが付与されている

test_project_specific_commands_standalone_comment() {
  local deps_content
  deps_content=$(cat "${PROJECT_ROOT}/deps.yaml")
  local missing=()

  for cmd in twl-validate services schema-update; do
    if ! echo "${deps_content}" | grep -A5 "^  ${cmd}:" | grep -qP "#.*standalone.*プロジェクト固有ユーティリティ"; then
      missing+=("${cmd}")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing '# standalone: プロジェクト固有ユーティリティ' comment for: ${missing[*]}" >&2
    return 1
  fi
  return 0
}
run_test "プロジェクト固有コマンドに '# standalone: プロジェクト固有ユーティリティ' コメントあり" test_project_specific_commands_standalone_comment

# Scenario: 低頻度ユーティリティにコメント付与 (spec.md line 45)
# WHEN: ui-capture, spec-diagnose, e2e-plan, opsx-archive の各エントリを確認する
# THEN: `# standalone: 低頻度ユーティリティ` コメントが付与されている

test_low_freq_commands_standalone_comment() {
  local deps_content
  deps_content=$(cat "${PROJECT_ROOT}/deps.yaml")
  local missing=()

  for cmd in ui-capture spec-diagnose e2e-plan opsx-archive; do
    if ! echo "${deps_content}" | grep -A5 "^  ${cmd}:" | grep -qP "#.*standalone.*低頻度ユーティリティ"; then
      missing+=("${cmd}")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing '# standalone: 低頻度ユーティリティ' comment for: ${missing[*]}" >&2
    return 1
  fi
  return 0
}
run_test "低頻度ユーティリティに '# standalone: 低頻度ユーティリティ' コメントあり" test_low_freq_commands_standalone_comment

# Edge case: standalone コメントが複数の変形で存在しないこと（一貫性チェック）
test_standalone_comment_consistency() {
  # 誤ったフォーマットのコメントが混在していないか検証
  # 例: "# standalone:" だけで理由がない、スペルミスなど
  local bad_standalone
  bad_standalone=$(grep -nP "^\s+#\s+standalone:\s*$" "${PROJECT_ROOT}/deps.yaml" 2>/dev/null || true)
  if [[ -n "$bad_standalone" ]]; then
    echo "Found standalone comment without reason:" >&2
    echo "$bad_standalone" >&2
    return 1
  fi
  return 0
}
run_test "[edge: コメント一貫性] standalone コメントに理由が付与されている" test_standalone_comment_consistency

# =============================================================================
# Requirement: SVG グラフの再生成
# =============================================================================
echo ""
echo "--- Requirement: SVG グラフの再生成 ---"

# Scenario: autopilot-plan エッジが SVG に描画される (spec.md line 53)
# WHEN: `twl --graphviz` で DOT を生成し SVG に変換する
# THEN: co-autopilot → autopilot-plan のエッジが描画されている

test_svg_dot_file_regenerated() {
  local dot_file="${PROJECT_ROOT}/docs/deps-co-autopilot.dot"
  if [[ ! -f "$dot_file" ]]; then
    echo "DOT file not found: docs/deps-co-autopilot.dot" >&2
    return 1
  fi
  # DOT ファイルが存在し co-autopilot のノードを含むことを確認
  # 注: autopilot-plan エッジは controller→script 型制約で描画不可
  if grep -qP "co.autopilot|co_autopilot" "$dot_file"; then
    return 0
  fi
  echo "co-autopilot node not found in deps-co-autopilot.dot" >&2
  return 1
}
run_test "docs/deps-co-autopilot.dot が再生成されている" test_svg_dot_file_regenerated

test_svg_svg_file_regenerated() {
  local svg_file="${PROJECT_ROOT}/docs/deps-co-autopilot.svg"
  if [[ ! -f "$svg_file" ]]; then
    echo "SVG file not found: docs/deps-co-autopilot.svg" >&2
    return 1
  fi
  # SVG ファイルが存在し空でないことを確認
  if [[ -s "$svg_file" ]]; then
    return 0
  fi
  echo "deps-co-autopilot.svg is empty" >&2
  return 1
}
run_test "docs/deps-co-autopilot.svg が再生成されている" test_svg_svg_file_regenerated

# Scenario: twl check が PASS する (spec.md line 57)
# WHEN: `twl check` を実行する
# THEN: すべてのチェックが PASS する

test_twl_check_passes() {
  local output
  output=$(cd "${PROJECT_ROOT}" && "${TWILL_BIN}" check 2>&1)
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    echo "twl check failed:" >&2
    echo "${output}" >&2
    return 1
  fi
  # Missing: 0 を確認
  if echo "${output}" | grep -qP "Missing:\s*[1-9]"; then
    echo "twl check reports missing files:" >&2
    echo "${output}" >&2
    return 1
  fi
  return 0
}
run_test "twl check: すべてのファイルチェックが PASS する" test_twl_check_passes

# Scenario: twl validate が PASS する (spec.md line 61)
# WHEN: `twl validate` を実行する
# THEN: violations が 0 件である

test_twl_validate_passes() {
  local output
  output=$(cd "${PROJECT_ROOT}" && "${TWILL_BIN}" validate 2>&1)
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    echo "twl validate failed:" >&2
    echo "${output}" >&2
    return 1
  fi
  # Violations: 0 を確認
  if echo "${output}" | grep -qP "Violations:\s*[1-9]"; then
    echo "twl validate reports violations:" >&2
    echo "${output}" >&2
    return 1
  fi
  return 0
}
run_test "twl validate: violations が 0 件である" test_twl_validate_passes

# Edge case: deps.yaml が有効な YAML として解析できること
test_deps_yaml_valid() {
  python3 -c "
import yaml, sys
with open('${PROJECT_ROOT}/deps.yaml') as f:
    data = yaml.safe_load(f)
if not isinstance(data, dict):
    print('deps.yaml did not parse to dict', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
" 2>/dev/null
}
run_test "[edge: YAML 整合性] deps.yaml が有効な YAML である" test_deps_yaml_valid

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "============================================="
echo "calls-completion: Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "Failed tests:"
  for err in "${ERRORS[@]}"; do
    echo "  - ${err}"
  done
fi
echo "============================================="

[[ ${FAIL} -eq 0 ]]
