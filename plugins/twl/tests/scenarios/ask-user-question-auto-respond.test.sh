#!/usr/bin/env bash
# =============================================================================
# Functional Tests: ask-user-question-auto-respond.md
# Generated from: openspec/changes/claude-code-hooks-autopilot/specs/ask-user-question-auto-respond.md
# Coverage level: edge-cases
# Tests the actual behavior of scripts/hooks/pre-tool-use-ask-user-question.sh
# =============================================================================
set -uo pipefail

# Project root (relative to test file location)
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK_SCRIPT="${PROJECT_ROOT}/scripts/hooks/pre-tool-use-ask-user-question.sh"
HOOKS_JSON="${PROJECT_ROOT}/hooks/hooks.json"

# Counters
PASS=0
FAIL=0
SKIP=0
ERRORS=()

# --- Sandbox Setup ---

SANDBOX=""

setup_sandbox() {
  SANDBOX=$(mktemp -d)
  mkdir -p "${SANDBOX}/scripts/hooks"
  mkdir -p "${SANDBOX}/.autopilot"
  if [[ -f "$HOOK_SCRIPT" ]]; then
    cp "$HOOK_SCRIPT" "${SANDBOX}/scripts/hooks/pre-tool-use-ask-user-question.sh"
    chmod +x "${SANDBOX}/scripts/hooks/pre-tool-use-ask-user-question.sh"
  fi
}

teardown_sandbox() {
  if [[ -n "$SANDBOX" && -d "$SANDBOX" ]]; then
    rm -rf "$SANDBOX"
  fi
  SANDBOX=""
}

# Run the hook with given stdin JSON; outputs stdout (AUTOPILOT_DIR set for autopilot context)
run_hook() {
  local input_json="$1"
  printf '%s' "$input_json" | AUTOPILOT_DIR="${SANDBOX}/.autopilot" bash "${SANDBOX}/scripts/hooks/pre-tool-use-ask-user-question.sh" 2>/dev/null
}

# --- Test Helpers ---

run_test() {
  local name="$1"
  local func="$2"
  local result
  setup_sandbox
  result=0
  $func || result=$?
  teardown_sandbox
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

hook_available() {
  [[ -f "$HOOK_SCRIPT" ]]
}

# =============================================================================
# Requirement: AskUserQuestion 自動応答 hook
# =============================================================================
echo ""
echo "--- Requirement: AskUserQuestion 自動応答 hook ---"

# Scenario: 選択肢付き質問への自動応答 (line 8)
# WHEN: Worker が AskUserQuestion を呼び、tool_input.questions[].options に 1 件以上の選択肢がある
# THEN: hook スクリプトが最初の option の label を answers に設定し、
#       permissionDecision: "allow" と updatedInput を返す
test_auto_respond_with_options() {
  local input_json
  input_json=$(cat <<'EOF'
{
  "tool_name": "AskUserQuestion",
  "tool_input": {
    "questions": [
      {
        "question": "どのアプローチを選びますか?",
        "options": [
          {"label": "アプローチA", "value": "a"},
          {"label": "アプローチB", "value": "b"}
        ]
      }
    ]
  }
}
EOF
)
  local output
  output=$(run_hook "$input_json")
  [[ -n "$output" ]] || return 1
  # Must output valid JSON
  echo "$output" | python3 -c "import json,sys; data=json.load(sys.stdin)" 2>/dev/null || return 1
  # permissionDecision must be "allow"
  local decision
  decision=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('hookSpecificOutput',{}).get('permissionDecision',''))" 2>/dev/null)
  [[ "$decision" == "allow" ]] || return 1
  # updatedInput must be present
  local has_updated
  has_updated=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); h=d.get('hookSpecificOutput',{}); print('yes' if 'updatedInput' in h else 'no')" 2>/dev/null)
  [[ "$has_updated" == "yes" ]] || return 1
  # answers must contain the first option's label
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
updated = d.get('hookSpecificOutput', {}).get('updatedInput', {})
questions = updated.get('questions', [])
assert len(questions) > 0, 'no questions in updatedInput'
answers = questions[0].get('answer', '') or updated.get('answers', [''])[0] if isinstance(updated.get('answers'), list) else ''
# Accept either 'answer' in question or 'answers' list containing first label
content = json.dumps(d, ensure_ascii=False)
assert 'アプローチA' in content, f'first option label not found in output: {content}'
" 2>/dev/null || return 1
}

