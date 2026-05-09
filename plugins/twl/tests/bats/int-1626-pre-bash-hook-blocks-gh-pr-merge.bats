#!/usr/bin/env bats
# int-1626-pre-bash-hook-blocks-gh-pr-merge.bats
#
# Issue #1626 AC3.7 — PreToolUse hook で gh pr merge 強制 block の integration test
#
# AC3: pre-bash-merge-gate-block.sh が以下を行う:
#   - tool_input.command が gh pr merge または auto-merge.sh にマッチ → 起動
#   - merge-gate.json status=FAIL → deny (permissionDecision=deny)
#   - merge-gate.json 不在 → graceful passthrough (gate 未実行 PR)
#   - merge-gate.json status=PASS/WARN → 通過
#   - TWL_MERGE_GATE_OVERRIDE='<理由>' 設定で通過 + audit log
#
# 検証シナリオ:
#   1. gh pr merge + status=FAIL → deny JSON 出力
#   2. auto-merge.sh + status=FAIL → deny JSON 出力 (一律 block)
#   3. gh pr merge + TWL_MERGE_GATE_OVERRIDE → 通過 + audit log
#   4. gh pr merge + merge-gate.json 不在 → graceful passthrough
#   5. gh pr merge + status=PASS → 通過
#   6. git status (無関係 command) → no-op

load 'helpers/common'

HOOKS_DIR=""

setup() {
  common_setup
  HOOKS_DIR="${REPO_ROOT}/scripts/hooks"
  # AUTOPILOT_DIR は common_setup で SANDBOX/.autopilot に設定済み
}

teardown() {
  common_teardown
}

# ===========================================================================
# Helper: HookOutput JSON payload を生成
# ===========================================================================
_make_payload() {
  local cmd="$1"
  jq -nc --arg c "$cmd" \
    '{tool_name:"Bash", tool_input:{command:$c}}'
}

# Helper: merge-gate.json を SANDBOX 配下に配置
_make_merge_gate_json() {
  local status="$1"
  local mg_path="${AUTOPILOT_DIR}/checkpoints/merge-gate.json"
  mkdir -p "$(dirname "$mg_path")"
  printf '{"status":"%s","result":"REJECTED","critical_count":1,"findings":[]}\n' "$status" > "$mg_path"
}

# ===========================================================================
# AC3.7-a: gh pr merge + status=FAIL → deny JSON
# ===========================================================================

@test "ac3.7a: gh pr merge + merge-gate FAIL → deny JSON 出力" {
  local hook="${HOOKS_DIR}/pre-bash-merge-gate-block.sh"
  [ -f "$hook" ]

  _make_merge_gate_json "FAIL"
  local payload
  payload=$(_make_payload "gh pr merge 123 --squash")

  run bash "$hook" <<< "$payload"
  assert_success  # hook 自体は exit 0 (deny は JSON で表現)
  assert_output --partial '"permissionDecision":"deny"'
  assert_output --partial 'merge-gate FAIL'
}

# ===========================================================================
# AC3.7-b: auto-merge.sh + status=FAIL → deny JSON (一律 block)
# ===========================================================================

@test "ac3.7b: auto-merge.sh + merge-gate FAIL → deny JSON (一律 block)" {
  local hook="${HOOKS_DIR}/pre-bash-merge-gate-block.sh"
  [ -f "$hook" ]

  _make_merge_gate_json "FAIL"
  local payload
  payload=$(_make_payload "bash plugins/twl/scripts/auto-merge.sh --issue 42 --pr 123")

  run bash "$hook" <<< "$payload"
  assert_success
  assert_output --partial '"permissionDecision":"deny"'
}

# ===========================================================================
# AC3.7-c: TWL_MERGE_GATE_OVERRIDE 付き → 通過 + audit log
# ===========================================================================

@test "ac3.7c: TWL_MERGE_GATE_OVERRIDE プレフィックス付き → 通過 + audit log 記録" {
  local hook="${HOOKS_DIR}/pre-bash-merge-gate-block.sh"
  [ -f "$hook" ]

  _make_merge_gate_json "FAIL"
  local payload
  payload=$(_make_payload "TWL_MERGE_GATE_OVERRIDE='stall-recovery: e2e timeout' gh pr merge 123 --squash")

  run bash "$hook" <<< "$payload"
  assert_success
  refute_output --partial '"permissionDecision":"deny"'

  # audit log が記録されている
  local audit_log="${AUTOPILOT_DIR}/merge-override-audit.log"
  [ -f "$audit_log" ]
  run grep -qF 'stall-recovery: e2e timeout' "$audit_log"
  assert_success
}

