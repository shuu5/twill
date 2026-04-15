#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: su-observer budget pause/resume 機構
# Issue: #599 — su-observer にセッション予算 pause/resume 機構を追加
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
  ((SKIP++))
}

SU_OBSERVER_SKILL="skills/su-observer/SKILL.md"
MONITOR_CATALOG="skills/su-observer/refs/monitor-channel-catalog.md"

# =============================================================================
# Requirement: Step 0 — budget-pause.json 復帰チェック
# Scenario: paused 状態からの回復 (Issue #599)
# WHEN: su-observer 起動時に .supervisor/budget-pause.json が存在し status=paused
# THEN: 回復シーケンスを実行し、全セッションを再開する
# =============================================================================
echo ""
echo "--- Requirement: Step 0 budget-pause.json 復帰チェック ---"

# Test: SKILL.md の Step 0 に budget-pause.json チェックが定義されている
test_skill_budget_pause_check_in_step0() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "budget-pause\.json"
}
run_test "SKILL.md Step 0 に budget-pause.json チェックが定義されている" test_skill_budget_pause_check_in_step0

# Test: SKILL.md に status: paused の場合の回復シーケンスが定義されている
test_skill_recovery_sequence_defined() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" 'status.*paused|paused.*status'
}
run_test "SKILL.md に status: paused の場合の回復シーケンスが定義されている" test_skill_recovery_sequence_defined

# Test: SKILL.md の回復シーケンスに orchestrator 再起動が含まれている
test_skill_recovery_orchestrator_restart() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "orchestrator.*再起動|orchestrator.*restart|session-comm\.sh.*inject.*orchestrator"
}
run_test "SKILL.md の回復シーケンスに orchestrator 再起動が含まれている" test_skill_recovery_orchestrator_restart

# Test: SKILL.md の回復シーケンスに Worker 再開指示が含まれている
test_skill_recovery_worker_resume() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "session-comm\.sh.*inject.*再開|Worker.*再開|paused_workers"
}
run_test "SKILL.md の回復シーケンスに Worker 再開指示が含まれている" test_skill_recovery_worker_resume

# Test: SKILL.md の回復後に budget-pause.json の status を resumed に更新する記述がある
test_skill_recovery_update_status_resumed() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" 'resumed'
}
run_test "SKILL.md の回復後に budget-pause.json status を resumed に更新する記述がある" test_skill_recovery_update_status_resumed

# Edge case: SKILL.md に budget 回復完了メッセージ（>>> budget 回復:）が定義されている
test_skill_recovery_completion_message() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" '>>> budget 回復'
}
run_test "SKILL.md [edge: >>> budget 回復: 完了メッセージが定義されている]" test_skill_recovery_completion_message

# =============================================================================
# Requirement: Step 1 — budget 残量チャネル（BUDGET-LOW）
# Scenario: 5h budget 残量の検知 (Issue #599)
# WHEN: su-observer が co-autopilot supervise 中に budget 残量が閾値以下になる
# THEN: BUDGET-LOW チャネルが検知し、安全停止シーケンスを実行する
# =============================================================================
echo ""
echo "--- Requirement: Step 1 BUDGET-LOW チャネル定義 ---"

# Test: SKILL.md の supervise iteration チャネルテーブルに BUDGET-LOW が定義されている
test_skill_budget_low_channel_in_table() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" 'BUDGET-LOW'
}
run_test "SKILL.md の supervise チャネルテーブルに BUDGET-LOW が定義されている" test_skill_budget_low_channel_in_table

# Test: SKILL.md に tmux capture-pane による budget 情報取得が定義されている
test_skill_tmux_budget_parse() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" 'tmux capture-pane.*budget|budget.*tmux capture-pane|capture-pane.*budget'
}
run_test "SKILL.md に tmux capture-pane による budget 情報取得が定義されている" test_skill_tmux_budget_parse

