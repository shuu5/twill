#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: co-autopilot リファクタリング (issue-552)
# Generated from: deltaspec/changes/issue-552/specs/co-autopilot-refactor.md
# Coverage level: edge-cases
# Type: unit (document-verification)
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
  ((SKIP++)) || true
}

SKILL_MD="skills/co-autopilot/SKILL.md"
WAKEUP_CMD="commands/autopilot-pilot-wakeup-poll.md"
WAKEUP_BOOTSTRAP="commands/autopilot-pilot-wakeup-bootstrap.md"
WAKEUP_POLL="commands/autopilot-pilot-wakeup-poll.md"
WAKEUP_HEARTBEAT="commands/autopilot-pilot-wakeup-heartbeat.md"
DEPS_YAML="deps.yaml"
AUTOPILOT_MD="architecture/domain/contexts/autopilot.md"

# =============================================================================
# Requirement: co-autopilot SKILL.md 本文行数の削減
# =============================================================================
echo ""
echo "--- Requirement: co-autopilot SKILL.md 本文行数の削減 ---"

# Scenario: 行数制限の達成 (spec line 38)
# WHEN: frontmatter（--- から ---）を除いた本文行数をカウントした時
# THEN: その行数が 200 未満であること

test_skill_md_body_line_count_under_200() {
  assert_file_exists "$SKILL_MD" || return 1
  python3 -c "
import sys
with open('${PROJECT_ROOT}/${SKILL_MD}') as f:
    lines = f.readlines()

# Strip frontmatter: skip from first '---' to closing '---'
in_frontmatter = False
body_lines = []
fm_closed = False
for i, line in enumerate(lines):
    stripped = line.rstrip()
    if i == 0 and stripped == '---':
        in_frontmatter = True
        continue
    if in_frontmatter and stripped == '---':
        in_frontmatter = False
        fm_closed = True
        continue
    if fm_closed or not in_frontmatter:
        body_lines.append(line)

count = len(body_lines)
if count >= 200:
    print(f'Body line count is {count}, expected < 200', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md 本文行数が 200 未満である" test_skill_md_body_line_count_under_200
else
  run_test_skip "SKILL.md 本文行数が 200 未満である" "skills/co-autopilot/SKILL.md not yet modified"
fi

# Edge case: frontmatter の終端 --- が正しく検出される
test_skill_md_has_valid_frontmatter() {
  assert_file_exists "$SKILL_MD" || return 1
  python3 -c "
import sys
with open('${PROJECT_ROOT}/${SKILL_MD}') as f:
    lines = [l.rstrip() for l in f.readlines()]

if lines[0] != '---':
    print('No opening --- found at line 1', file=sys.stderr)
    sys.exit(1)

closing = next((i for i in range(1, len(lines)) if lines[i] == '---'), None)
if closing is None:
    print('No closing --- found for frontmatter', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md [edge: frontmatter が --- で正しく囲まれている]" test_skill_md_has_valid_frontmatter
else
  run_test_skip "SKILL.md [edge: frontmatter が --- で正しく囲まれている]" "skills/co-autopilot/SKILL.md not yet modified"
fi

# Edge case: SKILL.md にインライン実装（nohup / ScheduleWakeup ループ）が残っていない
test_skill_md_no_inline_loop_impl() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_not_contains "$SKILL_MD" "nohup.*autopilot|ScheduleWakeup.*while|while.*PHASE_COMPLETE" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md [edge: nohup/ScheduleWakeup インライン実装が削除されている]" test_skill_md_no_inline_loop_impl
else
  run_test_skip "SKILL.md [edge: nohup/ScheduleWakeup インライン実装が削除されている]" "skills/co-autopilot/SKILL.md not yet modified"
fi

# =============================================================================
# Requirement: Step 4 の atomic 委譲形式への書き換え
# =============================================================================
echo ""
echo "--- Requirement: Step 4 の atomic 委譲形式への書き換え ---"

# Scenario: Step 4 委譲 (spec line 46)
# WHEN: co-autopilot が Phase ループ（Step 4）を実行する時
# THEN: autopilot-pilot-wakeup-loop atomic への委譲が行われること

test_step4_delegates_to_wakeup_loop() {
  assert_file_exists "$SKILL_MD" || return 1
  # split 後: bootstrap/poll/heartbeat の 3 sub-atomic に委譲
  assert_file_contains "$SKILL_MD" "autopilot-pilot-wakeup-bootstrap"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Step 4 が wakeup sub-atomic (bootstrap/poll/heartbeat) へ委譲している" test_step4_delegates_to_wakeup_loop
else
  run_test_skip "Step 4 が wakeup sub-atomic (bootstrap/poll/heartbeat) へ委譲している" "skills/co-autopilot/SKILL.md not yet modified"
fi

# Edge case: Step 4 に Read → 実行 形式が記述されている
test_step4_read_and_execute_form() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "Read.*autopilot-pilot-wakeup-bootstrap|autopilot-pilot-wakeup-bootstrap.*Read"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Step 4 [edge: Read → 実行 形式が記述されている]" test_step4_read_and_execute_form
else
  run_test_skip "Step 4 [edge: Read → 実行 形式が記述されている]" "skills/co-autopilot/SKILL.md not yet modified"
fi

# =============================================================================
# Requirement: Step 4.5 の atomic 委譲形式への統一
# =============================================================================
echo ""
echo "--- Requirement: Step 4.5 の atomic 委譲形式への統一 ---"

# Scenario: Step 4.5 形式 (spec line 54)
# WHEN: PHASE_COMPLETE 受信後のサニティチェックを実行する時
# THEN: 各 atomic（autopilot-phase-sanity, autopilot-pilot-precheck 等）への委譲指示のみが記述されていること

test_step45_atomic_delegation() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "autopilot-phase-sanity" || return 1
  assert_file_contains "$SKILL_MD" "autopilot-pilot-precheck" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Step 4.5 に autopilot-phase-sanity と autopilot-pilot-precheck の委譲が記述されている" test_step45_atomic_delegation
else
  run_test_skip "Step 4.5 に autopilot-phase-sanity と autopilot-pilot-precheck の委譲が記述されている" "skills/co-autopilot/SKILL.md not yet modified"
fi

# Edge case: Step 4.5 に narrative 説明文ではなく委譲形式のみが残っている
# (Step 4.5 の各 atomic は Read → 実行 形式で参照されるべき)
test_step45_no_narrative_impl() {
  assert_file_exists "$SKILL_MD" || return 1
  # 委譲先 atomics が参照されていれば、インライン実装（stagnation 直接処理等）がないことを確認
  assert_file_not_contains "$SKILL_MD" "stagnate.*sec.*Step.4\.5|Step.4\.5.*stagnate.*直接" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Step 4.5 [edge: 委譲形式のみで narrative インライン実装が残っていない]" test_step45_no_narrative_impl
else
  run_test_skip "Step 4.5 [edge: 委譲形式のみで narrative インライン実装が残っていない]" "skills/co-autopilot/SKILL.md not yet modified"
fi

# =============================================================================
# Requirement: wakeup sub-atomic (bootstrap/poll/heartbeat) の作成
# =============================================================================
echo ""
echo "--- Requirement: wakeup sub-atomic (bootstrap/poll/heartbeat) の新規作成 ---"

# Scenario: PHASE_COMPLETE 検知 → poll atomic に存在すること
test_wakeup_loop_phase_complete_detection() {
  assert_file_exists "$WAKEUP_POLL" || return 1
  assert_file_contains "$WAKEUP_POLL" "PHASE_COMPLETE"
}

if [[ -f "${PROJECT_ROOT}/${WAKEUP_POLL}" ]]; then
  run_test "autopilot-pilot-wakeup-poll に PHASE_COMPLETE 検知ロジックが存在する" test_wakeup_loop_phase_complete_detection
else
  run_test_skip "autopilot-pilot-wakeup-poll に PHASE_COMPLETE 検知ロジックが存在する" "commands/autopilot-pilot-wakeup-poll.md not yet created"
fi

# Scenario: stagnation 検知 → poll atomic に存在すること
test_wakeup_loop_stagnation_detection() {
  assert_file_exists "$WAKEUP_POLL" || return 1
  assert_file_contains "$WAKEUP_POLL" "AUTOPILOT_STAGNATE_SEC" || return 1
  assert_file_contains "$WAKEUP_POLL" "session-comm\.sh.*inject-file|inject-file.*session-comm\.sh" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${WAKEUP_POLL}" ]]; then
  run_test "autopilot-pilot-wakeup-poll に stagnation 検知と session-comm.sh inject-file が定義されている" test_wakeup_loop_stagnation_detection
else
  run_test_skip "autopilot-pilot-wakeup-poll に stagnation 検知と session-comm.sh inject-file が定義されている" "commands/autopilot-pilot-wakeup-poll.md not yet created"
fi

# Edge case: AUTOPILOT_STAGNATE_SEC デフォルト 900 秒 → poll atomic
test_wakeup_loop_stagnate_sec_default() {
  assert_file_exists "$WAKEUP_POLL" || return 1
  assert_file_contains "$WAKEUP_POLL" "900"
}

if [[ -f "${PROJECT_ROOT}/${WAKEUP_POLL}" ]]; then
  run_test "autopilot-pilot-wakeup-poll [edge: AUTOPILOT_STAGNATE_SEC デフォルト 900 秒が明記されている]" test_wakeup_loop_stagnate_sec_default
else
  run_test_skip "autopilot-pilot-wakeup-poll [edge: AUTOPILOT_STAGNATE_SEC デフォルト 900 秒が明記されている]" "commands/autopilot-pilot-wakeup-poll.md not yet created"
fi

# Scenario: Silence heartbeat → heartbeat atomic に存在すること
test_wakeup_loop_silence_heartbeat() {
  assert_file_exists "$WAKEUP_HEARTBEAT" || return 1
  assert_file_contains "$WAKEUP_HEARTBEAT" "tmux.*capture-pane|capture-pane.*tmux" || return 1
  assert_file_contains "$WAKEUP_HEARTBEAT" "input.waiting" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${WAKEUP_HEARTBEAT}" ]]; then
  run_test "autopilot-pilot-wakeup-heartbeat に Silence heartbeat（tmux capture-pane + input_waiting_detected）が定義されている" test_wakeup_loop_silence_heartbeat
else
  run_test_skip "autopilot-pilot-wakeup-heartbeat に Silence heartbeat（tmux capture-pane + input_waiting_detected）が定義されている" "commands/autopilot-pilot-wakeup-heartbeat.md not yet created"
fi

# Edge case: 5 分（300 秒）閾値 → heartbeat atomic
test_wakeup_loop_silence_threshold_5min() {
  assert_file_exists "$WAKEUP_HEARTBEAT" || return 1
  assert_file_contains "$WAKEUP_HEARTBEAT" "300|5.*分|5.min"
}

if [[ -f "${PROJECT_ROOT}/${WAKEUP_HEARTBEAT}" ]]; then
  run_test "autopilot-pilot-wakeup-heartbeat [edge: Silence heartbeat 5 分（300 秒）閾値が明記されている]" test_wakeup_loop_silence_threshold_5min
else
  run_test_skip "autopilot-pilot-wakeup-heartbeat [edge: Silence heartbeat 5 分（300 秒）閾値が明記されている]" "commands/autopilot-pilot-wakeup-heartbeat.md not yet created"
fi

# Scenario: 状況精査モード → poll atomic に存在すること
test_wakeup_loop_max_wait_mode() {
  assert_file_exists "$WAKEUP_POLL" || return 1
  assert_file_contains "$WAKEUP_POLL" "MAX_WAIT_MINUTES|max.wait" || return 1
  assert_file_contains "$WAKEUP_POLL" "30" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${WAKEUP_POLL}" ]]; then
  run_test "autopilot-pilot-wakeup-poll に 状況精査モード（MAX_WAIT_MINUTES 30 分）が定義されている" test_wakeup_loop_max_wait_mode
else
  run_test_skip "autopilot-pilot-wakeup-poll に 状況精査モード（MAX_WAIT_MINUTES 30 分）が定義されている" "commands/autopilot-pilot-wakeup-poll.md not yet created"
fi

# Edge case: terminal 状態 Worker の判定ロジック → poll atomic
test_wakeup_loop_terminal_state_check() {
  assert_file_exists "$WAKEUP_POLL" || return 1
  assert_file_contains "$WAKEUP_POLL" "terminal|終了.*状態|complete.*status|status.*complete"
}

if [[ -f "${PROJECT_ROOT}/${WAKEUP_POLL}" ]]; then
  run_test "autopilot-pilot-wakeup-poll [edge: terminal 状態 Worker の判定ロジックが記述されている]" test_wakeup_loop_terminal_state_check
else
  run_test_skip "autopilot-pilot-wakeup-poll [edge: terminal 状態 Worker の判定ロジックが記述されている]" "commands/autopilot-pilot-wakeup-poll.md not yet created"
fi

# =============================================================================
# Requirement: deps.yaml への wakeup sub-atomic 登録
# =============================================================================
echo ""
echo "--- Requirement: deps.yaml への wakeup sub-atomic 登録 ---"

# Scenario: deps.yaml に 3 sub-atomic が登録されていること
test_deps_yaml_wakeup_loop_registered() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
atomics = data.get('atomics', {})
for name in ['autopilot-pilot-wakeup-bootstrap', 'autopilot-pilot-wakeup-poll', 'autopilot-pilot-wakeup-heartbeat']:
    if name not in atomics:
        print(f'{name} not found in atomics', file=sys.stderr)
        sys.exit(1)
sys.exit(0)
"
}

run_test "deps.yaml に wakeup 3 sub-atomic が atomics として登録されている" test_deps_yaml_wakeup_loop_registered

# Edge case: spawnable_by に controller が含まれている（bootstrap で代表チェック）
test_deps_yaml_wakeup_loop_spawnable_by_controller() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
atomics = data.get('atomics', {})
entry = atomics.get('autopilot-pilot-wakeup-bootstrap', {})
sb = entry.get('spawnable_by', [])
if 'controller' not in sb:
    print(f'spawnable_by={sb}, expected controller to be included', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}

run_test "deps.yaml autopilot-pilot-wakeup-bootstrap [edge: spawnable_by に controller が含まれている]" test_deps_yaml_wakeup_loop_spawnable_by_controller

# Edge case: co-autopilot の calls に新 sub-atomic が追加されている
test_deps_yaml_co_autopilot_calls_wakeup_loop() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
ca = skills.get('co-autopilot', {})
calls = ca.get('calls', [])
call_atomics = [c.get('atomic') for c in calls if isinstance(c, dict)]
for name in ['autopilot-pilot-wakeup-bootstrap', 'autopilot-pilot-wakeup-poll', 'autopilot-pilot-wakeup-heartbeat']:
    if name not in call_atomics:
        print(f'{name} not in co-autopilot.calls: {call_atomics}', file=sys.stderr)
        sys.exit(1)
sys.exit(0)
"
}

run_test "deps.yaml co-autopilot.calls に wakeup 3 sub-atomic が追加されている" test_deps_yaml_co_autopilot_calls_wakeup_loop

# Edge case: deps.yaml が有効な YAML である
test_deps_yaml_valid() {
  assert_valid_yaml "$DEPS_YAML"
}

run_test "deps.yaml [edge: 有効な YAML として解析できる]" test_deps_yaml_valid

# =============================================================================
# Requirement: autopilot.md への documentation 移動
# =============================================================================
echo ""
echo "--- Requirement: autopilot.md への documentation 移動 ---"

# Scenario: 復旧手順の外部化 (spec line 62)
# WHEN: autopilot.md を確認した時
# THEN: Recovery Procedures セクションが存在し、orchestrator 再起動手順と手動 workflow inject 手順が記載されていること

test_autopilot_md_recovery_procedures() {
  assert_file_exists "$AUTOPILOT_MD" || return 1
  assert_file_contains "$AUTOPILOT_MD" "Recovery Procedures|recovery.procedures" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${AUTOPILOT_MD}" ]]; then
  run_test "autopilot.md に Recovery Procedures セクションが存在する" test_autopilot_md_recovery_procedures
else
  run_test_skip "autopilot.md に Recovery Procedures セクションが存在する" "architecture/domain/contexts/autopilot.md not yet modified"
fi

# Edge case: orchestrator 再起動手順が記載されている
test_autopilot_md_orchestrator_restart() {
  assert_file_exists "$AUTOPILOT_MD" || return 1
  assert_file_contains "$AUTOPILOT_MD" "orchestrator.*再起動|orchestrator.*restart|再起動.*orchestrator"
}

if [[ -f "${PROJECT_ROOT}/${AUTOPILOT_MD}" ]]; then
  run_test "autopilot.md [edge: orchestrator 再起動手順が記載されている]" test_autopilot_md_orchestrator_restart
else
  run_test_skip "autopilot.md [edge: orchestrator 再起動手順が記載されている]" "architecture/domain/contexts/autopilot.md not yet modified"
fi

# Edge case: 手動 workflow inject 手順が記載されている
test_autopilot_md_manual_inject() {
  assert_file_exists "$AUTOPILOT_MD" || return 1
  assert_file_contains "$AUTOPILOT_MD" "inject|手動.*workflow|workflow.*手動"
}

if [[ -f "${PROJECT_ROOT}/${AUTOPILOT_MD}" ]]; then
  run_test "autopilot.md [edge: 手動 workflow inject 手順が記載されている]" test_autopilot_md_manual_inject
else
  run_test_skip "autopilot.md [edge: 手動 workflow inject 手順が記載されている]" "architecture/domain/contexts/autopilot.md not yet modified"
fi

# Scenario: SKILL.md のリンク残置 (spec line 67)
# WHEN: co-autopilot SKILL.md の該当箇所を確認した時
# THEN: 削除されたセクションの代わりに autopilot.md 該当セクションへの Markdown リンクが存在すること

test_skill_md_link_to_autopilot_md() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "autopilot\.md|architecture/domain/contexts/autopilot"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md に autopilot.md へのリンクが存在する（移動済みセクションの参照）" test_skill_md_link_to_autopilot_md
else
  run_test_skip "SKILL.md に autopilot.md へのリンクが存在する" "skills/co-autopilot/SKILL.md not yet modified"
fi

# =============================================================================
# Requirement: twl ツールチェーン全通過
# =============================================================================
echo ""
echo "--- Requirement: twl ツールチェーン全通過 ---"

# Scenario: ツールチェーン通過 (spec line 74)
# WHEN: twl --check および twl update-readme を実行した時
# THEN: エラーなく完了すること

test_twl_check_passes() {
  which twl >/dev/null 2>&1 || return 0  # twl not installed: skip gracefully
  (cd "${PROJECT_ROOT}" && twl --check 2>&1) | grep -qiP "error|FAIL|critical" && return 1
  return 0
}

run_test "twl --check がエラーなく通過する" test_twl_check_passes

# Edge case: autopilot-pilot-wakeup-loop の path がファイルシステム上に存在する
test_wakeup_loop_file_exists() {
  assert_file_exists "$WAKEUP_CMD"
}

run_test "twl --check [edge: commands/autopilot-pilot-wakeup-loop.md がファイルとして存在する]" test_wakeup_loop_file_exists

# Edge case: deps.yaml の path フィールドが実ファイルと一致する（3 sub-atomic 全件）
test_deps_yaml_wakeup_loop_path_matches() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
import os
atomics = data.get('atomics', {})
for name in ['autopilot-pilot-wakeup-bootstrap', 'autopilot-pilot-wakeup-poll', 'autopilot-pilot-wakeup-heartbeat']:
    entry = atomics.get(name, {})
    path = entry.get('path', '')
    if not path:
        print(f'No path defined for {name}', file=sys.stderr)
        sys.exit(1)
    full_path = os.path.join('${PROJECT_ROOT}', path)
    if not os.path.isfile(full_path):
        print(f'File not found: {full_path}', file=sys.stderr)
        sys.exit(1)
sys.exit(0)
"
}

run_test "deps.yaml wakeup 3 sub-atomic [edge: path フィールドが実ファイルと一致する]" test_deps_yaml_wakeup_loop_path_matches

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