# ===========================================================================
# AC3.7-d: merge-gate.json 不在 → graceful passthrough
# ===========================================================================

@test "ac3.7d: merge-gate.json 不在 → graceful passthrough (no deny)" {
  local hook="${HOOKS_DIR}/pre-bash-merge-gate-block.sh"
  [ -f "$hook" ]

  # merge-gate.json は作らない
  local payload
  payload=$(_make_payload "gh pr merge 123 --squash")

  run bash "$hook" <<< "$payload"
  assert_success
  refute_output --partial '"permissionDecision":"deny"'
  [ -z "$output" ]  # 出力なし
}

# ===========================================================================
# AC3.7-e: status=PASS → 通過
# ===========================================================================

@test "ac3.7e: merge-gate.json status=PASS → 通過 (no deny)" {
  local hook="${HOOKS_DIR}/pre-bash-merge-gate-block.sh"
  [ -f "$hook" ]

  _make_merge_gate_json "PASS"
  local payload
  payload=$(_make_payload "gh pr merge 123 --squash")

  run bash "$hook" <<< "$payload"
  assert_success
  refute_output --partial '"permissionDecision":"deny"'
}

# ===========================================================================
# AC3.7-f: status=WARN → 通過
# ===========================================================================

@test "ac3.7f: merge-gate.json status=WARN → 通過 (no deny)" {
  local hook="${HOOKS_DIR}/pre-bash-merge-gate-block.sh"
  [ -f "$hook" ]

  _make_merge_gate_json "WARN"
  local payload
  payload=$(_make_payload "gh pr merge 123 --squash")

  run bash "$hook" <<< "$payload"
  assert_success
  refute_output --partial '"permissionDecision":"deny"'
}

# ===========================================================================
# AC3.7-g: 無関係コマンド → no-op
# ===========================================================================

@test "ac3.7g: git status (無関係 command) → no-op" {
  local hook="${HOOKS_DIR}/pre-bash-merge-gate-block.sh"
  [ -f "$hook" ]

  _make_merge_gate_json "FAIL"  # FAIL でも無関係コマンドは通過
  local payload
  payload=$(_make_payload "git status")

  run bash "$hook" <<< "$payload"
  assert_success
  [ -z "$output" ]
}

# ===========================================================================
# AC3.7-h: tool_name が Bash 以外 → no-op
# ===========================================================================

@test "ac3.7h: tool_name=Read → no-op" {
  local hook="${HOOKS_DIR}/pre-bash-merge-gate-block.sh"
  [ -f "$hook" ]

  _make_merge_gate_json "FAIL"
  local payload
  payload=$(jq -nc '{tool_name:"Read", tool_input:{file_path:"/tmp/foo"}}')

  run bash "$hook" <<< "$payload"
  assert_success
  [ -z "$output" ]
}

# ===========================================================================
# AC3.7-i: TWL_MERGE_GATE_OVERRIDE strict regex security test
#   echo TWL_MERGE_GATE_OVERRIDE='r' gh pr merge ... の bypass 試行を block する
# ===========================================================================

@test "ac3.7i: echo TWL_MERGE_GATE_OVERRIDE=... による bypass 試行 → deny (strict regex)" {
  local hook="${HOOKS_DIR}/pre-bash-merge-gate-block.sh"
  [ -f "$hook" ]

  _make_merge_gate_json "FAIL"
  # `echo` は env var prefix でないため strict regex で false → override 不認定 → deny
  local payload
  payload=$(_make_payload "echo TWL_MERGE_GATE_OVERRIDE='bypass' && gh pr merge 123 --squash")

  run bash "$hook" <<< "$payload"
  assert_success
  assert_output --partial '"permissionDecision":"deny"'
}

@test "ac3.7j: 複数 env var prefix chain (FOO=x BAR=y TWL_MERGE_GATE_OVERRIDE=z) → 通過" {
  local hook="${HOOKS_DIR}/pre-bash-merge-gate-block.sh"
  [ -f "$hook" ]

  _make_merge_gate_json "FAIL"
  # 複数 env var を chain した場合も strict regex で正常認識
  local payload
  payload=$(_make_payload "FOO=x BAR='val' TWL_MERGE_GATE_OVERRIDE='multi-env' gh pr merge 123 --squash")

  run bash "$hook" <<< "$payload"
  assert_success
  refute_output --partial '"permissionDecision":"deny"'
}
