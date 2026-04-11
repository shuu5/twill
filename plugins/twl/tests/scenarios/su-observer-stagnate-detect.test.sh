#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: su-observer stagnate 検知 / Worker idle 検知
# Generated from: deltaspec/changes/issue-475/specs/su-observer-stall-detection/spec.md
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
OBSERVE_ONCE_CMD="commands/observe-once.md"
INTERVENTION_CATALOG="refs/intervention-catalog.md"

# =============================================================================
# Requirement: 監視チャンネルマトリクス
# Scenario: Worker stall 検知 (spec line 15)
# WHEN: co-autopilot 起動後、cld-observe-loop を --pattern 'ap-*' --interval 180 で起動し、
#       いずれかの Worker の state file updated_at が AUTOPILOT_STAGNATE_SEC 以上更新されていない
# THEN: su-observer は WARN を出力し、intervention-catalog の pattern-7 照合を実行
# =============================================================================
echo ""
echo "--- Requirement: 監視チャンネルマトリクス / Worker stall 検知 ---"

# Test: SKILL.md に cld-observe-loop の --pattern 'ap-*' --interval 180 が定義されている
test_skill_observe_loop_pattern() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "cld-observe-loop.*--pattern.*ap-\*.*--interval\s*180|--pattern.*ap-\*|--interval\s*180"
}
run_test "SKILL.md に cld-observe-loop --pattern 'ap-*' --interval 180 が定義されている" test_skill_observe_loop_pattern

# Test: SKILL.md に AUTOPILOT_STAGNATE_SEC への言及がある
test_skill_stagnate_sec_defined() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "AUTOPILOT_STAGNATE_SEC"
}
run_test "SKILL.md に AUTOPILOT_STAGNATE_SEC 環境変数が定義されている" test_skill_stagnate_sec_defined

# Test: SKILL.md に stagnate 検知時の WARN 出力が言及されている
test_skill_warn_on_stagnate() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "WARN|stagnate.*検知|stagnate detect"
}
run_test "SKILL.md に stagnate 検知時 WARN 出力が定義されている" test_skill_warn_on_stagnate

# Test: SKILL.md に pattern-7 照合への言及がある
test_skill_pattern7_reference() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "pattern-7|pattern 7|pattern7"
}
run_test "SKILL.md に pattern-7 照合が定義されている" test_skill_pattern7_reference

# Edge case: SKILL.md に intervention-catalog への参照がある（stagnate 時の照合経路確認）
test_skill_intervention_catalog_ref() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "intervention-catalog"
}
run_test "SKILL.md [edge: intervention-catalog への参照が存在する]" test_skill_intervention_catalog_ref

# Edge case: AUTOPILOT_STAGNATE_SEC のデフォルト値 600 が記載されている
test_skill_stagnate_default_600() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "600"
}
run_test "SKILL.md [edge: AUTOPILOT_STAGNATE_SEC デフォルト値 600s が明記されている]" test_skill_stagnate_default_600

# =============================================================================
# Requirement: 監視チャンネルマトリクス
# Scenario: 監視チャンネル並行実行 (spec line 19)
# WHEN: su-observer が co-autopilot supervise モードに入る
# THEN: Monitor tool（Pilot tail）と cld-observe-loop（Worker 群）を同時に起動
# =============================================================================
echo ""
echo "--- Requirement: 監視チャンネル並行実行 ---"

# Test: SKILL.md に監視チャンネルマトリクスのテーブルが存在する
test_skill_channel_matrix_table() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  # マトリクス表の | チャンネル | 目的 | 閾値/間隔 | ヘッダーを確認
  assert_file_contains "$SU_OBSERVER_SKILL" "\|.*チャンネル.*\|.*目的.*\||\|.*channel.*\|.*purpose.*\|"
}
run_test "SKILL.md に監視チャンネルマトリクス テーブルが存在する" test_skill_channel_matrix_table

# Test: SKILL.md に Monitor tool（Pilot tail）が監視チャンネルとして定義されている
test_skill_monitor_tool_channel() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "Monitor\s*tool\s*\(Pilot\)|Monitor.*Pilot.*tail|tail\s*streaming"
}
run_test "SKILL.md に Monitor tool (Pilot tail) チャンネルが定義されている" test_skill_monitor_tool_channel

