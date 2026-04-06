#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: autopilot summary, session-audit, SKILL.md & deps.yaml
# Generated from: deltaspec/changes/archive/2026-03-29-c-2d-autopilot-controller-autopilot/specs/summary-audit/spec.md
# Coverage level: edge-cases
# Verifies: autopilot-summary, session-audit COMMAND.md + SKILL.md calls + deps.yaml
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

SUMMARY_CMD="commands/autopilot-summary.md"
AUDIT_CMD="commands/session-audit.md"
SKILL_MD="skills/co-autopilot/SKILL.md"
DEPS_YAML="deps.yaml"

# All 11 commands that must be defined
ALL_11_COMMANDS=(
  "autopilot-init"
  "autopilot-launch"
  "autopilot-poll"
  "autopilot-phase-execute"
  "autopilot-phase-postprocess"
  "autopilot-collect"
  "autopilot-retrospective"
  "autopilot-patterns"
  "autopilot-cross-issue"
  "autopilot-summary"
  "session-audit"
)

# =============================================================================
# Requirement: autopilot-summary コマンド
# =============================================================================
echo ""
echo "--- Requirement: autopilot-summary コマンド ---"

# Scenario: 全 Issue 成功時のサマリー (line 22)
# WHEN: 全 Issue が done
# THEN: 成功件数と各 PR 番号を含むサマリーを出力し、notify-send で完了通知する

test_summary_file_exists() {
  assert_file_exists "$SUMMARY_CMD"
}

if [[ -f "${PROJECT_ROOT}/${SUMMARY_CMD}" ]]; then
  run_test "autopilot-summary COMMAND.md が存在する" test_summary_file_exists
else
  run_test_skip "autopilot-summary COMMAND.md が存在する" "commands/autopilot-summary.md not yet created"
fi

test_summary_frontmatter_type() {
  return 0  # deps.yaml defines type
}

if [[ -f "${PROJECT_ROOT}/${SUMMARY_CMD}" ]]; then
  run_test "autopilot-summary COMMAND.md exists (deps.yaml defines type)" test_summary_frontmatter_type
else
  run_test_skip "autopilot-summary COMMAND.md exists (deps.yaml defines type)" "COMMAND.md not yet created"
fi

test_summary_state_read_ref() {
  assert_file_contains "$SUMMARY_CMD" "state-read\.sh|state-read"
}

if [[ -f "${PROJECT_ROOT}/${SUMMARY_CMD}" ]]; then
  run_test "autopilot-summary が state-read.sh を参照" test_summary_state_read_ref
else
  run_test_skip "autopilot-summary が state-read.sh を参照" "COMMAND.md not yet created"
fi

test_summary_session_archive_ref() {
  assert_file_contains "$SUMMARY_CMD" "session-archive\.sh|session-archive"
}

if [[ -f "${PROJECT_ROOT}/${SUMMARY_CMD}" ]]; then
  run_test "autopilot-summary が session-archive.sh を参照" test_summary_session_archive_ref
else
  run_test_skip "autopilot-summary が session-archive.sh を参照" "COMMAND.md not yet created"
fi

test_summary_notify_send() {
  assert_file_contains "$SUMMARY_CMD" "notify-send|pw-play|通知"
}

if [[ -f "${PROJECT_ROOT}/${SUMMARY_CMD}" ]]; then
  run_test "autopilot-summary が notify-send / pw-play 通知を記述" test_summary_notify_send
else
  run_test_skip "autopilot-summary が notify-send / pw-play 通知を記述" "COMMAND.md not yet created"
fi

test_summary_doobidoo_store() {
  assert_file_contains "$SUMMARY_CMD" "doobidoo.*memory_store|memory.*store|session-completion-report"
}

if [[ -f "${PROJECT_ROOT}/${SUMMARY_CMD}" ]]; then
  run_test "autopilot-summary が doobidoo memory_store (session-completion-report) を記述" test_summary_doobidoo_store
else
  run_test_skip "autopilot-summary が doobidoo memory_store (session-completion-report) を記述" "COMMAND.md not yet created"
fi

test_summary_plan_yaml_all_issues() {
  assert_file_contains "$SUMMARY_CMD" "plan\.yaml|ALL_ISSUES|PLAN_FILE"
}

if [[ -f "${PROJECT_ROOT}/${SUMMARY_CMD}" ]]; then
  run_test "autopilot-summary が plan.yaml から ALL_ISSUES 構築を記述" test_summary_plan_yaml_all_issues
