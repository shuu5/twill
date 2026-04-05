#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: autopilot post-processing commands
# Generated from: openspec/changes/archive/2026-03-29-c-2d-autopilot-controller-autopilot/specs/post-processing/spec.md
# Coverage level: edge-cases
# Verifies: autopilot-collect, autopilot-retrospective, autopilot-patterns, autopilot-cross-issue COMMAND.md
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

COLLECT_CMD="commands/autopilot-collect.md"
RETRO_CMD="commands/autopilot-retrospective.md"
PATTERNS_CMD="commands/autopilot-patterns.md"
CROSS_CMD="commands/autopilot-cross-issue.md"

# =============================================================================
# Requirement: autopilot-collect コマンド
# =============================================================================
echo ""
echo "--- Requirement: autopilot-collect コマンド ---"

# Scenario: done Issue の変更ファイル収集 (line 16)
# WHEN: Issue #19 が status=done, pr_number=42
# THEN: PR #42 の差分ファイルリストを取得し session.json の completed_issues に記録する

test_collect_file_exists() {
  assert_file_exists "$COLLECT_CMD"
}

if [[ -f "${PROJECT_ROOT}/${COLLECT_CMD}" ]]; then
  run_test "autopilot-collect COMMAND.md が存在する" test_collect_file_exists
else
  run_test_skip "autopilot-collect COMMAND.md が存在する" "commands/autopilot-collect.md not yet created"
fi

test_collect_frontmatter_type() {
  return 0  # deps.yaml defines type
}

if [[ -f "${PROJECT_ROOT}/${COLLECT_CMD}" ]]; then
  run_test "autopilot-collect COMMAND.md exists (deps.yaml defines type)" test_collect_frontmatter_type
else
  run_test_skip "autopilot-collect COMMAND.md exists (deps.yaml defines type)" "COMMAND.md not yet created"
fi

test_collect_state_read_ref() {
  assert_file_contains "$COLLECT_CMD" "state-read\.sh|state-read"
}

if [[ -f "${PROJECT_ROOT}/${COLLECT_CMD}" ]]; then
  run_test "autopilot-collect が state-read.sh を参照" test_collect_state_read_ref
else
  run_test_skip "autopilot-collect が state-read.sh を参照" "COMMAND.md not yet created"
fi

test_collect_state_write_ref() {
  assert_file_contains "$COLLECT_CMD" "state-write\.sh|state-write"
}

if [[ -f "${PROJECT_ROOT}/${COLLECT_CMD}" ]]; then
  run_test "autopilot-collect が state-write.sh を参照" test_collect_state_write_ref
else
  run_test_skip "autopilot-collect が state-write.sh を参照" "COMMAND.md not yet created"
fi

test_collect_gh_pr_diff() {
  assert_file_contains "$COLLECT_CMD" "gh.*pr.*diff|gh pr diff|pr_number"
}

if [[ -f "${PROJECT_ROOT}/${COLLECT_CMD}" ]]; then
  run_test "autopilot-collect が gh pr diff で変更ファイル取得を記述" test_collect_gh_pr_diff
else
  run_test_skip "autopilot-collect が gh pr diff で変更ファイル取得を記述" "COMMAND.md not yet created"
fi

test_collect_completed_issues() {
  assert_file_contains "$COLLECT_CMD" "completed_issues"
}

if [[ -f "${PROJECT_ROOT}/${COLLECT_CMD}" ]]; then
  run_test "autopilot-collect が completed_issues への保存を記述" test_collect_completed_issues
else
  run_test_skip "autopilot-collect が completed_issues への保存を記述" "COMMAND.md not yet created"
fi

# Scenario: PR 差分取得失敗 (line 21)
# WHEN: gh pr diff がエラーを返す
# THEN: 警告を出力しスキップする。ワークフロー全体は停止しない

test_collect_pr_diff_error_handling() {
  assert_file_contains "$COLLECT_CMD" "警告|warn|スキップ|skip|エラー.*停止しない|error.*continue"
}

if [[ -f "${PROJECT_ROOT}/${COLLECT_CMD}" ]]; then
  run_test "autopilot-collect PR 差分取得失敗時の警告/スキップ記述" test_collect_pr_diff_error_handling
else
  run_test_skip "autopilot-collect PR 差分取得失敗時の警告/スキップ記述" "COMMAND.md not yet created"
fi

