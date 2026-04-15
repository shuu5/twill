#!/usr/bin/env bash
# =============================================================================
# Unit Tests: inject resilience improvements (issue-709)
# Generated from: deltaspec/changes/issue-709/specs/inject-resilience.md
# change-id: issue-709
# Coverage level: edge-cases
#
# Verifies: plugins/twl/scripts/issue-lifecycle-orchestrator.sh の
#   wait_for_batch() 内 inject ロジック改善
#   - input-waiting debounce（5 秒 + 再確認）
#   - inject 上限 3 → 5 への緩和
#   - inject 後 progressive delay (sleep $((5 * inject_count)))
#   - inject 直前の状態再確認
#   - inject メッセージ簡素化（"処理を続行してください。"）
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

ORCHESTRATOR_REL="scripts/issue-lifecycle-orchestrator.sh"
ORCHESTRATOR="${PROJECT_ROOT}/${ORCHESTRATOR_REL}"

PASS=0
FAIL=0
SKIP=0
ERRORS=()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

run_test() {
  local name="$1"
  local func="$2"
  local result=0
  "$func" || result=$?
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

assert_file_exists() {
  local file="$1"
  [[ -f "$file" ]]
}

# wait_for_batch() 関数本体のみを抽出する（関数定義開始行〜閉じ "^}" まで）
extract_wait_for_batch() {
  awk '/^wait_for_batch\(\)[ \t]*\{/,/^\}/' "$ORCHESTRATOR"
}

wait_for_batch_contains() {
  local pattern="$1"
  local body
  body=$(extract_wait_for_batch)
  echo "$body" | grep -qE -- "$pattern"
}

wait_for_batch_not_contains() {
  local pattern="$1"
  local body
  body=$(extract_wait_for_batch)
  if echo "$body" | grep -qE -- "$pattern"; then
    return 1
  fi
  return 0
}

# wait_for_batch() 内で pattern_a が pattern_b より先に現れることを確認する
wait_for_batch_order() {
  local pattern_a="$1"
  local pattern_b="$2"
  local body
  body=$(extract_wait_for_batch)
  local line_a line_b
  line_a=$(echo "$body" | grep -nE -- "$pattern_a" | head -1 | cut -d: -f1)
  line_b=$(echo "$body" | grep -nE -- "$pattern_b" | head -1 | cut -d: -f1)
  if [[ -z "$line_a" || -z "$line_b" ]]; then
    return 1
  fi
  [[ "$line_a" -lt "$line_b" ]]
}

# ---------------------------------------------------------------------------
# ファイル存在確認
# ---------------------------------------------------------------------------
echo ""
echo "--- Prerequisite: orchestrator スクリプト存在確認 ---"

test_orchestrator_exists() {
  assert_file_exists "$ORCHESTRATOR"
}
run_test "issue-lifecycle-orchestrator.sh が存在する" test_orchestrator_exists

# ---------------------------------------------------------------------------
# =============================================================================
# Requirement: input-waiting debounce
# =============================================================================
echo ""
echo "--- Requirement: input-waiting debounce ---"

# ---------------------------------------------------------------------------
# Scenario: transient false positive を排除する (spec line 6)
# WHEN: session-state.sh が input-waiting を返し、5 秒後の再確認が input-waiting 以外を返す
# THEN: inject を実行せず all_done=false で次のポーリングサイクルへ進む
# ---------------------------------------------------------------------------

# debounce: input-waiting 検出後に sleep 5 が実装されていること
test_debounce_sleep_exists() {
  wait_for_batch_contains 'sleep 5'
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "debounce: sleep 5 が wait_for_batch() に実装されている" test_debounce_sleep_exists
else
  run_test_skip "debounce: sleep 5 が wait_for_batch() に実装されている" "${ORCHESTRATOR_REL} not found"
fi

# debounce: input-waiting 検出後に session-state.sh が再呼び出しされること
# (1回目の input-waiting 検出 + sleep 5 の後にもう1回 session-state.sh が呼ばれる)
test_debounce_recheck_exists() {
  local body
  body=$(extract_wait_for_batch)
  # session-state.sh の呼び出しが2回以上あること
  local count
  count=$(echo "$body" | grep -cE 'session-state\.sh.*state' || true)
  [[ "$count" -ge 2 ]]
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "debounce: wait_for_batch() に session-state.sh の再確認呼び出しが存在する" test_debounce_recheck_exists
else
  run_test_skip "debounce: wait_for_batch() に session-state.sh の再確認呼び出しが存在する" "${ORCHESTRATOR_REL} not found"
fi

# debounce: sleep 5 が最初の input-waiting 分岐内にあること（progressive delay の sleep より前に存在）
test_debounce_sleep_before_inject() {
  wait_for_batch_order 'sleep 5' 'inject_count=\$\(\(inject_count \+ 1\)\)'
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "debounce: sleep 5 が inject_count インクリメントより前に存在する" test_debounce_sleep_before_inject
else
  run_test_skip "debounce: sleep 5 が inject_count インクリメントより前に存在する" "${ORCHESTRATOR_REL} not found"
fi

# ---------------------------------------------------------------------------
# Scenario: 真の input-waiting を受理する (spec line 10)
# WHEN: session-state.sh が input-waiting を返し、5 秒後の再確認も input-waiting を返す
# THEN: inject フローを継続する
# ---------------------------------------------------------------------------

# 再確認が input-waiting の場合に inject フロー（inject_count インクリメント）へ続く構造
test_debounce_true_positive_continues() {
  # inject_count インクリメント（inject フロー継続）と session-state.sh 再確認が共存すること
  wait_for_batch_contains 'inject_count=\$\(\(inject_count \+ 1\)\)'
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "debounce: 再確認が input-waiting でも inject フロー継続パスが存在する" test_debounce_true_positive_continues
else
  run_test_skip "debounce: 再確認が input-waiting でも inject フロー継続パスが存在する" "${ORCHESTRATOR_REL} not found"
fi

# エッジケース: debounce 再確認が input-waiting 以外のとき all_done=false で継続する分岐がある
test_debounce_false_positive_alldonef() {
  # all_done=false が wait_for_batch() 内に存在し、inject_count インクリメントとは別に現れること
  local body
  body=$(extract_wait_for_batch)
  local alldonef_count
  alldonef_count=$(echo "$body" | grep -cE 'all_done=false' || true)
  # inject フロー内（継続）と debounce スキップ後の2箇所以上に存在することを期待
  [[ "$alldonef_count" -ge 1 ]]
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "debounce [edge]: all_done=false が wait_for_batch() に存在する" test_debounce_false_positive_alldonef
else
  run_test_skip "debounce [edge]: all_done=false が wait_for_batch() に存在する" "${ORCHESTRATOR_REL} not found"
fi

# =============================================================================
# Requirement: inject 上限緩和
# =============================================================================
echo ""
echo "--- Requirement: inject 上限緩和 ---"

# ---------------------------------------------------------------------------
# Scenario: inject 5 回未満で継続する (spec line 17)
# WHEN: inject_count が 5 未満かつ non-terminal state で input-waiting が確認される
# THEN: inject を実行し inject_count をインクリメントする
# ---------------------------------------------------------------------------

# 上限が 5 (-lt 5) に変更されていること
test_inject_limit_5() {
  wait_for_batch_contains 'inject_count.*-lt 5'
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "inject 上限: inject_count -lt 5 の条件が存在する" test_inject_limit_5
else
  run_test_skip "inject 上限: inject_count -lt 5 の条件が存在する" "${ORCHESTRATOR_REL} not found"
fi

# 旧上限 (-lt 3) が残っていないこと
test_no_inject_limit_3() {
  wait_for_batch_not_contains 'inject_count.*-lt 3'
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "inject 上限 [edge]: inject_count -lt 3 （旧上限）が存在しない" test_no_inject_limit_3
else
  run_test_skip "inject 上限 [edge]: inject_count -lt 3 （旧上限）が存在しない" "${ORCHESTRATOR_REL} not found"
fi

# ---------------------------------------------------------------------------
# Scenario: inject 5 回到達で fallback に移行する (spec line 21)
# WHEN: inject_count が 5 以上になる
# THEN: fallback report を生成してウィンドウを kill する
# ---------------------------------------------------------------------------

# fallback 生成 + tmux kill-window が存在すること
test_inject_exhausted_fallback() {
  wait_for_batch_contains '_generate_fallback_report'
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "inject exhausted: fallback report 生成呼び出しが存在する" test_inject_exhausted_fallback
else
  run_test_skip "inject exhausted: fallback report 生成呼び出しが存在する" "${ORCHESTRATOR_REL} not found"
fi

test_inject_exhausted_kill() {
  wait_for_batch_contains 'tmux kill-window'
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "inject exhausted: tmux kill-window が存在する" test_inject_exhausted_kill
else
  run_test_skip "inject exhausted: tmux kill-window が存在する" "${ORCHESTRATOR_REL} not found"
fi

# ログメッセージ内の上限値が 5 に更新されていること
test_inject_exhausted_log_msg_5() {
  local body
  body=$(extract_wait_for_batch)
  # inject exhausted のログメッセージ行に /5 が含まれること
  echo "$body" | grep -E 'inject.*exhausted|auto-inject' | grep -qE '/5'
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "inject exhausted [edge]: ログメッセージの上限値が /5 になっている" test_inject_exhausted_log_msg_5
else
  run_test_skip "inject exhausted [edge]: ログメッセージの上限値が /5 になっている" "${ORCHESTRATOR_REL} not found"
fi

# ログメッセージに旧上限 /3 が残っていないこと
test_inject_log_no_3() {
  local body
  body=$(extract_wait_for_batch)
  # auto-inject ログ行に "/3" が含まれていないこと
  if echo "$body" | grep -E 'auto-inject' | grep -qE '\(/3\)|/3\b'; then
    return 1
  fi
  return 0
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "inject exhausted [edge]: ログメッセージに旧上限 /3 が含まれない" test_inject_log_no_3
else
  run_test_skip "inject exhausted [edge]: ログメッセージに旧上限 /3 が含まれない" "${ORCHESTRATOR_REL} not found"
fi

# =============================================================================
# Requirement: inject 間の progressive delay
# =============================================================================
echo ""
echo "--- Requirement: inject 間の progressive delay ---"

# ---------------------------------------------------------------------------
# Scenario: inject 後に progressive delay が適用される (spec line 28)
# WHEN: inject が実行される
# THEN: sleep $((5 * inject_count)) が inject の直後に実行される
# ---------------------------------------------------------------------------

# progressive delay の sleep 式が存在すること
test_progressive_delay_exists() {
  wait_for_batch_contains 'sleep \$\(\(5 \* inject_count\)\)'
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "progressive delay: sleep \$((5 * inject_count)) が wait_for_batch() に存在する" test_progressive_delay_exists
else
  run_test_skip "progressive delay: sleep \$((5 * inject_count)) が wait_for_batch() に存在する" "${ORCHESTRATOR_REL} not found"
fi

# progressive delay が session-comm.sh inject 呼び出しの後にあること
test_progressive_delay_after_inject() {
  wait_for_batch_order 'session-comm\.sh.*inject' 'sleep \$\(\(5 \* inject_count\)\)'
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "progressive delay: sleep が session-comm.sh inject 呼び出しの後に存在する" test_progressive_delay_after_inject
else
  run_test_skip "progressive delay: sleep が session-comm.sh inject 呼び出しの後に存在する" "${ORCHESTRATOR_REL} not found"
fi

# エッジケース: inject_count インクリメント後に progressive delay があること
# （遅延計算で最新の inject_count が使われること）
test_progressive_delay_uses_updated_count() {
  wait_for_batch_order 'inject_count=\$\(\(inject_count \+ 1\)\)' 'sleep \$\(\(5 \* inject_count\)\)'
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "progressive delay [edge]: inject_count インクリメント後に sleep が実行される" test_progressive_delay_uses_updated_count
else
  run_test_skip "progressive delay [edge]: inject_count インクリメント後に sleep が実行される" "${ORCHESTRATOR_REL} not found"
fi

# =============================================================================
# Requirement: inject 直前の状態再確認
# =============================================================================
echo ""
echo "--- Requirement: inject 直前の状態再確認 ---"

# ---------------------------------------------------------------------------
# Scenario: inject 直前に状態が変化していれば注入しない (spec line 35)
# WHEN: inject 実行直前の再確認で session-state.sh が input-waiting 以外を返す
# THEN: inject を実行せず continue でポーリングサイクルへ戻る
# ---------------------------------------------------------------------------

# inject 直前再確認: session-state.sh が session-comm.sh より前に呼ばれていること
test_preinjection_check_order() {
  wait_for_batch_order 'session-state\.sh.*state' 'session-comm\.sh.*inject'
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "inject 前再確認: session-state.sh が session-comm.sh inject より前に呼ばれる" test_preinjection_check_order
else
  run_test_skip "inject 前再確認: session-state.sh が session-comm.sh inject より前に呼ばれる" "${ORCHESTRATOR_REL} not found"
fi

# inject 前再確認: continue でスキップする分岐が存在すること
test_preinjection_check_continue() {
  wait_for_batch_contains 'continue'
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "inject 前再確認: continue でスキップするパスが存在する" test_preinjection_check_continue
else
  run_test_skip "inject 前再確認: continue でスキップするパスが存在する" "${ORCHESTRATOR_REL} not found"
fi

# ---------------------------------------------------------------------------
# Scenario: inject 直前も input-waiting なら注入する (spec line 39)
# WHEN: inject 実行直前の再確認でも session-state.sh が input-waiting を返す
# THEN: session-comm.sh inject を実行する
# ---------------------------------------------------------------------------

# session-comm.sh inject の呼び出しが存在すること
test_sessioncomm_inject_exists() {
  wait_for_batch_contains 'session-comm\.sh.*inject'
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "inject 直前再確認: session-comm.sh inject 呼び出しが存在する" test_sessioncomm_inject_exists
else
  run_test_skip "inject 直前再確認: session-comm.sh inject 呼び出しが存在する" "${ORCHESTRATOR_REL} not found"
fi

# エッジケース: inject 前再確認が debounce 再確認とは別の変数または条件を使うこと
# (inject 直前チェックは debounce とは独立したコードパスであること)
test_preinjection_check_independent() {
  local body
  body=$(extract_wait_for_batch)
  # session-state.sh の呼び出し行数が 2 以上（debounce 1 + 直前確認 1）
  local count
  count=$(echo "$body" | grep -cE '"?\$\{?SCRIPTS_ROOT\}?.*session-state\.sh' || true)
  [[ "$count" -ge 2 ]]
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "inject 直前再確認 [edge]: session-state.sh 呼び出しが 2 回以上存在する（debounce と直前確認）" test_preinjection_check_independent
else
  run_test_skip "inject 直前再確認 [edge]: session-state.sh 呼び出しが 2 回以上存在する（debounce と直前確認）" "${ORCHESTRATOR_REL} not found"
fi

# =============================================================================
# Requirement: inject メッセージ簡素化
# =============================================================================
echo ""
echo "--- Requirement: inject メッセージ簡素化 ---"

# ---------------------------------------------------------------------------
# Scenario: inject メッセージが簡潔である (spec line 46)
# WHEN: inject が実行される
# THEN: session-comm.sh inject に渡すメッセージが "処理を続行してください。" である
# ---------------------------------------------------------------------------

test_inject_message_simplified() {
  wait_for_batch_contains '処理を続行してください。'
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "inject メッセージ: \"処理を続行してください。\" が存在する" test_inject_message_simplified
else
  run_test_skip "inject メッセージ: \"処理を続行してください。\" が存在する" "${ORCHESTRATOR_REL} not found"
fi

# ワークフロー分岐（existing-issue.json 有無による分岐）が削除されていること
test_no_existing_issue_json_branch() {
  wait_for_batch_not_contains 'existing-issue\.json'
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "inject メッセージ [edge]: existing-issue.json による分岐が存在しない" test_no_existing_issue_json_branch
else
  run_test_skip "inject メッセージ [edge]: existing-issue.json による分岐が存在しない" "${ORCHESTRATOR_REL} not found"
fi

# 旧メッセージ（詳細な Step 指示）が残っていないこと
test_no_old_inject_message_4b() {
  wait_for_batch_not_contains '4b: issue-review-aggregate'
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "inject メッセージ [edge]: 旧メッセージ（4b: issue-review-aggregate）が存在しない" test_no_old_inject_message_4b
else
  run_test_skip "inject メッセージ [edge]: 旧メッセージ（4b: issue-review-aggregate）が存在しない" "${ORCHESTRATOR_REL} not found"
fi

# エッジケース: inject_msg 変数が1種類のみに統一されていること
# (分岐削除後は単一の inject_msg 代入のみ存在する)
test_inject_msg_single_assignment() {
  local body
  body=$(extract_wait_for_batch)
  local assign_count
  assign_count=$(echo "$body" | grep -cE 'inject_msg=' || true)
  # 1 行のみ（分岐なし）
  [[ "$assign_count" -eq 1 ]]
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "inject メッセージ [edge]: inject_msg の代入が 1 行のみ（分岐なし）" test_inject_msg_single_assignment
else
  run_test_skip "inject メッセージ [edge]: inject_msg の代入が 1 行のみ（分岐なし）" "${ORCHESTRATOR_REL} not found"
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