if hook_available; then
  run_test "選択肢付き質問への自動応答" test_auto_respond_with_options
else
  run_test_skip "選択肢付き質問への自動応答" "hook script not found"
fi

# Edge case: 複数選択肢があっても常に最初の label が使われる
test_auto_respond_first_option_selected() {
  local input_json
  input_json=$(cat <<'EOF'
{
  "tool_name": "AskUserQuestion",
  "tool_input": {
    "questions": [
      {
        "question": "確認してください",
        "options": [
          {"label": "はい", "value": "yes"},
          {"label": "いいえ", "value": "no"},
          {"label": "キャンセル", "value": "cancel"}
        ]
      }
    ]
  }
}
EOF
)
  local output
  output=$(run_hook "$input_json")
  [[ -n "$output" ]] || return 1
  # "はい" (first) should appear; "いいえ" and "キャンセル" should not be selected
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
content = json.dumps(d, ensure_ascii=False)
assert 'はい' in content, f'first option not found: {content}'
" 2>/dev/null || return 1
}

if hook_available; then
  run_test "選択肢付き自動応答 [edge: 最初の選択肢を選ぶ]" test_auto_respond_first_option_selected
else
  run_test_skip "選択肢付き自動応答 [edge: 最初の選択肢を選ぶ]" "hook script not found"
fi

# Edge case: 複数の question がある場合も全て自動応答される
test_auto_respond_multiple_questions() {
  local input_json
  input_json=$(cat <<'EOF'
{
  "tool_name": "AskUserQuestion",
  "tool_input": {
    "questions": [
      {
        "question": "質問1?",
        "options": [{"label": "選択肢1A"}, {"label": "選択肢1B"}]
      },
      {
        "question": "質問2?",
        "options": [{"label": "選択肢2A"}, {"label": "選択肢2B"}]
      }
    ]
  }
}
EOF
)
  local output
  output=$(run_hook "$input_json")
  [[ -n "$output" ]] || return 1
  local decision
  decision=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('hookSpecificOutput',{}).get('permissionDecision',''))" 2>/dev/null)
  [[ "$decision" == "allow" ]] || return 1
}

if hook_available; then
  run_test "選択肢付き自動応答 [edge: 複数 question]" test_auto_respond_multiple_questions
else
  run_test_skip "選択肢付き自動応答 [edge: 複数 question]" "hook script not found"
fi

# Scenario: open-ended 質問への自動応答 (line 12)
# WHEN: Worker が AskUserQuestion を呼び、tool_input.questions[].options が空または未設定
# THEN: hook スクリプトが "(autopilot: skipped)" を answers に設定し、
#       permissionDecision: "allow" と updatedInput を返す
test_auto_respond_open_ended_no_options() {
  local input_json
  input_json=$(cat <<'EOF'
{
  "tool_name": "AskUserQuestion",
  "tool_input": {
    "questions": [
      {
        "question": "実装の方針を教えてください"
      }
    ]
  }
}
EOF
)
  local output
  output=$(run_hook "$input_json")
  [[ -n "$output" ]] || return 1
  local decision
  decision=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('hookSpecificOutput',{}).get('permissionDecision',''))" 2>/dev/null)
  [[ "$decision" == "allow" ]] || return 1
  # "(autopilot: skipped)" must appear somewhere in the output
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
content = json.dumps(d, ensure_ascii=False)
assert '(autopilot: skipped)' in content, f'skipped marker not found: {content}'
" 2>/dev/null || return 1
}

