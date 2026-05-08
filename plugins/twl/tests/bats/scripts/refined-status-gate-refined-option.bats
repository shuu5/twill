#!/usr/bin/env bats
# refined-status-gate-refined-option.bats - Refined option ID (3d983780) 拡張テスト
#
# Issue #1561: pre-bash-refined-status-gate.sh に Refined option ID (3d983780) の check を追加
# AC1: hook が 3d983780 + evidence なし で deny JSON を出力する
# AC2: evidence あり（spec-review-session / Phase4-complete.json）で allow
# AC4: bypass フラグは hook 内で check しない
# AC5: R1-R7 シナリオ
# AC6: deny メッセージに /twl:co-issue refine #N と ADR-024 が含まれる
# AC7: 47fc9ee4 (In Progress) check がリグレッションしない
#
# R1: 3d983780 + evidence なし → deny (RED: hook が 3d983780 を未検査のため no-op → FAIL)
# R2: 3d983780 + .spec-review-session-*.json あり → allow
# R3: 3d983780 + Phase4-complete.json あり → allow (RED: Phase4 check 未実装)
# R4: 47fc9ee4 + evidence なし → deny (regression)
# R5: 47fc9ee4 + .spec-review-session-*.json あり → allow (regression)
# R6: 3d9837801 (部分一致) + evidence なし → no-op (word boundary 確認)
# R7: deny メッセージに /twl:co-issue refine と ADR-024 が含まれる (RED: 現メッセージは /twl:workflow-issue-refine)

load '../helpers/common'

HOOK_SCRIPT_NAME="pre-bash-refined-status-gate.sh"

setup() {
  common_setup
  # REPO_ROOT = plugins/twl (common.bash 参照)
  cp "$REPO_ROOT/scripts/hooks/$HOOK_SCRIPT_NAME" "$SANDBOX/scripts/$HOOK_SCRIPT_NAME"
  chmod +x "$SANDBOX/scripts/$HOOK_SCRIPT_NAME"
}

teardown() {
  common_teardown
}

# Helper: JSON payload を生成してファイルに書き込み hook を実行
_run_hook_cmd() {
  local cmd="$1"
  local payload_file="$SANDBOX/hook-payload.json"
  jq -nc --arg cmd "$cmd" '{tool_name: "Bash", tool_input: {command: $cmd}}' > "$payload_file"
  run bash "$SANDBOX/scripts/$HOOK_SCRIPT_NAME" < "$payload_file"
}

# ---------------------------------------------------------------------------
# R1: 3d983780 + evidence なし → deny
# ---------------------------------------------------------------------------
# RED: 現在の hook は 47fc9ee4 のみ check。3d983780 はマッチせず exit 0 で出力なし。
# 実装後: 3d983780 もマッチし deny JSON を出力する → GREEN
@test "R1: gh project item-edit with 3d983780 (Refined option ID) + evidence なし → deny" {
  export SESSION_TMP_DIR="$SANDBOX/session-tmp"
  export CONTROLLER_ISSUE_DIR="$SANDBOX/.controller-issue"
  mkdir -p "$SANDBOX/session-tmp"

  _run_hook_cmd "gh project item-edit --field-id PVTSSF_abc --single-select-option-id 3d983780 --project-id PVT_xyz"

  assert_success
  assert_output --partial '"permissionDecision":"deny"'
}

# ---------------------------------------------------------------------------
# R2: 3d983780 + .spec-review-session-*.json あり → allow
# ---------------------------------------------------------------------------
# 実装後: 3d983780 マッチするが spec-review session ファイル存在 → evidence あり → allow
@test "R2: gh project item-edit with 3d983780 + .spec-review-session-*.json あり → allow" {
  export SESSION_TMP_DIR="$SANDBOX/session-tmp"
  export CONTROLLER_ISSUE_DIR="$SANDBOX/.controller-issue"
  mkdir -p "$SANDBOX/session-tmp"
  touch "$SANDBOX/session-tmp/.spec-review-session-test123.json"

  _run_hook_cmd "gh project item-edit --field-id PVTSSF_abc --single-select-option-id 3d983780 --project-id PVT_xyz"

  assert_success
  refute_output --partial '"permissionDecision":"deny"'
}

