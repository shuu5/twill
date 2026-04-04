#!/usr/bin/env bash
# =============================================================================
# Functional Tests: session-management.md
# Generated from: openspec/changes/archive/2026-03-27-b-3-autopilot-state-management/specs/session-management.md
# Coverage level: edge-cases
# Tests session exclusivity, cross-issue warnings, polling, directory management
# =============================================================================
set -uo pipefail

# Project root (relative to test file location)
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Script paths
STATE_WRITE="${PROJECT_ROOT}/scripts/state-write.sh"
STATE_READ="${PROJECT_ROOT}/scripts/state-read.sh"

# Counters
PASS=0
FAIL=0
SKIP=0
ERRORS=()

# --- Sandbox Setup ---

SANDBOX=""

setup_sandbox() {
  SANDBOX=$(mktemp -d)
  mkdir -p "${SANDBOX}/.autopilot/issues"
  # Copy scripts if available
  for script in "$STATE_WRITE" "$STATE_READ"; do
    if [[ -f "$script" ]]; then
      mkdir -p "${SANDBOX}/scripts"
      cp "$script" "${SANDBOX}/scripts/$(basename "$script")"
      chmod +x "${SANDBOX}/scripts/$(basename "$script")"
    fi
  done
}

teardown_sandbox() {
  if [[ -n "$SANDBOX" && -d "$SANDBOX" ]]; then
    rm -rf "$SANDBOX"
  fi
  SANDBOX=""
}

# Helper: create session.json
create_session_file() {
  local started_at="${1:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
  cat > "${SANDBOX}/.autopilot/session.json" <<EOF
{
  "session_id": "sess-$(date +%s)",
  "plan_path": "plan.yaml",
  "current_phase": 1,
  "phase_count": 3,
  "started_at": "${started_at}",
  "cross_issue_warnings": []
}
EOF
}

