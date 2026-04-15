#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: su-observer Event Emission 統合 (#570)
# hook ベース検知（プライマリ）と Hybrid フォールバック（polling）の実装確認
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

SU_OBSERVER_SKILL="skills/su-observer/SKILL.md"
MONITOR_CATALOG="skills/su-observer/refs/monitor-channel-catalog.md"
DEPS_YAML="deps.yaml"

# =============================================================================
# Requirement: su-observer SKILL.md の Hybrid 検知ポリシー追加
# Scenario: heartbeat ファイル存在時に STAGNATE プライマリ検知が動作する (Issue #570)
# WHEN: .supervisor/events/heartbeat-* ファイルが存在し mtime が閾値を超過している
# THEN: su-observer は heartbeat mtime を STAGNATE の主要ソースとして使用しなければならない（SHALL）
# =============================================================================
echo ""
echo "--- Requirement: Hybrid 検知ポリシー（STAGNATE / heartbeat プライマリ） ---"

# Test: SKILL.md に Hybrid 検知ポリシーの記述がある
test_hybrid_detection_policy_exists() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "Hybrid.*検知|hybrid.*detection"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "SKILL.md に Hybrid 検知ポリシーの記述がある" test_hybrid_detection_policy_exists
else
  run_test_skip "Hybrid 検知ポリシー記述" "${SU_OBSERVER_SKILL} not found"
fi

# Test: SKILL.md に heartbeat mtime プライマリ検知の記述がある
test_heartbeat_primary_detection() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "heartbeat.*mtime|heartbeat.*プライマリ|heartbeat-\*"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "SKILL.md に heartbeat mtime プライマリ検知の記述がある" test_heartbeat_primary_detection
else
  run_test_skip "heartbeat プライマリ検知" "${SU_OBSERVER_SKILL} not found"
fi

# Test: SKILL.md に .supervisor/events/ ディレクトリへの参照がある
test_events_dir_referenced() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "\.supervisor/events"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "SKILL.md に .supervisor/events/ への参照がある" test_events_dir_referenced
else
  run_test_skip ".supervisor/events 参照" "${SU_OBSERVER_SKILL} not found"
fi

# Edge case: SKILL.md に AUTOPILOT_STAGNATE_SEC 閾値の参照がある
test_stagnate_threshold_referenced() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "AUTOPILOT_STAGNATE_SEC"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "[edge] AUTOPILOT_STAGNATE_SEC 閾値が参照されている" test_stagnate_threshold_referenced
else
  run_test_skip "[edge] AUTOPILOT_STAGNATE_SEC 閾値参照" "${SU_OBSERVER_SKILL} not found"
fi

# =============================================================================
# Requirement: INPUT-WAIT hook プライマリ検知
# Scenario: input-wait ファイル存在時に即時 INPUT-WAIT 検知が動作する (Issue #570)
# WHEN: .supervisor/events/input-wait-* ファイルが存在する
# THEN: su-observer はファイル存在を即時 INPUT-WAIT として報告しなければならない（SHALL）
# =============================================================================
echo ""
echo "--- Requirement: INPUT-WAIT hook プライマリ検知 ---"

# Test: SKILL.md に input-wait ファイル存在検知の記述がある
test_input_wait_hook_detection() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "input-wait.*プライマリ|input-wait-\*.*存在|INPUT-WAIT.*input-wait"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "SKILL.md に input-wait hook プライマリ検知の記述がある" test_input_wait_hook_detection
else
  run_test_skip "input-wait hook プライマリ検知" "${SU_OBSERVER_SKILL} not found"
fi

# Test: SKILL.md に INPUT-WAIT フォールバック（session-state.sh）の記述がある
test_input_wait_fallback() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "session-state\.sh.*フォールバック|フォールバック.*session-state\.sh|input-wait.*不在.*フォールバック|不在.*session-state"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "SKILL.md に INPUT-WAIT フォールバック記述がある" test_input_wait_fallback
else
  run_test_skip "INPUT-WAIT フォールバック" "${SU_OBSERVER_SKILL} not found"
fi

# =============================================================================
# Requirement: NON-TERMINAL hook プライマリ検知
# Scenario: skill-step ファイル存在時に構造化検知が動作する (Issue #570)
# WHEN: .supervisor/events/skill-step-* ファイルが存在する
# THEN: su-observer はファイル内容を解析して NON-TERMINAL を検知しなければならない（SHALL）
# =============================================================================
echo ""
echo "--- Requirement: NON-TERMINAL hook プライマリ検知 ---"

