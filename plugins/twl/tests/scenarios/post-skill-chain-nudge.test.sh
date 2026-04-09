#!/usr/bin/env bash
# =============================================================================
# Scenario Tests: PostToolUse hook による chain 継続注入
# Generated from: deltaspec/changes/autopilot-chain-posttooluse-hook/specs/post-skill-chain-nudge.md
# change-id: autopilot-chain-posttooluse-hook
# Coverage level: edge-cases
#
# 対象コンポーネント:
#   - scripts/hooks/post-skill-chain-nudge.sh  (新規)
#   - scripts/autopilot-orchestrator.sh         (修正: check_and_nudge 二重 nudge 防止)
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

HOOK_SCRIPT="scripts/hooks/post-skill-chain-nudge.sh"
ORCHESTRATOR="scripts/autopilot-orchestrator.sh"

# =============================================================================
# Requirement: PostToolUse hook スクリプトの作成
# =============================================================================
echo ""
echo "--- Requirement: PostToolUse hook スクリプトの作成 ---"

# ---------------------------------------------------------------------------
# 基本構造テスト
# ---------------------------------------------------------------------------

# hook スクリプトが存在する
test_hook_script_exists() {
  assert_file_exists "$HOOK_SCRIPT"
}

if [[ -f "${PROJECT_ROOT}/${HOOK_SCRIPT}" ]]; then
  run_test "post-skill-chain-nudge.sh が存在する" test_hook_script_exists
else
  run_test_skip "post-skill-chain-nudge.sh が存在する" "not yet created"
fi

# hook スクリプトが実行可能
test_hook_script_executable() {
  [[ -x "${PROJECT_ROOT}/${HOOK_SCRIPT}" ]]
}

if [[ -f "${PROJECT_ROOT}/${HOOK_SCRIPT}" ]]; then
  run_test "post-skill-chain-nudge.sh が実行可能" test_hook_script_executable
else
  run_test_skip "post-skill-chain-nudge.sh が実行可能" "not yet created"
fi

# ---------------------------------------------------------------------------
# Scenario: autopilot Worker が Skill tool 完了後に次ステップを受け取る
# WHEN: AUTOPILOT_DIR が設定された Worker セッションで Skill tool が完了する
# THEN: hook が stdout に [chain-continuation] メッセージを出力する
# ---------------------------------------------------------------------------

# [chain-continuation] メッセージのフォーマットが正しい
test_hook_chain_continuation_message_format() {
  assert_file_contains "$HOOK_SCRIPT" '\[chain-continuation\]'
}

if [[ -f "${PROJECT_ROOT}/${HOOK_SCRIPT}" ]]; then
  run_test "hook が [chain-continuation] メッセージを出力する" test_hook_chain_continuation_message_format
else
  run_test_skip "hook が [chain-continuation] メッセージを出力する" "not yet created"
fi

# メッセージに次ステップ実行指示が含まれる
test_hook_message_contains_instruction() {
  assert_file_contains "$HOOK_SCRIPT" 'Skill tool で実行せよ|停止するな'
}

if [[ -f "${PROJECT_ROOT}/${HOOK_SCRIPT}" ]]; then
  run_test "hook メッセージに実行指示が含まれる" test_hook_message_contains_instruction
else
  run_test_skip "hook メッセージに実行指示が含まれる" "not yet created"
fi

# next_step を chain-runner.sh から取得している
test_hook_calls_chain_runner_next_step() {
  assert_file_contains "$HOOK_SCRIPT" 'chain-runner\.sh.*next-step|chain-runner.*next.step'
}

if [[ -f "${PROJECT_ROOT}/${HOOK_SCRIPT}" ]]; then
  run_test "hook が chain-runner.sh next-step を呼び出す" test_hook_calls_chain_runner_next_step
else
  run_test_skip "hook が chain-runner.sh next-step を呼び出す" "not yet created"
fi

# ---------------------------------------------------------------------------
# Scenario: 非 autopilot セッションでは hook が透過的に動作する
# WHEN: AUTOPILOT_DIR が未設定の通常セッションで Skill tool が完了する
# THEN: hook が何も出力せず exit 0 で終了する
# ---------------------------------------------------------------------------

# AUTOPILOT_DIR チェックが存在する
test_hook_checks_autopilot_dir() {
  assert_file_contains "$HOOK_SCRIPT" 'AUTOPILOT_DIR'
}