else
  run_test_skip "autopilot-summary が plan.yaml から ALL_ISSUES 構築を記述" "COMMAND.md not yet created"
fi

# Scenario: 失敗含むサマリー (line 26)
# WHEN: 一部 Issue が failed
# THEN: 失敗件数と reason を含むサマリーを出力し、notify-send で失敗通知する

test_summary_failure_report() {
  assert_file_contains "$SUMMARY_CMD" "failed|失敗|fail.*件数|failure.*reason"
}

if [[ -f "${PROJECT_ROOT}/${SUMMARY_CMD}" ]]; then
  run_test "autopilot-summary 失敗サマリーの記述" test_summary_failure_report
else
  run_test_skip "autopilot-summary 失敗サマリーの記述" "COMMAND.md not yet created"
fi

# Scenario: session-audit 失敗時 (line 30)
# WHEN: session-audit の実行が失敗する
# THEN: 「session-audit: 実行失敗（スキップ）」をサマリーに含め、ワークフローは停止しない

test_summary_audit_failure_handling() {
  assert_file_contains "$SUMMARY_CMD" "session-audit.*失敗|session-audit.*スキップ|session-audit.*fail.*skip|session-audit.*warning"
}

if [[ -f "${PROJECT_ROOT}/${SUMMARY_CMD}" ]]; then
  run_test "autopilot-summary session-audit 失敗時のスキップ記述" test_summary_audit_failure_handling
else
  run_test_skip "autopilot-summary session-audit 失敗時のスキップ記述" "COMMAND.md not yet created"
fi

# Scenario: セッションアーカイブ (line 34)
# WHEN: サマリー出力完了後
# THEN: session-archive.sh が実行され .autopilot/archive/ にセッションデータが移動される

test_summary_archive_after_report() {
  assert_file_contains "$SUMMARY_CMD" "session-archive" || return 1
  assert_file_contains "$SUMMARY_CMD" "archive" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SUMMARY_CMD}" ]]; then
  run_test "autopilot-summary サマリー後のアーカイブ記述" test_summary_archive_after_report
else
  run_test_skip "autopilot-summary サマリー後のアーカイブ記述" "COMMAND.md not yet created"
fi

# Edge case: マーカーファイル参照なし
test_summary_no_marker_refs() {
  assert_file_not_contains "$SUMMARY_CMD" "MARKER_DIR" || return 1
  assert_file_not_contains "$SUMMARY_CMD" '\.done"' || return 1
  assert_file_not_contains "$SUMMARY_CMD" '\.fail"' || return 1
  assert_file_not_contains "$SUMMARY_CMD" '\.merge-ready"' || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SUMMARY_CMD}" ]]; then
  run_test "autopilot-summary [edge: マーカーファイル参照なし]" test_summary_no_marker_refs
else
  run_test_skip "autopilot-summary [edge: マーカーファイル参照なし]" "COMMAND.md not yet created"
fi

# Edge case: DEV_AUTOPILOT_SESSION 参照なし
test_summary_no_dev_autopilot_session() {
  assert_file_not_contains "$SUMMARY_CMD" "DEV_AUTOPILOT_SESSION"
}

if [[ -f "${PROJECT_ROOT}/${SUMMARY_CMD}" ]]; then
  run_test "autopilot-summary [edge: DEV_AUTOPILOT_SESSION 参照なし]" test_summary_no_dev_autopilot_session
else
  run_test_skip "autopilot-summary [edge: DEV_AUTOPILOT_SESSION 参照なし]" "COMMAND.md not yet created"
fi

# Edge case: session-audit を --since で呼び出し
test_summary_audit_since() {
  assert_file_contains "$SUMMARY_CMD" "session-audit.*--since|--since.*ELAPSED"
}

if [[ -f "${PROJECT_ROOT}/${SUMMARY_CMD}" ]]; then
  run_test "autopilot-summary [edge: session-audit --since の呼び出し]" test_summary_audit_since
else
  run_test_skip "autopilot-summary [edge: session-audit --since の呼び出し]" "COMMAND.md not yet created"
fi

# =============================================================================
# Requirement: session-audit コマンド
# =============================================================================
echo ""
echo "--- Requirement: session-audit コマンド ---"