# Test: SKILL.md に閾値（デフォルト 15 分）が定義されている
test_skill_budget_threshold_15min() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" '15.*分|15 min|threshold.*15|15.*threshold'
}
run_test "SKILL.md に budget 閾値（デフォルト 15 分）が定義されている" test_skill_budget_threshold_15min

# Test: SKILL.md に orchestrator 停止処理が定義されている
test_skill_orchestrator_stop() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" 'orchestrator.*停止|orchestrator.*stop|kill.*orchestrator|orchestrator.*pid|orchestrator\.pid'
}
run_test "SKILL.md に orchestrator 停止処理が定義されている" test_skill_orchestrator_stop

# Test: SKILL.md に Escape 送信処理が定義されている（kill 禁止）
test_skill_escape_not_kill() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" 'Escape.*送信|send-keys.*Escape|tmux send-keys.*Escape'
}
run_test "SKILL.md に全 autopilot window への Escape 送信が定義されている（kill 禁止）" test_skill_escape_not_kill

# Test: SKILL.md に budget-pause.json への停止状態記録が定義されている
test_skill_budget_pause_json_write() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" 'budget-pause\.json.*記録|budget-pause\.json.*paused|budget-pause\.json'
}
run_test "SKILL.md に budget-pause.json への停止状態記録が定義されている" test_skill_budget_pause_json_write

# Test: SKILL.md に CronCreate による回復スケジューリングが定義されている
test_skill_cron_create_recovery() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" 'CronCreate.*回復|CronCreate.*budget|CronCreate'
}
run_test "SKILL.md に CronCreate による回復スケジューリングが定義されている" test_skill_cron_create_recovery

# Edge case: SKILL.md の budget 検知フォールバック（session-comm.sh capture）が定義されている
test_skill_budget_fallback() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" 'session-comm\.sh.*capture.*budget|フォールバック.*budget|budget.*フォールバック'
}
run_test "SKILL.md [edge: budget 検知フォールバック（session-comm.sh capture）が定義されている]" test_skill_budget_fallback

# Edge case: Worker の kill 禁止が明示されている
test_skill_worker_kill_prohibited() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  # kill 禁止 は不変条件として SKILL.md の禁止事項または注記に含まれるはず
  # BUDGET-LOW 停止は Escape のみ（kill なし）で行う
  assert_file_contains "$SU_OBSERVER_SKILL" 'Escape.*のみ|kill.*禁止|不変条件.*kill|kill.*不変条件'
}
run_test "SKILL.md [edge: Worker kill 禁止が明示され Escape のみ使用する旨が定義されている]" test_skill_worker_kill_prohibited

# =============================================================================
# Requirement: monitor-channel-catalog.md — BUDGET-LOW チャネル定義
# Scenario: BUDGET-LOW チャネルの定義追加 (Issue #599)
# WHEN: monitor-channel-catalog.md を参照する
# THEN: BUDGET-LOW チャネルが閾値・介入層・bash スニペット付きで定義されている
# =============================================================================
echo ""
echo "--- Requirement: monitor-channel-catalog.md BUDGET-LOW チャネル ---"

# Test: monitor-channel-catalog.md のチャネル一覧テーブルに BUDGET-LOW が存在する
test_catalog_budget_low_in_table() {
  assert_file_exists "$MONITOR_CATALOG" || return 1
  assert_file_contains "$MONITOR_CATALOG" 'BUDGET-LOW'
}
run_test "monitor-channel-catalog.md チャネル一覧テーブルに BUDGET-LOW が存在する" test_catalog_budget_low_in_table