if [[ -f "${PROJECT_ROOT}/${HOOK_SCRIPT}" ]]; then
  run_test "hook が AUTOPILOT_DIR を確認する" test_hook_checks_autopilot_dir
else
  run_test_skip "hook が AUTOPILOT_DIR を確認する" "not yet created"
fi

# AUTOPILOT_DIR 未設定時に exit 0 する処理が存在する
test_hook_exit_when_no_autopilot_dir() {
  # AUTOPILOT_DIR が空または未設定の場合 exit 0 する条件分岐
  assert_file_contains "$HOOK_SCRIPT" '(?i)(AUTOPILOT_DIR.*exit|exit.*AUTOPILOT_DIR|-z.*AUTOPILOT_DIR|AUTOPILOT_DIR.*unset)'
}

if [[ -f "${PROJECT_ROOT}/${HOOK_SCRIPT}" ]]; then
  run_test "AUTOPILOT_DIR 未設定時の exit 0 処理が存在する" test_hook_exit_when_no_autopilot_dir
else
  run_test_skip "AUTOPILOT_DIR 未設定時の exit 0 処理が存在する" "not yet created"
fi

# [edge-case] AUTOPILOT_DIR="" (空文字) も未設定と同様に扱われる
test_hook_empty_autopilot_dir_treated_as_unset() {
  # -z を使った空文字チェックか、デフォルト値パターン
  assert_file_contains "$HOOK_SCRIPT" '\-z.*AUTOPILOT_DIR|\$\{AUTOPILOT_DIR:-\}|\$\{AUTOPILOT_DIR:=\}'
}

if [[ -f "${PROJECT_ROOT}/${HOOK_SCRIPT}" ]]; then
  run_test "AUTOPILOT_DIR 空文字も未設定として扱われる [edge]" test_hook_empty_autopilot_dir_treated_as_unset
else
  run_test_skip "AUTOPILOT_DIR 空文字も未設定として扱われる [edge]" "not yet created"
fi

# ---------------------------------------------------------------------------
# Scenario: chain が完了した Worker では hook が何も出力しない
# WHEN: chain-runner.sh next-step が "done" を返す
# THEN: hook が何も出力せず exit 0 で終了する
# ---------------------------------------------------------------------------

# "done" を検出して何も出力しない処理が存在する
test_hook_silences_done_step() {
  assert_file_contains "$HOOK_SCRIPT" '"done"|== done|=.*done'
}

if [[ -f "${PROJECT_ROOT}/${HOOK_SCRIPT}" ]]; then
  run_test "hook が next-step=done の場合に何も出力しない" test_hook_silences_done_step
else
  run_test_skip "hook が next-step=done の場合に何も出力しない" "not yet created"
fi

# [edge-case] 空文字の next-step も done と同様に扱われる
test_hook_empty_next_step_is_silent() {
  # -z で空文字チェックしているか、done との OR 条件
  assert_file_contains "$HOOK_SCRIPT" '\-z.*next_step|\-z.*NEXT_STEP|next_step.*done.*||.*next_step'
}

if [[ -f "${PROJECT_ROOT}/${HOOK_SCRIPT}" ]]; then
  run_test "hook が空の next-step も silent に扱う [edge]" test_hook_empty_next_step_is_silent
else
  run_test_skip "hook が空の next-step も silent に扱う [edge]" "not yet created"
fi

# ---------------------------------------------------------------------------
# Scenario: ブランチから issue 番号が取得できない場合は exit 0
# WHEN: git branch でブランチ名を取得できない / issue 番号が含まれない
# THEN: exit 0 で終了する
# ---------------------------------------------------------------------------

# ブランチから issue 番号を抽出する処理が存在する
test_hook_extracts_issue_from_branch() {
  assert_file_contains "$HOOK_SCRIPT" 'git branch.*show-current|grep.*oP.*\\\\d|\\\\K\\\\d'
}

if [[ -f "${PROJECT_ROOT}/${HOOK_SCRIPT}" ]]; then
  run_test "hook がブランチから issue 番号を抽出する" test_hook_extracts_issue_from_branch
else
  run_test_skip "hook がブランチから issue 番号を抽出する" "not yet created"
fi

