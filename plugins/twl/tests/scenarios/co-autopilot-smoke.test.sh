#!/usr/bin/env bash
# =============================================================================
# Integration Smoke Tests: co-autopilot Pilot startup flow
# Issue #409: co-autopilot SKILL.md 変更の integration test 追加
#
# Coverage:
#   - autopilot-plan.sh 引数バリデーション（GitHub API 不要）
#   - autopilot-plan.sh --explicit による plan.yaml 生成（gh 認証済み時）
#   - python3 -m twl.autopilot.state の write/read 基本動作
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

# state module が使用可能か確認
_STATE_AVAILABLE=false
if python3 -c "import twl.autopilot.state" 2>/dev/null; then
  _STATE_AVAILABLE=true
fi

# gh 認証状態の確認
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

# =============================================================================
# autopilot-plan.sh 引数バリデーション（GitHub API 不要）
# =============================================================================
echo ""
echo "--- autopilot-plan.sh 引数バリデーション ---"

PLAN_SCRIPT="${SCRIPTS_DIR}/autopilot-plan.sh"

# Scenario: 引数なし → exit 1
# WHEN: autopilot-plan.sh を引数なしで実行する
# THEN: exit code 1 で終了し、Usage メッセージが表示される
test_plan_no_args() {
  [[ -f "$PLAN_SCRIPT" ]] || return 1
  local output exit_code=0
  output=$(bash "$PLAN_SCRIPT" 2>&1) || exit_code=$?
  [[ $exit_code -ne 0 ]] && echo "$output" | grep -q "Usage:"
}

if [[ -f "$PLAN_SCRIPT" ]]; then
  run_test "autopilot-plan.sh: 引数なしで exit 1 + Usage 表示" test_plan_no_args
else
  run_test_skip "autopilot-plan.sh: 引数なしで exit 1 + Usage 表示" "スクリプト不在: ${PLAN_SCRIPT}"
fi

# Scenario: --explicit のみ（--project-dir 欠如）→ exit 1
# WHEN: --explicit は指定するが --project-dir と --repo-mode を省略して実行する
# THEN: exit code 1 で終了する
test_plan_missing_project_dir() {
  [[ -f "$PLAN_SCRIPT" ]] || return 1
  ! bash "$PLAN_SCRIPT" --explicit "1" 2>/dev/null
}

if [[ -f "$PLAN_SCRIPT" ]]; then
  run_test "autopilot-plan.sh: --project-dir 省略で exit 1" test_plan_missing_project_dir
else
  run_test_skip "autopilot-plan.sh: --project-dir 省略で exit 1" "スクリプト不在: ${PLAN_SCRIPT}"
fi

# =============================================================================
# autopilot-plan.sh --explicit: plan.yaml 生成（gh 認証済み時のみ）
# =============================================================================
echo ""
echo "--- autopilot-plan.sh --explicit: plan.yaml 生成 ---"

# Scenario: --explicit で plan.yaml が生成される
# WHEN: gh 認証済みで autopilot-plan.sh --explicit "409" を一時ディレクトリで実行する
# THEN: TMPDIR/.autopilot/plan.yaml が生成され exit code が 0
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

if [[ "$_GH_AUTHED" == "true" && -f "$PLAN_SCRIPT" ]]; then
  run_test "autopilot-plan.sh --explicit: plan.yaml が生成される" test_plan_explicit_generates_yaml
elif [[ ! -f "$PLAN_SCRIPT" ]]; then
  run_test_skip "autopilot-plan.sh --explicit: plan.yaml が生成される" "スクリプト不在: ${PLAN_SCRIPT}"
else
  run_test_skip "autopilot-plan.sh --explicit: plan.yaml が生成される" "gh 未認証"
fi

# Scenario: 生成された plan.yaml に session_id と phases が含まれる
# WHEN: --explicit で plan.yaml が生成された後
# THEN: plan.yaml に session_id: と phases: キーが存在する
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

if [[ "$_GH_AUTHED" == "true" && -f "$PLAN_SCRIPT" ]]; then
  run_test "autopilot-plan.sh --explicit: plan.yaml に session_id + phases が含まれる" test_plan_yaml_structure
