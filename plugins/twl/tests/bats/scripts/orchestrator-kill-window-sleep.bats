#!/usr/bin/env bats
# orchestrator-kill-window-sleep.bats
#
# AC-3d: bats regression test — issue-lifecycle-orchestrator.sh の
#         kill-window 連続呼び出しで sleep 1 が挿入されていることを検証
#
# 対象: plugins/twl/scripts/issue-lifecycle-orchestrator.sh
# Issue: #1360 — P0 incident: tmux server protected scope

load '../helpers/common'

setup() {
  common_setup

  ORCHESTRATOR="${REPO_ROOT}/scripts/issue-lifecycle-orchestrator.sh"
  export ORCHESTRATOR
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: ターゲット行の次行に sleep 1 があることを確認する
# ---------------------------------------------------------------------------
assert_sleep_after_line() {
  local file="$1"
  local lineno="$2"
  local next_line
  # 直後行（空行は最大2行スキップ）で sleep 1 を探す（sleep 10 等の部分マッチを避ける）
  local i
  for i in 1 2 3; do
    next_line="$(sed -n "$((lineno + i))p" "${file}")"
    if echo "${next_line}" | grep -qE '^[[:space:]]*$'; then
      continue
    fi
    if echo "${next_line}" | grep -qE '^[[:space:]]*sleep 1([[:space:]]|$)'; then
      return 0
    fi
    echo "FAIL: ${file}:${lineno} の kill-window 直後 (L$((lineno + i))) に sleep 1 がない"
    echo "  actual: ${next_line}"
    return 1
  done
  echo "FAIL: ${file}:${lineno} の kill-window 直後 3 行以内に sleep 1 がない"
  return 1
}

# ---------------------------------------------------------------------------
# AC-3d: 各 kill-window 箇所に sleep 1 が挿入されていることを検証
# ---------------------------------------------------------------------------

@test "ac3d: orchestrator kill-window L372 直後に sleep 1 がある" {
  # RED: sleep 1 が未挿入のため fail
  run assert_sleep_after_line "${ORCHESTRATOR}" 372
  [ "${status}" -eq 0 ]
}

@test "ac3d: orchestrator kill-window L411 直後に sleep 1 がある" {
  # RED: sleep 1 が未挿入のため fail
  run assert_sleep_after_line "${ORCHESTRATOR}" 411
  [ "${status}" -eq 0 ]
}

@test "ac3d: orchestrator kill-window L562 直後に sleep 1 がある" {
  # RED: sleep 1 が未挿入のため fail
  run assert_sleep_after_line "${ORCHESTRATOR}" 562
  [ "${status}" -eq 0 ]
}

@test "ac3d: orchestrator kill-window L589 直後に sleep 1 がある" {
  # RED: sleep 1 が未挿入のため fail
  run assert_sleep_after_line "${ORCHESTRATOR}" 589
  [ "${status}" -eq 0 ]
}

@test "ac3d: orchestrator kill-window L595 直後に sleep 1 がある" {
  # RED: sleep 1 が未挿入のため fail
  run assert_sleep_after_line "${ORCHESTRATOR}" 595
  [ "${status}" -eq 0 ]
}

@test "ac3d: orchestrator kill-window L641 直後に sleep 1 がある" {
  # RED: sleep 1 が未挿入のため fail
  run assert_sleep_after_line "${ORCHESTRATOR}" 641
  [ "${status}" -eq 0 ]
}

@test "ac3d: orchestrator kill-window L712 直後に sleep 1 がある" {
  # RED: sleep 1 が未挿入のため fail
  run assert_sleep_after_line "${ORCHESTRATOR}" 712
  [ "${status}" -eq 0 ]
}

@test "ac3d: orchestrator kill-window L728 直後に sleep 1 がある" {
  # RED: sleep 1 が未挿入のため fail
  run assert_sleep_after_line "${ORCHESTRATOR}" 728
  [ "${status}" -eq 0 ]
}

@test "ac3d: orchestrator kill-window L753 直後に sleep 1 がある" {
  # RED: sleep 1 が未挿入のため fail
  run assert_sleep_after_line "${ORCHESTRATOR}" 753
  [ "${status}" -eq 0 ]
}

@test "ac3d: orchestrator kill-window L792 直後に sleep 1 がある" {
  # RED: sleep 1 が未挿入のため fail
  run assert_sleep_after_line "${ORCHESTRATOR}" 792
  [ "${status}" -eq 0 ]
}

@test "ac3d: orchestrator の kill-window 直後 sleep 1 挿入が全 10 箇所に存在する（集約）" {
  # 全 kill-window 直後（空行スキップ）に sleep 1 があることを一括検証
  local count
  count=$(awk '/tmux kill-window.*2>\/dev\/null.*true/{found=1; next} found && /^[[:space:]]*$/{next} found && /^[[:space:]]*sleep 1([[:space:]]|$)/{count++; found=0; next} found{found=0} END{print count+0}' \
    "${ORCHESTRATOR}")
  echo "sleep 1 挿入済み箇所: ${count}/10"
  [ "${count}" -ge 10 ]
}