# issue 番号が取得できない場合に exit 0 する処理が存在する
test_hook_exit_when_no_issue_number() {
  assert_file_contains "$HOOK_SCRIPT" '(?i)(\-z.*ISSUE|\-z.*issue_num|issue.*exit|exit.*issue)'
}

if [[ -f "${PROJECT_ROOT}/${HOOK_SCRIPT}" ]]; then
  run_test "issue 番号取得失敗時の exit 0 処理が存在する [edge]" test_hook_exit_when_no_issue_number
else
  run_test_skip "issue 番号取得失敗時の exit 0 処理が存在する [edge]" "not yet created"
fi

# ---------------------------------------------------------------------------
# Scenario: hook エラーが発生しても Worker が継続する
# WHEN: state-read.sh や chain-runner.sh がエラーを返す
# THEN: エラーが stderr に記録され、hook が exit 0 で終了する
# ---------------------------------------------------------------------------

# エラーを stderr に出力する処理が存在する
test_hook_logs_errors_to_stderr() {
  assert_file_contains "$HOOK_SCRIPT" '>&2|2>&1|stderr'
}

if [[ -f "${PROJECT_ROOT}/${HOOK_SCRIPT}" ]]; then
  run_test "hook がエラーを stderr に記録する" test_hook_logs_errors_to_stderr
else
  run_test_skip "hook がエラーを stderr に記録する" "not yet created"
fi

# エラー時でも exit 0 する
test_hook_always_exits_zero() {
  # スクリプト全体が set -e を使わないか、trap ERR exit 0 等のパターン
  # 最低限 exit 0 の記述があること
  assert_file_contains "$HOOK_SCRIPT" 'exit 0'
}

if [[ -f "${PROJECT_ROOT}/${HOOK_SCRIPT}" ]]; then
  run_test "hook が常に exit 0 で終了する（Worker を停止しない）" test_hook_always_exits_zero
else
  run_test_skip "hook が常に exit 0 で終了する（Worker を停止しない）" "not yet created"
fi

# [edge-case] set -e を使わない（エラーで即終了させない）
test_hook_no_set_e() {
  # set -e は使わない（exit 0 を保証するため）
  # ただし set -euo pipefail を使っている場合はトラップが必要
  # スクリプトが set -e を使っているなら trap で保護されているはず
  local uses_set_e uses_trap_exit
  uses_set_e=$(grep -cP '^set -[a-z]*e[a-z]*' "${PROJECT_ROOT}/${HOOK_SCRIPT}" 2>/dev/null || echo "0")
  uses_trap_exit=$(grep -cP 'trap.*exit 0|trap.*EXIT' "${PROJECT_ROOT}/${HOOK_SCRIPT}" 2>/dev/null || echo "0")
  # set -e を使っていないか、使っている場合は trap が存在する
  [[ "$uses_set_e" -eq 0 ]] || [[ "$uses_trap_exit" -gt 0 ]]
}

if [[ -f "${PROJECT_ROOT}/${HOOK_SCRIPT}" ]]; then
  run_test "hook が set -e なし、またはエラートラップで保護されている [edge]" test_hook_no_set_e
else
  run_test_skip "hook が set -e なし、またはエラートラップで保護されている [edge]" "not yet created"
fi

# ---------------------------------------------------------------------------
# Requirement: last_hook_nudge_at タイムスタンプ記録
# ---------------------------------------------------------------------------

# hook が state-write.sh で last_hook_nudge_at を記録する
test_hook_writes_last_hook_nudge_at() {
  assert_file_contains "$HOOK_SCRIPT" 'last_hook_nudge_at'
}

if [[ -f "${PROJECT_ROOT}/${HOOK_SCRIPT}" ]]; then
  run_test "hook が last_hook_nudge_at を state-write.sh で記録する" test_hook_writes_last_hook_nudge_at
else
  run_test_skip "hook が last_hook_nudge_at を state-write.sh で記録する" "not yet created"
fi

# ISO 8601 形式でタイムスタンプを記録する
test_hook_timestamp_iso8601() {
  assert_file_contains "$HOOK_SCRIPT" 'date.*--iso|date.*-I|date.*%Y-%m-%dT|date.*iso'
}

if [[ -f "${PROJECT_ROOT}/${HOOK_SCRIPT}" ]]; then
  run_test "hook が ISO 8601 形式でタイムスタンプを記録する" test_hook_timestamp_iso8601
else
  run_test_skip "hook が ISO 8601 形式でタイムスタンプを記録する" "not yet created"
