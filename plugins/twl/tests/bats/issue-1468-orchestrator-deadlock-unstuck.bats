#!/usr/bin/env bats
# issue-1468-orchestrator-deadlock-unstuck.bats
#
# Issue #1468: autopilot-orchestrator LAST_INJECTED_STEP suppression deadlock fix
#
# AC1: orchestrator に terminal phrase 検知 + auto re-inject (Approach A) を実装
# AC2: chain-runner.sh autopilot-detect で明示 terminal phrase emit (Approach C)
# AC3: bats test で deadlock 再現 + 自動 unstuck 検証
# AC4: stagnate timeout fallback (Approach B) を opt-in env で実装
# AC5: Wave 54+ で deadlock 自然解消することを確認 (structural check)
#
# RED: 実装前は AC1/AC2/AC4 関連テストが fail
# GREEN: 実装後に全テスト PASS

load 'helpers/common'

SCRIPTS_ROOT=""
CHAIN_RUNNER=""
INJECT_LIB=""
ORCHESTRATOR_SH=""

setup() {
  common_setup

  SCRIPTS_ROOT="${REPO_ROOT}/scripts"
  CHAIN_RUNNER="${SCRIPTS_ROOT}/chain-runner.sh"
  INJECT_LIB="${SCRIPTS_ROOT}/lib/inject-next-workflow.sh"
  ORCHESTRATOR_SH="${SCRIPTS_ROOT}/autopilot-orchestrator.sh"

  # Create minimal issue state file (issue field required for resolve_issue_num Priority 1)
  cat > "$SANDBOX/.autopilot/issues/issue-42.json" <<'STATEEOF'
{
  "status": "running",
  "issue": 42,
  "current_step": "workflow-pr-fix",
  "branch": "feat/42-test-branch",
  "pr": ""
}
STATEEOF

  # gh stub
  stub_command "gh" 'echo ""'

  # tmux stub: default returns no terminal phrase
  stub_command "tmux" 'echo ""'
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: chain-runner.sh autopilot-detect を sandbox 環境で実行する
#
# WORKER_ISSUE_NUM=42 で Priority 0 issue 解決（git ブランチ抽出不要）
# AUTOPILOT_DIR=$SANDBOX/.autopilot で state ファイルを直接参照
# python3 stub で status / current_step を制御
# ---------------------------------------------------------------------------
_run_autopilot_detect() {
  local autopilot_status="${1:-running}"
  local current_step="${2:-workflow-pr-fix}"

  # python3 stub: autopilot state read を制御
  cat > "$STUB_BIN/python3" <<PYSTUB
#!/usr/bin/env bash
args="\$*"
if [[ "\$args" =~ "--field status" ]]; then
  echo "${autopilot_status}"
elif [[ "\$args" =~ "--field current_step" ]]; then
  echo "${current_step}"
else
  echo ""
fi
PYSTUB
  chmod +x "$STUB_BIN/python3"

  # WORKER_ISSUE_NUM: resolve_issue_num Priority 0 (git 不要)
  # AUTOPILOT_DIR: resolve_autopilot_dir が直接使用
  WORKER_ISSUE_NUM=42 AUTOPILOT_DIR="$SANDBOX/.autopilot" \
    run bash "$CHAIN_RUNNER" autopilot-detect
}

# ===========================================================================
# AC2: chain-runner.sh autopilot-detect で terminal phrase emit (Approach C)
#
# RED: 現在の step_autopilot_detect() は "IS_AUTOPILOT=true" のみ出力。
#      ">>> chain-step-completed:" が含まれないため assert が FAIL。
# GREEN: 実装後は ">>> chain-step-completed: workflow-pr-fix → autopilot 引き継ぎ待ち"
#        が出力される。
# ===========================================================================

@test "ac2: autopilot-detect は IS_AUTOPILOT=true を出力する（既存動作の回帰防止）" {
  # 既存動作が壊れていないことを確認（regression test）
  # GREEN: 実装前後ともに PASS すべき
  _run_autopilot_detect "running" "workflow-pr-fix"
  assert_output --partial "IS_AUTOPILOT=true"
}

@test "ac2: autopilot-detect は running 時に '>>> chain-step-completed:' を出力する" {
  # AC2 機能テスト: IS_AUTOPILOT=true 停止時に terminal phrase を emit
  # RED: 現在の実装は terminal phrase を出力しないため FAIL
  _run_autopilot_detect "running" "workflow-pr-fix"
  assert_output --partial ">>> chain-step-completed:"
}

@test "ac2: autopilot-detect は current_step を terminal phrase に含める" {
  # AC2: chain-step-completed の後に current_step 値が続く
  # RED: 実装前は terminal phrase 自体が存在しない
  _run_autopilot_detect "running" "workflow-pr-fix"
  assert_output --partial "workflow-pr-fix"
}

@test "ac2: autopilot=false 時は terminal phrase を出力しない" {
  # status=done → IS_AUTOPILOT=false → terminal phrase を出力しない
  # GREEN: 実装前後ともに PASS すべき（false 時に誤 emit しないことの確認）
  _run_autopilot_detect "done" "workflow-pr-merge"
  refute_output --partial ">>> chain-step-completed:"
}

@test "ac2: chain-runner.sh に terminal phrase emit ロジックが存在する（structural check）" {
  # AC2 structural: chain-runner.sh が "chain-step-completed" パターンを含む
  # RED: 実装前は grep が FAIL する
  run grep -qF "chain-step-completed" "$CHAIN_RUNNER"
  assert_success
}

# ===========================================================================
# AC1: orchestrator に terminal phrase 検知 + auto re-inject (Approach A)
#
# LAST_INJECTED_STEP[$entry] == current_step（通常は重複 inject 抑制）でも、
# Worker pane に terminal phrase が存在する場合は bypass して re-inject する。
#
# RED: 現在の実装にバイパスロジックがないため structural test が FAIL。
# GREEN: 実装後は autopilot-orchestrator.sh に terminal phrase チェックが追加される。
# ===========================================================================

@test "ac1: autopilot-orchestrator.sh に terminal phrase 検知ロジックが存在する（structural）" {
  # AC1 structural: "chain-step-completed" または terminal phrase チェックパターンが存在する
  # RED: 実装前は grep が FAIL する
  run grep -qE "(chain-step-completed|terminal.phrase|bypass.*LAST_INJECTED)" "$ORCHESTRATOR_SH"
  assert_success
}

@test "ac1: autopilot-orchestrator.sh に LAST_INJECTED_STEP bypass ロジックが存在する（structural）" {
  # AC1 structural: LAST_INJECTED_STEP を空にするバイパスパターンが存在する
  # 期待パターン: LAST_INJECTED_STEP[...]=""  または  unset LAST_INJECTED_STEP[...]
  # RED: 実装前はこのパターンが存在しないため FAIL
  run grep -qE 'LAST_INJECTED_STEP\[.*\]=""' "$ORCHESTRATOR_SH"
  assert_success
}

@test "ac1: inject-next-workflow.sh または orchestrator に terminal phrase 検知ロジックが存在する（structural）" {
  # Approach A の実装として inject-next-workflow.sh か orchestrator に
  # terminal phrase 検知 ("chain-step-completed" など) が追加されることを期待する
  # RED: 実装前は両ファイルともパターンが存在しないため FAIL
  run bash -c "
    grep -qE '(chain-step-completed|_has_terminal_phrase|_check_terminal_phrase)' '${INJECT_LIB}' || \
    grep -qE '(chain-step-completed|_has_terminal_phrase|_check_terminal_phrase)' '${ORCHESTRATOR_SH}'
  "
  assert_success
}

# ===========================================================================
# AC3: bats test で deadlock 再現 + 自動 unstuck 検証
#
# deadlock 条件:
#   - LAST_INJECTED_STEP[$entry] == current_step (inject 抑制)
#   - Worker pane が terminal phrase を出力（IS_AUTOPILOT=true 停止済み）
#   - 通常: inject されない → deadlock
#   - 修正後: terminal phrase 検知 → bypass → inject 成功
#
# 主なテストは structural（orchestrator の bypass ロジック存在確認）
# ===========================================================================

@test "ac3: deadlock 状態の LAST_INJECTED_STEP 抑制パスが orchestrator に存在する（baseline structural）" {
  # baseline: orchestrator に LAST_INJECTED_STEP 重複抑制ロジックが存在することを確認
  # GREEN: 実装前後ともに PASS（抑制ロジック自体は既存）
  run grep -qF "LAST_INJECTED_STEP" "$ORCHESTRATOR_SH"
  assert_success
}

@test "ac3: terminal phrase あり → LAST_INJECTED_STEP リセットで deadlock 解消（structural）" {
  # deadlock 検知 → LAST_INJECTED_STEP をリセットして次サイクルで re-inject する実装確認
  # RED: 実装前は LAST_INJECTED_STEP reset パターンが存在しない
  run grep -qE 'LAST_INJECTED_STEP\[.*\]=""' "$ORCHESTRATOR_SH"
  assert_success
}

@test "ac3: deadlock 自動 unstuck のシーケンス — chain-step-completed + bypass の組み合わせ（structural）" {
  # AC2 (chain-step-completed emit) + AC1 (bypass) の連携が両ファイルに実装されていること
  # RED: 実装前は両パターンとも存在しない
  local has_ac2=0
  local has_ac1=0
  grep -qF "chain-step-completed" "$CHAIN_RUNNER" && has_ac2=1
  grep -qE 'LAST_INJECTED_STEP\[.*\]=""' "$ORCHESTRATOR_SH" && has_ac1=1

  run bash -c "[[ '${has_ac2}' -eq 1 ]] && [[ '${has_ac1}' -eq 1 ]]"
  assert_success
}

# ===========================================================================
# AC4: stagnate timeout fallback (Approach B) を opt-in env で実装
#
# AUTOPILOT_AUTO_UNSTUCK=1 を設定した場合、RESOLVE_FAIL_COUNT が閾値を超えると
# 自動で re-inject を試みる（LAST_INJECTED_STEP を無視する強制 inject）。
#
# RED: 現在の実装は stagnate WARN のみで auto-inject なし → FAIL
# GREEN: AUTOPILOT_AUTO_UNSTUCK=1 + 閾値超過 → inject 発火
# ===========================================================================

@test "ac4: inject-next-workflow.sh に AUTOPILOT_AUTO_UNSTUCK 変数の参照が存在する（structural）" {
  # AC4 structural: Approach B opt-in env が inject-next-workflow.sh に実装されている
  # RED: 現在は AUTOPILOT_AUTO_UNSTUCK が参照されていない
  run grep -qF "AUTOPILOT_AUTO_UNSTUCK" "$INJECT_LIB"
  assert_success
}

@test "ac4: autopilot-orchestrator.sh に AUTOPILOT_AUTO_UNSTUCK 参照が存在する（structural）" {
  # AC4: orchestrator 側でも opt-in env を参照
  # RED: 実装前は参照なし
  run grep -qF "AUTOPILOT_AUTO_UNSTUCK" "$ORCHESTRATOR_SH"
  assert_success
}

@test "ac4: AUTOPILOT_AUTO_UNSTUCK opt-in 時の auto-unstuck ロジックが実装されている（structural）" {
  # AC4 実装の核心: stagnate 状態 + AUTOPILOT_AUTO_UNSTUCK=1 → force inject
  # 実装パターンを確認（auto-unstuck / force inject コメントまたはコード）
  # RED: 現在の stagnate path は WARN のみで inject しない
  run grep -qE "(auto.unstuck|force.*inject|AUTOPILOT_AUTO_UNSTUCK.*inject)" "$INJECT_LIB"
  assert_success
}

# ===========================================================================
# AC5: deadlock 自然解消のための実装完備確認（structural integration check）
#
# Wave 54+ で Pilot 介入なしに deadlock が解消されるためには
# AC1 + AC2 + AC4 が全て実装されている必要がある。
#
# RED: 実装前は AC1/AC2/AC4 が揃っていないため FAIL
# GREEN: 全 AC 実装後に PASS
# ===========================================================================

@test "ac5: AC1 の LAST_INJECTED_STEP bypass が実装済み" {
  run grep -qE 'LAST_INJECTED_STEP\[.*\]=""' "$ORCHESTRATOR_SH"
  assert_success
}

@test "ac5: AC2 の chain-step-completed emit が実装済み" {
  run grep -qF "chain-step-completed" "$CHAIN_RUNNER"
  assert_success
}

@test "ac5: AC4 の AUTOPILOT_AUTO_UNSTUCK opt-in が実装済み" {
  run grep -qF "AUTOPILOT_AUTO_UNSTUCK" "$INJECT_LIB"
  assert_success
}

@test "ac5: autopilot-orchestrator.sh は bash -n を通過する（syntax check）" {
  run bash -n "$ORCHESTRATOR_SH"
  assert_success
}

@test "ac5: chain-runner.sh は bash -n を通過する（syntax check）" {
  run bash -n "$CHAIN_RUNNER"
  assert_success
}

@test "ac5: inject-next-workflow.sh は bash -n を通過する（syntax check）" {
  run bash -n "$INJECT_LIB"
  assert_success
}