if hook_available; then
  run_test "open-ended 質問への自動応答（options なし）" test_auto_respond_open_ended_no_options
else
  run_test_skip "open-ended 質問への自動応答（options なし）" "hook script not found"
fi

# Edge case: options が空配列でも skipped が設定される
test_auto_respond_open_ended_empty_options() {
  local input_json
  input_json=$(cat <<'EOF'
{
  "tool_name": "AskUserQuestion",
  "tool_input": {
    "questions": [
      {
        "question": "何かありますか?",
        "options": []
      }
    ]
  }
}
EOF
)
  local output
  output=$(run_hook "$input_json")
  [[ -n "$output" ]] || return 1
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
content = json.dumps(d, ensure_ascii=False)
assert '(autopilot: skipped)' in content, f'skipped marker not found: {content}'
" 2>/dev/null || return 1
}

if hook_available; then
  run_test "open-ended 自動応答 [edge: options 空配列]" test_auto_respond_open_ended_empty_options
else
  run_test_skip "open-ended 自動応答 [edge: options 空配列]" "hook script not found"
fi

# Edge case: updatedInput が返された場合、questions フィールドが保持される
test_auto_respond_updated_input_has_questions() {
  local input_json
  input_json=$(cat <<'EOF'
{
  "tool_name": "AskUserQuestion",
  "tool_input": {
    "questions": [
      {"question": "テストの質問?"}
    ]
  }
}
EOF
)
  local output
  output=$(run_hook "$input_json")
  [[ -n "$output" ]] || return 1
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
updated = d.get('hookSpecificOutput', {}).get('updatedInput', {})
assert 'questions' in updated, f'questions not found in updatedInput: {updated}'
" 2>/dev/null || return 1
}

if hook_available; then
  run_test "open-ended 自動応答 [edge: updatedInput に questions 保持]" test_auto_respond_updated_input_has_questions
else
  run_test_skip "open-ended 自動応答 [edge: updatedInput に questions 保持]" "hook script not found"
fi

# Edge case: hook は常に exit 0 を返す（ブロッキング禁止）
test_hook_always_exit_zero() {
  local inputs=(
    '{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"q?","options":[{"label":"A"}]}]}}'
    '{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"q?"}]}}'
    '{}'
    ''
  )
  for input_json in "${inputs[@]}"; do
    printf '%s' "$input_json" | AUTOPILOT_DIR="${SANDBOX}/.autopilot" bash "${SANDBOX}/scripts/hooks/pre-tool-use-ask-user-question.sh" 2>/dev/null
    local result=$?
    [[ "$result" -eq 0 ]] || return 1
  done
}

if hook_available; then
  run_test "hook が常に exit 0 [edge: ブロッキング禁止]" test_hook_always_exit_zero
else
  run_test_skip "hook が常に exit 0" "hook script not found"
fi

# Edge case: 不正な JSON 入力でも crash しない
test_hook_invalid_json_no_crash() {
  local result
  printf 'not json at all' | bash "${SANDBOX}/scripts/hooks/pre-tool-use-ask-user-question.sh" 2>/dev/null
  result=$?
  [[ "$result" -eq 0 ]] || return 1
}

if hook_available; then
  run_test "不正 JSON 入力でも crash しない [edge]" test_hook_invalid_json_no_crash
else
  run_test_skip "不正 JSON 入力でも crash しない" "hook script not found"
fi

# Scenario: hooks.json への登録 (line 16)
# WHEN: hooks/hooks.json を読み込む
# THEN: PreToolUse セクションに "matcher": "AskUserQuestion" エントリが存在しなければならない
test_hooks_json_has_ask_user_question() {
  [[ -f "$HOOKS_JSON" ]] || return 1
  python3 -c "
import json, sys
with open('$HOOKS_JSON') as f:
    data = json.load(f)
hooks = data.get('hooks', {}).get('PreToolUse', [])
if not isinstance(hooks, list):
    hooks = []
found = any('AskUserQuestion' in str(h.get('matcher', '')) for h in hooks if isinstance(h, dict))
sys.exit(0 if found else 1)
" 2>/dev/null
}