# Test: BUDGET-LOW の介入層が Auto であることが定義されている
test_catalog_budget_low_layer_auto() {
  assert_file_exists "$MONITOR_CATALOG" || return 1
  python3 - "${PROJECT_ROOT}/${MONITOR_CATALOG}" <<'PYEOF'
import re, sys

with open(sys.argv[1]) as f:
    content = f.read()

# BUDGET-LOW 行を含むテーブル行を探し、Auto が含まれるか確認
lines = content.split('\n')
for line in lines:
    if 'BUDGET-LOW' in line and '|' in line:
        if 'Auto' in line or 'auto' in line:
            sys.exit(0)

print('BUDGET-LOW row not found with Auto layer', file=sys.stderr)
sys.exit(1)
PYEOF
}
run_test "monitor-channel-catalog.md の BUDGET-LOW 介入層が Auto である" test_catalog_budget_low_layer_auto

# Test: monitor-channel-catalog.md に BUDGET-LOW の詳細セクションがある
test_catalog_budget_low_section_exists() {
  assert_file_exists "$MONITOR_CATALOG" || return 1
  assert_file_contains "$MONITOR_CATALOG" '\[BUDGET-LOW\].*—|##.*BUDGET-LOW'
}
run_test "monitor-channel-catalog.md に BUDGET-LOW の詳細セクションが存在する" test_catalog_budget_low_section_exists

# Test: BUDGET-LOW セクションに閾値（15 分）が定義されている
test_catalog_budget_low_threshold() {
  assert_file_exists "$MONITOR_CATALOG" || return 1
  assert_file_contains "$MONITOR_CATALOG" '15.*分|15 min|threshold_minutes'
}
run_test "monitor-channel-catalog.md の BUDGET-LOW セクションに閾値 15 分が定義されている" test_catalog_budget_low_threshold