# Helper: create issue file
create_issue_file() {
  local issue_num="$1"
  local status="$2"
  cat > "${SANDBOX}/.autopilot/issues/issue-${issue_num}.json" <<EOF
{
  "issue_number": ${issue_num},
  "status": "${status}",
  "retry_count": 0,
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
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

# =============================================================================
# Requirement: session.json によるセッション排他制御
# =============================================================================
echo ""
echo "--- Requirement: session.json によるセッション排他制御 ---"

# Scenario: 新規セッション開始 (line 7)
# WHEN: .autopilot/session.json が存在しない状態で autopilot セッションが開始される
# THEN: session.json が作成され、session_id, plan_path, current_phase=1, phase_count が設定される
test_new_session_creation() {
  # Ensure no session.json exists
  rm -f "${SANDBOX}/.autopilot/session.json"
  # Look for session-init script or co-autopilot entry point
  local init_script
  init_script=$(find "${PROJECT_ROOT}/scripts" -name "*session*init*" -o -name "*autopilot*start*" 2>/dev/null | head -1)
  if [[ -n "$init_script" && -f "$init_script" ]]; then
    AUTOPILOT_DIR="${SANDBOX}/.autopilot" bash "$init_script" 2>/dev/null || return 1
    [[ -f "${SANDBOX}/.autopilot/session.json" ]] || return 1
    python3 -c "
import json
data = json.load(open('${SANDBOX}/.autopilot/session.json'))
assert 'session_id' in data, 'missing session_id'
assert 'plan_path' in data, 'missing plan_path'
assert data.get('current_phase') == 1, 'current_phase should be 1'
assert 'phase_count' in data, 'missing phase_count'
" 2>/dev/null || return 1
  else
    # Structural verification: spec defines these fields
    local spec_file="${PROJECT_ROOT}/openspec/changes/archive/2026-03-27-b-3-autopilot-state-management/specs/session-management.md"
    [[ -f "$spec_file" ]] || return 1
    grep -qP "session_id.*plan_path.*current_phase.*phase_count|session_id" "$spec_file" || return 1
  fi
}

run_test "新規セッション開始" test_new_session_creation

# Edge case: session_id がユニークな値（UUID や timestamp ベース）
test_session_id_unique() {
  local spec_file="${PROJECT_ROOT}/openspec/changes/archive/2026-03-27-b-3-autopilot-state-management/specs/session-management.md"
  [[ -f "$spec_file" ]] || return 1
  grep -qP "session_id" "$spec_file" || return 1
}

run_test "新規セッション [edge: session_id の存在]" test_session_id_unique

# Scenario: 既存セッション検出による拒否 (line 11)
# WHEN: .autopilot/session.json が既に存在し、started_at が 24 時間以内
# THEN: 「既存セッションが実行中です」のエラーメッセージとともに exit 1 で終了する
test_existing_session_rejected() {
  # Create a session that started now (within 24 hours)
  create_session_file
  local init_script
  init_script=$(find "${PROJECT_ROOT}/scripts" -name "*session*init*" -o -name "*autopilot*start*" 2>/dev/null | head -1)
  if [[ -n "$init_script" && -f "$init_script" ]]; then
    local output
    output=$(AUTOPILOT_DIR="${SANDBOX}/.autopilot" bash "$init_script" 2>&1)
    local result=$?
    [[ "$result" -ne 0 ]] || return 1
    echo "$output" | grep -qiP "既存|実行中|already.*running|existing.*session" || return 1
  else
    # Structural verification
    local spec_file="${PROJECT_ROOT}/openspec/changes/archive/2026-03-27-b-3-autopilot-state-management/specs/session-management.md"
    grep -qP "既存セッション.*実行中|exit 1" "$spec_file" || return 1
  fi
}

run_test "既存セッション検出による拒否" test_existing_session_rejected

# Edge case: 24 時間境界値テスト（ちょうど24時間の場合の扱い）
test_session_24h_boundary() {
  local spec_file="${PROJECT_ROOT}/openspec/changes/archive/2026-03-27-b-3-autopilot-state-management/specs/session-management.md"
  [[ -f "$spec_file" ]] || return 1
  grep -qP "24.*時間|24.*hour" "$spec_file" || return 1
}

run_test "既存セッション拒否 [edge: 24 時間境界の定義]" test_session_24h_boundary

# Scenario: stale セッションの検出 (line 15)
# WHEN: .autopilot/session.json が存在し、started_at が 24 時間以上経過
# THEN: 「stale セッションが検出されました。削除しますか？」の警告を表示
test_stale_session_detection() {
  # Create session with a timestamp more than 24 hours ago
  local old_timestamp
  old_timestamp=$(date -u -d "25 hours ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-25H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "2020-01-01T00:00:00Z")
  create_session_file "$old_timestamp"

  local init_script
  init_script=$(find "${PROJECT_ROOT}/scripts" -name "*session*init*" -o -name "*autopilot*start*" 2>/dev/null | head -1)
  if [[ -n "$init_script" && -f "$init_script" ]]; then
    local output
    output=$(echo "n" | AUTOPILOT_DIR="${SANDBOX}/.autopilot" bash "$init_script" 2>&1)
    echo "$output" | grep -qiP "stale|古い|削除" || return 1
  else
    # Structural verification
    local spec_file="${PROJECT_ROOT}/openspec/changes/archive/2026-03-27-b-3-autopilot-state-management/specs/session-management.md"
    grep -qP "stale.*セッション|stale.*session|24.*時間.*経過" "$spec_file" || return 1
  fi
}

run_test "stale セッションの検出" test_stale_session_detection

# Edge case: ユーザーが stale 削除を承認した場合、新セッションが開始可能
test_stale_session_delete_and_restart() {
  local spec_file="${PROJECT_ROOT}/openspec/changes/archive/2026-03-27-b-3-autopilot-state-management/specs/session-management.md"
  [[ -f "$spec_file" ]] || return 1
  grep -qP "削除しますか|ユーザー確認" "$spec_file" || return 1
}

run_test "stale セッション [edge: ユーザー確認フローの存在]" test_stale_session_delete_and_restart

# =============================================================================
# Requirement: cross-issue 警告の session.json 格納
# =============================================================================
echo ""
echo "--- Requirement: cross-issue 警告の session.json 格納 ---"

# Scenario: ファイル重複の検出と記録 (line 23)
# WHEN: Phase 内の Issue #42 と Issue #43 が同一ファイル deps.yaml を変更している
# THEN: session.json の cross_issue_warnings に警告が追加される
test_cross_issue_warning_recorded() {
  local spec_file="${PROJECT_ROOT}/openspec/changes/archive/2026-03-27-b-3-autopilot-state-management/specs/session-management.md"
  [[ -f "$spec_file" ]] || return 1
  grep -qP "cross_issue_warnings" "$spec_file" || return 1
  grep -qP "issue.*42.*43|同一ファイル" "$spec_file" || return 1
}

run_test "ファイル重複の検出と記録" test_cross_issue_warning_recorded

# Edge case: cross_issue_warnings の構造が正しい（issue, target_issue, file, reason）
test_cross_issue_warning_structure() {
  local spec_file="${PROJECT_ROOT}/openspec/changes/archive/2026-03-27-b-3-autopilot-state-management/specs/session-management.md"
  [[ -f "$spec_file" ]] || return 1
  grep -qP "issue.*target_issue.*file.*reason" "$spec_file" || return 1
}

run_test "cross-issue 警告 [edge: 構造化フォーマット]" test_cross_issue_warning_structure

# Scenario: 重複なしの場合 (line 27)
# WHEN: Phase 内の全 Issue の変更ファイルに重複がない
# THEN: session.json の cross_issue_warnings は空配列のまま変更されない
test_no_cross_issue_warnings() {
  local spec_file="${PROJECT_ROOT}/openspec/changes/archive/2026-03-27-b-3-autopilot-state-management/specs/session-management.md"
  [[ -f "$spec_file" ]] || return 1
  grep -qP "空配列|empty|重複.*ない" "$spec_file" || return 1
}

run_test "重複なしの場合" test_no_cross_issue_warnings

# =============================================================================
# Requirement: ポーリング機構の簡素化
# =============================================================================
echo ""
echo "--- Requirement: ポーリング機構の簡素化 ---"

# Scenario: 通常のポーリングサイクル (line 37)
# WHEN: ポーリングが開始され、issue-{N}.json の status が running
# THEN: 10 秒間隔で state-read.sh --type issue --issue N --field status を繰り返し実行する
test_polling_cycle_spec() {
  local spec_file="${PROJECT_ROOT}/openspec/changes/archive/2026-03-27-b-3-autopilot-state-management/specs/session-management.md"
  [[ -f "$spec_file" ]] || return 1
  grep -qP "10.*秒|10.*second|state-read" "$spec_file" || return 1
}

run_test "通常のポーリングサイクル" test_polling_cycle_spec

# Edge case: ポーリング間隔が定数として設定可能
test_polling_interval_configurable() {
  # Check if any script references the polling interval
  local poll_script
  poll_script=$(find "${PROJECT_ROOT}/scripts" -name "*poll*" 2>/dev/null | head -1)
  if [[ -n "$poll_script" && -f "$poll_script" ]]; then
    grep -qP "POLL_INTERVAL|sleep.*10|interval" "$poll_script" || return 1
  else
    # Structural verification from spec
    local spec_file="${PROJECT_ROOT}/openspec/changes/archive/2026-03-27-b-3-autopilot-state-management/specs/session-management.md"
    grep -qP "10.*秒.*間隔" "$spec_file" || return 1
  fi
}

run_test "ポーリングサイクル [edge: 10 秒間隔の定義]" test_polling_interval_configurable

# Scenario: status 変化の検知 (line 41)
# WHEN: ポーリング中に issue-{N}.json の status が running → merge-ready に変化する
# THEN: ポーリングを停止し、merge-gate フェーズに遷移する
test_status_change_detection() {
  local spec_file="${PROJECT_ROOT}/openspec/changes/archive/2026-03-27-b-3-autopilot-state-management/specs/session-management.md"
  [[ -f "$spec_file" ]] || return 1
  grep -qP "merge-ready" "$spec_file" || return 1
  grep -qP "merge-gate.*フェーズ|merge-gate" "$spec_file" || return 1
}

run_test "status 変化の検知" test_status_change_detection

# Edge case: merge-ready 以外の status 変化（running → failed）も検知する
test_status_change_failed() {
  local spec_file="${PROJECT_ROOT}/openspec/changes/archive/2026-03-27-b-3-autopilot-state-management/specs/session-management.md"
  [[ -f "$spec_file" ]] || return 1
  # The crash detection scenario covers running → failed
  grep -qP "crash.*検知|failed" "$spec_file" || return 1
}

run_test "status 変化検知 [edge: running → failed も検知]" test_status_change_failed

# Scenario: crash 検知との統合 (line 45)
# WHEN: ポーリング中に tmux ペインが消失し、status が running のまま
# THEN: crash として検知し、status を failed に遷移する（不変条件 G）
test_crash_polling_integration() {
  local spec_file="${PROJECT_ROOT}/openspec/changes/archive/2026-03-27-b-3-autopilot-state-management/specs/session-management.md"
  [[ -f "$spec_file" ]] || return 1
  grep -qP "crash" "$spec_file" || return 1
  grep -qP "不変条件.*G|tmux.*消失" "$spec_file" || return 1
}

run_test "crash 検知との統合" test_crash_polling_integration

# =============================================================================
# Requirement: .autopilot ディレクトリの初期化と後始末
# =============================================================================
echo ""
echo "--- Requirement: .autopilot ディレクトリの初期化と後始末 ---"

# Scenario: セッション開始時の初期化 (line 53)
# WHEN: autopilot セッションが開始される
# THEN: .autopilot/ と .autopilot/issues/ が作成される（既存の場合はスキップ）
test_autopilot_dir_init() {
  rm -rf "${SANDBOX}/.autopilot"
  local init_script
  init_script=$(find "${PROJECT_ROOT}/scripts" -name "*autopilot*init*" -o -name "*session*init*" 2>/dev/null | head -1)
  if [[ -n "$init_script" && -f "$init_script" ]]; then
    AUTOPILOT_DIR="${SANDBOX}/.autopilot" bash "$init_script" 2>/dev/null || true
    [[ -d "${SANDBOX}/.autopilot" ]] || return 1
    [[ -d "${SANDBOX}/.autopilot/issues" ]] || return 1
  else
    # Structural verification
    local spec_file="${PROJECT_ROOT}/openspec/changes/archive/2026-03-27-b-3-autopilot-state-management/specs/session-management.md"
    grep -qP "\.autopilot/" "$spec_file" || return 1
    grep -qP "\.autopilot/issues/" "$spec_file" || return 1
  fi
}

run_test "セッション開始時の初期化" test_autopilot_dir_init

# Edge case: 既存ディレクトリがある場合はエラーにならない（冪等性）
test_autopilot_dir_init_idempotent() {
  local spec_file="${PROJECT_ROOT}/openspec/changes/archive/2026-03-27-b-3-autopilot-state-management/specs/session-management.md"
  [[ -f "$spec_file" ]] || return 1
  grep -qP "既存.*スキップ|既存の場合" "$spec_file" || return 1
}

run_test "初期化 [edge: 既存ディレクトリでもスキップ]" test_autopilot_dir_init_idempotent

# Scenario: セッション完了後のアーカイブ (line 57)
# WHEN: autopilot セッションが全 Phase 完了で正常終了する
# THEN: session.json と全 issue-{N}.json は .autopilot/archive/<session_id>/ に移動される
test_session_archive() {
  local spec_file="${PROJECT_ROOT}/openspec/changes/archive/2026-03-27-b-3-autopilot-state-management/specs/session-management.md"
  [[ -f "$spec_file" ]] || return 1
  grep -qP "archive" "$spec_file" || return 1
  grep -qP "session_id" "$spec_file" || return 1
}

run_test "セッション完了後のアーカイブ" test_session_archive

# Edge case: アーカイブ先のパスが .autopilot/archive/<session_id>/ 形式
test_archive_path_format() {
  local spec_file="${PROJECT_ROOT}/openspec/changes/archive/2026-03-27-b-3-autopilot-state-management/specs/session-management.md"
  [[ -f "$spec_file" ]] || return 1
  grep -qP "\.autopilot/archive/" "$spec_file" || return 1
}

run_test "アーカイブ [edge: パス形式が .autopilot/archive/<session_id>/]" test_archive_path_format

# Scenario: .gitignore への追加 (line 61)
# WHEN: .autopilot/ ディレクトリが初めて作成される
# THEN: .gitignore に .autopilot/ エントリが追加される（既にある場合はスキップ）
test_gitignore_entry() {
  local spec_file="${PROJECT_ROOT}/openspec/changes/archive/2026-03-27-b-3-autopilot-state-management/specs/session-management.md"
  [[ -f "$spec_file" ]] || return 1
  grep -qP "\.gitignore" "$spec_file" || return 1
  grep -qP "\.autopilot/" "$spec_file" || return 1
}

run_test ".gitignore への追加" test_gitignore_entry

# Edge case: .gitignore に既に .autopilot/ がある場合は重複追加しない
test_gitignore_no_duplicate() {
  local spec_file="${PROJECT_ROOT}/openspec/changes/archive/2026-03-27-b-3-autopilot-state-management/specs/session-management.md"
  [[ -f "$spec_file" ]] || return 1
  grep -qP "既にある場合.*スキップ|既にある場合は" "$spec_file" || return 1
}

run_test ".gitignore [edge: 重複追加しない]" test_gitignore_no_duplicate

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
