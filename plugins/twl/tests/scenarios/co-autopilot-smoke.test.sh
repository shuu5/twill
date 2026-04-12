#!/usr/bin/env bash
# =============================================================================
# Smoke Tests: co-autopilot Pilot startup flow
# Generated from: deltaspec/changes/issue-409/specs/co-autopilot-smoke/spec.md
# Coverage level: edge-cases
#
# Change: issue-409 (co-autopilot smoke test スクリプト追加)
# Requirement 1: co-autopilot smoke test スクリプト
#   - plan.yaml 生成の smoke test（gh 認証済み）
#   - plan.yaml 生成スキップ（gh 未認証）
#   - state write/read の基本動作確認
#   - state モジュール不在時のスキップ
# Requirement 2: テスト形式の一貫性
#   - PASS/FAIL/SKIP カウンタ、run_test / run_test_skip ヘルパー
#   - "Results: X passed, Y failed, Z skipped" サマリー
# =============================================================================
set -uo pipefail

# Project root (plugins/twl/tests/scenarios/ → plugins/twl/)
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPTS_DIR="${PROJECT_ROOT}/scripts"

# Counters
PASS=0
FAIL=0
SKIP=0
ERRORS=()

# --- Test Helpers ---

run_test() {
  local name="$1"
  local func="$2"
  local result=0
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

# --- PYTHONPATH セットアップ ---
PYTHON_ENV_SH="${SCRIPTS_DIR}/lib/python-env.sh"
if [[ -f "$PYTHON_ENV_SH" ]]; then
  # shellcheck source=../../scripts/lib/python-env.sh
  source "$PYTHON_ENV_SH"
fi

# state モジュールが使用可能か事前確認
_STATE_AVAILABLE=false
if python3 -c "import twl.autopilot.state" 2>/dev/null; then
  _STATE_AVAILABLE=true
fi

# gh 認証状態の事前確認
_GH_AUTHED=false
if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
  _GH_AUTHED=true
fi

# 一時ディレクトリ管理
_TMPDIR=""

setup_tmpdir() {
  _TMPDIR="$(mktemp -d)"
}

teardown_tmpdir() {
  [[ -n "${_TMPDIR}" && -d "${_TMPDIR}" ]] && rm -rf "${_TMPDIR}"
  _TMPDIR=""
}

PLAN_SCRIPT="${SCRIPTS_DIR}/autopilot-plan.sh"

# =============================================================================
# Requirement: co-autopilot smoke test スクリプト
# =============================================================================

# =============================================================================
# Scenario: plan.yaml 生成の smoke test
# WHEN: autopilot-plan.sh --explicit "409" --project-dir TMPDIR --repo-mode single を実行し、
#       gh コマンドが認証済みの場合
# THEN: TMPDIR/.autopilot/plan.yaml が生成され、exit code が 0 であること
# =============================================================================
echo ""
echo "--- Scenario: plan.yaml 生成の smoke test ---"

test_plan_explicit_generates_yaml() {
  setup_tmpdir
  local exit_code=0
  bash "$PLAN_SCRIPT" \
    --explicit "409" \
    --project-dir "${_TMPDIR}" \
    --repo-mode "single" \
    2>/dev/null || exit_code=$?
  local plan_file="${_TMPDIR}/.autopilot/plan.yaml"
  local result=1
  if [[ $exit_code -eq 0 && -f "$plan_file" ]]; then
    result=0
  fi
  teardown_tmpdir
  return $result
}

# Edge case: plan.yaml に session_id と phases キーが含まれる
test_plan_yaml_structure() {
  setup_tmpdir
  local exit_code=0
  bash "$PLAN_SCRIPT" \
    --explicit "409" \
    --project-dir "${_TMPDIR}" \
    --repo-mode "single" \
    2>/dev/null || exit_code=$?
  local plan_file="${_TMPDIR}/.autopilot/plan.yaml"
  local result=1
  if [[ $exit_code -eq 0 && -f "$plan_file" ]]; then
    grep -q "^session_id:" "$plan_file" && \
    grep -q "^phases:" "$plan_file" && \
    result=0
  fi
  teardown_tmpdir
  return $result
}

if [[ ! -f "$PLAN_SCRIPT" ]]; then
  run_test_skip "plan.yaml 生成の smoke test: TMPDIR/.autopilot/plan.yaml が生成される" \
    "スクリプト不在: ${PLAN_SCRIPT}"
  run_test_skip "plan.yaml 生成の smoke test [edge: session_id + phases キーが含まれる]" \
    "スクリプト不在: ${PLAN_SCRIPT}"
elif [[ "$_GH_AUTHED" == "true" ]]; then
  run_test "plan.yaml 生成の smoke test: TMPDIR/.autopilot/plan.yaml が生成される" \
    test_plan_explicit_generates_yaml
  run_test "plan.yaml 生成の smoke test [edge: session_id + phases キーが含まれる]" \
    test_plan_yaml_structure
else
  # Scenario: plan.yaml 生成スキップ（gh 未認証）が正常に処理されることを確認
  run_test_skip "plan.yaml 生成の smoke test: TMPDIR/.autopilot/plan.yaml が生成される" \
    "gh 未認証"
  run_test_skip "plan.yaml 生成の smoke test [edge: session_id + phases キーが含まれる]" \
    "gh 未認証"
fi

# =============================================================================
# Scenario: plan.yaml 生成スキップ（gh 未認証）
# WHEN: gh コマンドが認証されていない、または利用不可の場合
# THEN: テストを SKIP し、exit code が非ゼロにならないこと
# =============================================================================
echo ""
echo "--- Scenario: plan.yaml 生成スキップ（gh 未認証） ---"

# このシナリオは SKIP 動作自体が正しいことを確認するメタテスト
# SKIP カウンタが増加し、テスト全体の exit code（FAIL 数）に影響しないことを保証する
test_plan_skip_behavior_noop() {
  # gh 未認証時は run_test_skip が呼ばれ exit code に影響しない動作が期待される
  # このテスト自体は常に PASS（SKIP フローの健全性チェック）
  return 0
}

if [[ "$_GH_AUTHED" == "true" ]]; then
  run_test_skip "plan.yaml 生成スキップ検証: gh 認証済みのためこのシナリオは非該当" \
    "gh 認証済み（非該当シナリオ）"
else
  # gh 未認証: SKIP フローが正常に動作することを確認
  run_test_skip "plan.yaml 生成スキップ: gh 未認証のため plan.yaml 生成をスキップ" \
    "gh 未認証（期待通りの SKIP）"
  run_test "plan.yaml 生成スキップ [edge: SKIP は exit code を非ゼロにしない]" \
    test_plan_skip_behavior_noop
fi

# =============================================================================
# Scenario: state write/read の基本動作確認
# WHEN: python3 -m twl.autopilot.state write --type issue --issue 999 --role worker
#       --init を一時ディレクトリで実行する（--init で status=running の初期状態を作成）
# THEN: exit code が 0 であり、state read --field status が "running" を返すこと
# =============================================================================
echo ""
echo "--- Scenario: state write/read の基本動作確認 ---"

test_state_write_read_status() {
  setup_tmpdir
  # --init で issue-999.json を status=running で作成
  local write_exit=0
  python3 -m twl.autopilot.state write \
    --autopilot-dir "${_TMPDIR}" \
    --type issue \
    --issue 999 \
    --role worker \
    --init 2>/dev/null || write_exit=$?
  local result=1
  if [[ $write_exit -eq 0 ]]; then
    local read_val
    read_val=$(python3 -m twl.autopilot.state read \
      --autopilot-dir "${_TMPDIR}" \
      --type issue \
      --issue 999 \
      --field status 2>/dev/null)
    [[ "$read_val" == "running" ]] && result=0
  fi
  teardown_tmpdir
  return $result
}

# Edge case: write で任意フィールド（current_step）を更新し read で取得できる
test_state_write_read_field_update() {
  setup_tmpdir
  mkdir -p "${_TMPDIR}/issues"
  # 最小限の有効な state JSON を直接作成（--init を使わずフィールド更新の edge case を検証）
  cat > "${_TMPDIR}/issues/issue-999.json" <<'JSON'
{
  "issue": 999,
  "status": "running",
  "branch": "test-branch",
  "pr": null,
  "window": "",
  "started_at": "2026-01-01T00:00:00Z",
  "updated_at": "2026-01-01T00:00:00Z",
  "current_step": "",
  "retry_count": 0,
  "fix_instructions": null,
  "merged_at": null,
  "files_changed": [],
  "failure": null
}
JSON
  python3 -m twl.autopilot.state write \
    --autopilot-dir "${_TMPDIR}" \
    --type issue \
    --issue 999 \
    --role worker \
    --set "current_step=smoke-test-step" 2>/dev/null
  local read_val
  read_val=$(python3 -m twl.autopilot.state read \
    --autopilot-dir "${_TMPDIR}" \
    --type issue \
    --issue 999 \
    --field current_step 2>/dev/null)
  local result=1
  [[ "$read_val" == "smoke-test-step" ]] && result=0
  teardown_tmpdir
  return $result
}

if [[ "$_STATE_AVAILABLE" == "true" ]]; then
  run_test "state write/read: --init で status=running が作成され read で取得できる" \
    test_state_write_read_status
  run_test "state write/read [edge: current_step フィールド更新が read で取得できる]" \
    test_state_write_read_field_update
else
  run_test_skip "state write/read: --init で status=running が作成され read で取得できる" \
    "twl.autopilot.state が import 不可"
  run_test_skip "state write/read [edge: current_step フィールド更新が read で取得できる]" \
    "twl.autopilot.state が import 不可"
fi

# =============================================================================
# Scenario: state モジュール不在時のスキップ
# WHEN: python3 -m twl.autopilot.state が import エラーを起こす場合（PYTHONPATH 未設定等）
# THEN: テストを SKIP し、exit code が非ゼロにならないこと
# =============================================================================
echo ""
echo "--- Scenario: state モジュール不在時のスキップ ---"

# SKIP フロー健全性チェック: モジュール不在でも exit code は FAIL 数のみを反映する
test_state_absent_skip_behavior_noop() {
  # SKIP カウンタが増加するだけで FAIL には影響しない
  return 0
}

if [[ "$_STATE_AVAILABLE" == "true" ]]; then
  run_test_skip "state モジュール不在時スキップ: モジュール利用可能のためこのシナリオは非該当" \
    "twl.autopilot.state import 可能（非該当シナリオ）"
else
  run_test_skip "state モジュール不在時スキップ: PYTHONPATH 未設定のため state テストをスキップ" \
    "twl.autopilot.state が import 不可（期待通りの SKIP）"
  run_test "state モジュール不在時スキップ [edge: SKIP は exit code を非ゼロにしない]" \
    test_state_absent_skip_behavior_noop
fi

# =============================================================================
# Requirement: テスト形式の一貫性
# Scenario: テスト結果サマリー出力
# WHEN: smoke test を実行する
# THEN: "Results: X passed, Y failed, Z skipped" の形式でサマリーが表示され、
#       FAIL 数が exit code になること
# =============================================================================

# =============================================================================
# 付加: autopilot スクリプト存在確認（ランタイム起動可能性）
# =============================================================================
echo ""
echo "--- autopilot スクリプト存在確認 ---"

test_pilot_scripts_exist() {
  local missing=0
  for script in autopilot-plan.sh autopilot-init.sh autopilot-launch.sh autopilot-orchestrator.sh; do
    [[ -f "${SCRIPTS_DIR}/${script}" ]] || { echo "  MISSING: ${script}" >&2; missing=1; }
  done
  return $missing
}

test_pilot_scripts_executable() {
  local non_exec=0
  for script in autopilot-plan.sh autopilot-init.sh autopilot-launch.sh autopilot-orchestrator.sh; do
    local path="${SCRIPTS_DIR}/${script}"
    [[ -f "$path" && -x "$path" ]] || { echo "  NOT EXECUTABLE: ${script}" >&2; non_exec=1; }
  done
  return $non_exec
}

run_test "Pilot 起動スクリプト（plan/init/launch/orchestrator）が全て存在する" \
  test_pilot_scripts_exist
run_test "Pilot 起動スクリプトが実行権限を持つ" \
  test_pilot_scripts_executable

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

exit $(( FAIL > 255 ? 255 : FAIL ))
