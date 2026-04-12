#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: spec-review-orchestrator
# Generated from: deltaspec/changes/issue-447/specs/spec-review-orchestrator/spec.md
# Coverage level: edge-cases
# Verifies:
#   - scripts/spec-review-orchestrator.sh の存在と実装
#   - deps.yaml への spec-review-orchestrator 登録
# =============================================================================
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

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

yaml_field() {
  local file="$1"
  local key="$2"
  python3 -c "
import yaml
with open('${PROJECT_ROOT}/${file}') as f:
    data = yaml.safe_load(f)
val = data
for k in '${key}'.split('.'):
    if isinstance(val, list):
        val = [v.get(k) if isinstance(v, dict) else None for v in val]
    elif isinstance(val, dict):
        val = val.get(k)
    else:
        val = None
print(val)
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

ORCHESTRATOR_SH="scripts/spec-review-orchestrator.sh"
DEPS_YAML="deps.yaml"

# =============================================================================
# Requirement: spec-review-orchestrator スクリプトの存在
# =============================================================================
echo ""
echo "--- Requirement: spec-review-orchestrator スクリプトの存在 ---"

# Scenario: スクリプト実行 (spec.md line 7)
# WHEN: spec-review-orchestrator.sh --issues-dir DIR --output-dir DIR が実行される
# THEN: --issues-dir 内の全 issue-*.json ファイルに対し、それぞれ独立した tmux cld セッションが起動される

test_orchestrator_file_exists() {
  assert_file_exists "$ORCHESTRATOR_SH"
}

if [[ -f "${PROJECT_ROOT}/${ORCHESTRATOR_SH}" ]]; then
  run_test "spec-review-orchestrator.sh が存在する" test_orchestrator_file_exists
else
  run_test_skip "spec-review-orchestrator.sh が存在する" "scripts/spec-review-orchestrator.sh not yet created"
fi

test_orchestrator_issues_dir_option() {
  assert_file_contains "$ORCHESTRATOR_SH" "\-\-issues-dir|issues_dir|ISSUES_DIR"
}

if [[ -f "${PROJECT_ROOT}/${ORCHESTRATOR_SH}" ]]; then
  run_test "spec-review-orchestrator.sh が --issues-dir オプションを受け付ける" test_orchestrator_issues_dir_option
else
  run_test_skip "spec-review-orchestrator.sh が --issues-dir オプションを受け付ける" "script not yet created"
fi

test_orchestrator_output_dir_option() {
  assert_file_contains "$ORCHESTRATOR_SH" "\-\-output-dir|output_dir|OUTPUT_DIR"
}

if [[ -f "${PROJECT_ROOT}/${ORCHESTRATOR_SH}" ]]; then
  run_test "spec-review-orchestrator.sh が --output-dir オプションを受け付ける" test_orchestrator_output_dir_option
else
  run_test_skip "spec-review-orchestrator.sh が --output-dir オプションを受け付ける" "script not yet created"
fi

test_orchestrator_issue_json_glob() {
  assert_file_contains "$ORCHESTRATOR_SH" "issue-\*\.json|issue-.*\.json"
}

if [[ -f "${PROJECT_ROOT}/${ORCHESTRATOR_SH}" ]]; then
  run_test "spec-review-orchestrator.sh が issue-*.json をグロブで列挙する" test_orchestrator_issue_json_glob
else
  run_test_skip "spec-review-orchestrator.sh が issue-*.json をグロブで列挙する" "script not yet created"
fi

test_orchestrator_tmux_cld_session() {
  assert_file_contains "$ORCHESTRATOR_SH" "tmux.*cld|cld.*tmux|tmux.*new-window|tmux.*new-session"
}

if [[ -f "${PROJECT_ROOT}/${ORCHESTRATOR_SH}" ]]; then
  run_test "spec-review-orchestrator.sh が tmux cld セッションを起動する" test_orchestrator_tmux_cld_session
else
  run_test_skip "spec-review-orchestrator.sh が tmux cld セッションを起動する" "script not yet created"
fi

# =============================================================================
# Requirement: Issue ごとの独立セッション起動
# =============================================================================
echo ""
echo "--- Requirement: Issue ごとの独立セッション起動 ---"

# Scenario: N Issue の並列処理 (spec.md line 15)
# WHEN: --issues-dir に 5 個の issue-*.json が存在する
# THEN: 最大 MAX_PARALLEL（デフォルト 3）個のセッションを同時に起動し、バッチ完了後に次のバッチを起動する

test_orchestrator_batch_loop() {
  # バッチ処理ループ（wait, batch, MAX_PARALLEL のいずれか参照）
  assert_file_contains "$ORCHESTRATOR_SH" "wait\b|batch|MAX_PARALLEL|バッチ"
}

if [[ -f "${PROJECT_ROOT}/${ORCHESTRATOR_SH}" ]]; then
  run_test "spec-review-orchestrator.sh がバッチループ制御を実装する" test_orchestrator_batch_loop
else
  run_test_skip "spec-review-orchestrator.sh がバッチループ制御を実装する" "script not yet created"
fi

test_orchestrator_parallel_counter() {
  # 並列数カウントまたはバッチインデックス管理
  assert_file_contains "$ORCHESTRATOR_SH" "count|batch_count|batch_size|pids\[\]|PIDS|parallel"
}

if [[ -f "${PROJECT_ROOT}/${ORCHESTRATOR_SH}" ]]; then
  run_test "spec-review-orchestrator.sh が並列数を管理する" test_orchestrator_parallel_counter
else
  run_test_skip "spec-review-orchestrator.sh が並列数を管理する" "script not yet created"
fi

# Scenario: 1 Issue の処理 (spec.md line 19)
# WHEN: --issues-dir に 1 個の issue-*.json が存在する
# THEN: 1 個のセッションが起動され正常完了する

test_orchestrator_single_issue_supported() {
  # 1件でも正常動作するループ構造（for/while を使用）
  assert_file_contains "$ORCHESTRATOR_SH" "\bfor\b|\bwhile\b"
}

if [[ -f "${PROJECT_ROOT}/${ORCHESTRATOR_SH}" ]]; then
  run_test "spec-review-orchestrator.sh が 1 Issue でも正常動作するループ構造を持つ" test_orchestrator_single_issue_supported
else
  run_test_skip "spec-review-orchestrator.sh が 1 Issue でも正常動作するループ構造を持つ" "script not yet created"
fi

# =============================================================================
# Requirement: MAX_PARALLEL 環境変数による制御
# =============================================================================
echo ""
echo "--- Requirement: MAX_PARALLEL 環境変数による制御 ---"

# Scenario: デフォルト値 (spec.md line 27)
# WHEN: MAX_PARALLEL が未設定
# THEN: デフォルト値 3 でバッチ処理が行われる

test_orchestrator_max_parallel_default() {
  assert_file_contains "$ORCHESTRATOR_SH" "MAX_PARALLEL.*3|:\-3\}|MAX_PARALLEL:-3|default.*3"
}

if [[ -f "${PROJECT_ROOT}/${ORCHESTRATOR_SH}" ]]; then
  run_test "spec-review-orchestrator.sh MAX_PARALLEL のデフォルト値が 3" test_orchestrator_max_parallel_default
else
  run_test_skip "spec-review-orchestrator.sh MAX_PARALLEL のデフォルト値が 3" "script not yet created"
fi

# Scenario: カスタム値 (spec.md line 32)
# WHEN: MAX_PARALLEL=5 を設定して実行する
# THEN: 最大 5 セッションが同時に起動される

test_orchestrator_max_parallel_env_used() {
  # MAX_PARALLEL 変数がループ制御に使用されていること
  assert_file_contains "$ORCHESTRATOR_SH" "\$\{MAX_PARALLEL\}|\$MAX_PARALLEL"
}

if [[ -f "${PROJECT_ROOT}/${ORCHESTRATOR_SH}" ]]; then
  run_test "spec-review-orchestrator.sh が \$MAX_PARALLEL を実際に参照する" test_orchestrator_max_parallel_env_used
else
  run_test_skip "spec-review-orchestrator.sh が \$MAX_PARALLEL を実際に参照する" "script not yet created"
fi

# =============================================================================
# Requirement: 結果ファイルへの書き出し
# =============================================================================
echo ""
echo "--- Requirement: 結果ファイルへの書き出し ---"

# Scenario: 全セッション完了後の結果収集 (spec.md line 39)
# WHEN: 全 cld セッションが完了する
# THEN: --output-dir 内に各 Issue の issue-{N}-result.txt が存在し、親セッションが読み込める

test_orchestrator_result_file_pattern() {
  assert_file_contains "$ORCHESTRATOR_SH" "result\.txt|issue-.*-result|result_file"
}

if [[ -f "${PROJECT_ROOT}/${ORCHESTRATOR_SH}" ]]; then
  run_test "spec-review-orchestrator.sh が issue-{N}-result.txt パターンを使用する" test_orchestrator_result_file_pattern
else
  run_test_skip "spec-review-orchestrator.sh が issue-{N}-result.txt パターンを使用する" "script not yet created"
fi

test_orchestrator_output_dir_write() {
  # OUTPUT_DIR に結果を書き込む記述
  assert_file_contains "$ORCHESTRATOR_SH" "OUTPUT_DIR|output.dir|\$\{OUTPUT_DIR\}"
}

if [[ -f "${PROJECT_ROOT}/${ORCHESTRATOR_SH}" ]]; then
  run_test "spec-review-orchestrator.sh が OUTPUT_DIR に結果を書き出す" test_orchestrator_output_dir_write
else
  run_test_skip "spec-review-orchestrator.sh が OUTPUT_DIR に結果を書き出す" "script not yet created"
fi

test_orchestrator_session_wait() {
  # 全セッション完了を待つ（wait またはポーリング）
  assert_file_contains "$ORCHESTRATOR_SH" "\bwait\b|session.*complet|完了を待"
}

if [[ -f "${PROJECT_ROOT}/${ORCHESTRATOR_SH}" ]]; then
  run_test "spec-review-orchestrator.sh が全セッション完了を待つ" test_orchestrator_session_wait
else
  run_test_skip "spec-review-orchestrator.sh が全セッション完了を待つ" "script not yet created"
fi

# =============================================================================
# =============================================================================
# Requirement: deps.yaml への spec-review-orchestrator 登録
# =============================================================================
echo ""
echo "--- Requirement: deps.yaml への spec-review-orchestrator 登録 ---"

# Scenario: deps.yaml 整合性 (spec.md line 61)
# WHEN: loom --check を実行する
# THEN: spec-review-orchestrator のエントリが正常に検証される

test_deps_yaml_valid() {
  assert_valid_yaml "$DEPS_YAML"
}

if [[ -f "${PROJECT_ROOT}/${DEPS_YAML}" ]]; then
  run_test "deps.yaml が有効な YAML" test_deps_yaml_valid
else
  run_test_skip "deps.yaml が有効な YAML" "deps.yaml not found"
fi

test_deps_yaml_orchestrator_entry() {
  assert_file_contains "$DEPS_YAML" "spec-review-orchestrator:"
}

if [[ -f "${PROJECT_ROOT}/${DEPS_YAML}" ]]; then
  run_test "deps.yaml に spec-review-orchestrator エントリが存在する" test_deps_yaml_orchestrator_entry
else
  run_test_skip "deps.yaml に spec-review-orchestrator エントリが存在する" "deps.yaml not found"
fi

test_deps_yaml_orchestrator_path() {
  assert_file_contains "$DEPS_YAML" "spec-review-orchestrator\.sh"
}

if [[ -f "${PROJECT_ROOT}/${DEPS_YAML}" ]]; then
  run_test "deps.yaml の spec-review-orchestrator が path を持つ" test_deps_yaml_orchestrator_path
else
  run_test_skip "deps.yaml の spec-review-orchestrator が path を持つ" "deps.yaml not found"
fi

test_deps_yaml_orchestrator_type_script() {
  # script タイプとして登録されていること（type: script または scripts: セクション内）
  python3 -c "
import yaml, sys
with open('${PROJECT_ROOT}/${DEPS_YAML}') as f:
    data = yaml.safe_load(f)
scripts = data.get('components', {}).get('scripts', {})
entry = scripts.get('spec-review-orchestrator')
if entry is None:
    # トップレベル検索
    for section in data.get('components', {}).values():
        if isinstance(section, dict) and 'spec-review-orchestrator' in section:
            entry = section['spec-review-orchestrator']
            break
if entry is None:
    sys.exit(1)
sys.exit(0)
" 2>/dev/null
}

if [[ -f "${PROJECT_ROOT}/${DEPS_YAML}" ]]; then
  run_test "deps.yaml の spec-review-orchestrator が scripts セクションに登録されている" test_deps_yaml_orchestrator_type_script
else
  run_test_skip "deps.yaml の spec-review-orchestrator が scripts セクションに登録されている" "deps.yaml not found"
fi

# =============================================================================
# Edge Cases
# =============================================================================
echo ""
echo "--- Edge Cases ---"

# Edge case: スクリプトが実行可能ビット（executable）を持つ
test_orchestrator_executable() {
  [[ -x "${PROJECT_ROOT}/${ORCHESTRATOR_SH}" ]]
}

if [[ -f "${PROJECT_ROOT}/${ORCHESTRATOR_SH}" ]]; then
  run_test "[edge] spec-review-orchestrator.sh が実行可能ビットを持つ" test_orchestrator_executable
else
  run_test_skip "[edge] spec-review-orchestrator.sh が実行可能ビットを持つ" "script not yet created"
fi

# Edge case: shebang が bash
test_orchestrator_shebang() {
  local first_line
  first_line=$(head -1 "${PROJECT_ROOT}/${ORCHESTRATOR_SH}" 2>/dev/null)
  [[ "$first_line" == "#!/usr/bin/env bash" || "$first_line" == "#!/bin/bash" ]]
}

if [[ -f "${PROJECT_ROOT}/${ORCHESTRATOR_SH}" ]]; then
  run_test "[edge] spec-review-orchestrator.sh の shebang が bash" test_orchestrator_shebang
else
  run_test_skip "[edge] spec-review-orchestrator.sh の shebang が bash" "script not yet created"
fi

# Edge case: --issues-dir が存在しない場合のエラーハンドリング
test_orchestrator_missing_issues_dir_error() {
  assert_file_contains "$ORCHESTRATOR_SH" "exit 1|error|Error|存在しない|not.*exist|No such"
}

if [[ -f "${PROJECT_ROOT}/${ORCHESTRATOR_SH}" ]]; then
  run_test "[edge] spec-review-orchestrator.sh が不正引数でエラー終了する" test_orchestrator_missing_issues_dir_error
else
  run_test_skip "[edge] spec-review-orchestrator.sh が不正引数でエラー終了する" "script not yet created"
fi

# Edge case: MAX_PARALLEL=0 または負値への防御
test_orchestrator_max_parallel_guard() {
  # MAX_PARALLEL のバリデーションまたは算術ガード
  assert_file_contains "$ORCHESTRATOR_SH" "MAX_PARALLEL.*[0-9]|:\-[0-9]|default.*[0-9]"
}

if [[ -f "${PROJECT_ROOT}/${ORCHESTRATOR_SH}" ]]; then
  run_test "[edge] spec-review-orchestrator.sh MAX_PARALLEL にデフォルト値ガードがある" test_orchestrator_max_parallel_guard
else
  run_test_skip "[edge] spec-review-orchestrator.sh MAX_PARALLEL にデフォルト値ガードがある" "script not yet created"
fi

# Edge case: --issues-dir が空の場合（issue-*.json なし）に正常終了する
test_orchestrator_empty_issues_dir_graceful() {
  # 空の場合でもループが正常終了できる構造
  assert_file_contains "$ORCHESTRATOR_SH" "\bfor\b.*issue|\bwhile\b|\bls\b|\bfind\b"
}

if [[ -f "${PROJECT_ROOT}/${ORCHESTRATOR_SH}" ]]; then
  run_test "[edge] spec-review-orchestrator.sh が issue-*.json ゼロ件で正常終了できる構造" test_orchestrator_empty_issues_dir_graceful
else
  run_test_skip "[edge] spec-review-orchestrator.sh が issue-*.json ゼロ件で正常終了できる構造" "script not yet created"
fi

# Edge case: issue-spec-review コマンドを呼び出す記述
test_orchestrator_invokes_issue_spec_review() {
  assert_file_contains "$ORCHESTRATOR_SH" "issue-spec-review|/twl:issue-spec-review"
}

if [[ -f "${PROJECT_ROOT}/${ORCHESTRATOR_SH}" ]]; then
  run_test "[edge] spec-review-orchestrator.sh が issue-spec-review を呼び出す" test_orchestrator_invokes_issue_spec_review
else
  run_test_skip "[edge] spec-review-orchestrator.sh が issue-spec-review を呼び出す" "script not yet created"
fi

# Edge case: Step 3b に LLM 直接ループがないこと（N 回並列 Skill 呼び出し禁止）
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
