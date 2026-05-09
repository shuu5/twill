#!/usr/bin/env bats
# int-1626-pre-bash-hook-blocks-gh-pr-merge.bats
#
# Issue #1626 AC3.7: integration test
# merge-gate.json status=FAIL 状態で gh pr merge -R ... 1234 を
# Bash tool 経由実行して block 発火を検証
#
# RED: 全テストは実装前に fail する

_INTEGRATION_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
_TESTS_DIR="$(cd "$_INTEGRATION_DIR/.." && pwd)"
REPO_ROOT="$(cd "$_TESTS_DIR/.." && pwd)"
_LIB_DIR="$_TESTS_DIR/lib"

load "${_LIB_DIR}/bats-support/load"
load "${_LIB_DIR}/bats-assert/load"

setup() {
  SANDBOX="$(mktemp -d)"
  export SANDBOX

  SCRIPTS_DIR="${REPO_ROOT}/scripts"
  HOOK_SCRIPT="${SCRIPTS_DIR}/pre-bash-merge-gate-block.sh"

  mkdir -p "${SANDBOX}/.autopilot/checkpoints"
}

teardown() {
  if [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]]; then
    rm -rf "$SANDBOX"
  fi
}

# ===========================================================================
# AC3.7: integration test — merge-gate.json status=FAIL で gh pr merge をブロック
# ===========================================================================

@test "int-1626-ac3.7: pre-bash-merge-gate-block.sh が存在する" {
  # AC: スクリプトが新設されていること
  # RED: ファイルが未作成のため fail
  [ -f "$HOOK_SCRIPT" ]
}

@test "int-1626-ac3.7b: merge-gate.json status=FAIL で gh pr merge -R が block される" {
  # AC: merge-gate.json status=FAIL 状態で gh pr merge -R ... 1234 を実行して block 発火
  # RED: スクリプトが存在しないため fail
  [ -f "$HOOK_SCRIPT" ]

  # merge-gate.json を FAIL 状態にする
  cat > "${SANDBOX}/.autopilot/checkpoints/merge-gate.json" <<'JSON'
{
  "status": "FAIL",
  "result": "REJECTED",
  "reason": "RED-only PR detected"
}
JSON

  # gh pr merge コマンドを hook スクリプト経由で実行
  run bash "$HOOK_SCRIPT" \
    --autopilot-dir "${SANDBOX}/.autopilot" \
    --command "gh pr merge -R shuu5/twill 1234"

  # BLOCK（exit 1）であること
  assert_failure
  [ "$status" -eq 1 ]
}

@test "int-1626-ac3.7c: merge-gate.json status=FAIL で gh pr merge --merge が block される" {
  # AC: --merge フラグ付きの gh pr merge も block
  # RED: スクリプトが存在しないため fail
  [ -f "$HOOK_SCRIPT" ]

  cat > "${SANDBOX}/.autopilot/checkpoints/merge-gate.json" <<'JSON'
{"status":"FAIL","result":"REJECTED"}
JSON

  run bash "$HOOK_SCRIPT" \
    --autopilot-dir "${SANDBOX}/.autopilot" \
    --command "gh pr merge --merge 1234"

  assert_failure
  [ "$status" -eq 1 ]
}

@test "int-1626-ac3.7d: merge-gate.json 未存在で gh pr merge が block される（fail-closed）" {
  # AC: merge-gate.json 未存在は fail-closed（REJECT）
  # RED: スクリプトが存在しないため fail
  [ -f "$HOOK_SCRIPT" ]

  # merge-gate.json を配置しない
  ls "${SANDBOX}/.autopilot/checkpoints/" | grep -v 'merge-gate.json' || true

  run bash "$HOOK_SCRIPT" \
    --autopilot-dir "${SANDBOX}/.autopilot" \
    --command "gh pr merge 1234"

  assert_failure
  [ "$status" -eq 1 ]
}

@test "int-1626-ac3.7e: merge-gate.json status=PASS で gh pr merge が通過する" {
  # AC: status=PASS のみ通過
  # RED: スクリプトが存在しないため fail
  [ -f "$HOOK_SCRIPT" ]

  cat > "${SANDBOX}/.autopilot/checkpoints/merge-gate.json" <<'JSON'
{"status":"PASS","result":"MERGED"}
JSON

  run bash "$HOOK_SCRIPT" \
    --autopilot-dir "${SANDBOX}/.autopilot" \
    --command "gh pr merge 1234"

  assert_success
}

@test "int-1626-ac3.7f: block 時に BLOCK メッセージが出力される" {
  # AC: block 発火時にユーザーへの通知メッセージが出力される
  # RED: スクリプトが存在しないため fail
  [ -f "$HOOK_SCRIPT" ]

  cat > "${SANDBOX}/.autopilot/checkpoints/merge-gate.json" <<'JSON'
{"status":"FAIL","result":"REJECTED"}
JSON

  run bash "$HOOK_SCRIPT" \
    --autopilot-dir "${SANDBOX}/.autopilot" \
    --command "gh pr merge 1234"

  assert_failure
  assert_output --partial "BLOCK"
}

@test "int-1626-ac3.7g: TWL_MERGE_GATE_OVERRIDE 設定時は通過し audit log に記録される" {
  # AC: override 設定時のみ通過 + audit log 記録
  # RED: スクリプトが存在しないため fail
  [ -f "$HOOK_SCRIPT" ]

  cat > "${SANDBOX}/.autopilot/checkpoints/merge-gate.json" <<'JSON'
{"status":"FAIL","result":"REJECTED"}
JSON

  run bash -c "TWL_MERGE_GATE_OVERRIDE='stall-recovery-1626' bash '$HOOK_SCRIPT' --autopilot-dir '${SANDBOX}/.autopilot' --command 'gh pr merge 1234'"
  assert_success

  local audit_log="${SANDBOX}/.autopilot/merge-override-audit.log"
  [ -f "$audit_log" ]
  run grep -qF 'stall-recovery-1626' "$audit_log"
  assert_success
}