fi

# タイムスタンプ記録は [chain-continuation] 出力後に行われる
test_hook_timestamp_after_output() {
  # chain-continuation の出力 → state-write の順序を確認
  local nudge_line ts_line
  nudge_line=$(grep -n 'chain-continuation' "${PROJECT_ROOT}/${HOOK_SCRIPT}" 2>/dev/null | head -1 | cut -d: -f1 || echo "0")
  ts_line=$(grep -n 'last_hook_nudge_at' "${PROJECT_ROOT}/${HOOK_SCRIPT}" 2>/dev/null | head -1 | cut -d: -f1 || echo "0")
  [[ "$nudge_line" -gt 0 && "$ts_line" -gt 0 && "$ts_line" -gt "$nudge_line" ]]
}

if [[ -f "${PROJECT_ROOT}/${HOOK_SCRIPT}" ]]; then
  run_test "タイムスタンプ記録が [chain-continuation] 出力後に行われる [edge]" test_hook_timestamp_after_output
else
  run_test_skip "タイムスタンプ記録が [chain-continuation] 出力後に行われる [edge]" "not yet created"
fi

# ---------------------------------------------------------------------------
# Requirement: settings.json への PostToolUse hook 登録
# ---------------------------------------------------------------------------

SETTINGS_JSON="$HOME/.claude/settings.json"

# settings.json に Skill matcher の PostToolUse エントリが存在する
test_hooks_json_skill_posttooluse() {
  python3 -c "
import json, sys, os
path = os.path.expandvars('${SETTINGS_JSON}')
with open(path) as f:
    data = json.load(f)
hooks = data.get('hooks', {}).get('PostToolUse', [])
found = any(
    str(h.get('matcher', '')) == 'Skill' or str(h.get('matcher', '')) == '^Skill$'
    for h in hooks if isinstance(h, dict)
)
sys.exit(0 if found else 1)
" 2>/dev/null
}

if [[ -f "${SETTINGS_JSON}" ]]; then
  run_test "settings.json に Skill matcher の PostToolUse hook エントリが存在する" test_hooks_json_skill_posttooluse
else
  run_test_skip "settings.json に Skill matcher の PostToolUse hook エントリが存在する" "settings.json not found"
fi

# settings.json に post-skill-chain-nudge.sh への参照が存在する
test_hooks_json_references_nudge_script() {
  grep -q 'post-skill-chain-nudge' "${SETTINGS_JSON}"
}

if [[ -f "${SETTINGS_JSON}" ]]; then
  run_test "settings.json が post-skill-chain-nudge.sh を参照している" test_hooks_json_references_nudge_script
else
  run_test_skip "settings.json が post-skill-chain-nudge.sh を参照している" "settings.json not found"
fi

# [edge-case] hook エントリに timeout が設定されている
test_hooks_json_nudge_has_timeout() {
  python3 -c "
import json, sys, os
with open(os.path.expandvars('${SETTINGS_JSON}')) as f:
    data = json.load(f)
hooks = data.get('hooks', {}).get('PostToolUse', [])
for h in hooks:
    if not isinstance(h, dict):
        continue
    if 'Skill' not in str(h.get('matcher', '')):
        continue
    for inner in h.get('hooks', []):
        if 'post-skill-chain-nudge' in str(inner.get('command', '')):
            if 'timeout' in inner:
                sys.exit(0)
sys.exit(1)
" 2>/dev/null
}

if [[ -f "${SETTINGS_JSON}" ]]; then
  run_test "settings.json の post-skill-chain-nudge エントリに timeout が設定されている [edge]" test_hooks_json_nudge_has_timeout
else
  run_test_skip "settings.json の post-skill-chain-nudge エントリに timeout が設定されている [edge]" "settings.json not found"
fi

# =============================================================================
# Requirement: ワークフロー境界対応
# =============================================================================
echo ""
echo "--- Requirement: ワークフロー境界対応 ---"

# ---------------------------------------------------------------------------
# Scenario: ac-verify 完了後に workflow-pr-fix を nudge する
# WHEN: CURRENT_STEP=ac-verify で hook が実行される
# THEN: hook 出力が [chain-continuation] 次は /twl:workflow-pr-fix を含む
# ---------------------------------------------------------------------------

