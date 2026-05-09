#!/usr/bin/env bats
# int-1626-warning-fix-cannot-add-red-only-label.bats
#
# Issue #1626 AC5.3: integration test
# gh pr edit --add-label red-only 後の merge-gate 再走で
# CRITICAL が維持されることを確認
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
# AC5.3: integration test — red-only label 付与後も CRITICAL が維持される
# ===========================================================================

@test "int-1626-ac5.3: red-only label 付与後に merge-gate 再走で CRITICAL が維持される" {
  # AC: regression scenario — label 付与（gh pr edit --add-label red-only）後
  #     merge-gate 再走で follow-up 不在なら CRITICAL 維持
  # RED: AC1.3 の AND 条件が未実装のため WARNING が返り CRITICAL にならない
  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  # gh stub: follow-up 不在
  _stub_command "gh" 'exit 0'

  # scenario: red-only label が付与済み、テストファイルのみ
  local pr_json
  pr_json='{"labels":[{"name":"red-only"}],"files":[{"path":"plugins/twl/tests/bats/regression-test.bats"}]}'

  run bash "$script" --pr-json "$pr_json" --pr-number 1608

  # label 付与だけでは escape hatch にならない（follow-up 不在 → CRITICAL）
  assert_output --partial "CRITICAL"
  refute_output --partial "WARNING"
}

@test "int-1626-ac5.3b: red-only label のみ付与では WARNING に降格しない" {
  # AC: label 付与が WARNING bypass として機能しないことを確認
  # RED: 現状 red-only label で WARNING を返す（bypass が可能）
  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  _stub_command "gh" 'exit 0'

  local pr_json
  pr_json='{"labels":[{"name":"red-only"}],"files":[{"path":"plugins/twl/tests/bats/regression-test.bats"}]}'

  run bash "$script" --pr-json "$pr_json" --pr-number 1608

  # WARNING が出力されないこと（CRITICAL のみ）
  refute_output --partial "WARNING"
}

@test "int-1626-ac5.3c: red-only label + follow-up 起票済み → WARNING（escape hatch が機能する）" {
  # AC: 正しい escape hatch — follow-up 存在時のみ WARNING に降格
  # RED: AND 条件が未実装のため follow-up 存在時の挙動が不定
  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  # gh stub: follow-up Issue が存在（marker ベース検索で発見）
  _stub_command "gh" 'printf "42\tfollow-up: RED-only PR #1608\n"'

  local pr_json
  pr_json='{"labels":[{"name":"red-only"}],"files":[{"path":"plugins/twl/tests/bats/regression-test.bats"}]}'

  run bash "$script" --pr-json "$pr_json" --pr-number 1608

  # follow-up 存在 → WARNING（escape hatch 有効）
  assert_output --partial "WARNING"
  refute_output --partial "CRITICAL"
}

@test "int-1626-ac5.3d: label 付与後の merge-gate-check-red-only.sh 再走で REJECT を維持する" {
  # AC: merge-gate layer での REJECT 維持
  # RED: REJECT path への条件分岐が未実装
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  # git stub: テストファイルのみ（RED-only PR）
  _stub_command "git" 'printf "plugins/twl/tests/bats/regression-test.bats\n"'

  # gh stub: red-only label 付き、follow-up 不在
  cat > "${STUB_BIN}/gh" <<'GHSTUB'
#!/usr/bin/env bash
if echo "$*" | grep -qE "pr view.*labels|labels.*pr view"; then
  printf '{"labels":[{"name":"red-only"}]}\n'
elif echo "$*" | grep -qE "issue list|issue search"; then
  exit 0
elif echo "$*" | grep -qF "issue create"; then
  echo "https://github.com/shuu5/twill/issues/999"
fi
GHSTUB
  chmod +x "${STUB_BIN}/gh"

  export PR_NUM=1608
  run bash "$script"

  # REJECT（exit 1）
  assert_failure
  [ "$status" -eq 1 ]
}

@test "int-1626-ac5.3e: label なし PR は従来通り CRITICAL（regression guard）" {
  # AC: red-only label のない test-only PR は従来通り CRITICAL
  # RED: AC1 実装後に既存パスが壊れると fail
  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  _stub_command "gh" 'exit 0'

  local pr_json
  pr_json='{"labels":[],"files":[{"path":"plugins/twl/tests/bats/regression-test.bats"}]}'

  run bash "$script" --pr-json "$pr_json"

  # label なし → 従来通り CRITICAL
  assert_output --partial "CRITICAL"
}