# Test: SKILL.md に cld-observe-loop（Worker 群 polling）チャンネルが定義されている
test_skill_observe_loop_channel() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "cld-observe-loop"
}
run_test "SKILL.md に cld-observe-loop (Worker 群 polling) チャンネルが定義されている" test_skill_observe_loop_channel

# Test: SKILL.md に issue-*.json mtime 監視チャンネルが定義されている
test_skill_mtime_channel() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "issue-\*\.json.*mtime|mtime.*issue-\*|state stagnate"
}
run_test "SKILL.md に issue-*.json mtime 監視チャンネルが定義されている" test_skill_mtime_channel

# Test: SKILL.md に gh pr list チャンネルが定義されている
test_skill_gh_pr_list_channel() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "gh pr list"
}
run_test "SKILL.md に gh pr list (state.pr 差分検知) チャンネルが定義されている" test_skill_gh_pr_list_channel

# Test: SKILL.md に session-comm.sh capture チャンネルが定義されている
test_skill_session_comm_channel() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "session-comm\.sh.*capture|session-comm.*capture"
}
run_test "SKILL.md に session-comm.sh capture チャンネルが定義されている" test_skill_session_comm_channel

# Edge case: 監視チャンネルが5つ定義されている（マトリクス行数確認）
test_skill_five_channels() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  python3 - "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" <<'PYEOF'
import re, sys

with open(sys.argv[1]) as f:
    content = f.read()

# チャンネルマトリクステーブルのデータ行を数える（ヘッダー行・区切り行除く）
# | で始まり | で終わるテーブル行で、--- を含まないもの
table_lines = [
    line.strip() for line in content.split('\n')
    if re.match(r'^\|', line.strip()) and '---' not in line and '目的' not in line and 'purpose' not in line and 'チャンネル' not in line and 'channel' not in line
]

# 監視チャンネルマトリクスに含まれる行（Monitor / cld-observe-loop / mtime / session-comm / gh pr list）
channel_keywords = ['Monitor', 'cld-observe-loop', 'mtime', 'session-comm', 'gh pr list']
found = sum(1 for kw in channel_keywords if any(kw in line for line in table_lines))

if found < 5:
    print(f'Expected 5 channels in matrix, found {found} matching keywords', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PYEOF
}
run_test "SKILL.md [edge: 監視チャンネルが5つ定義されている]" test_skill_five_channels

# Edge case: どちらか一方のみ起動禁止の記述がある
test_skill_both_required() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "同時|並行|concurrent|どちらか一方.*禁止|must.*both|両方"
}
run_test "SKILL.md [edge: Monitor と cld-observe-loop の同時起動が必須であることが明記されている]" test_skill_both_required

# =============================================================================
# Requirement: state stagnate 検知（observe-once 拡張）
# Scenario: stagnate ファイル検出 (spec line 27)
# WHEN: observe-once を実行し、issue-*.json の mtime が AUTOPILOT_STAGNATE_SEC 以上古い
# THEN: JSON 出力の stagnate_files 配列に該当ファイルパスを含め WARN を出力
# =============================================================================
echo ""
echo "--- Requirement: state stagnate 検知 / stagnate ファイル検出 ---"

# Test: observe-once.md に stagnate_files フィールドが定義されている
test_observe_once_stagnate_files_field() {
  assert_file_exists "$OBSERVE_ONCE_CMD" || return 1
  assert_file_contains "$OBSERVE_ONCE_CMD" "stagnate_files"
}
run_test "observe-once.md に stagnate_files フィールドが定義されている" test_observe_once_stagnate_files_field

# Test: observe-once.md に .autopilot/issues/issue-*.json の mtime チェックが定義されている
test_observe_once_mtime_check() {
  assert_file_exists "$OBSERVE_ONCE_CMD" || return 1
  assert_file_contains "$OBSERVE_ONCE_CMD" "\.autopilot/issues/issue-\*\.json|mtime.*チェック|mtime.*check"
}
run_test "observe-once.md に .autopilot/issues/issue-*.json mtime チェックが定義されている" test_observe_once_mtime_check