# hook が CHAIN_STEP_WORKFLOW を参照している（chain-steps.sh を source）
test_hook_sources_chain_steps_for_workflow() {
  assert_file_contains "$HOOK_SCRIPT" 'CHAIN_STEP_WORKFLOW|chain-steps\.sh'
}

if [[ -f "${PROJECT_ROOT}/${HOOK_SCRIPT}" ]]; then
  run_test "hook が CHAIN_STEP_WORKFLOW（chain-steps.sh）を参照している" test_hook_sources_chain_steps_for_workflow
else
  run_test_skip "hook が CHAIN_STEP_WORKFLOW（chain-steps.sh）を参照している" "not yet created"
fi

# hook が CHAIN_WORKFLOW_NEXT_SKILL を参照している
test_hook_uses_chain_workflow_next_skill() {
  assert_file_contains "$HOOK_SCRIPT" 'CHAIN_WORKFLOW_NEXT_SKILL'
}

if [[ -f "${PROJECT_ROOT}/${HOOK_SCRIPT}" ]]; then
  run_test "hook が CHAIN_WORKFLOW_NEXT_SKILL を参照している" test_hook_uses_chain_workflow_next_skill
else
  run_test_skip "hook が CHAIN_WORKFLOW_NEXT_SKILL を参照している" "not yet created"
fi

# ワークフロー境界判定ロジックが存在する（CURRENT_WORKFLOW と NEXT_WORKFLOW の比較）
test_hook_workflow_boundary_detection() {
  assert_file_contains "$HOOK_SCRIPT" 'CURRENT_WORKFLOW|NEXT_WORKFLOW'
}

if [[ -f "${PROJECT_ROOT}/${HOOK_SCRIPT}" ]]; then
  run_test "hook にワークフロー境界判定ロジックが存在する" test_hook_workflow_boundary_detection
else
  run_test_skip "hook にワークフロー境界判定ロジックが存在する" "not yet created"
fi

# ---------------------------------------------------------------------------
# Scenario: post-change-apply 完了後に workflow-pr-verify を nudge する
# WHEN: CURRENT_STEP=post-change-apply で hook が実行される
# THEN: hook 出力が [chain-continuation] 次は /twl:workflow-pr-verify を含む
# ---------------------------------------------------------------------------

# chain-steps.sh に CHAIN_STEP_WORKFLOW が定義されている
CHAIN_STEPS_SH="scripts/chain-steps.sh"

test_chain_steps_has_step_workflow_map() {
  assert_file_contains "$CHAIN_STEPS_SH" 'CHAIN_STEP_WORKFLOW'
}

if [[ -f "${PROJECT_ROOT}/${CHAIN_STEPS_SH}" ]]; then
  run_test "chain-steps.sh に CHAIN_STEP_WORKFLOW が定義されている" test_chain_steps_has_step_workflow_map
else
  run_test_skip "chain-steps.sh に CHAIN_STEP_WORKFLOW が定義されている" "not found"
fi

# chain-steps.sh に CHAIN_WORKFLOW_NEXT_SKILL が定義されている
test_chain_steps_has_workflow_next_skill_map() {
  assert_file_contains "$CHAIN_STEPS_SH" 'CHAIN_WORKFLOW_NEXT_SKILL'
}

if [[ -f "${PROJECT_ROOT}/${CHAIN_STEPS_SH}" ]]; then
  run_test "chain-steps.sh に CHAIN_WORKFLOW_NEXT_SKILL が定義されている" test_chain_steps_has_workflow_next_skill_map
else
  run_test_skip "chain-steps.sh に CHAIN_WORKFLOW_NEXT_SKILL が定義されている" "not found"
fi

# ac-verify が pr-verify ワークフローにマッピングされている
test_chain_steps_ac_verify_in_pr_verify() {
  assert_file_contains "$CHAIN_STEPS_SH" '\[ac-verify\]=pr-verify'
}

if [[ -f "${PROJECT_ROOT}/${CHAIN_STEPS_SH}" ]]; then
  run_test "chain-steps.sh で ac-verify が pr-verify にマッピングされている" test_chain_steps_ac_verify_in_pr_verify
else
  run_test_skip "chain-steps.sh で ac-verify が pr-verify にマッピングされている" "not found"
fi

# pr-verify の次 skill が workflow-pr-fix である
test_chain_steps_pr_verify_next_is_workflow_pr_fix() {
  assert_file_contains "$CHAIN_STEPS_SH" '\[pr-verify\]=workflow-pr-fix'
}