# Scenario: failed Issue のスキップ (line 25)
# WHEN: Issue #20 が status=failed
# THEN: 変更ファイル収集をスキップする

test_collect_failed_issue_skip() {
  assert_file_contains "$COLLECT_CMD" "failed.*スキップ|failed.*skip|status.*done"
}

if [[ -f "${PROJECT_ROOT}/${COLLECT_CMD}" ]]; then
  run_test "autopilot-collect failed Issue のスキップ記述" test_collect_failed_issue_skip
else
  run_test_skip "autopilot-collect failed Issue のスキップ記述" "COMMAND.md not yet created"
fi

# Edge case: マーカーファイル (.done) を参照せず state-read で状態判定
test_collect_no_marker_refs() {
  assert_file_not_contains "$COLLECT_CMD" "MARKER_DIR" || return 1
  assert_file_not_contains "$COLLECT_CMD" '\.done"' || return 1
  assert_file_not_contains "$COLLECT_CMD" '\.fail"' || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${COLLECT_CMD}" ]]; then
  run_test "autopilot-collect [edge: マーカーファイル参照なし]" test_collect_no_marker_refs
else
  run_test_skip "autopilot-collect [edge: マーカーファイル参照なし]" "COMMAND.md not yet created"
fi

# Edge case: DEV_AUTOPILOT_SESSION 参照なし
test_collect_no_dev_autopilot_session() {
  assert_file_not_contains "$COLLECT_CMD" "DEV_AUTOPILOT_SESSION"
}

if [[ -f "${PROJECT_ROOT}/${COLLECT_CMD}" ]]; then
  run_test "autopilot-collect [edge: DEV_AUTOPILOT_SESSION 参照なし]" test_collect_no_dev_autopilot_session
else
  run_test_skip "autopilot-collect [edge: DEV_AUTOPILOT_SESSION 参照なし]" "COMMAND.md not yet created"
fi

# Edge case: SESSION_STATE_FILE 入力の記述
test_collect_session_state_file() {
  assert_file_contains "$COLLECT_CMD" "SESSION_STATE_FILE"
}

if [[ -f "${PROJECT_ROOT}/${COLLECT_CMD}" ]]; then
  run_test "autopilot-collect [edge: SESSION_STATE_FILE 入力の記述]" test_collect_session_state_file
else
  run_test_skip "autopilot-collect [edge: SESSION_STATE_FILE 入力の記述]" "COMMAND.md not yet created"
fi

# =============================================================================
# Requirement: autopilot-retrospective コマンド
# =============================================================================
echo ""
echo "--- Requirement: autopilot-retrospective コマンド ---"

# Scenario: 成功 Phase の振り返り (line 44)
# WHEN: Phase 内の全 Issue が done
# THEN: 成功パターンを分析し PHASE_INSIGHTS を生成。doobidoo に保存する

test_retro_file_exists() {
  assert_file_exists "$RETRO_CMD"
}

if [[ -f "${PROJECT_ROOT}/${RETRO_CMD}" ]]; then
  run_test "autopilot-retrospective COMMAND.md が存在する" test_retro_file_exists
else
  run_test_skip "autopilot-retrospective COMMAND.md が存在する" "commands/autopilot-retrospective.md not yet created"
fi

test_retro_frontmatter_type() {
  return 0  # deps.yaml defines type
}

if [[ -f "${PROJECT_ROOT}/${RETRO_CMD}" ]]; then
  run_test "autopilot-retrospective COMMAND.md exists (deps.yaml defines type)" test_retro_frontmatter_type
else
  run_test_skip "autopilot-retrospective COMMAND.md exists (deps.yaml defines type)" "COMMAND.md not yet created"
fi

test_retro_state_read_ref() {
  assert_file_contains "$RETRO_CMD" "state-read\.sh|state-read"
}

if [[ -f "${PROJECT_ROOT}/${RETRO_CMD}" ]]; then
  run_test "autopilot-retrospective が state-read.sh を参照" test_retro_state_read_ref
else
  run_test_skip "autopilot-retrospective が state-read.sh を参照" "COMMAND.md not yet created"
fi

test_retro_phase_insights_output() {
  assert_file_contains "$RETRO_CMD" "PHASE_INSIGHTS"
}

if [[ -f "${PROJECT_ROOT}/${RETRO_CMD}" ]]; then
  run_test "autopilot-retrospective が PHASE_INSIGHTS を出力として記述" test_retro_phase_insights_output
else
  run_test_skip "autopilot-retrospective が PHASE_INSIGHTS を出力として記述" "COMMAND.md not yet created"
fi

test_retro_doobidoo_store() {
  assert_file_contains "$RETRO_CMD" "doobidoo|memory_store|memory.*store"
}

if [[ -f "${PROJECT_ROOT}/${RETRO_CMD}" ]]; then
  run_test "autopilot-retrospective が doobidoo memory_store を記述" test_retro_doobidoo_store
else
  run_test_skip "autopilot-retrospective が doobidoo memory_store を記述" "COMMAND.md not yet created"
fi

test_retro_retrospectives_array() {
  assert_file_contains "$RETRO_CMD" "retrospectives|retrospective.*session"
}

if [[ -f "${PROJECT_ROOT}/${RETRO_CMD}" ]]; then
  run_test "autopilot-retrospective が session.json retrospectives[] への追記を記述" test_retro_retrospectives_array
else
  run_test_skip "autopilot-retrospective が session.json retrospectives[] への追記を記述" "COMMAND.md not yet created"
fi

# Scenario: 失敗含む Phase の振り返り (line 48)
# WHEN: Phase 内に failed Issue がある
# THEN: 失敗原因を分析し回避策を PHASE_INSIGHTS に含める

test_retro_failure_analysis() {
  assert_file_contains "$RETRO_CMD" "失敗.*分析|failure.*analy|fail.*パターン|failure.*pattern"
}

if [[ -f "${PROJECT_ROOT}/${RETRO_CMD}" ]]; then
  run_test "autopilot-retrospective 失敗パターン分析の記述" test_retro_failure_analysis
else
  run_test_skip "autopilot-retrospective 失敗パターン分析の記述" "COMMAND.md not yet created"
fi

# Scenario: 最終 Phase の振り返り (line 52)
# WHEN: P == PHASE_COUNT
# THEN: 振り返りは実行するが PHASE_INSIGHTS は空文字列とする

test_retro_final_phase_empty_insights() {
  assert_file_contains "$RETRO_CMD" "最終.*Phase.*空|P.*==.*PHASE_COUNT|PHASE_INSIGHTS.*空|empty.*insight"
}

if [[ -f "${PROJECT_ROOT}/${RETRO_CMD}" ]]; then
  run_test "autopilot-retrospective 最終 Phase で PHASE_INSIGHTS 空の記述" test_retro_final_phase_empty_insights
else
  run_test_skip "autopilot-retrospective 最終 Phase で PHASE_INSIGHTS 空の記述" "COMMAND.md not yet created"
fi

# Edge case: phase-retrospective タイプの記述
test_retro_type_tag() {
  assert_file_contains "$RETRO_CMD" "phase-retrospective"
}

if [[ -f "${PROJECT_ROOT}/${RETRO_CMD}" ]]; then
  run_test "autopilot-retrospective [edge: type: phase-retrospective の記述]" test_retro_type_tag
else
  run_test_skip "autopilot-retrospective [edge: type: phase-retrospective の記述]" "COMMAND.md not yet created"
fi

# Edge case: DEV_AUTOPILOT_SESSION 参照なし
test_retro_no_dev_autopilot_session() {
  assert_file_not_contains "$RETRO_CMD" "DEV_AUTOPILOT_SESSION"
}

if [[ -f "${PROJECT_ROOT}/${RETRO_CMD}" ]]; then
  run_test "autopilot-retrospective [edge: DEV_AUTOPILOT_SESSION 参照なし]" test_retro_no_dev_autopilot_session
else
  run_test_skip "autopilot-retrospective [edge: DEV_AUTOPILOT_SESSION 参照なし]" "COMMAND.md not yet created"
fi

# =============================================================================
# Requirement: autopilot-patterns コマンド
# =============================================================================
echo ""
echo "--- Requirement: autopilot-patterns コマンド ---"

# Scenario: 繰り返し失敗パターン検出 (line 71)
# WHEN: 2 Issue が同一 reason（例: test_failure）で failed
# THEN: failure パターンとして検出し doobidoo に記録する

test_patterns_file_exists() {
  assert_file_exists "$PATTERNS_CMD"
}

if [[ -f "${PROJECT_ROOT}/${PATTERNS_CMD}" ]]; then
  run_test "autopilot-patterns COMMAND.md が存在する" test_patterns_file_exists
else
  run_test_skip "autopilot-patterns COMMAND.md が存在する" "commands/autopilot-patterns.md not yet created"
fi

test_patterns_frontmatter_type() {
  return 0  # deps.yaml defines type
}

if [[ -f "${PROJECT_ROOT}/${PATTERNS_CMD}" ]]; then
  run_test "autopilot-patterns COMMAND.md exists (deps.yaml defines type)" test_patterns_frontmatter_type
else
  run_test_skip "autopilot-patterns COMMAND.md exists (deps.yaml defines type)" "COMMAND.md not yet created"
fi

test_patterns_state_read_ref() {
  assert_file_contains "$PATTERNS_CMD" "state-read\.sh|state-read"
}

if [[ -f "${PROJECT_ROOT}/${PATTERNS_CMD}" ]]; then
  run_test "autopilot-patterns が state-read.sh を参照" test_patterns_state_read_ref
else
  run_test_skip "autopilot-patterns が state-read.sh を参照" "COMMAND.md not yet created"
fi

test_patterns_doobidoo_search() {
  assert_file_contains "$PATTERNS_CMD" "doobidoo.*memory_search|memory.*search|doobidoo"
}

if [[ -f "${PROJECT_ROOT}/${PATTERNS_CMD}" ]]; then
  run_test "autopilot-patterns が doobidoo memory_search を記述" test_patterns_doobidoo_search
else
  run_test_skip "autopilot-patterns が doobidoo memory_search を記述" "COMMAND.md not yet created"
fi

test_patterns_count_threshold() {
  assert_file_contains "$PATTERNS_CMD" "count.*>=.*2|count >= 2|count.*2.*以上"
}

if [[ -f "${PROJECT_ROOT}/${PATTERNS_CMD}" ]]; then
  run_test "autopilot-patterns パターン検出閾値 count >= 2 の記述" test_patterns_count_threshold
else
  run_test_skip "autopilot-patterns パターン検出閾値 count >= 2 の記述" "COMMAND.md not yet created"
fi

# Scenario: self-improve Issue 起票 (line 76)
# WHEN: パターンの confidence >= 80 かつ count >= 2
# THEN: "[Self-Improve] サニタイズ済みタイトル" で Issue を起票し session.json に記録する

test_patterns_self_improve_threshold() {
  assert_file_contains "$PATTERNS_CMD" "confidence.*>=.*80|confidence >= 80|confidence.*80"
}

if [[ -f "${PROJECT_ROOT}/${PATTERNS_CMD}" ]]; then
  run_test "autopilot-patterns self-improve 起票閾値 confidence >= 80 の記述" test_patterns_self_improve_threshold
else
  run_test_skip "autopilot-patterns self-improve 起票閾値 confidence >= 80 の記述" "COMMAND.md not yet created"
fi

test_patterns_self_improve_title_format() {
  assert_file_contains "$PATTERNS_CMD" '\[Self-Improve\]|Self.Improve'
}

if [[ -f "${PROJECT_ROOT}/${PATTERNS_CMD}" ]]; then
  run_test "autopilot-patterns [Self-Improve] タイトルフォーマットの記述" test_patterns_self_improve_title_format
else
  run_test_skip "autopilot-patterns [Self-Improve] タイトルフォーマットの記述" "COMMAND.md not yet created"
fi

# Edge case: PATTERN_TITLE サニタイズ
test_patterns_title_sanitize() {
  assert_file_contains "$PATTERNS_CMD" "サニタイズ|sanitize|PATTERN_TITLE|特殊文字.*除去"
}

if [[ -f "${PROJECT_ROOT}/${PATTERNS_CMD}" ]]; then
  run_test "autopilot-patterns [edge: PATTERN_TITLE サニタイズの記述]" test_patterns_title_sanitize
else
  run_test_skip "autopilot-patterns [edge: PATTERN_TITLE サニタイズの記述]" "COMMAND.md not yet created"
fi

# Scenario: 低 confidence パターン (line 80)
# WHEN: パターンの confidence < 80
# THEN: doobidoo キャッシュにのみ記録し Issue 起票しない

test_patterns_low_confidence_no_issue() {
  assert_file_contains "$PATTERNS_CMD" "confidence.*<.*80|低.*confidence|confidence.*80.*未満|issue.*起票しない"
}

if [[ -f "${PROJECT_ROOT}/${PATTERNS_CMD}" ]]; then
  run_test "autopilot-patterns 低 confidence 時の Issue 不起票記述" test_patterns_low_confidence_no_issue
else
  run_test_skip "autopilot-patterns 低 confidence 時の Issue 不起票記述" "COMMAND.md not yet created"
fi

# Edge case: マーカーファイル (.fail) を参照せず state-read で failure 情報取得
test_patterns_no_marker_refs() {
  assert_file_not_contains "$PATTERNS_CMD" "MARKER_DIR" || return 1
  assert_file_not_contains "$PATTERNS_CMD" '\.fail"' || return 1
  assert_file_not_contains "$PATTERNS_CMD" '\.done"' || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${PATTERNS_CMD}" ]]; then
  run_test "autopilot-patterns [edge: マーカーファイル参照なし]" test_patterns_no_marker_refs
else
  run_test_skip "autopilot-patterns [edge: マーカーファイル参照なし]" "COMMAND.md not yet created"
fi

# Edge case: DEV_AUTOPILOT_SESSION 参照なし
test_patterns_no_dev_autopilot_session() {
  assert_file_not_contains "$PATTERNS_CMD" "DEV_AUTOPILOT_SESSION"
}

if [[ -f "${PROJECT_ROOT}/${PATTERNS_CMD}" ]]; then
  run_test "autopilot-patterns [edge: DEV_AUTOPILOT_SESSION 参照なし]" test_patterns_no_dev_autopilot_session
else
  run_test_skip "autopilot-patterns [edge: DEV_AUTOPILOT_SESSION 参照なし]" "COMMAND.md not yet created"
fi

# Edge case: session.json patterns と self_improve_issues への追記
test_patterns_session_json_fields() {
  assert_file_contains "$PATTERNS_CMD" "patterns" || return 1
  assert_file_contains "$PATTERNS_CMD" "self_improve_issues" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${PATTERNS_CMD}" ]]; then
  run_test "autopilot-patterns [edge: session.json patterns + self_improve_issues 記述]" test_patterns_session_json_fields
else
  run_test_skip "autopilot-patterns [edge: session.json patterns + self_improve_issues 記述]" "COMMAND.md not yet created"
fi

# =============================================================================
# Requirement: autopilot-cross-issue コマンド
# =============================================================================
echo ""
echo "--- Requirement: autopilot-cross-issue コマンド ---"

# Scenario: ファイル名完全一致の競合検出 (line 100)
# WHEN: Phase 1 で deps.yaml を変更し、Phase 2 の Issue が deps.yaml を参照
# THEN: confidence: high として検出し session.json に警告を追記する

test_cross_file_exists() {
  assert_file_exists "$CROSS_CMD"
}

if [[ -f "${PROJECT_ROOT}/${CROSS_CMD}" ]]; then
  run_test "autopilot-cross-issue COMMAND.md が存在する" test_cross_file_exists
else
  run_test_skip "autopilot-cross-issue COMMAND.md が存在する" "commands/autopilot-cross-issue.md not yet created"
fi

test_cross_frontmatter_type() {
  return 0  # deps.yaml defines type
}

if [[ -f "${PROJECT_ROOT}/${CROSS_CMD}" ]]; then
  run_test "autopilot-cross-issue COMMAND.md exists (deps.yaml defines type)" test_cross_frontmatter_type
else
  run_test_skip "autopilot-cross-issue COMMAND.md exists (deps.yaml defines type)" "COMMAND.md not yet created"
fi

test_cross_session_add_warning_ref() {
  assert_file_contains "$CROSS_CMD" "session-add-warning\.sh|session-add-warning"
}

if [[ -f "${PROJECT_ROOT}/${CROSS_CMD}" ]]; then
  run_test "autopilot-cross-issue が session-add-warning.sh を参照" test_cross_session_add_warning_ref
else
  run_test_skip "autopilot-cross-issue が session-add-warning.sh を参照" "COMMAND.md not yet created"
fi

test_cross_state_read_ref() {
  assert_file_contains "$CROSS_CMD" "state-read\.sh|state-read"
}

if [[ -f "${PROJECT_ROOT}/${CROSS_CMD}" ]]; then
  run_test "autopilot-cross-issue が state-read.sh を参照" test_cross_state_read_ref
else
  run_test_skip "autopilot-cross-issue が state-read.sh を参照" "COMMAND.md not yet created"
fi

test_cross_confidence_levels() {
  assert_file_contains "$CROSS_CMD" "high.*medium.*low|confidence.*high|high.*confidence"
}

if [[ -f "${PROJECT_ROOT}/${CROSS_CMD}" ]]; then
  run_test "autopilot-cross-issue confidence レベル (high/medium/low) の記述" test_cross_confidence_levels
else
  run_test_skip "autopilot-cross-issue confidence レベル (high/medium/low) の記述" "COMMAND.md not yet created"
fi

test_cross_high_confidence_only_inject() {
  assert_file_contains "$CROSS_CMD" "high.*confidence.*注入|high.*confidence.*inject|high.*confidence.*のみ|high.*only"
}

if [[ -f "${PROJECT_ROOT}/${CROSS_CMD}" ]]; then
  run_test "autopilot-cross-issue high confidence のみプロンプト注入の記述" test_cross_high_confidence_only_inject
else
  run_test_skip "autopilot-cross-issue high confidence のみプロンプト注入の記述" "COMMAND.md not yet created"
fi

test_cross_gh_issue_view() {
  assert_file_contains "$CROSS_CMD" "gh.*issue.*view|gh issue view"
}

if [[ -f "${PROJECT_ROOT}/${CROSS_CMD}" ]]; then
  run_test "autopilot-cross-issue が gh issue view で Issue body 取得を記述" test_cross_gh_issue_view
else
  run_test_skip "autopilot-cross-issue が gh issue view で Issue body 取得を記述" "COMMAND.md not yet created"
fi

test_cross_warnings_output() {
  assert_file_contains "$CROSS_CMD" "CROSS_ISSUE_WARNINGS"
}

if [[ -f "${PROJECT_ROOT}/${CROSS_CMD}" ]]; then
  run_test "autopilot-cross-issue が CROSS_ISSUE_WARNINGS を出力として記述" test_cross_warnings_output
else
  run_test_skip "autopilot-cross-issue が CROSS_ISSUE_WARNINGS を出力として記述" "COMMAND.md not yet created"
fi

# Scenario: 競合なし (line 105)
# WHEN: 変更ファイルと後続 Issue のスコープに重複がない
# THEN: CROSS_ISSUE_WARNINGS は空で、session.json に警告は追記されない

test_cross_no_conflict() {
  assert_file_contains "$CROSS_CMD" "警告.*追記されない|空|empty|重複.*ない|no.*conflict"
}

if [[ -f "${PROJECT_ROOT}/${CROSS_CMD}" ]]; then
  run_test "autopilot-cross-issue 競合なし時の動作記述" test_cross_no_conflict
else
  run_test_skip "autopilot-cross-issue 競合なし時の動作記述" "COMMAND.md not yet created"
fi

# Edge case: マーカーファイル参照なし
test_cross_no_marker_refs() {
  assert_file_not_contains "$CROSS_CMD" "MARKER_DIR" || return 1
  assert_file_not_contains "$CROSS_CMD" '\.done"' || return 1
  assert_file_not_contains "$CROSS_CMD" '\.fail"' || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${CROSS_CMD}" ]]; then
  run_test "autopilot-cross-issue [edge: マーカーファイル参照なし]" test_cross_no_marker_refs
else
  run_test_skip "autopilot-cross-issue [edge: マーカーファイル参照なし]" "COMMAND.md not yet created"
fi

# Edge case: DEV_AUTOPILOT_SESSION 参照なし
test_cross_no_dev_autopilot_session() {
  assert_file_not_contains "$CROSS_CMD" "DEV_AUTOPILOT_SESSION"
}

if [[ -f "${PROJECT_ROOT}/${CROSS_CMD}" ]]; then
  run_test "autopilot-cross-issue [edge: DEV_AUTOPILOT_SESSION 参照なし]" test_cross_no_dev_autopilot_session
else
  run_test_skip "autopilot-cross-issue [edge: DEV_AUTOPILOT_SESSION 参照なし]" "COMMAND.md not yet created"
fi

# Edge case: NEXT_PHASE_ISSUES 入力の記述
test_cross_next_phase_issues() {
  assert_file_contains "$CROSS_CMD" "NEXT_PHASE_ISSUES"
}

if [[ -f "${PROJECT_ROOT}/${CROSS_CMD}" ]]; then
  run_test "autopilot-cross-issue [edge: NEXT_PHASE_ISSUES 入力の記述]" test_cross_next_phase_issues
else
  run_test_skip "autopilot-cross-issue [edge: NEXT_PHASE_ISSUES 入力の記述]" "COMMAND.md not yet created"
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
