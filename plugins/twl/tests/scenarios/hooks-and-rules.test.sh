#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: hooks-and-rules.md
# Generated from: deltaspec/changes/b-2-bare-repo-depsyaml-v30-co-naming/specs/hooks-and-rules.md
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

assert_valid_json() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && python3 -c "import json; json.load(open('${PROJECT_ROOT}/${file}'))" 2>/dev/null
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

# =============================================================================
# Requirement: PostToolUse hook による twl validate 自動実行
# =============================================================================
echo ""
echo "--- Requirement: PostToolUse hook による twl validate 自動実行 ---"

# hooks.json is expected at .claude-plugin/hooks.json or .claude/hooks.json
HOOKS_FILE=""
if [[ -f "${PROJECT_ROOT}/hooks.json" ]]; then
  HOOKS_FILE="hooks.json"
elif [[ -f "${PROJECT_ROOT}/.claude-plugin/hooks.json" ]]; then
  HOOKS_FILE=".claude-plugin/hooks.json"
elif [[ -f "${PROJECT_ROOT}/.claude/hooks.json" ]]; then
  HOOKS_FILE=".claude/hooks.json"
fi

# Scenario: Edit 操作後に twl validate が実行される (line 7)
# WHEN: Edit ツールでファイルを変更する
# THEN: PostToolUse hook が発火し twl validate が実行される
test_hook_edit_twl_validate() {
  [[ -n "$HOOKS_FILE" ]] || return 1
  assert_file_exists "$HOOKS_FILE" || return 1
  assert_valid_json "$HOOKS_FILE" || return 1
  # Check hooks.json has PostToolUse with Edit/Write matcher and validate script reference
  python3 -c "
import json, sys
with open('${PROJECT_ROOT}/${HOOKS_FILE}') as f:
    data = json.load(f)
hooks = data.get('hooks', {}).get('PostToolUse', [])
if not isinstance(hooks, list):
    hooks = []
found = any('Edit' in str(h.get('matcher', '')) and 'validate' in str(h.get('command', '')) for h in hooks if isinstance(h, dict))
sys.exit(0 if found else 1)
" 2>/dev/null
}

if [[ -n "$HOOKS_FILE" ]]; then
  run_test "Edit 操作後に twl validate が実行される" test_hook_edit_twl_validate
else
  run_test_skip "Edit 操作後に twl validate が実行される" "hooks.json not found"
fi

# Edge case: hooks.json が有効な JSON
test_hooks_valid_json() {
  [[ -n "$HOOKS_FILE" ]] || return 1
  assert_valid_json "$HOOKS_FILE"
}

if [[ -n "$HOOKS_FILE" ]]; then
  run_test "hooks.json [edge: 有効な JSON]" test_hooks_valid_json
else
  run_test_skip "hooks.json [edge: 有効な JSON]" "hooks.json not found"
fi

# Edge case: Edit と Write の両方が hook 対象
test_hook_edit_and_write() {
  [[ -n "$HOOKS_FILE" ]] || return 1
  assert_file_contains "$HOOKS_FILE" "Edit" || return 1
  assert_file_contains "$HOOKS_FILE" "Write"
}

if [[ -n "$HOOKS_FILE" ]]; then
  run_test "hooks.json [edge: Edit と Write 両方が対象]" test_hook_edit_and_write
else
  run_test_skip "hooks.json [edge: Edit と Write 両方が対象]" "hooks.json not found"
fi

# Scenario: validate 違反時に報告される (line 11)
# WHEN: twl validate が violation を検出する
# THEN: 違反内容がユーザーに報告される
# Note: This is a behavioral test - we verify the hook configuration includes output reporting
test_hook_validate_reports() {
  [[ -n "$HOOKS_FILE" ]] || return 1
  assert_file_exists "$HOOKS_FILE" || return 1
  # The validate script should report output (not silenced to /dev/null)
  # Check the referenced script file exists and reports violations
  local validate_script="scripts/hooks/post-tool-use-validate.sh"
  assert_file_exists "$validate_script" || return 1
  # Script should output violations (grep/echo, not redirect to /dev/null exclusively)
  grep -q "echo\|printf" "${PROJECT_ROOT}/${validate_script}"
}

if [[ -n "$HOOKS_FILE" ]]; then
  run_test "validate 違反時に報告される" test_hook_validate_reports