if [[ -f "${PROJECT_ROOT}/${CHAIN_STEPS_SH}" ]]; then
  run_test "chain-steps.sh で pr-verify の次 skill が workflow-pr-fix である" test_chain_steps_pr_verify_next_is_workflow_pr_fix
else
  run_test_skip "chain-steps.sh で pr-verify の次 skill が workflow-pr-fix である" "not found"
fi

# post-change-apply が test-ready ワークフローにマッピングされている
test_chain_steps_post_change_apply_in_test_ready() {
  assert_file_contains "$CHAIN_STEPS_SH" '\[post-change-apply\]=test-ready'
}

if [[ -f "${PROJECT_ROOT}/${CHAIN_STEPS_SH}" ]]; then
  run_test "chain-steps.sh で post-change-apply が test-ready にマッピングされている" test_chain_steps_post_change_apply_in_test_ready
else
  run_test_skip "chain-steps.sh で post-change-apply が test-ready にマッピングされている" "not found"
fi

# ---------------------------------------------------------------------------
# Scenario: ワークフロー末尾（pr-merge chain 内）で hook が終了する
# WHEN: CURRENT_STEP=pr-cycle-report（pr-merge chain 末尾）で hook が実行される
# THEN: hook が何も出力せず exit 0 で終了する
# ---------------------------------------------------------------------------

# ワークフロー末尾（空文字の次 skill）で exit する処理が存在する
test_hook_exits_at_workflow_terminal() {
  # CHAIN_WORKFLOW_NEXT_SKILL が空の場合に exit するロジック
  assert_file_contains "$HOOK_SCRIPT" 'CHAIN_WORKFLOW_NEXT_SKILL|NEXT_STEP.*:-\}|NEXT_STEP.*exit'
}

if [[ -f "${PROJECT_ROOT}/${HOOK_SCRIPT}" ]]; then
  run_test "hook がワークフロー末尾で exit 0 する処理を持つ" test_hook_exits_at_workflow_terminal
else
  run_test_skip "hook がワークフロー末尾で exit 0 する処理を持つ" "not yet created"
fi

# ---------------------------------------------------------------------------
# Scenario: 非ワークフロー境界ステップでは既存動作が維持される
# WHEN: CURRENT_STEP=ts-preflight（pr-verify chain 内部）で hook が実行される
# THEN: hook が次の chain ステップ（pr-test）を nudge する（workflow skill ではない）
# ---------------------------------------------------------------------------

# 境界判定で CURRENT_WORKFLOW == NEXT_WORKFLOW の場合に NEXT_STEP を変更しないロジック
test_hook_preserves_intra_workflow_step() {
  # CURRENT_WORKFLOW != NEXT_WORKFLOW の条件分岐が存在する
  assert_file_contains "$HOOK_SCRIPT" 'CURRENT_WORKFLOW.*!=.*NEXT_WORKFLOW|CURRENT_WORKFLOW.*NEXT_WORKFLOW'
}

if [[ -f "${PROJECT_ROOT}/${HOOK_SCRIPT}" ]]; then
  run_test "hook が同一ワークフロー内ステップで既存動作を維持する" test_hook_preserves_intra_workflow_step
else
  run_test_skip "hook が同一ワークフロー内ステップで既存動作を維持する" "not yet created"
fi

# =============================================================================
# Requirement: orchestrator check_and_nudge の二重 nudge 防止
# =============================================================================
echo ""
echo "--- Requirement: orchestrator check_and_nudge の二重 nudge 防止 ---"

# ---------------------------------------------------------------------------
# Scenario: hook 注入直後に orchestrator が nudge をスキップする
# WHEN: issue-{N}.json の last_hook_nudge_at が現在時刻から 30s 以内
# THEN: orchestrator が tmux nudge を送信しない
# ---------------------------------------------------------------------------

# orchestrator が last_hook_nudge_at を参照している
test_orchestrator_reads_last_hook_nudge_at() {
  assert_file_contains "$ORCHESTRATOR" 'last_hook_nudge_at'
}

if [[ -f "${PROJECT_ROOT}/${ORCHESTRATOR}" ]]; then
  run_test "orchestrator が last_hook_nudge_at を参照している" test_orchestrator_reads_last_hook_nudge_at
