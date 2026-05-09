#!/usr/bin/env bats
# int-1626-layer1-fail-closed-on-fetch-failure.bats
#
# Issue #1626 AC4.4: integration test
# origin/main ref 削除モックで git diff を空にし、gh pr view も unset で REJECT 確認
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
# AC4.4: integration test
# origin/main ref 削除モックで git diff を空にし、gh pr view も unset で REJECT 確認
# ===========================================================================

@test "int-1626-ac4.4: git diff 空 + gh pr view 失敗 → REJECT: 変更ファイル取得不能 で exit 1" {
  # AC: origin/main ref 削除モック → git diff 空 → gh pr view unset → fail-closed REJECT
  # RED: fallback ロジックが未実装のため exit 0 してしまう
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  # git stub: origin/main ref 削除を模擬（diff が空）
  _stub_command "git" 'exit 0'

  # gh stub: API 失敗（PR_NUM 不在または接続失敗）
  _stub_command "gh" 'exit 1'

  # PR_NUM を unset
  unset PR_NUM 2>/dev/null || true

  run bash "$script"

  # fail-closed REJECT（exit 1）
  assert_failure
  [ "$status" -eq 1 ]
}

@test "int-1626-ac4.4b: REJECT メッセージに 取得不能 が含まれる" {
  # AC: REJECT: 変更ファイル取得不能 — fail-closed を出力
  # RED: この出力パスが存在しない
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  _stub_command "git" 'exit 0'
  _stub_command "gh" 'exit 1'

  unset PR_NUM 2>/dev/null || true

  run bash "$script"

  assert_output --partial "REJECT"
  assert_output --partial "取得不能"
}

@test "int-1626-ac4.4c: git diff 空 + PR_NUM 設定 + gh pr view 成功 → fallback でファイルリスト取得" {
  # AC: fallback パス — gh pr view が成功した場合はファイルリストを使用して判定
  # RED: fallback ロジックが未実装
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  # git stub: 空（origin/main ref なし）
  _stub_command "git" 'exit 0'

  # gh stub: pr view でテストファイルを返す
  cat > "${STUB_BIN}/gh" <<'GHSTUB'
#!/usr/bin/env bash
if echo "$*" | grep -qE "pr view.*files|files.*pr view"; then
  printf "plugins/twl/tests/bats/somefile.bats\n"
else
  exit 0
fi
GHSTUB
  chmod +x "${STUB_BIN}/gh"

  export PR_NUM=1234

  run bash "$script"

  # テストファイルのみ → REJECT（exit 1）
  assert_failure
  [ "$status" -eq 1 ]
  assert_output --partial "REJECT"
}

@test "int-1626-ac4.4d: git diff 空 + gh pr view fallback で実装ファイルあり → PASS" {
  # AC: fallback で取得したファイルに実装ファイルが含まれる → PASS
  # RED: fallback ロジックが未実装
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  _stub_command "git" 'exit 0'

  cat > "${STUB_BIN}/gh" <<'GHSTUB'
#!/usr/bin/env bash
if echo "$*" | grep -qE "pr view.*files|files.*pr view"; then
  printf "plugins/twl/scripts/some-script.sh\nplugins/twl/tests/bats/somefile.bats\n"
else
  exit 0
fi
GHSTUB
  chmod +x "${STUB_BIN}/gh"

  export PR_NUM=1234

  run bash "$script"

  # 実装ファイルあり → PASS（exit 0）
  assert_success
}

@test "int-1626-ac4.4e: git diff が有効（非空）の場合は gh pr view を呼ばない（fallback 発動しない）" {
  # AC: git diff が空でない場合は従来パスを使用（fallback 不発動）
  # RED: fallback 実装後に常に gh を呼ぶようになっていた場合に fail
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  local gh_log="${SANDBOX}/gh-calls.log"

  # git stub: 実装ファイルを返す（非空）
  cat > "${STUB_BIN}/git" <<'GITSTUB'
#!/usr/bin/env bash
printf "plugins/twl/scripts/some-script.sh\n"
GITSTUB
  chmod +x "${STUB_BIN}/git"

  # gh stub: 呼ばれたらログ記録
  cat > "${STUB_BIN}/gh" <<GHSTUB
#!/usr/bin/env bash
if echo "\$*" | grep -qE "pr view.*files|files.*pr view"; then
  echo "\$*" >> "${gh_log}"
  printf "plugins/twl/scripts/some-script.sh\n"
fi
GHSTUB
  chmod +x "${STUB_BIN}/gh"

  export PR_NUM=1234
  run bash "$script"

  # 実装ファイルあり → PASS
  assert_success

  # gh pr view が呼ばれていないこと（fallback 不発動）
  if [ -f "$gh_log" ]; then
    run grep -qE 'pr view.*files|files.*pr view' "$gh_log"
    assert_failure
  fi
}