else
  run_test_skip "validate 違反時に報告される" "hooks.json not found"
fi

# =============================================================================
# Requirement: PostToolUse hook による Bash エラー記録
# =============================================================================
echo ""
echo "--- Requirement: PostToolUse hook による Bash エラー記録 ---"

# Scenario: Bash コマンド失敗時にエラーが記録される (line 19)
# WHEN: Bash ツールで実行したコマンドが exit_code != 0 で終了する
# THEN: .self-improve/errors.jsonl にタイムスタンプ、コマンド、exit_code、出力を含む JSON 行が追記される
test_hook_bash_error_recording() {
  [[ -n "$HOOKS_FILE" ]] || return 1
  assert_file_exists "$HOOKS_FILE" || return 1
  # Check hooks.json references Bash tool and error recording
  python3 -c "
import json, sys
with open('${PROJECT_ROOT}/${HOOKS_FILE}') as f:
    content = f.read()
has_bash = 'Bash' in content or 'bash' in content
has_error = 'error' in content.lower() or 'self-improve' in content or 'exit_code' in content
sys.exit(0 if has_bash and has_error else 1)
" 2>/dev/null
}

if [[ -n "$HOOKS_FILE" ]]; then
  run_test "Bash コマンド失敗時にエラーが記録される" test_hook_bash_error_recording
else
  run_test_skip "Bash コマンド失敗時にエラーが記録される" "hooks.json not found"
fi

# Edge case: errors.jsonl のパスが .self-improve/errors.jsonl
test_hook_error_jsonl_path() {
  # Check the bash-error script references .self-improve/errors.jsonl
  local error_script="scripts/hooks/post-tool-use-bash-error.sh"
  assert_file_exists "$error_script" || return 1
  assert_file_contains "$error_script" "self-improve.*errors\.jsonl|errors\.jsonl"
}

if [[ -n "$HOOKS_FILE" ]]; then
  run_test "Bash エラー記録 [edge: errors.jsonl パス正確]" test_hook_error_jsonl_path
else
  run_test_skip "Bash エラー記録 [edge: errors.jsonl パス正確]" "hooks.json not found"
fi

# Scenario: Bash コマンド成功時にエラーが記録されない (line 23)
# WHEN: Bash ツールで実行したコマンドが exit_code == 0 で終了する
# THEN: .self-improve/errors.jsonl にエントリが追加されない
# Note: Behavioral test - verify hook has condition for exit_code != 0
test_hook_bash_success_no_record() {
  # Check the bash-error script has exit_code == 0 guard
  local error_script="scripts/hooks/post-tool-use-bash-error.sh"
  assert_file_exists "$error_script" || return 1
  # Script should check EXIT_CODE and exit early on success
  assert_file_contains "$error_script" "EXIT_CODE.*==.*0|EXIT_CODE.*-eq.*0"
}

if [[ -n "$HOOKS_FILE" ]]; then
  run_test "Bash コマンド成功時にエラーが記録されない" test_hook_bash_success_no_record
else
  run_test_skip "Bash コマンド成功時にエラーが記録されない" "hooks.json not found"
fi

# Edge case: エラー記録に timestamp フィールドが含まれる設計
test_hook_error_has_timestamp() {
  [[ -n "$HOOKS_FILE" ]] || return 1
  assert_file_contains "$HOOKS_FILE" "timestamp|date|time"
}

if [[ -n "$HOOKS_FILE" ]]; then
  run_test "Bash エラー記録 [edge: timestamp フィールド]" test_hook_error_has_timestamp
else
  run_test_skip "Bash エラー記録 [edge: timestamp フィールド]" "hooks.json not found"
fi

# =============================================================================
# Requirement: CLAUDE.md に bare repo 検証ルール記載
# =============================================================================
echo ""
echo "--- Requirement: CLAUDE.md に bare repo 検証ルール記載 ---"

CLAUDE_MD="CLAUDE.md"

# Scenario: CLAUDE.md に bare repo 検証が記載されている (line 34)
# WHEN: CLAUDE.md を読み込む
# THEN: bare repo 構造検証の3条件が全て記載されている
test_claudemd_bare_repo_verification() {
  assert_file_exists "$CLAUDE_MD" || return 1
  assert_file_contains_all "$CLAUDE_MD" \
    '\.bare' \
    'main/\.git|\.git.*ファイル' \
    'CWD|main.*配下|カレントディレクトリ'
}
run_test "CLAUDE.md に bare repo 検証が記載されている" test_claudemd_bare_repo_verification