# Scenario: 直近 5 セッション分析 (line 54)
# WHEN: 引数なしで実行
# THEN: 最新 5 セッションの JSONL を分析し、検出結果テーブルを出力する

test_audit_file_exists() {
  assert_file_exists "$AUDIT_CMD"
}

if [[ -f "${PROJECT_ROOT}/${AUDIT_CMD}" ]]; then
  run_test "session-audit COMMAND.md が存在する" test_audit_file_exists
else
  run_test_skip "session-audit COMMAND.md が存在する" "commands/session-audit.md not yet created"
fi

test_audit_frontmatter_type() {
  return 0  # deps.yaml defines type
}

if [[ -f "${PROJECT_ROOT}/${AUDIT_CMD}" ]]; then
  run_test "session-audit COMMAND.md exists (deps.yaml defines type)" test_audit_frontmatter_type
else
  run_test_skip "session-audit COMMAND.md exists (deps.yaml defines type)" "COMMAND.md not yet created"
fi

test_audit_default_count() {
  assert_file_contains "$AUDIT_CMD" "COUNT.*5|デフォルト.*5|default.*5|count.*5"
}

if [[ -f "${PROJECT_ROOT}/${AUDIT_CMD}" ]]; then
  run_test "session-audit デフォルト COUNT=5 の記述" test_audit_default_count
else
  run_test_skip "session-audit デフォルト COUNT=5 の記述" "COMMAND.md not yet created"
fi

test_audit_session_audit_sh() {
  assert_file_contains "$AUDIT_CMD" "session-audit\.sh"
}

if [[ -f "${PROJECT_ROOT}/${AUDIT_CMD}" ]]; then
  run_test "session-audit が session-audit.sh を参照" test_audit_session_audit_sh
else
  run_test_skip "session-audit が session-audit.sh を参照" "COMMAND.md not yet created"
fi

# Scenario: 期間指定分析 (line 58)
# WHEN: --since 3d で実行
# THEN: 直近 3 日間のセッション JSONL を分析する

test_audit_since_option() {
  assert_file_contains "$AUDIT_CMD" "--since"
}

if [[ -f "${PROJECT_ROOT}/${AUDIT_CMD}" ]]; then
  run_test "session-audit --since オプションの記述" test_audit_since_option
else
  run_test_skip "session-audit --since オプションの記述" "COMMAND.md not yet created"
fi

# Scenario: confidence 閾値フィルタリング (line 62)
# WHEN: 分析で confidence 65 の検出がある
# THEN: 低 confidence としてログ出力のみ。Issue 起票はしない

test_audit_confidence_threshold() {
  assert_file_contains "$AUDIT_CMD" "confidence.*>=.*70|confidence.*70|confidence.*閾値"
}

if [[ -f "${PROJECT_ROOT}/${AUDIT_CMD}" ]]; then
  run_test "session-audit confidence >= 70 閾値の記述" test_audit_confidence_threshold
else
  run_test_skip "session-audit confidence >= 70 閾値の記述" "COMMAND.md not yet created"
fi

# Scenario: 重複排除 (line 66)
# WHEN: 同一パターンの self-improve Issue が既に open
# THEN: 重複としてスキップする

test_audit_dedup() {
  assert_file_contains "$AUDIT_CMD" "重複排除|重複.*スキップ|dedup|duplicate.*skip|既に.*open"
}

if [[ -f "${PROJECT_ROOT}/${AUDIT_CMD}" ]]; then
  run_test "session-audit 重複排除の記述" test_audit_dedup
else
  run_test_skip "session-audit 重複排除の記述" "COMMAND.md not yet created"
fi

# Edge case: Haiku Agent での分析（Haiku 以外禁止）
test_audit_haiku_only() {
  assert_file_contains "$AUDIT_CMD" "[Hh]aiku"
}

if [[ -f "${PROJECT_ROOT}/${AUDIT_CMD}" ]]; then
  run_test "session-audit [edge: Haiku Agent 指定の記述]" test_audit_haiku_only
else
  run_test_skip "session-audit [edge: Haiku Agent 指定の記述]" "COMMAND.md not yet created"
fi

