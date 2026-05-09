#!/usr/bin/env bats
# int-1626-followup-verify-and-condition.bats
#
# Issue #1626 AC1.6: integration test
# red-only label のみ・follow-up 不在シナリオで CRITICAL を確認
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

  # stub bin
  STUB_BIN="${SANDBOX}/.stub-bin"
  mkdir -p "$STUB_BIN"
  _ORIGINAL_PATH="$PATH"
  export PATH="${STUB_BIN}:${PATH}"
}

teardown() {
  if [[ -n "${_ORIGINAL_PATH:-}" ]]; then
    export PATH="$_ORIGINAL_PATH"
  fi
  if [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]]; then
    rm -rf "$SANDBOX"
  fi
}

_stub_command() {
  local name="$1"
  local body="${2:-exit 0}"
  cat > "${STUB_BIN}/${name}" <<STUB
#!/usr/bin/env bash
${body}
STUB
  chmod +x "${STUB_BIN}/${name}"
}

# ===========================================================================
# AC1.6: integration test — red-only label のみ・follow-up 不在シナリオで CRITICAL を確認
# ===========================================================================

@test "int-1626-ac1.6: red-only label のみ・follow-up 不在 → worker-red-only-detector.sh が CRITICAL を返す" {
  # AC: integration scenario — red-only label 付き + follow-up Issue 不在 → CRITICAL
  # RED: AC1.3 の AND 条件ロジックが未実装のため WARNING が返り CRITICAL にならない

  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  # gh stub: follow-up Issue 検索で空を返す（不在）
  _stub_command "gh" 'exit 0'

  # scenario: red-only label 付き、テストファイルのみ変更
  local pr_json
  pr_json='{"labels":[{"name":"red-only"}],"files":[{"path":"plugins/twl/tests/bats/int-test-scenario.bats"}]}'

  run bash "$script" --pr-json "$pr_json" --pr-number 1234

  # CRITICAL が出力されること（follow-up 不在のため WARNING ではない）
  assert_output --partial "CRITICAL"
  refute_output --partial "WARNING"
}

@test "int-1626-ac1.6b: red-only label のみ・follow-up 不在 → status: FAIL が含まれる" {
  # AC: escape hatch 完全閉鎖 — status: FAIL
  # RED: 現状 FAIL status が出力されない
  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  _stub_command "gh" 'exit 0'

  local pr_json
  pr_json='{"labels":[{"name":"red-only"}],"files":[{"path":"plugins/twl/tests/bats/int-test-scenario.bats"}]}'

  run bash "$script" --pr-json "$pr_json" --pr-number 1234

  assert_output --partial "FAIL"
}

@test "int-1626-ac1.6c: red-only label + follow-up 存在 → WARNING に留まる（escape hatch 有効）" {
  # AC: AND 条件の正常パス — follow-up 存在時は WARNING（現状維持）
  # RED: AND 条件が未実装のため follow-up 存在時の挙動も不定
  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  # gh stub: follow-up Issue が存在する（marker 検索で結果あり）
  _stub_command "gh" 'printf "99\tfollow-up: RED-only PR #1234\n"'

  local pr_json
  pr_json='{"labels":[{"name":"red-only"}],"files":[{"path":"plugins/twl/tests/bats/int-test-scenario.bats"}]}'

  run bash "$script" --pr-json "$pr_json" --pr-number 1234

  # follow-up 存在時は WARNING（escape hatch 有効）
  assert_output --partial "WARNING"
  refute_output --partial "CRITICAL"
}

@test "int-1626-ac1.6d: red-only label なし・test-only → CRITICAL を返す（既存動作維持）" {
  # AC: label なし + test-only → 従来通り CRITICAL（regression guard）
  # RED: 既存動作が変わっていた場合に検知
  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  _stub_command "gh" 'exit 0'

  # label なし、テストファイルのみ
  local pr_json
  pr_json='{"labels":[],"files":[{"path":"plugins/twl/tests/bats/int-test-scenario.bats"}]}'

  run bash "$script" --pr-json "$pr_json"

  # 従来通り CRITICAL
  assert_output --partial "CRITICAL"
}
