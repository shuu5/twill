#!/usr/bin/env bats
# int-1626-followup-auto-create-on-reject.bats
#
# Issue #1626 AC2.5 — REJECT path から follow-up Issue 自動起票の integration test
#
# AC2: merge-gate-check-red-only.sh の REJECT path で red-only label 付き PR の
#      follow-up Issue を `red-only-followup-create.sh` 経由で自動起票する。
#      idempotent: 既存の `<!-- follow-up-for: PR #N -->` marker 付き Issue があれば skip。
#
# 検証シナリオ:
#   1. red-only label 付き + follow-up 不在 → red-only-followup-create.sh が呼ばれる
#   2. red-only label 付き + follow-up 存在 → 起票しない（idempotent）
#   3. red-only label なし → 起票しない
#   4. gh pr view 失敗でも REJECT は確実に exit 1

load 'helpers/common'

SCRIPTS_DIR=""

setup() {
  common_setup
  SCRIPTS_DIR="${REPO_ROOT}/scripts"
  # gh stub のログ取り先
  export GH_CALL_LOG="${SANDBOX}/gh-calls.log"
  export FOLLOWUP_INVOKED_LOG="${SANDBOX}/followup-invoked.log"
}

teardown() {
  common_teardown
}

# ===========================================================================
# Helper: red-only-followup-create.sh を SANDBOX 内で stub に差し替える
# ===========================================================================
_stub_followup_create() {
  cat > "${SANDBOX}/scripts/red-only-followup-create.sh" <<STUB_EOF
#!/usr/bin/env bash
echo "INVOKED: \$*" >> "${FOLLOWUP_INVOKED_LOG}"
exit 0
STUB_EOF
  chmod +x "${SANDBOX}/scripts/red-only-followup-create.sh"
}

# ===========================================================================
# AC2.5-a: red-only label + follow-up 不在 → followup-create が呼ばれる
# ===========================================================================

@test "ac2.5a: red-only label + follow-up 不在 → red-only-followup-create.sh が呼ばれる" {
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  # SANDBOX 内のスクリプトを書き換え可能にコピー（既に common_setup でコピー済み）
  _stub_followup_create

  # git: test ファイルのみを返す（RED-only 状態）
  stub_command "git" '
case "$*" in
  *"diff"*"--name-only"*"origin/main"*) echo "plugins/twl/tests/bats/sample.bats" ;;
  *) exit 0 ;;
esac'

  # gh: PR 番号 42、red-only label、follow-up Issue list は空配列
  stub_command "gh" "
case \"\$*\" in
  *\"pr view\"*\"number\"*) echo '42' ;;
  *\"pr view\"*\"labels\"*) echo 'true' ;;
  *\"issue list\"*) echo '[]' ;;
  *) echo \"\$*\" >> '${GH_CALL_LOG}' ;;
esac"

  # SANDBOX のスクリプトを実行
  run bash "${SANDBOX}/scripts/merge-gate-check-red-only.sh"
  assert_failure  # RED-only → REJECT exit 1

  # red-only-followup-create.sh が呼ばれたことを確認
  [ -f "$FOLLOWUP_INVOKED_LOG" ]
  run grep -qF -- '--pr-number 42' "$FOLLOWUP_INVOKED_LOG"
  assert_success
  run grep -qF -- '--merge-gate-result REJECTED' "$FOLLOWUP_INVOKED_LOG"
  assert_success
}

# ===========================================================================
# AC2.5-b: red-only label + follow-up 存在 → 起票スキップ（idempotent）
# ===========================================================================

@test "ac2.5b: red-only label + follow-up 存在 → 起票しない（idempotent）" {
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  _stub_followup_create

  # git: test ファイルのみ
  stub_command "git" '
case "$*" in
  *"diff"*"--name-only"*"origin/main"*) echo "plugins/twl/tests/bats/sample.bats" ;;
  *) exit 0 ;;
esac'

  # gh: PR 番号 99、red-only label、follow-up Issue は marker 付きで存在
  stub_command "gh" '
case "$*" in
  *"pr view"*"number"*) echo "99" ;;
  *"pr view"*"labels"*) echo "true" ;;
  *"issue list"*)
    cat <<JSON_EOF
[{"number":888,"body":"<!-- follow-up-for: PR #99 -->\n\n本文..."}]
JSON_EOF
    ;;
  *) ;;
esac'

  run bash "${SANDBOX}/scripts/merge-gate-check-red-only.sh"
  assert_failure  # REJECT は維持
  assert_output --partial "idempotent skip"

  # followup-create が呼ばれていないこと
  if [[ -f "$FOLLOWUP_INVOKED_LOG" ]]; then
    run grep -qF -- '--pr-number 99' "$FOLLOWUP_INVOKED_LOG"
    assert_failure
  fi
}

# ===========================================================================
# AC2.5-c: red-only label なし → 起票しない
# ===========================================================================

@test "ac2.5c: red-only label なし → followup-create を呼ばない" {
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  _stub_followup_create

  stub_command "git" '
case "$*" in
  *"diff"*"--name-only"*"origin/main"*) echo "plugins/twl/tests/bats/sample.bats" ;;
  *) exit 0 ;;
esac'

  # gh: red-only label が付いていない
  stub_command "gh" '
case "$*" in
  *"pr view"*"number"*) echo "55" ;;
  *"pr view"*"labels"*) echo "false" ;;
  *"issue list"*) echo "[]" ;;
  *) ;;
esac'

  run bash "${SANDBOX}/scripts/merge-gate-check-red-only.sh"
  assert_failure  # REJECT

  # followup-create が呼ばれていないこと
  [ ! -f "$FOLLOWUP_INVOKED_LOG" ] || ! grep -qF -- '--pr-number 55' "$FOLLOWUP_INVOKED_LOG"
}

# ===========================================================================
# AC2.5-d: gh pr view 失敗でも REJECT は確実に exit 1
# ===========================================================================

@test "ac2.5d: gh pr view 失敗時も REJECT は確実に exit 1（followup 起票はスキップ）" {
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  _stub_followup_create

  stub_command "git" '
case "$*" in
  *"diff"*"--name-only"*"origin/main"*) echo "plugins/twl/tests/bats/sample.bats" ;;
  *) exit 0 ;;
esac'

  # gh: 全ての呼び出しが exit 1
  stub_command "gh" 'exit 1'

  run bash "${SANDBOX}/scripts/merge-gate-check-red-only.sh"
  assert_failure  # REJECT は確実
  assert_output --partial "REJECT: RED-only PR"

  # followup-create は呼ばれていない（PR 番号取得失敗のため）
  [ ! -f "$FOLLOWUP_INVOKED_LOG" ]
}