elif [[ ! -f "$PLAN_SCRIPT" ]]; then
  run_test_skip "autopilot-plan.sh --explicit: plan.yaml に session_id + phases が含まれる" "スクリプト不在: ${PLAN_SCRIPT}"
else
  run_test_skip "autopilot-plan.sh --explicit: plan.yaml に session_id + phases が含まれる" "gh 未認証"
fi

# =============================================================================
# python3 -m twl.autopilot.state: state write/read 基本動作
# =============================================================================
echo ""
echo "--- twl.autopilot.state: write/read 基本動作 ---"

# Scenario: state write で current_step が書き込まれる
# WHEN: 一時ディレクトリに issue-999.json を作成し state write でフィールドを更新する
# THEN: state read で更新されたフィールド値が返される
test_state_write_read() {
  setup_tmpdir
  mkdir -p "${_TMPDIR}/issues"
  # 最小限の有効な state JSON を作成
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
  "failure": null,
  "workflow_done": null
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
  run_test "state write: current_step が書き込まれ read で取得できる" test_state_write_read
else
  run_test_skip "state write: current_step が書き込まれ read で取得できる" "twl.autopilot.state が import 不可"
fi

# Scenario: state write で workflow_done が書き込まれる
# WHEN: state write --set "workflow_done=setup" を実行する
# THEN: state read --field workflow_done が "setup" を返す
test_state_workflow_done() {
  setup_tmpdir
  mkdir -p "${_TMPDIR}/issues"
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
  "failure": null,
  "workflow_done": null
}
JSON
  python3 -m twl.autopilot.state write \
    --autopilot-dir "${_TMPDIR}" \
    --type issue \
    --issue 999 \
    --role worker \
    --set "workflow_done=setup" 2>/dev/null
  local read_val
  read_val=$(python3 -m twl.autopilot.state read \
    --autopilot-dir "${_TMPDIR}" \
    --type issue \
    --issue 999 \
    --field workflow_done 2>/dev/null)
  local result=1
  [[ "$read_val" == "setup" ]] && result=0
  teardown_tmpdir
  return $result
}

if [[ "$_STATE_AVAILABLE" == "true" ]]; then
  run_test "state write: workflow_done=setup が書き込まれ read で取得できる" test_state_workflow_done
else
  run_test_skip "state write: workflow_done=setup が書き込まれ read で取得できる" "twl.autopilot.state が import 不可"
fi

# =============================================================================
# autopilot スクリプト存在確認（ランタイム起動可能性）
# =============================================================================
echo ""
echo "--- autopilot スクリプト存在確認 ---"

# Scenario: Pilot 起動に必要なスクリプトが存在する
# WHEN: Pilot が起動フローを実行する
# THEN: autopilot-plan.sh / autopilot-init.sh / autopilot-launch.sh / autopilot-orchestrator.sh が存在しなければならない
test_pilot_scripts_exist() {
  local missing=0
  for script in autopilot-plan.sh autopilot-init.sh autopilot-launch.sh autopilot-orchestrator.sh; do
    [[ -f "${SCRIPTS_DIR}/${script}" ]] || { echo "  MISSING: ${script}" >&2; missing=1; }
  done
  return $missing
}

run_test "Pilot 起動スクリプト（plan/init/launch/orchestrator）が全て存在する" test_pilot_scripts_exist

# Scenario: 各スクリプトが実行可能権限を持つ
# WHEN: スクリプトを実行しようとする
# THEN: 各スクリプトに実行権限（chmod +x）があること
test_pilot_scripts_executable() {
  local non_exec=0
  for script in autopilot-plan.sh autopilot-init.sh autopilot-launch.sh autopilot-orchestrator.sh; do
    local path="${SCRIPTS_DIR}/${script}"
    [[ -f "$path" && -x "$path" ]] || { echo "  NOT EXECUTABLE: ${script}" >&2; non_exec=1; }
  done
  return $non_exec
}

run_test "Pilot 起動スクリプトが実行権限を持つ" test_pilot_scripts_executable

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