# Test: SKILL.md に skill-step 内容解析の記述がある
test_skill_step_hook_detection() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "skill-step.*内容解析|skill-step.*プライマリ|skill-step-\*"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "SKILL.md に skill-step 内容解析の記述がある" test_skill_step_hook_detection
else
  run_test_skip "skill-step 内容解析" "${SU_OBSERVER_SKILL} not found"
fi

# Test: SKILL.md に NON-TERMINAL フォールバック（session-comm.sh capture）の記述がある
test_non_terminal_fallback() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "session-comm\.sh.*capture|skill-step.*不在.*フォールバック|capture.*フォールバック"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "SKILL.md に NON-TERMINAL フォールバック記述がある" test_non_terminal_fallback
else
  run_test_skip "NON-TERMINAL フォールバック" "${SU_OBSERVER_SKILL} not found"
fi

# =============================================================================
# Requirement: WORKERS session-end 補完
# Scenario: session-end ファイルが読み出し後に削除される (Issue #570)
# WHEN: .supervisor/events/session-end-* ファイルが存在する
# THEN: su-observer はファイルを読み出し後に個別削除しなければならない（SHALL）
# =============================================================================
echo ""
echo "--- Requirement: WORKERS session-end 補完と個別削除 ---"

# Test: SKILL.md に session-end 補完の記述がある
test_session_end_supplement() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "session-end.*補完|session-end-\*"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "SKILL.md に session-end 補完の記述がある" test_session_end_supplement
else
  run_test_skip "session-end 補完" "${SU_OBSERVER_SKILL} not found"
fi

# Test: SKILL.md に session-end 読み出し後削除の記述がある（SHALL）
test_session_end_delete_after_read() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "session-end.*読み出し後.*削除|読み出し後.*個別削除|SHALL.*session-end|session-end.*SHALL"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "SKILL.md に session-end 読み出し後削除（SHALL）の記述がある" test_session_end_delete_after_read
else
  run_test_skip "session-end 読み出し後削除" "${SU_OBSERVER_SKILL} not found"
fi

# =============================================================================
# Requirement: Wave 完了時のイベントファイル一括クリーンアップ
# Scenario: externalize-state 実行後に .supervisor/events/ 配下の全ファイルを削除する (Issue #570)
# WHEN: Wave 完了を検知して externalize-state を実行した後
# THEN: su-observer は .supervisor/events/ 配下の全ファイルを一括削除しなければならない（SHALL）
# =============================================================================
echo ""
echo "--- Requirement: Wave 完了時イベントファイル一括クリーンアップ ---"

# Test: SKILL.md に Wave 完了時のイベントファイル一括クリーンアップの記述がある
test_wave_complete_cleanup() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "イベントファイル.*クリーンアップ|events.*クリーンアップ|クリーンアップ.*events"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "SKILL.md に Wave 完了時クリーンアップの記述がある" test_wave_complete_cleanup
else
  run_test_skip "Wave 完了時クリーンアップ" "${SU_OBSERVER_SKILL} not found"
fi

# Test: SKILL.md に externalize-state 後のクリーンアップが記述されている
test_cleanup_after_externalize_state() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "externalize-state.*クリーンアップ|クリーンアップ.*MUST|一括クリーンアップ.*MUST"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "SKILL.md に externalize-state 後クリーンアップ（MUST）の記述がある" test_cleanup_after_externalize_state
else
  run_test_skip "externalize-state 後クリーンアップ" "${SU_OBSERVER_SKILL} not found"
fi

# Edge case: rm -f .supervisor/events/* コマンドが記述されている
test_cleanup_command_exists() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "rm.*-f.*\.supervisor/events"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "[edge] rm -f .supervisor/events/* コマンドが記述されている" test_cleanup_command_exists
else
  run_test_skip "[edge] クリーンアップコマンド存在" "${SU_OBSERVER_SKILL} not found"
fi

# =============================================================================
# Requirement: PILOT-IDLE と PHASE-DONE は既存 polling のまま変更なし
# Scenario: PILOT-IDLE と PHASE-DONE はイベントファイル対象外 (Issue #570)
# WHEN: PILOT-IDLE または PHASE-DONE を検知する場合
# THEN: su-observer は既存の polling ロジックを変更してはならない（SHALL NOT）
# =============================================================================
echo ""
echo "--- Requirement: PILOT-IDLE / PHASE-DONE 既存 polling 維持 ---"

# Test: SKILL.md に PILOT-IDLE がイベントファイル対象外であることが記述されている
test_pilot_idle_no_hook() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "PILOT-IDLE.*対象外|PILOT-IDLE.*既存.*polling|PILOT-IDLE.*変更.*なし"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "SKILL.md に PILOT-IDLE が対象外であることが記述されている" test_pilot_idle_no_hook
else
  run_test_skip "PILOT-IDLE 対象外" "${SU_OBSERVER_SKILL} not found"
