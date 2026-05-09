#!/usr/bin/env bats
# int-1626-followup-auto-create-on-reject.bats
#
# Issue #1626 AC2.5: integration test
# REJECT 経路で gh issue create --draft が呼ばれることを mock で検証
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

# ===========================================================================
# AC2.5: integration test — REJECT 経路で gh issue create --draft が呼ばれる
# ===========================================================================

@test "int-1626-ac2.5: REJECT 経路で gh issue create --draft が呼ばれる（mock 検証）" {
  # AC: REJECT path で red-only-followup-create.sh が invoke され gh issue create --draft が実行される
  # RED: REJECT path への条件分岐ロジックが未実装のため gh issue create が呼ばれない
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  # git stub: テストファイルのみ（RED-only PR を模擬）
  cat > "${STUB_BIN}/git" <<'GITSTUB'
#!/usr/bin/env bash
if echo "$*" | grep -qE "diff.*origin/main|diff.*HEAD"; then
  printf "plugins/twl/tests/bats/somefile.bats\n"
else
  git "$@"
fi
GITSTUB
  chmod +x "${STUB_BIN}/git"

  # gh stub: label 取得・follow-up 検索・issue create を模擬
  local gh_log="${SANDBOX}/gh-calls.log"
  cat > "${STUB_BIN}/gh" <<GHSTUB
#!/usr/bin/env bash
if echo "\$*" | grep -qE "pr view.*labels|labels.*pr view"; then
  printf '{"labels":[{"name":"red-only"}]}\n'
elif echo "\$*" | grep -qE "issue list|issue search"; then
  # follow-up 不在
  exit 0
elif echo "\$*" | grep -qF "issue create"; then
  echo "\$*" >> "${gh_log}"
  echo "https://github.com/shuu5/twill/issues/999"
fi
GHSTUB
  chmod +x "${STUB_BIN}/gh"

  export PR_NUM=1234
  run bash "$script"

  # REJECT 経路であること（exit 1）
  assert_failure
  [ "$status" -eq 1 ]

  # gh issue create が呼ばれていること
  [ -f "$gh_log" ]
  run grep -qF 'issue create' "$gh_log"
  assert_success
}

@test "int-1626-ac2.5b: REJECT 経路で gh issue create --draft フラグが使用される" {
  # AC: draft Issue として起票される（--draft フラグが必須）
  # RED: ロジックが未実装
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  cat > "${STUB_BIN}/git" <<'GITSTUB'
#!/usr/bin/env bash
printf "plugins/twl/tests/bats/somefile.bats\n"
GITSTUB
  chmod +x "${STUB_BIN}/git"

  local gh_log="${SANDBOX}/gh-calls.log"
  cat > "${STUB_BIN}/gh" <<GHSTUB
#!/usr/bin/env bash
if echo "\$*" | grep -qE "pr view.*labels|labels.*pr view"; then
  printf '{"labels":[{"name":"red-only"}]}\n'
elif echo "\$*" | grep -qE "issue list|issue search"; then
  exit 0
elif echo "\$*" | grep -qF "issue create"; then
  echo "\$*" >> "${gh_log}"
  echo "https://github.com/shuu5/twill/issues/999"
fi
GHSTUB
  chmod +x "${STUB_BIN}/gh"

  export PR_NUM=1234
  run bash "$script"

  # --draft フラグが使用されていること
  [ -f "$gh_log" ]
  run grep -qF -- '--draft' "$gh_log"
  assert_success
}

@test "int-1626-ac2.5c: REJECT 後も merge-gate は exit 1 を維持する（起票しても merge を止める）" {
  # AC: 起票後も exit 1 を維持 — observer/人間に follow-up Issue review を要求
  # RED: 起票ロジック自体が未実装
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  cat > "${STUB_BIN}/git" <<'GITSTUB'
#!/usr/bin/env bash
printf "plugins/twl/tests/bats/somefile.bats\n"
GITSTUB
  chmod +x "${STUB_BIN}/git"

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

  export PR_NUM=1234
  run bash "$script"

  # 起票後も exit 1（merge を止める）
  assert_failure
  [ "$status" -eq 1 ]
}

@test "int-1626-ac2.5d: red-only label 付き PR で follow-up 存在時は gh issue create が呼ばれない（idempotent）" {
  # AC: follow-up 存在時は invoke しない（idempotent）
  # RED: 存在チェックロジックが未実装
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  cat > "${STUB_BIN}/git" <<'GITSTUB'
#!/usr/bin/env bash
printf "plugins/twl/tests/bats/somefile.bats\n"
GITSTUB
  chmod +x "${STUB_BIN}/git"

  local gh_log="${SANDBOX}/gh-calls.log"
  cat > "${STUB_BIN}/gh" <<GHSTUB
#!/usr/bin/env bash
if echo "\$*" | grep -qE "pr view.*labels|labels.*pr view"; then
  printf '{"labels":[{"name":"red-only"}]}\n'
elif echo "\$*" | grep -qE "issue list|issue search"; then
  # follow-up 存在
  printf "99\tfollow-up: RED-only PR #1234\n"
elif echo "\$*" | grep -qF "issue create"; then
  echo "\$*" >> "${gh_log}"
  echo "https://github.com/shuu5/twill/issues/999"
fi
GHSTUB
  chmod +x "${STUB_BIN}/gh"

  export PR_NUM=1234
  run bash "$script"

  # follow-up 存在時は gh issue create が呼ばれないこと
  if [ -f "$gh_log" ]; then
    run grep -qF 'issue create' "$gh_log"
    assert_failure
  fi
  # 起票なしでも REJECT（exit 1）は維持
  assert_failure
}
