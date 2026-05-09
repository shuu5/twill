#!/usr/bin/env bats
# ac-test-1626-regression.bats
#
# Issue #1626: bug(merge-gate): red-only label-based bypass
#
# AC5.1: regression test scenario — gh pr edit --add-label red-only を Bash で実行後、
#         merge-gate を再走させる
# AC5.2: AC1 の AND 条件により red-only label + follow-up 不在 → CRITICAL 維持を確認
#
# RED: 全テストは実装前に fail する

load 'helpers/common'

SCRIPTS_DIR=""

setup() {
  common_setup
  SCRIPTS_DIR="${REPO_ROOT}/scripts"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC5.1: regression test scenario — red-only label 付与後に merge-gate を再走
#
# RED: AC1.1-1.3 の AND 条件が実装されていないため fail
# ===========================================================================

@test "ac5.1: red-only label 付与後の merge-gate 再走で worker-red-only-detector.sh が follow-up 存在を確認する" {
  # AC: gh pr edit --add-label red-only 後に merge-gate 再走 → follow-up 存在確認が発動
  # RED: AC1.1 の follow-up 検証ロジックが未実装のため fail
  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  local gh_log="${SANDBOX}/gh-calls.log"

  # gh stub: label 付与は成功、follow-up Issue 検索は空
  cat > "$STUB_BIN/gh" <<GHSTUB
#!/usr/bin/env bash
if echo "\$*" | grep -qF "pr edit"; then
  # red-only label 付与
  exit 0
elif echo "\$*" | grep -qE "issue list|issue search"; then
  echo "\$*" >> "${gh_log}"
  # follow-up 不在
  exit 0
fi
GHSTUB
  chmod +x "$STUB_BIN/gh"

  # Step 1: label 付与（regression scenario）
  run bash -c "${STUB_BIN}/gh pr edit 1234 --add-label red-only"
  assert_success

  # Step 2: merge-gate 再走（worker-red-only-detector.sh で検証）
  local pr_json='{"labels":[{"name":"red-only"}],"files":[{"path":"plugins/twl/tests/bats/somefile.bats"}]}'
  run bash "$script" --pr-json "$pr_json" --pr-number 1234

  # follow-up Issue 検索が行われること
  [ -f "$gh_log" ]
  run grep -qE 'issue list|issue search' "$gh_log"
  assert_success
}

@test "ac5.1b: red-only label 付与後の merge-gate 再走シナリオが end-to-end で機能する" {
  # AC: regression scenario — label 付与 → merge-gate 再走 → AND 条件評価
  # RED: AC1 の AND 条件が未実装のため end-to-end が機能しない
  local worker_script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  local gate_script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$worker_script" ]
  [ -f "$gate_script" ]

  # git stub: テストファイルのみ
  stub_command "git" 'printf "plugins/twl/tests/bats/somefile.bats\n"'

  # gh stub: red-only label 付き、follow-up 不在
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
if echo "$*" | grep -qE "pr view.*labels|labels.*pr view"; then
  printf '{"labels":[{"name":"red-only"}]}\n'
elif echo "$*" | grep -qE "issue list|issue search"; then
  exit 0
elif echo "$*" | grep -qF "issue create"; then
  echo "https://github.com/shuu5/twill/issues/888"
fi
GHSTUB
  chmod +x "$STUB_BIN/gh"

  export PR_NUM=1234
  run bash "$gate_script"

  # red-only label + follow-up 不在 → REJECT（exit 1）
  assert_failure
  [ "$status" -eq 1 ]
}

# ===========================================================================
# AC5.2: AC1 の AND 条件により red-only label + follow-up 不在 → CRITICAL 維持を確認
#
# RED: AC1.3 の CRITICAL 復旧ロジックが未実装のため fail
# ===========================================================================

@test "ac5.2: red-only label + follow-up 不在 → CRITICAL を維持する（AND 条件確認）" {
  # AC: AC1 の AND 条件: red-only label + follow-up 不在 → CRITICAL（status: FAIL）
  # RED: 現状 red-only label 付きで WARNING を返す（AC1.3 未実装）
  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  # gh stub: follow-up Issue 不在
  stub_command "gh" 'exit 0'

  local pr_json='{"labels":[{"name":"red-only"}],"files":[{"path":"plugins/twl/tests/bats/somefile.bats"}]}'
  run bash "$script" --pr-json "$pr_json" --pr-number 9999

  # CRITICAL が出力されること（WARNING ではない）
  assert_output --partial "CRITICAL"
  refute_output --partial "WARNING"
}

@test "ac5.2b: red-only label + follow-up 不在 → status: FAIL が含まれる（AND 条件確認）" {
  # AC: escape hatch 完全閉鎖 — FAIL status
  # RED: 現状 FAIL が含まれない
  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  stub_command "gh" 'exit 0'

  local pr_json='{"labels":[{"name":"red-only"}],"files":[{"path":"plugins/twl/tests/bats/somefile.bats"}]}'
  run bash "$script" --pr-json "$pr_json" --pr-number 9999

  assert_output --partial "FAIL"
}

@test "ac5.2c: red-only label + follow-up 存在 → WARNING（現状維持、CRITICAL に昇格しない）" {
  # AC: AND 条件: follow-up 存在時は WARNING に留まる（escape hatch が有効）
  # RED: follow-up 存在確認ロジックが未実装のため AND 評価が行われない
  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  # gh stub: follow-up Issue が存在
  stub_command "gh" 'printf "99\tfollow-up: RED-only PR #9999\n"'

  local pr_json='{"labels":[{"name":"red-only"}],"files":[{"path":"plugins/twl/tests/bats/somefile.bats"}]}'
  run bash "$script" --pr-json "$pr_json" --pr-number 9999

  # follow-up 存在時は WARNING（CRITICAL ではない）
  assert_output --partial "WARNING"
  refute_output --partial "CRITICAL"
}

@test "ac5.2d: red-only label 付与後の CRITICAL 維持により manual merge bypass が防止される" {
  # AC: regression scenario の核心 — label 付与後も CRITICAL が維持され bypass を防ぐ
  # RED: AC1.3 未実装のため bypass が可能な状態
  local worker_script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$worker_script" ]

  stub_command "gh" 'exit 0'

  # PR #1608 型の regression: label 付与後も CRITICAL が維持されること
  local pr_json='{"labels":[{"name":"red-only"}],"files":[{"path":"plugins/twl/tests/bats/somefile.bats"}]}'
  run bash "$worker_script" --pr-json "$pr_json" --pr-number 1608

  # label 付与だけでは escape hatch にならない（follow-up 不在のため CRITICAL）
  assert_output --partial "CRITICAL"
  refute_output --partial "WARNING"
}