# ---------------------------------------------------------------------------
# R3: 3d983780 + Phase4-complete.json あり → allow
# ---------------------------------------------------------------------------
# RED: 現在の hook に Phase4-complete.json check が未実装。
# 実装後: CONTROLLER_ISSUE_DIR 配下に Phase4-complete.json 存在 → evidence あり → allow
@test "R3: gh project item-edit with 3d983780 + Phase4-complete.json あり → allow" {
  export SESSION_TMP_DIR="$SANDBOX/session-tmp"
  export CONTROLLER_ISSUE_DIR="$SANDBOX/.controller-issue"
  mkdir -p "$SANDBOX/session-tmp"
  mkdir -p "$SANDBOX/.controller-issue/issue-42"
  touch "$SANDBOX/.controller-issue/issue-42/Phase4-complete.json"

  _run_hook_cmd "gh project item-edit --field-id PVTSSF_abc --single-select-option-id 3d983780 --project-id PVT_xyz"

  assert_success
  refute_output --partial '"permissionDecision":"deny"'
}

# ---------------------------------------------------------------------------
# R4: 47fc9ee4 + evidence なし → deny (regression)
# ---------------------------------------------------------------------------
# GREEN: 既存実装済み。リグレッション確認。
@test "R4: gh project item-edit with 47fc9ee4 (In Progress option ID) + evidence なし → deny (regression)" {
  export SESSION_TMP_DIR="$SANDBOX/session-tmp"
  export CONTROLLER_ISSUE_DIR="$SANDBOX/.controller-issue"
  mkdir -p "$SANDBOX/session-tmp"

  _run_hook_cmd "gh project item-edit --field-id PVTSSF_abc --single-select-option-id 47fc9ee4 --project-id PVT_xyz"

  assert_success
  assert_output --partial '"permissionDecision":"deny"'
}

# ---------------------------------------------------------------------------
# R5: 47fc9ee4 + .spec-review-session-*.json あり → allow (regression)
# ---------------------------------------------------------------------------
# GREEN: 既存実装済み。リグレッション確認。
@test "R5: gh project item-edit with 47fc9ee4 + .spec-review-session-*.json あり → allow (regression)" {
  export SESSION_TMP_DIR="$SANDBOX/session-tmp"
  export CONTROLLER_ISSUE_DIR="$SANDBOX/.controller-issue"
  mkdir -p "$SANDBOX/session-tmp"
  touch "$SANDBOX/session-tmp/.spec-review-session-test456.json"

  _run_hook_cmd "gh project item-edit --field-id PVTSSF_abc --single-select-option-id 47fc9ee4 --project-id PVT_xyz"

  assert_success
  refute_output --partial '"permissionDecision":"deny"'
}

# ---------------------------------------------------------------------------
# R6: 3d9837801 (部分一致) + evidence なし → no-op (word boundary 確認)
# ---------------------------------------------------------------------------
# 3d9837801 は 3d983780 に '1' を付加した値。word boundary \b でマッチしないこと。
@test "R6: 3d9837801 (partial match of 3d983780) + evidence なし → no-op (word boundary guard)" {
  export SESSION_TMP_DIR="$SANDBOX/session-tmp"
  export CONTROLLER_ISSUE_DIR="$SANDBOX/.controller-issue"
  mkdir -p "$SANDBOX/session-tmp"

  _run_hook_cmd "gh project item-edit --field-id PVTSSF_abc --single-select-option-id 3d9837801 --project-id PVT_xyz"

  assert_success
  refute_output --partial '"permissionDecision":"deny"'
}

# ---------------------------------------------------------------------------
# R7: deny メッセージに /twl:co-issue refine および ADR-024 が含まれる
# ---------------------------------------------------------------------------
# RED: 現在のメッセージは /twl:workflow-issue-refine を案内。/twl:co-issue refine を未含有。
# 実装後: AC6 準拠のメッセージに更新 → GREEN
@test "R7: deny メッセージに /twl:co-issue refine および ADR-024 が含まれる" {
  export SESSION_TMP_DIR="$SANDBOX/session-tmp"
  export CONTROLLER_ISSUE_DIR="$SANDBOX/.controller-issue"
  mkdir -p "$SANDBOX/session-tmp"

  # 3d983780 パターンで deny を発生させる（R1 と同じ条件）
  _run_hook_cmd "gh project item-edit --field-id PVTSSF_abc --single-select-option-id 3d983780 --project-id PVT_xyz"

  assert_success
  assert_output --partial '"permissionDecision":"deny"'
  assert_output --partial '/twl:co-issue refine'
  assert_output --partial 'ADR-024'
}