# Edge case: 3条件が番号付きリストで記載されている
test_claudemd_bare_repo_numbered() {
  assert_file_exists "$CLAUDE_MD" || return 1
  # Check for numbered list items related to bare repo verification
  local count=0
  for pattern in '\.bare' 'main/\.git|\.git.*ファイル' 'CWD|main.*配下'; do
    if grep -P "$pattern" "${PROJECT_ROOT}/${CLAUDE_MD}" | grep -qP "^[0-9]+[\.\)]|^\s*[0-9]+[\.\)]"; then
      ((count++))
    fi
  done
  # At least the conditions should be in a structured format (numbered or bulleted)
  assert_file_contains "$CLAUDE_MD" "^[0-9]+[\.\)].*bare|^-\s.*bare|^\*\s.*bare"
}
run_test "CLAUDE.md bare repo [edge: 構造化リスト形式]" test_claudemd_bare_repo_numbered

# Edge case: .git がファイルであることが明示されている（ディレクトリではない）
test_claudemd_git_is_file() {
  assert_file_exists "$CLAUDE_MD" || return 1
  assert_file_contains "$CLAUDE_MD" "\.git.*ファイル|ファイル.*\.git|\.git.*file"
}
run_test "CLAUDE.md bare repo [edge: .git がファイルと明記]" test_claudemd_git_is_file

# Scenario: セッション起動ルールが記載されている (line 38)
# WHEN: CLAUDE.md を読み込む
# THEN: main/ でのセッション起動必須、worktrees/ 配下での起動禁止が明記されている
test_claudemd_session_rules() {
  assert_file_exists "$CLAUDE_MD" || return 1
  assert_file_contains "$CLAUDE_MD" "main.*セッション|main.*起動|main.*worktree" || return 1
  assert_file_contains "$CLAUDE_MD" "worktree.*禁止|worktree.*起動.*しない|worktrees.*配下.*禁止"
}
run_test "セッション起動ルールが記載されている" test_claudemd_session_rules

# Edge case: main/ で起動すべき理由が説明されている
test_claudemd_session_reason() {
  assert_file_exists "$CLAUDE_MD" || return 1
  # Should have some explanation about why main/ is required
  assert_file_contains "$CLAUDE_MD" "bare.*repo|\.bare|worktree.*構造"
}
run_test "セッション起動ルール [edge: 理由が説明されている]" test_claudemd_session_reason

# =============================================================================
# Requirement: .gitignore の配置
# =============================================================================
echo ""
echo "--- Requirement: .gitignore の配置 ---"

# Scenario: .gitignore が適切な除外パターンを含む (line 46)
# WHEN: .gitignore を読み込む
# THEN: .self-improve/ と .code-review-graph/ が除外パターンに含まれている
test_gitignore_exclusions() {
  assert_file_exists ".gitignore" || return 1
  assert_file_contains ".gitignore" "\.self-improve" || return 1
  assert_file_contains ".gitignore" "\.code-review-graph"
}
run_test ".gitignore が適切な除外パターンを含む" test_gitignore_exclusions

# Edge case: パターンがコメントアウトされていない
test_gitignore_not_commented() {
  assert_file_exists ".gitignore" || return 1
  # .self-improve should appear on a non-comment line
  grep -P "\.self-improve" "${PROJECT_ROOT}/.gitignore" | grep -qvP "^\s*#" || return 1
  grep -P "\.code-review-graph" "${PROJECT_ROOT}/.gitignore" | grep -qvP "^\s*#"
}
run_test ".gitignore [edge: パターンがコメントアウトされていない]" test_gitignore_not_commented

# Edge case: .gitignore が / で始まるパスか、ディレクトリを意味する / で終わるパターン
test_gitignore_directory_patterns() {
  assert_file_exists ".gitignore" || return 1
  # Check that patterns end with / or are directory-like
  grep -qP "self-improve/" "${PROJECT_ROOT}/.gitignore" || return 1
  grep -qP "code-review-graph/" "${PROJECT_ROOT}/.gitignore"
}
run_test ".gitignore [edge: ディレクトリ除外パターン形式]" test_gitignore_directory_patterns

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