fi

# Test: SKILL.md に PHASE-DONE がイベントファイル対象外であることが記述されている
test_phase_done_no_hook() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "PHASE-DONE.*対象外|PHASE-DONE.*既存.*polling|PHASE-DONE.*変更.*なし"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "SKILL.md に PHASE-DONE が対象外であることが記述されている" test_phase_done_no_hook
else
  run_test_skip "PHASE-DONE 対象外" "${SU_OBSERVER_SKILL} not found"
fi

# =============================================================================
# Requirement: monitor-channel-catalog.md hook ベース検知セクション追加
# Scenario: 各チャンネルに hook ベース検知セクションが追加されている (Issue #570)
# WHEN: monitor-channel-catalog.md を参照する
# THEN: STAGNATE / INPUT-WAIT / NON-TERMINAL / WORKERS チャンネルに hook ベース検知セクションが追加されている（SHALL）
# =============================================================================
echo ""
echo "--- Requirement: monitor-channel-catalog.md hook ベース検知セクション ---"

# Test: monitor-channel-catalog.md に hook ベース検知セクションがある
test_catalog_hook_section_exists() {
  assert_file_exists "$MONITOR_CATALOG" || return 1
  assert_file_contains "$MONITOR_CATALOG" "hook.*ベース.*検知|hook.*プライマリ"
}

if [[ -f "${PROJECT_ROOT}/${MONITOR_CATALOG}" ]]; then
  run_test "monitor-channel-catalog.md に hook ベース検知セクションがある" test_catalog_hook_section_exists
else
  run_test_skip "hook ベース検知セクション" "${MONITOR_CATALOG} not found"
fi

# Test: STAGNATE セクションに heartbeat hook 検知が追加されている
test_stagnate_heartbeat_hook() {
  assert_file_exists "$MONITOR_CATALOG" || return 1
  assert_file_contains "$MONITOR_CATALOG" "heartbeat.*プライマリ|heartbeat-\*.*mtime"
}

if [[ -f "${PROJECT_ROOT}/${MONITOR_CATALOG}" ]]; then
  run_test "STAGNATE セクションに heartbeat hook 検知が追加されている" test_stagnate_heartbeat_hook
else
  run_test_skip "STAGNATE heartbeat hook" "${MONITOR_CATALOG} not found"
fi

# Test: INPUT-WAIT セクションに input-wait hook 検知が追加されている
test_input_wait_hook_in_catalog() {
  assert_file_exists "$MONITOR_CATALOG" || return 1
  assert_file_contains "$MONITOR_CATALOG" "input-wait.*プライマリ|IW_FOUND"
}

if [[ -f "${PROJECT_ROOT}/${MONITOR_CATALOG}" ]]; then
  run_test "INPUT-WAIT セクションに hook 検知が追加されている" test_input_wait_hook_in_catalog
else
  run_test_skip "INPUT-WAIT hook カタログ" "${MONITOR_CATALOG} not found"
fi

# Test: NON-TERMINAL セクションに skill-step hook 検知が追加されている
test_non_terminal_skill_step_hook() {
  assert_file_exists "$MONITOR_CATALOG" || return 1
  assert_file_contains "$MONITOR_CATALOG" "skill-step.*プライマリ|SS_FOUND"
}

if [[ -f "${PROJECT_ROOT}/${MONITOR_CATALOG}" ]]; then
  run_test "NON-TERMINAL セクションに skill-step hook 検知が追加されている" test_non_terminal_skill_step_hook
else
  run_test_skip "NON-TERMINAL skill-step hook" "${MONITOR_CATALOG} not found"
fi

# Test: WORKERS セクションに session-end hook 補完が追加されている
test_workers_session_end_hook() {
  assert_file_exists "$MONITOR_CATALOG" || return 1
  assert_file_contains "$MONITOR_CATALOG" "session-end.*補完|SE_SESSION"
}

if [[ -f "${PROJECT_ROOT}/${MONITOR_CATALOG}" ]]; then
  run_test "WORKERS セクションに session-end hook 補完が追加されている" test_workers_session_end_hook
else
  run_test_skip "WORKERS session-end hook" "${MONITOR_CATALOG} not found"
fi

# Edge case: WORKERS の session-end 削除コマンドがカタログに記述されている
test_catalog_session_end_delete() {
  assert_file_exists "$MONITOR_CATALOG" || return 1
  assert_file_contains "$MONITOR_CATALOG" "rm.*-f.*session-end|個別削除.*SHALL"
}

if [[ -f "${PROJECT_ROOT}/${MONITOR_CATALOG}" ]]; then
  run_test "[edge] session-end 削除コマンドがカタログに記述されている" test_catalog_session_end_delete