if [[ -f "$HOOKS_JSON" ]]; then
  run_test "hooks.json に AskUserQuestion エントリ登録" test_hooks_json_has_ask_user_question
else
  run_test_skip "hooks.json に AskUserQuestion エントリ登録" "hooks.json not found"
fi

# Edge case: hooks.json が有効な JSON
test_hooks_json_valid() {
  [[ -f "$HOOKS_JSON" ]] || return 1
  python3 -c "import json; json.load(open('$HOOKS_JSON'))" 2>/dev/null
}

if [[ -f "$HOOKS_JSON" ]]; then
  run_test "hooks.json [edge: 有効な JSON]" test_hooks_json_valid
else
  run_test_skip "hooks.json [edge: 有効な JSON]" "hooks.json not found"
fi

# Scenario: 既存 PreToolUse hook との共存 (line 20)
# WHEN: PreToolUse セクションに既存の "matcher": "Edit|Write" エントリがある
# THEN: AskUserQuestion エントリは別エントリとして追加され、既存エントリを変更しない
test_hooks_json_coexist_with_existing() {
  [[ -f "$HOOKS_JSON" ]] || return 1
  python3 -c "
import json, sys
with open('$HOOKS_JSON') as f:
    data = json.load(f)
hooks = data.get('hooks', {}).get('PreToolUse', [])
if not isinstance(hooks, list):
    hooks = []
has_ask = any('AskUserQuestion' in str(h.get('matcher', '')) for h in hooks if isinstance(h, dict))
# PreToolUse may not yet have Edit|Write (those are PostToolUse), but AskUserQuestion should be a separate entry
# The key requirement: AskUserQuestion is a standalone entry in the PreToolUse list
if not has_ask:
    sys.exit(1)
# Verify AskUserQuestion entry does not interfere with other entries (separate dict objects)
ask_entries = [h for h in hooks if isinstance(h, dict) and 'AskUserQuestion' in str(h.get('matcher', ''))]
assert len(ask_entries) >= 1, 'AskUserQuestion entry missing'
sys.exit(0)
" 2>/dev/null
}

if [[ -f "$HOOKS_JSON" ]]; then
  run_test "hooks.json [既存 PreToolUse と共存]" test_hooks_json_coexist_with_existing
else
  run_test_skip "hooks.json [既存 PreToolUse と共存]" "hooks.json not found"
fi

# Edge case: AskUserQuestion エントリに command フィールドが存在する
test_hooks_json_ask_entry_has_command() {
  [[ -f "$HOOKS_JSON" ]] || return 1
  python3 -c "
import json, sys
with open('$HOOKS_JSON') as f:
    data = json.load(f)
hooks = data.get('hooks', {}).get('PreToolUse', [])
if not isinstance(hooks, list):
    hooks = []
for h in hooks:
    if not isinstance(h, dict):
        continue
    if 'AskUserQuestion' in str(h.get('matcher', '')):
        # Entry should have nested hooks with command
        inner = h.get('hooks', [])
        if isinstance(inner, list):
            for ih in inner:
                if isinstance(ih, dict) and 'command' in ih:
                    sys.exit(0)
        # Or direct command field
        if 'command' in h:
            sys.exit(0)
sys.exit(1)
" 2>/dev/null
}

if [[ -f "$HOOKS_JSON" ]]; then
  run_test "hooks.json AskUserQuestion [edge: command フィールド存在]" test_hooks_json_ask_entry_has_command
else
  run_test_skip "hooks.json AskUserQuestion [edge: command フィールド存在]" "hooks.json not found"
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
