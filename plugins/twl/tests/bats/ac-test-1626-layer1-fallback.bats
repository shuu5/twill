#!/usr/bin/env bats
# ac-test-1626-layer1-fallback.bats
#
# Issue #1626: bug(merge-gate): red-only label-based bypass
#
# AC4.1: git diff --name-only origin/main が空文字を返した場合、
#         gh pr view ${PR_NUM} --json files -q '.files[].path' で fallback 取得
# AC4.2: gh pr view も失敗（PR_NUM 不在 / API 失敗）時は明示的に
#         REJECT: 変更ファイル取得不能 — fail-closed を出力して exit 1
# AC4.3: 既存の「変更ファイルあり、test-only」判定パスは現状維持（regression guard）
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
# AC4.1: git diff が空の場合に gh pr view で fallback 取得
#
# RED: 現状 fallback ロジックが存在しない（空文字で exit 0 してしまう）
# ===========================================================================

@test "ac4.1: merge-gate-check-red-only.sh は git diff 空時に gh pr view でファイルリストを fallback 取得する" {
  # AC: git diff --name-only origin/main が空文字 → gh pr view ${PR_NUM} --json files で fallback
  # RED: 現状空ファイルリストで exit 0 するため fallback が存在しない
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  # git stub: 空文字を返す（origin/main から差分なし）
  stub_command "git" 'exit 0'

  # gh stub: fallback でテストファイルのリストを返す
  local gh_log="${SANDBOX}/gh-calls.log"
  cat > "$STUB_BIN/gh" <<GHSTUB
#!/usr/bin/env bash
if echo "\$*" | grep -qE "pr view.*files|files.*pr view"; then
  echo "\$*" >> "${gh_log}"
  printf "plugins/twl/tests/bats/somefile.bats\n"
fi
GHSTUB
  chmod +x "$STUB_BIN/gh"

  export PR_NUM=1234
  run bash "$script"

  # gh pr view が呼ばれていること（fallback が発動）
  [ -f "$gh_log" ]
  run grep -qE 'pr view.*files|files.*pr view' "$gh_log"
  assert_success
}

@test "ac4.1b: merge-gate-check-red-only.sh のスクリプトに gh pr view fallback ロジックが存在する（静的確認）" {
  # AC: gh pr view ${PR_NUM} --json files -q '.files[].path' によるフォールバック
  # RED: 現状 fallback ロジックが存在しない
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  run grep -qE 'gh pr view.*files|fallback|PR_NUM' "$script"
  assert_success
}

@test "ac4.1c: merge-gate-check-red-only.sh は git diff 空 + fallback でテストのみファイル → REJECT する" {
  # AC: fallback 取得したファイルリストでも RED-only 判定が動作すること
  # RED: fallback ロジックが未実装
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  stub_command "git" 'exit 0'

  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
if echo "$*" | grep -qE "pr view.*files|files.*pr view"; then
  printf "plugins/twl/tests/bats/somefile.bats\n"
fi
GHSTUB
  chmod +x "$STUB_BIN/gh"

  export PR_NUM=1234
  run bash "$script"

  # テストのみなので REJECT（exit 1）
  assert_failure
  assert_output --partial "REJECT"
}

# ===========================================================================
# AC4.2: gh pr view 失敗時は明示的に REJECT: 変更ファイル取得不能 — fail-closed を出力して exit 1
#
# RED: 現状 fail-closed ロジックが存在しない
# ===========================================================================

@test "ac4.2: merge-gate-check-red-only.sh は gh pr view 失敗時に fail-closed で exit 1 する" {
  # AC: gh pr view 失敗（PR_NUM 不在 / API 失敗）時は REJECT + exit 1（fail-closed）
  # RED: 現状この fail-closed パスが存在しない
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  # git stub: 空文字（fallback トリガー）
  stub_command "git" 'exit 0'

  # gh stub: pr view が失敗
  stub_command "gh" 'exit 1'

  # PR_NUM を設定しない（または API 失敗）
  run bash "$script"

  assert_failure
  [ "$status" -eq 1 ]
}

@test "ac4.2b: merge-gate-check-red-only.sh は gh pr view 失敗時に REJECT 変更ファイル取得不能 を出力する" {
  # AC: REJECT: 変更ファイル取得不能 — fail-closed メッセージを出力
  # RED: 現状このメッセージを出力するロジックが存在しない
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  stub_command "git" 'exit 0'
  stub_command "gh" 'exit 1'

  run bash "$script"

  assert_output --partial "REJECT"
  assert_output --partial "取得不能"
}

@test "ac4.2c: merge-gate-check-red-only.sh は PR_NUM 未設定で gh fallback 失敗時も fail-closed" {
  # AC: PR_NUM 不在 → gh pr view 呼び出し不能 → fail-closed
  # RED: fallback ロジックが未実装
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  stub_command "git" 'exit 0'
  # gh が呼ばれないか、呼ばれても失敗する
  stub_command "gh" 'exit 1'

  # PR_NUM unset
  unset PR_NUM 2>/dev/null || true
  run bash "$script"

  assert_failure
  [ "$status" -eq 1 ]
}

# ===========================================================================
# AC4.3: 既存の「変更ファイルあり、test-only」判定パスは現状維持（regression guard）
#
# RED: regression guard — 既存動作が変わると fail する
# ===========================================================================

@test "ac4.3: merge-gate-check-red-only.sh は test-only PR で REJECT する（regression guard）" {
  # AC: 既存の test-only 判定パスは現状維持
  # RED: fallback 実装後に既存動作が壊れると fail する
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  # git diff でテストファイルのみ返す（既存の動作パス）
  stub_command "git" 'printf "plugins/twl/tests/bats/somefile.bats\n"'

  run bash "$script"

  # 現状維持: test-only は REJECT（exit 1）
  assert_failure
  [ "$status" -eq 1 ]
  assert_output --partial "REJECT"
}

@test "ac4.3b: merge-gate-check-red-only.sh は実装ファイルを含む PR で PASS する（regression guard）" {
  # AC: 実装ファイルが含まれる場合は通過（既存動作維持）
  # RED: fallback 実装後に既存動作が壊れると fail する
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  # git diff で実装ファイルも返す
  stub_command "git" 'printf "plugins/twl/scripts/some-script.sh\nplugins/twl/tests/bats/somefile.bats\n"'

  run bash "$script"

  # 実装ファイルあり → 通過（exit 0）
  assert_success
}

@test "ac4.3c: merge-gate-check-red-only.sh は変更ファイルが空の場合（origin/main と同一）で PASS する（regression guard）" {
  # AC: 変更ファイルなし（git diff 空）の場合の動作
  # NOTE: fallback 実装後に PR_NUM が不在の場合は fail-closed になる可能性があるため、
  #       PR_NUM なし + git diff 空の場合の挙動を確認する
  # RED: fallback 実装で既存の空ファイル=PASS が壊れる場合に fail する
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  # git stub: 完全に空（変更なし）
  stub_command "git" 'exit 0'
  # gh stub: fallback も空（または失敗）
  stub_command "gh" 'exit 1'

  # PR_NUM なし（既存テストが依存している動作）
  unset PR_NUM 2>/dev/null || true

  run bash "$script"

  # AC4.2 の fail-closed により exit 1 が期待される（仕様変更の確認）
  # fallback 前の既存動作: exit 0
  # fallback 後の期待動作: exit 1（fail-closed）
  # 実装者はどちらの動作にするか選択する必要がある
  # RED: 現状 exit 0 だが AC4.2 実装後は exit 1 になる
  assert_failure
}