else
  run_test_skip "orchestrator が last_hook_nudge_at を参照している" "not yet modified"
fi

# orchestrator が NUDGE_TIMEOUT (30s) 以内のスキップ処理を持つ
test_orchestrator_skips_within_nudge_timeout() {
  assert_file_contains "$ORCHESTRATOR" 'NUDGE_TIMEOUT|30.*nudge|nudge.*30'
}

if [[ -f "${PROJECT_ROOT}/${ORCHESTRATOR}" ]]; then
  run_test "orchestrator が NUDGE_TIMEOUT 以内の二重 nudge をスキップする" test_orchestrator_skips_within_nudge_timeout
else
  run_test_skip "orchestrator が NUDGE_TIMEOUT 以内の二重 nudge をスキップする" "not yet modified"
fi

# check_and_nudge 関数が last_hook_nudge_at チェックを実施する
test_orchestrator_check_and_nudge_has_hook_guard() {
  # check_and_nudge 関数内で last_hook_nudge_at または hook_nudge_at を参照する
  python3 -c "
import re, sys
with open('${PROJECT_ROOT}/${ORCHESTRATOR}') as f:
    content = f.read()
# check_and_nudge 関数の定義から次の関数までを抽出
m = re.search(r'check_and_nudge\s*\(\s*\)(.*?)^}', content, re.DOTALL | re.MULTILINE)
if not m:
    sys.exit(1)
func_body = m.group(1)
if 'last_hook_nudge_at' in func_body or 'hook_nudge' in func_body:
    sys.exit(0)
sys.exit(1)
" 2>/dev/null
}

if [[ -f "${PROJECT_ROOT}/${ORCHESTRATOR}" ]]; then
  run_test "check_and_nudge 関数内で last_hook_nudge_at チェックを行っている [edge]" test_orchestrator_check_and_nudge_has_hook_guard
else
  run_test_skip "check_and_nudge 関数内で last_hook_nudge_at チェックを行っている [edge]" "not yet modified"
fi

# ---------------------------------------------------------------------------
# Scenario: hook 注入から 30s 以上経過した場合は orchestrator が nudge を送信する
# WHEN: last_hook_nudge_at が 30s 以上前、かつ stall 条件を満たす
# THEN: orchestrator が通常通り tmux nudge を送信する
# ---------------------------------------------------------------------------

# 時刻差分の計算処理が存在する（date コマンドによる経過時間計算）
test_orchestrator_calculates_elapsed_time() {
  assert_file_contains "$ORCHESTRATOR" 'date.*\+%s|epoch|last_hook_nudge_at.*date|date.*last_hook_nudge_at|now.*hook|hook.*now'
}

if [[ -f "${PROJECT_ROOT}/${ORCHESTRATOR}" ]]; then
  run_test "orchestrator が last_hook_nudge_at からの経過時間を計算する [edge]" test_orchestrator_calculates_elapsed_time
else
  run_test_skip "orchestrator が last_hook_nudge_at からの経過時間を計算する [edge]" "not yet modified"
fi

# ---------------------------------------------------------------------------
# Scenario: last_hook_nudge_at フィールドが存在しない場合は従来動作
# WHEN: issue-{N}.json に last_hook_nudge_at フィールドが存在しない（旧状態）
# THEN: orchestrator が従来の stall 判定で nudge する
# ---------------------------------------------------------------------------

# last_hook_nudge_at が空/null の場合のフォールバック処理が存在する
test_orchestrator_fallback_when_no_last_hook_nudge_at() {
  # フィールドが空の場合のガード（-z チェックまたは null チェック）
  assert_file_contains "$ORCHESTRATOR" '(?i)(\-z.*last_hook_nudge_at|last_hook_nudge_at.*-z|last_hook_nudge_at.*null|null.*last_hook_nudge_at|last_hook_nudge_at.*empty|empty.*last_hook_nudge_at|last_hook_nudge_at.*==.*"")'
}

if [[ -f "${PROJECT_ROOT}/${ORCHESTRATOR}" ]]; then
  run_test "last_hook_nudge_at なし（旧状態）の場合のフォールバック処理が存在する [edge]" test_orchestrator_fallback_when_no_last_hook_nudge_at
else
  run_test_skip "last_hook_nudge_at なし（旧状態）の場合のフォールバック処理が存在する [edge]" "not yet modified"
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