# Test: observe-once.md に AUTOPILOT_STAGNATE_SEC の参照がある
test_observe_once_stagnate_sec() {
  assert_file_exists "$OBSERVE_ONCE_CMD" || return 1
  assert_file_contains "$OBSERVE_ONCE_CMD" "AUTOPILOT_STAGNATE_SEC"
}
run_test "observe-once.md に AUTOPILOT_STAGNATE_SEC 参照が定義されている" test_observe_once_stagnate_sec

# Test: observe-once.md に WARN: state stagnate detected 出力が定義されている
test_observe_once_warn_output() {
  assert_file_exists "$OBSERVE_ONCE_CMD" || return 1
  assert_file_contains "$OBSERVE_ONCE_CMD" "WARN.*state stagnate detected|WARN.*stagnate"
}
run_test "observe-once.md に 'WARN: state stagnate detected: <path>' 出力が定義されている" test_observe_once_warn_output

# Edge case: observe-once.md の WARN 出力フォーマットに <path> のプレースホルダーがある
test_observe_once_warn_path_format() {
  assert_file_exists "$OBSERVE_ONCE_CMD" || return 1
  assert_file_contains "$OBSERVE_ONCE_CMD" "WARN.*stagnate.*<path>|stagnate.*detected.*<path>|stagnate.*\$\{.*\}|stagnate.*\$path"
}
run_test "observe-once.md [edge: WARN フォーマットに <path> プレースホルダーが含まれる]" test_observe_once_warn_path_format

# Edge case: stagnate_files は配列型 (string[]) として定義されている
test_observe_once_stagnate_files_array_type() {
  assert_file_exists "$OBSERVE_ONCE_CMD" || return 1
  assert_file_contains "$OBSERVE_ONCE_CMD" "stagnate_files.*string\[\]|stagnate_files.*\[\]|stagnate_files.*array"
}
run_test "observe-once.md [edge: stagnate_files が配列型として定義されている]" test_observe_once_stagnate_files_array_type

# =============================================================================
# Requirement: state stagnate 検知（observe-once 拡張）
# Scenario: stagnate なし (spec line 31)
# WHEN: observe-once を実行し、全 state file の mtime が AUTOPILOT_STAGNATE_SEC 秒以内
# THEN: stagnate_files は空配列 [] を出力し、WARN は出力しない
# =============================================================================
echo ""
echo "--- Requirement: stagnate なし / 正常系 ---"

# Test: observe-once.md に stagnate なし時の空配列出力が定義されている
test_observe_once_empty_array_no_stagnate() {
  assert_file_exists "$OBSERVE_ONCE_CMD" || return 1
  assert_file_contains "$OBSERVE_ONCE_CMD" "\[\]|空配列|empty array"
}
run_test "observe-once.md に stagnate なし時の stagnate_files: [] が定義されている" test_observe_once_empty_array_no_stagnate