else
  run_test_skip "[edge] session-end 削除コマンド" "${MONITOR_CATALOG} not found"
fi

# =============================================================================
# Requirement: Hybrid フォールバック（hook 不在時に polling へ切り替わる）
# Scenario: hook ファイルが不在の場合に既存 polling にフォールバックする (Issue #570)
# WHEN: .supervisor/events/ 配下にイベントファイルが存在しない
# THEN: su-observer は既存の polling ロジックにフォールバックしなければならない（SHALL）
# =============================================================================
echo ""
echo "--- Requirement: Hybrid フォールバック（polling）---"

# Test: monitor-channel-catalog.md に heartbeat 不在時の polling フォールバックが記述されている
test_stagnate_fallback_in_catalog() {
  assert_file_exists "$MONITOR_CATALOG" || return 1
  assert_file_contains "$MONITOR_CATALOG" "heartbeat.*不在.*フォールバック|HB_FOUND.*false"
}

if [[ -f "${PROJECT_ROOT}/${MONITOR_CATALOG}" ]]; then
  run_test "STAGNATE フォールバック（heartbeat 不在時）がカタログに記述されている" test_stagnate_fallback_in_catalog
else
  run_test_skip "STAGNATE フォールバック" "${MONITOR_CATALOG} not found"
fi

# Test: monitor-channel-catalog.md に input-wait 不在時の polling フォールバックが記述されている
test_input_wait_fallback_in_catalog() {
  assert_file_exists "$MONITOR_CATALOG" || return 1
  assert_file_contains "$MONITOR_CATALOG" "input-wait.*不在.*フォールバック|IW_FOUND.*false"
}

if [[ -f "${PROJECT_ROOT}/${MONITOR_CATALOG}" ]]; then
  run_test "INPUT-WAIT フォールバック（input-wait 不在時）がカタログに記述されている" test_input_wait_fallback_in_catalog
else
  run_test_skip "INPUT-WAIT フォールバック" "${MONITOR_CATALOG} not found"
fi

# Test: monitor-channel-catalog.md に skill-step 不在時の polling フォールバックが記述されている
test_non_terminal_fallback_in_catalog() {
  assert_file_exists "$MONITOR_CATALOG" || return 1
  assert_file_contains "$MONITOR_CATALOG" "skill-step.*不在.*フォールバック|SS_FOUND.*false"
}

if [[ -f "${PROJECT_ROOT}/${MONITOR_CATALOG}" ]]; then
  run_test "NON-TERMINAL フォールバック（skill-step 不在時）がカタログに記述されている" test_non_terminal_fallback_in_catalog
else
  run_test_skip "NON-TERMINAL フォールバック" "${MONITOR_CATALOG} not found"
fi

# =============================================================================
# Requirement: deps.yaml 更新
# Scenario: 変更されたコンポーネントの deps.yaml が更新されている (Issue #570)
# WHEN: deps.yaml を確認する
# THEN: su-observer と monitor-channel-catalog の description が更新されている（SHALL）
# =============================================================================
echo ""
echo "--- Requirement: deps.yaml 更新 ---"

# Test: deps.yaml が有効な YAML である
test_deps_yaml_valid() {
  assert_valid_yaml "$DEPS_YAML"
}

if [[ -f "${PROJECT_ROOT}/${DEPS_YAML}" ]]; then
  run_test "deps.yaml が有効な YAML である" test_deps_yaml_valid
else
  run_test_skip "deps.yaml 有効性" "${DEPS_YAML} not found"
fi

# Test: deps.yaml の su-observer エントリが存在する
test_deps_su_observer_exists() {
  assert_file_exists "$DEPS_YAML" || return 1
  assert_file_contains "$DEPS_YAML" "su-observer:"
}

if [[ -f "${PROJECT_ROOT}/${DEPS_YAML}" ]]; then
  run_test "deps.yaml に su-observer エントリが存在する" test_deps_su_observer_exists
else
  run_test_skip "deps.yaml su-observer エントリ" "${DEPS_YAML} not found"
fi

# Test: deps.yaml の monitor-channel-catalog エントリが存在する
test_deps_catalog_exists() {
  assert_file_exists "$DEPS_YAML" || return 1
  assert_file_contains "$DEPS_YAML" "monitor-channel-catalog:"
}

if [[ -f "${PROJECT_ROOT}/${DEPS_YAML}" ]]; then
  run_test "deps.yaml に monitor-channel-catalog エントリが存在する" test_deps_catalog_exists
else
  run_test_skip "deps.yaml monitor-channel-catalog エントリ" "${DEPS_YAML} not found"
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