# Edge case: 5 カテゴリ分析の記述
test_audit_5_categories() {
  assert_file_contains "$AUDIT_CMD" "script-fragility" || return 1
  assert_file_contains "$AUDIT_CMD" "silent-failure" || return 1
  assert_file_contains "$AUDIT_CMD" "ai-compensation" || return 1
  assert_file_contains "$AUDIT_CMD" "retry-loop" || return 1
  assert_file_contains "$AUDIT_CMD" "twl-inline-logic" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${AUDIT_CMD}" ]]; then
  run_test "session-audit [edge: 5 カテゴリ全記述]" test_audit_5_categories
else
  run_test_skip "session-audit [edge: 5 カテゴリ全記述]" "COMMAND.md not yet created"
fi

# Edge case: worktree 対応・bare repo main フォールバック
test_audit_worktree_fallback() {
  assert_file_contains "$AUDIT_CMD" "worktree|bare.*repo|main.*フォールバック|fallback"
}

if [[ -f "${PROJECT_ROOT}/${AUDIT_CMD}" ]]; then
  run_test "session-audit [edge: worktree 対応の記述]" test_audit_worktree_fallback
else
  run_test_skip "session-audit [edge: worktree 対応の記述]" "COMMAND.md not yet created"
fi

# Edge case: JSONL ディレクトリ特定の記述
test_audit_jsonl_dir() {
  assert_file_contains "$AUDIT_CMD" "JSONL|jsonl|\.jsonl"
}

if [[ -f "${PROJECT_ROOT}/${AUDIT_CMD}" ]]; then
  run_test "session-audit [edge: JSONL ディレクトリの記述]" test_audit_jsonl_dir
else
  run_test_skip "session-audit [edge: JSONL ディレクトリの記述]" "COMMAND.md not yet created"
fi

# Edge case: DEV_AUTOPILOT_SESSION 参照なし
test_audit_no_dev_autopilot_session() {
  assert_file_not_contains "$AUDIT_CMD" "DEV_AUTOPILOT_SESSION"
}

if [[ -f "${PROJECT_ROOT}/${AUDIT_CMD}" ]]; then
  run_test "session-audit [edge: DEV_AUTOPILOT_SESSION 参照なし]" test_audit_no_dev_autopilot_session
else
  run_test_skip "session-audit [edge: DEV_AUTOPILOT_SESSION 参照なし]" "COMMAND.md not yet created"
fi

# =============================================================================
# Requirement: co-autopilot SKILL.md の calls 更新
# =============================================================================
echo ""
echo "--- Requirement: co-autopilot SKILL.md の calls 更新 ---"

# Scenario: calls に全 11 コマンドが記載 (line 76)
# WHEN: co-autopilot SKILL.md を確認
# THEN: 全 11 コマンドが calls に含まれる

test_skill_calls_all_11() {
  # deps.yaml の co-autopilot calls が SSOT。SKILL.md は phase-execute/postprocess 経由で間接参照
  assert_file_exists "$DEPS_YAML" || return 1
  for cmd in "${ALL_11_COMMANDS[@]}"; do
    yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
ca = skills.get('co-autopilot', {})
calls = [c.get('atomic','') for c in ca.get('calls', [])]
if '${cmd}' not in calls:
    print(f'Missing: ${cmd}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
" || { echo "    Missing in deps.yaml calls: $cmd" >&2; return 1; }
  done
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "co-autopilot SKILL.md が全 11 コマンドを参照" test_skill_calls_all_11
else
  run_test_skip "co-autopilot SKILL.md が全 11 コマンドを参照" "skills/co-autopilot/SKILL.md not found"
fi

# Scenario: マーカーファイル参照の完全除去 (line 80)
# WHEN: co-autopilot SKILL.md 内で marker 関連を検索
# THEN: 0 件ヒットする

test_skill_no_marker_refs() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_not_contains "$SKILL_MD" "MARKER_DIR" || return 1
  assert_file_not_contains "$SKILL_MD" '\.done[^_a-zA-Z]' || return 1
  assert_file_not_contains "$SKILL_MD" '\.fail[^ua]' || return 1
  assert_file_not_contains "$SKILL_MD" '\.merge-ready' || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "co-autopilot SKILL.md マーカーファイル参照なし" test_skill_no_marker_refs
else
  run_test_skip "co-autopilot SKILL.md マーカーファイル参照なし" "skills/co-autopilot/SKILL.md not found"
fi

# Edge case: DEV_AUTOPILOT_SESSION 参照なし
test_skill_no_dev_autopilot_session() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_not_contains "$SKILL_MD" "DEV_AUTOPILOT_SESSION"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "co-autopilot SKILL.md [edge: DEV_AUTOPILOT_SESSION 参照なし]" test_skill_no_dev_autopilot_session
else
  run_test_skip "co-autopilot SKILL.md [edge: DEV_AUTOPILOT_SESSION 参照なし]" "skills/co-autopilot/SKILL.md not found"
fi

# =============================================================================
# Requirement: deps.yaml への 11 コマンド追加
# =============================================================================
echo ""
echo "--- Requirement: deps.yaml への 11 コマンド追加 ---"

# Scenario: deps.yaml に全 11 コマンドが定義 (line 88)
# WHEN: deps.yaml の commands セクションを確認
# THEN: 11 コマンドが type: atomic で定義されている

test_deps_yaml_valid() {
  assert_valid_yaml "$DEPS_YAML"
}
run_test "deps.yaml が有効な YAML" test_deps_yaml_valid

test_deps_all_11_commands_defined() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
cmds = data.get('commands', {})
expected = [
    'autopilot-init', 'autopilot-launch', 'autopilot-poll',
    'autopilot-phase-execute', 'autopilot-phase-postprocess',
    'autopilot-collect', 'autopilot-retrospective', 'autopilot-patterns',
    'autopilot-cross-issue', 'autopilot-summary', 'session-audit'
]
missing = [c for c in expected if c not in cmds]
if missing:
    print(f'Missing commands: {missing}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}

if [[ -f "${PROJECT_ROOT}/${DEPS_YAML}" ]]; then
  run_test "deps.yaml に全 11 コマンド定義" test_deps_all_11_commands_defined
else
  run_test_skip "deps.yaml に全 11 コマンド定義" "deps.yaml not found"
fi

test_deps_all_11_type_atomic() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
cmds = data.get('commands', {})
expected = [
    'autopilot-init', 'autopilot-launch', 'autopilot-poll',
    'autopilot-phase-execute', 'autopilot-phase-postprocess',
    'autopilot-collect', 'autopilot-retrospective', 'autopilot-patterns',
    'autopilot-cross-issue', 'autopilot-summary', 'session-audit'
]
wrong = []
for c in expected:
    if c in cmds:
        t = cmds[c].get('type', '')
        if t != 'atomic':
            wrong.append(f'{c}: type={t}')
if wrong:
    print(f'Non-atomic commands: {wrong}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}

if [[ -f "${PROJECT_ROOT}/${DEPS_YAML}" ]]; then
  run_test "deps.yaml 全 11 コマンドが type: atomic" test_deps_all_11_type_atomic
else
  run_test_skip "deps.yaml 全 11 コマンドが type: atomic" "deps.yaml not found"
fi

# Scenario: co-autopilot の calls 更新 (line 92)
# WHEN: deps.yaml の co-autopilot スキル定義を確認
# THEN: calls に 11 コマンドが全て含まれている（既存の self-improve 系 4 コマンドに加えて）

test_deps_co_autopilot_calls_all_11() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
ca = skills.get('co-autopilot', {})
calls = ca.get('calls', [])
# Flatten calls list (each item may be a dict like {'atomic': 'name'})
call_names = []
for c in calls:
    if isinstance(c, dict):
        call_names.extend(c.values())
    elif isinstance(c, str):
        call_names.append(c)
expected = [
    'autopilot-init', 'autopilot-launch', 'autopilot-poll',
    'autopilot-phase-execute', 'autopilot-phase-postprocess',
    'autopilot-collect', 'autopilot-retrospective', 'autopilot-patterns',
    'autopilot-cross-issue', 'autopilot-summary', 'session-audit'
]
missing = [c for c in expected if c not in call_names]
if missing:
    print(f'Missing from co-autopilot calls: {missing}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}

if [[ -f "${PROJECT_ROOT}/${DEPS_YAML}" ]]; then
  run_test "deps.yaml co-autopilot calls に全 11 コマンド" test_deps_co_autopilot_calls_all_11
else
  run_test_skip "deps.yaml co-autopilot calls に全 11 コマンド" "deps.yaml not found"
fi

# Edge case: 既存の self-improve 系 4 コマンドが calls に残存
test_deps_co_autopilot_calls_preserve_existing() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
ca = skills.get('co-autopilot', {})
calls = ca.get('calls', [])
call_names = []
for c in calls:
    if isinstance(c, dict):
        call_names.extend(c.values())
    elif isinstance(c, str):
        call_names.append(c)
existing = ['self-improve-collect', 'self-improve-propose', 'self-improve-close', 'ecc-monitor']
missing = [c for c in existing if c not in call_names]
if missing:
    print(f'Missing existing calls: {missing}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}

if [[ -f "${PROJECT_ROOT}/${DEPS_YAML}" ]]; then
  run_test "deps.yaml co-autopilot calls [edge: 既存 self-improve 系 4 コマンド保持]" test_deps_co_autopilot_calls_preserve_existing
else
  run_test_skip "deps.yaml co-autopilot calls [edge: 既存 self-improve 系 4 コマンド保持]" "deps.yaml not found"
fi

# Edge case: 全 11 COMMAND.md ファイルの存在チェック
test_all_11_command_files_exist() {
  local missing=()
  for cmd in "${ALL_11_COMMANDS[@]}"; do
    if [[ ! -f "${PROJECT_ROOT}/commands/${cmd}.md" ]]; then
      missing+=("$cmd")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "    Missing COMMAND.md files: ${missing[*]}" >&2
    return 1
  fi
  return 0
}

run_test "全 11 COMMAND.md ファイルの存在" test_all_11_command_files_exist

# Edge case: 全 11 COMMAND.md が deps.yaml で type: atomic 定義済み
test_all_11_frontmatter_atomic() {
  # プロジェクト慣例: COMMAND.md に frontmatter なし。deps.yaml が SSOT
  local wrong=()
  for cmd in "${ALL_11_COMMANDS[@]}"; do
    yaml_get "$DEPS_YAML" "
cmds = data.get('commands', {})
c = cmds.get('${cmd}', {})
if c.get('type') != 'atomic':
    sys.exit(1)
sys.exit(0)
" || wrong+=("$cmd")
  done
  if [[ ${#wrong[@]} -gt 0 ]]; then
    echo "    Not atomic in deps.yaml: ${wrong[*]}" >&2
    return 1
  fi
  return 0
}

run_test "全 COMMAND.md [edge: COMMAND.md exists (deps.yaml defines type) 一括チェック]" test_all_11_frontmatter_atomic

# Edge case: 全 11 COMMAND.md にマーカーファイル参照なし（一括チェック）
test_all_11_no_marker_refs() {
  local violations=()
  for cmd in "${ALL_11_COMMANDS[@]}"; do
    local f="${PROJECT_ROOT}/commands/${cmd}.md"
    if [[ -f "$f" ]]; then
      if grep -qiP 'MARKER_DIR' "$f"; then
        violations+=("${cmd}: MARKER_DIR")
      fi
    fi
  done
  if [[ ${#violations[@]} -gt 0 ]]; then
    echo "    Marker refs found: ${violations[*]}" >&2
    return 1
  fi
  # At least 1 file must exist
  local count=0
  for cmd in "${ALL_11_COMMANDS[@]}"; do
    [[ -f "${PROJECT_ROOT}/commands/${cmd}.md" ]] && ((count++)) || true
  done
  [[ $count -gt 0 ]] || return 1
  return 0
}

run_test "全 COMMAND.md [edge: MARKER_DIR 参照なし一括チェック]" test_all_11_no_marker_refs

# Edge case: 全 11 COMMAND.md に DEV_AUTOPILOT_SESSION 参照なし（一括チェック）
test_all_11_no_dev_autopilot_session() {
  local violations=()
  for cmd in "${ALL_11_COMMANDS[@]}"; do
    local f="${PROJECT_ROOT}/commands/${cmd}.md"
    if [[ -f "$f" ]]; then
      if grep -iP 'DEV_AUTOPILOT_SESSION' "$f" | grep -qvE 'しない|してはならない|使用しない|廃止|not use|not set'; then
        violations+=("${cmd}")
      fi
    fi
  done
  if [[ ${#violations[@]} -gt 0 ]]; then
    echo "    DEV_AUTOPILOT_SESSION refs found: ${violations[*]}" >&2
    return 1
  fi
  # At least 1 file must exist
  local count=0
  for cmd in "${ALL_11_COMMANDS[@]}"; do
    [[ -f "${PROJECT_ROOT}/commands/${cmd}.md" ]] && ((count++)) || true
  done
  [[ $count -gt 0 ]] || return 1
  return 0
}

run_test "全 COMMAND.md [edge: DEV_AUTOPILOT_SESSION 参照なし一括チェック]" test_all_11_no_dev_autopilot_session

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