# Edge case: observe-once.md の JSON 出力例に stagnate_files が含まれている
test_observe_once_json_example_has_stagnate_files() {
  assert_file_exists "$OBSERVE_ONCE_CMD" || return 1
  python3 - "${PROJECT_ROOT}/${OBSERVE_ONCE_CMD}" <<'PYEOF'
import re, sys

with open(sys.argv[1]) as f:
    content = f.read()

# JSON コードブロックを探す
json_blocks = re.findall(r'```json\s*(.*?)\s*```', content, re.DOTALL)
has_stagnate_files = any('stagnate_files' in block for block in json_blocks)

if not has_stagnate_files:
    print('No JSON code block contains stagnate_files field', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PYEOF
}
run_test "observe-once.md [edge: JSON 出力例に stagnate_files フィールドが含まれている]" test_observe_once_json_example_has_stagnate_files

# Edge case: 既存フィールド（window, timestamp, lines, capture, session_state）が保持されている
test_observe_once_existing_fields_preserved() {
  assert_file_exists "$OBSERVE_ONCE_CMD" || return 1
  local existing_fields=("window" "timestamp" "lines" "capture" "session_state")
  for field in "${existing_fields[@]}"; do
    if ! assert_file_contains "$OBSERVE_ONCE_CMD" "\"${field}\""; then
      echo "Missing existing field: ${field}" >&2
      return 1
    fi
  done
  return 0
}
run_test "observe-once.md [edge: 既存 JSON フィールドが全て保持されている]" test_observe_once_existing_fields_preserved

# =============================================================================
# Requirement: Worker idle 検知パターン（intervention-catalog pattern-7）
# Scenario: 自動回復（pattern-7） (spec line 39)
# WHEN: state updated_at が 600 秒以上古い AND worker pane に '>>> 実装完了:' を含む
# THEN: Layer 0 Auto として /twl:workflow-pr-verify を inject し InterventionRecord を記録
# =============================================================================
echo ""
echo "--- Requirement: Worker idle 検知 / 自動回復 (pattern-7) ---"

# Test: intervention-catalog.md に pattern-7 が定義されている
test_catalog_pattern7_exists() {
  assert_file_exists "$INTERVENTION_CATALOG" || return 1
  assert_file_contains "$INTERVENTION_CATALOG" "pattern-7|pattern 7|パターン\s*7"
}
run_test "intervention-catalog.md に pattern-7 が定義されている" test_catalog_pattern7_exists

# Test: pattern-7 が Layer 0 Auto に分類されている
test_catalog_pattern7_layer0() {
  assert_file_exists "$INTERVENTION_CATALOG" || return 1
  python3 - "${PROJECT_ROOT}/${INTERVENTION_CATALOG}" <<'PYEOF'
import re, sys

with open(sys.argv[1]) as f:
    content = f.read()

# Layer 0: Auto セクションを抽出
layer0_match = re.search(r'## Layer 0.*?(?=## Layer [12]|\Z)', content, re.DOTALL | re.IGNORECASE)
if not layer0_match:
    print('Layer 0 section not found', file=sys.stderr)
    sys.exit(1)

layer0_content = layer0_match.group(0)
if not re.search(r'pattern-7|pattern 7|パターン\s*7', layer0_content, re.IGNORECASE):
    print('pattern-7 not found in Layer 0 Auto section', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PYEOF
}
run_test "intervention-catalog.md の pattern-7 が Layer 0 Auto に分類されている" test_catalog_pattern7_layer0

# Test: pattern-7 の検出条件に state stagnate (600 秒以上) が含まれている
test_catalog_pattern7_stagnate_condition() {
  assert_file_exists "$INTERVENTION_CATALOG" || return 1
  assert_file_contains "$INTERVENTION_CATALOG" "600.*秒.*stagnate|stagnate.*600|updated_at.*600|AUTOPILOT_STAGNATE_SEC"
}
run_test "intervention-catalog.md の pattern-7 検出条件に 600 秒 stagnate が含まれている" test_catalog_pattern7_stagnate_condition

# Test: pattern-7 の検出条件に '>>> 実装完了:' シグナルが含まれている
test_catalog_pattern7_completion_signal() {
  assert_file_exists "$INTERVENTION_CATALOG" || return 1
  assert_file_contains "$INTERVENTION_CATALOG" ">>> 実装完了:|実装完了"
}
run_test "intervention-catalog.md の pattern-7 検出条件に '>>> 実装完了:' が含まれている" test_catalog_pattern7_completion_signal

# Test: pattern-7 の修復手順に /twl:workflow-pr-verify の inject が定義されている
test_catalog_pattern7_inject_pr_verify() {
  assert_file_exists "$INTERVENTION_CATALOG" || return 1
  assert_file_contains "$INTERVENTION_CATALOG" "workflow-pr-verify|twl:workflow-pr-verify"
}
run_test "intervention-catalog.md の pattern-7 修復手順に /twl:workflow-pr-verify inject が定義されている" test_catalog_pattern7_inject_pr_verify

# Test: pattern-7 の事後処理に InterventionRecord 記録が定義されている
test_catalog_pattern7_intervention_record() {
  assert_file_exists "$INTERVENTION_CATALOG" || return 1
  python3 - "${PROJECT_ROOT}/${INTERVENTION_CATALOG}" <<'PYEOF'
import re, sys

with open(sys.argv[1]) as f:
    content = f.read()

# pattern-7 セクションを抽出（次のパターン見出しまで）
p7_match = re.search(r'(pattern-7|パターン\s*7).*?(?=###\s+パターン|###\s+pattern|\Z)', content, re.DOTALL | re.IGNORECASE)
if not p7_match:
    print('pattern-7 section not found', file=sys.stderr)
    sys.exit(1)

p7_content = p7_match.group(0)
if not re.search(r'InterventionRecord|intervention.*record', p7_content, re.IGNORECASE):
    print('InterventionRecord not found in pattern-7 section', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PYEOF
}
run_test "intervention-catalog.md の pattern-7 事後処理に InterventionRecord 記録が定義されている" test_catalog_pattern7_intervention_record

# Edge case: pattern-7 の inject 先が対象 Worker window であることが明記されている
test_catalog_pattern7_target_window() {
  assert_file_exists "$INTERVENTION_CATALOG" || return 1
  assert_file_contains "$INTERVENTION_CATALOG" "Worker.*window|window.*Worker|対象.*Worker|target.*window"
}
run_test "intervention-catalog.md [edge: pattern-7 inject 先が Worker window と明記されている]" test_catalog_pattern7_target_window

# Edge case: --spec issue-<N> 引数の形式が定義されている
test_catalog_pattern7_spec_arg_format() {
  assert_file_exists "$INTERVENTION_CATALOG" || return 1
  assert_file_contains "$INTERVENTION_CATALOG" "--spec issue-<N>|--spec issue-|spec issue"
}
run_test "intervention-catalog.md [edge: pattern-7 に --spec issue-<N> 引数形式が定義されている]" test_catalog_pattern7_spec_arg_format

# =============================================================================
# Requirement: Worker idle 検知パターン（intervention-catalog pattern-7）
# Scenario: 検出条件が部分的にしか満たされない場合 (spec line 43)
# WHEN: state stagnate は検出されたが '>>> 実装完了:' が含まれない
# THEN: pattern-7 ではなく Layer 1 Confirm（パターン4: Worker 長時間 idle）として処理
# =============================================================================
echo ""
echo "--- Requirement: stagnate のみ（完了シグナルなし）→ Layer 1 Confirm ---"

# Test: intervention-catalog.md に pattern-4 (Worker 長時間 idle) が Layer 1 Confirm に存在する
test_catalog_pattern4_layer1() {
  assert_file_exists "$INTERVENTION_CATALOG" || return 1
  python3 - "${PROJECT_ROOT}/${INTERVENTION_CATALOG}" <<'PYEOF'
import re, sys

with open(sys.argv[1]) as f:
    content = f.read()

layer1_match = re.search(r'## Layer 1.*?(?=## Layer [02]|\Z)', content, re.DOTALL | re.IGNORECASE)
if not layer1_match:
    print('Layer 1 section not found', file=sys.stderr)
    sys.exit(1)

layer1_content = layer1_match.group(0)
if not re.search(r'pattern-4|pattern 4|パターン\s*4', layer1_content, re.IGNORECASE):
    print('pattern-4 not found in Layer 1 Confirm section', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PYEOF
}
run_test "intervention-catalog.md に pattern-4 (Worker 長時間 idle) が Layer 1 Confirm に存在する" test_catalog_pattern4_layer1

# Edge case: pattern-7 の検出条件が AND 条件であることが明示されている
test_catalog_pattern7_and_condition() {
  assert_file_exists "$INTERVENTION_CATALOG" || return 1
  python3 - "${PROJECT_ROOT}/${INTERVENTION_CATALOG}" <<'PYEOF'
import re, sys

with open(sys.argv[1]) as f:
    content = f.read()

p7_match = re.search(r'(pattern-7|パターン\s*7).*?(?=###\s+パターン|###\s+pattern|\Z)', content, re.DOTALL | re.IGNORECASE)
if not p7_match:
    print('pattern-7 section not found', file=sys.stderr)
    sys.exit(1)

p7_content = p7_match.group(0)
# AND / かつ / both conditions
if not re.search(r'\bAND\b|かつ|両方|and.*condition', p7_content, re.IGNORECASE):
    print('AND condition not explicitly stated in pattern-7', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PYEOF
}
run_test "intervention-catalog.md [edge: pattern-7 の検出条件が AND 結合であることが明示されている]" test_catalog_pattern7_and_condition

# Edge case: pattern-7 完了シグナルなし時の Layer 1 Confirm フォールバックが記述されている
test_catalog_pattern7_fallback_to_pattern4() {
  assert_file_exists "$INTERVENTION_CATALOG" || return 1
  assert_file_contains "$INTERVENTION_CATALOG" "実装完了.*含まれない|含まれない.*Layer 1|pattern-4.*フォールバック|pattern-4.*fallback|Layer 1.*Confirm.*stagnate|stagnate.*pattern-4"
}
run_test "intervention-catalog.md [edge: '>>> 実装完了:' なし時に pattern-4 (Layer 1 Confirm) へのフォールバックが記述されている]" test_catalog_pattern7_fallback_to_pattern4

# =============================================================================
# Requirement: observe-once JSON 出力スキーマ拡張
# Scenario: JSON フィールド追加 (spec line 53)
# WHEN: observe-once を実行する
# THEN: 出力 JSON に stagnate_files: string[] フィールドを含む、既存フィールドは変更しない
# =============================================================================
echo ""
echo "--- Requirement: observe-once JSON スキーマ拡張 ---"

# Test: observe-once.md の JSON スキーマに stagnate_files フィールドが追加されている
test_observe_once_schema_extended() {
  assert_file_exists "$OBSERVE_ONCE_CMD" || return 1
  assert_file_contains "$OBSERVE_ONCE_CMD" "stagnate_files"
}
run_test "observe-once.md の JSON スキーマに stagnate_files が追加されている" test_observe_once_schema_extended

# Test: 既存フィールド window が残っている
test_observe_once_window_preserved() {
  assert_file_exists "$OBSERVE_ONCE_CMD" || return 1
  assert_file_contains "$OBSERVE_ONCE_CMD" "\"window\""
}
run_test "observe-once.md の既存フィールド 'window' が保持されている" test_observe_once_window_preserved

# Test: 既存フィールド timestamp が残っている
test_observe_once_timestamp_preserved() {
  assert_file_exists "$OBSERVE_ONCE_CMD" || return 1
  assert_file_contains "$OBSERVE_ONCE_CMD" "\"timestamp\""
}
run_test "observe-once.md の既存フィールド 'timestamp' が保持されている" test_observe_once_timestamp_preserved

# Test: 既存フィールド session_state が残っている
test_observe_once_session_state_preserved() {
  assert_file_exists "$OBSERVE_ONCE_CMD" || return 1
  assert_file_contains "$OBSERVE_ONCE_CMD" "\"session_state\""
}
run_test "observe-once.md の既存フィールド 'session_state' が保持されている" test_observe_once_session_state_preserved

# Edge case: stagnate_files が既存フィールドより後に追加されている（スキーマ拡張で前方互換）
test_observe_once_stagnate_files_appended() {
  assert_file_exists "$OBSERVE_ONCE_CMD" || return 1
  python3 - "${PROJECT_ROOT}/${OBSERVE_ONCE_CMD}" <<'PYEOF'
import re, sys

with open(sys.argv[1]) as f:
    content = f.read()

# JSON コードブロックを探す
json_blocks = re.findall(r'```json\s*(.*?)\s*```', content, re.DOTALL)

for block in json_blocks:
    if 'stagnate_files' in block and 'session_state' in block:
        # session_state が stagnate_files より前に出現するか確認
        session_pos = block.find('"session_state"')
        stagnate_pos = block.find('"stagnate_files"')
        if session_pos < stagnate_pos:
            sys.exit(0)  # 正しい順序

print('stagnate_files not found after session_state in any JSON block', file=sys.stderr)
sys.exit(1)
PYEOF
}
run_test "observe-once.md [edge: stagnate_files が session_state より後に追加されている（前方互換）]" test_observe_once_stagnate_files_appended

# Edge case: observe-once.md に mtime チェックの Step が追加されている
test_observe_once_mtime_step() {
  assert_file_exists "$OBSERVE_ONCE_CMD" || return 1
  assert_file_contains "$OBSERVE_ONCE_CMD" "Step.*mtime|mtime.*Step|Step.*stagnate"
}
run_test "observe-once.md [edge: mtime チェック用の Step が追加されている]" test_observe_once_mtime_step

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