# Test: BUDGET-LOW セクションに bash スニペットが含まれている
test_catalog_budget_low_bash_snippet() {
  assert_file_exists "$MONITOR_CATALOG" || return 1
  python3 - "${PROJECT_ROOT}/${MONITOR_CATALOG}" <<'PYEOF'
import re, sys

with open(sys.argv[1]) as f:
    content = f.read()

# BUDGET-LOW セクションを抽出
section_match = re.search(r'## \[BUDGET-LOW\].*?(?=^## |\Z)', content, re.DOTALL | re.MULTILINE)
if not section_match:
    print('BUDGET-LOW section not found', file=sys.stderr)
    sys.exit(1)

section = section_match.group(0)
if '```bash' not in section:
    print('No bash snippet in BUDGET-LOW section', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PYEOF
}
run_test "monitor-channel-catalog.md の BUDGET-LOW セクションに bash スニペットが含まれている" test_catalog_budget_low_bash_snippet

# Test: BUDGET-LOW セクションに停止シーケンス（orchestrator 停止 + Escape）が定義されている
test_catalog_budget_low_stop_sequence() {
  assert_file_exists "$MONITOR_CATALOG" || return 1
  python3 - "${PROJECT_ROOT}/${MONITOR_CATALOG}" <<'PYEOF'
import re, sys

with open(sys.argv[1]) as f:
    content = f.read()

section_match = re.search(r'## \[BUDGET-LOW\].*?(?=^## |\Z)', content, re.DOTALL | re.MULTILINE)
if not section_match:
    print('BUDGET-LOW section not found', file=sys.stderr)
    sys.exit(1)

section = section_match.group(0)
has_orchestrator = bool(re.search(r'orchestrator.*停止|orchestrator.*stop|kill.*orchestrator', section, re.IGNORECASE))
has_escape = bool(re.search(r'Escape|send-keys', section))
has_budget_pause_json = bool(re.search(r'budget-pause\.json', section))

if not (has_orchestrator and has_escape and has_budget_pause_json):
    missing = []
    if not has_orchestrator: missing.append('orchestrator stop')
    if not has_escape: missing.append('Escape send')
    if not has_budget_pause_json: missing.append('budget-pause.json')
    print(f'Missing in stop sequence: {", ".join(missing)}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PYEOF
}
run_test "monitor-channel-catalog.md の BUDGET-LOW 停止シーケンスに orchestrator 停止・Escape・budget-pause.json が定義されている" test_catalog_budget_low_stop_sequence

# Test: BUDGET-LOW セクションに再開シーケンスが定義されている
test_catalog_budget_low_resume_sequence() {
  assert_file_exists "$MONITOR_CATALOG" || return 1
  python3 - "${PROJECT_ROOT}/${MONITOR_CATALOG}" <<'PYEOF'
import re, sys

with open(sys.argv[1]) as f:
    content = f.read()

section_match = re.search(r'## \[BUDGET-LOW\].*?(?=^## |\Z)', content, re.DOTALL | re.MULTILINE)
if not section_match:
    print('BUDGET-LOW section not found', file=sys.stderr)
    sys.exit(1)

section = section_match.group(0)
has_resume = bool(re.search(r'再開|resume', section, re.IGNORECASE))

if not has_resume:
    print('Resume sequence not found in BUDGET-LOW section', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PYEOF
}
run_test "monitor-channel-catalog.md の BUDGET-LOW セクションに再開シーケンスが定義されている" test_catalog_budget_low_resume_sequence

# Edge case: Wave 種別ガイドで BUDGET-LOW が co-autopilot 実行中に推奨されている
test_catalog_wave_guide_includes_budget_low() {
  assert_file_exists "$MONITOR_CATALOG" || return 1
  python3 - "${PROJECT_ROOT}/${MONITOR_CATALOG}" <<'PYEOF'
import re, sys

with open(sys.argv[1]) as f:
    content = f.read()

# Wave 種別ガイドセクションを探す
wave_guide_match = re.search(r'## Wave 種別.*?(?=^## |\Z)', content, re.DOTALL | re.MULTILINE)
if not wave_guide_match:
    print('Wave guide section not found', file=sys.stderr)
    sys.exit(1)

wave_guide = wave_guide_match.group(0)
if 'BUDGET-LOW' not in wave_guide:
    print('BUDGET-LOW not in Wave guide table', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PYEOF
}
run_test "monitor-channel-catalog.md [edge: Wave 種別ガイドに BUDGET-LOW が含まれている]" test_catalog_wave_guide_includes_budget_low

# Edge case: budget-config.json で閾値を override できる旨が定義されている
test_catalog_budget_config_json_override() {
  assert_file_exists "$MONITOR_CATALOG" || return 1
  assert_file_contains "$MONITOR_CATALOG" 'budget-config\.json'
}
run_test "monitor-channel-catalog.md [edge: budget-config.json による閾値 override が定義されている]" test_catalog_budget_config_json_override

# =============================================================================
# Requirement: status line パース — 柔軟な正規表現ベース
# Scenario: budget パース (Issue #599)
# WHEN: status line の budget フォーマットが変動する
# THEN: 正規表現ベースのパーサーが対応する
# =============================================================================
echo ""
echo "--- Requirement: status line budget パース ---"

# Test: SKILL.md または monitor-catalog に正規表現ベースのパーサーが定義されている
test_regex_based_parser() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" 'grep -oP.*budget|grep.*budget.*oP|grep.*oP.*budget'
}
run_test "SKILL.md に正規表現ベースの budget パーサーが定義されている" test_regex_based_parser

# Test: SKILL.md に時間単位（h / m）の変換処理が定義されている
test_time_unit_conversion() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" '[0-9].*\*.*60|60.*BASH_REMATCH|BUDGET_MIN.*60'
}
run_test "SKILL.md に h/m 単位の分換算ロジックが定義されている" test_time_unit_conversion

# Edge case: 取得不能時の WARN 出力が定義されている
test_warn_on_budget_unavailable() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" 'WARN.*budget|budget.*WARN|budget.*取得できません'
}
run_test "SKILL.md [edge: budget 情報取得不能時に WARN を出力し検知をスキップする旨が定義されている]" test_warn_on_budget_unavailable

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
