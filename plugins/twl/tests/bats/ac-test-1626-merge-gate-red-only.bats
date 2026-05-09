#!/usr/bin/env bats
# ac-test-1626-merge-gate-red-only.bats
#
# Issue #1626: bug(merge-gate): red-only label-based bypass
#
# AC2.1: merge-gate-check-red-only.sh に gh pr view --json labels で PR の label 取得ロジックを追加し、
#         REJECT path（exit 1 直前）に red-only-followup-create.sh invoke 条件分岐を追加
#         （red-only label 付き かつ follow-up 不在の場合のみ）
# AC2.2: 起票後も merge-gate-check-red-only.sh は exit 1 を維持
# AC2.3: red-only-followup-create.sh 失敗時は merge-gate 全体が fail-closed（exit 1）
# AC2.4: red-only-followup-create.sh を idempotent 化
#         （同 PR 用 follow-up が既存ならスキップして exit 0）
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
# AC2.1: merge-gate-check-red-only.sh に gh pr view --json labels ロジック追加
#         REJECT path で red-only-followup-create.sh を条件付き invoke
#
# RED: 現状 gh pr view --json labels ロジックが存在しない
# ===========================================================================

@test "ac2.1: merge-gate-check-red-only.sh が gh pr view --json labels で label を取得する（静的確認）" {
  # AC: gh pr view --json labels ロジックが merge-gate-check-red-only.sh に追加される
  # RED: 現状このロジックが存在しない
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  run grep -qF 'gh pr view' "$script"
  assert_success
}

@test "ac2.1b: merge-gate-check-red-only.sh は --json labels フラグを使用する（静的確認）" {
  # AC: labels 取得に --json labels オプションを使用
  # RED: 現状 gh pr view 呼び出し自体が存在しない
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  run grep -qE 'gh pr view.*--json.*labels|gh pr view.*labels' "$script"
  assert_success
}

@test "ac2.1c: merge-gate-check-red-only.sh の REJECT path で red-only-followup-create.sh を条件付き invoke する（静的確認）" {
  # AC: REJECT path（exit 1 直前）に red-only-followup-create.sh invoke 条件分岐を追加
  #     red-only label 付き かつ follow-up 不在の場合のみ invoke
  # RED: 現状 red-only-followup-create.sh への呼び出しが存在しない
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  run grep -qF 'red-only-followup-create.sh' "$script"
  assert_success
}

@test "ac2.1d: merge-gate-check-red-only.sh は red-only label かつ follow-up 不在の場合のみ followup-create を invoke する" {
  # AC: 条件分岐 — red-only label 付き かつ follow-up 不在 → red-only-followup-create.sh を invoke
  # RED: 現状条件分岐が存在しないため follow-up-create が呼ばれない
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  # モック git: テストファイルのみ返す（RED-only PRを模擬）
  stub_command "git" 'echo "plugins/twl/tests/bats/somefile.bats"'

  # モック gh: label 取得で red-only を返し、follow-up 検索では空を返す
  local gh_log="${SANDBOX}/gh-calls.log"
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
if echo "$*" | grep -qE "pr view.*labels|labels.*pr view"; then
  printf '{"labels":[{"name":"red-only"}]}\n'
elif echo "$*" | grep -qE "issue list|issue search"; then
  # follow-up 不在
  exit 0
elif echo "$*" | grep -qF "issue create"; then
  echo "$*" >> "$SANDBOX/gh-calls.log"
  echo "https://github.com/shuu5/twill/issues/999"
fi
GHSTUB
  chmod +x "$STUB_BIN/gh"
  export SANDBOX

  run bash "$script"

  # red-only-followup-create.sh が invoke されること（gh issue create が呼ばれる）
  [ -f "$gh_log" ]
  run grep -qF 'issue create' "$gh_log"
  assert_success
}

# ===========================================================================
# AC2.2: 起票後も merge-gate-check-red-only.sh は exit 1 を維持
#         （merge は止め、observer/人間に follow-up Issue review を要求）
#
# RED: 現状 follow-up 起票ロジック自体が存在しない
# ===========================================================================

@test "ac2.2: merge-gate-check-red-only.sh は red-only PR で follow-up 起票後も exit 1 を返す" {
  # AC: 起票後も merge-gate は exit 1 を維持してマージを止める
  # RED: 現状条件分岐が未実装のためこの動作を検証できない
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  stub_command "git" 'echo "plugins/twl/tests/bats/somefile.bats"'

  local gh_log="${SANDBOX}/gh-calls.log"
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
if echo "$*" | grep -qE "pr view.*labels|labels.*pr view"; then
  printf '{"labels":[{"name":"red-only"}]}\n'
elif echo "$*" | grep -qE "issue list|issue search"; then
  exit 0
elif echo "$*" | grep -qF "issue create"; then
  echo "$*" >> "$SANDBOX/gh-calls.log"
  echo "https://github.com/shuu5/twill/issues/999"
fi
GHSTUB
  chmod +x "$STUB_BIN/gh"
  export SANDBOX

  run bash "$script"

  # follow-up 起票後も exit 1 でマージを止める
  assert_failure
  [ "$status" -eq 1 ]
}

# ===========================================================================
# AC2.3: red-only-followup-create.sh 失敗時は merge-gate 全体が fail-closed（exit 1）
#
# RED: 現状 followup-create 呼び出し自体が存在しない
# ===========================================================================

@test "ac2.3: red-only-followup-create.sh 失敗時に merge-gate が fail-closed（exit 1）" {
  # AC: followup-create.sh 失敗時は merge-gate 全体が fail-closed
  # RED: 現状 followup-create 呼び出しが存在しないため fail-closed を検証できない
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  stub_command "git" 'echo "plugins/twl/tests/bats/somefile.bats"'

  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
if echo "$*" | grep -qE "pr view.*labels|labels.*pr view"; then
  printf '{"labels":[{"name":"red-only"}]}\n'
elif echo "$*" | grep -qE "issue list|issue search"; then
  exit 0
elif echo "$*" | grep -qF "issue create"; then
  # followup-create 失敗を模擬
  echo "ERROR: gh issue create failed" >&2
  exit 1
fi
GHSTUB
  chmod +x "$STUB_BIN/gh"

  run bash "$script"

  # followup-create 失敗時も fail-closed（exit 1）
  assert_failure
  [ "$status" -eq 1 ]
}

# ===========================================================================
# AC2.4: red-only-followup-create.sh を idempotent 化
#         （同 PR 用 follow-up が既存ならスキップして exit 0）
#
# RED: 現状 idempotent チェックが存在しない
# ===========================================================================

@test "ac2.4: red-only-followup-create.sh は同 PR の follow-up が既存ならスキップして exit 0" {
  # AC: idempotent — 同 PR 用 follow-up が既存ならスキップして exit 0
  # RED: 現状既存チェックロジックが存在しない
  local script="${SCRIPTS_DIR}/red-only-followup-create.sh"
  [ -f "$script" ]

  local gh_log="${SANDBOX}/gh-calls.log"
  cat > "$STUB_BIN/gh" <<GHSTUB
#!/usr/bin/env bash
if echo "\$*" | grep -qE "issue list|issue search"; then
  # 既存 follow-up が存在することを返す
  printf "99\tfollow-up: RED-only PR #1234\n"
elif echo "\$*" | grep -qF "issue create"; then
  # 既存なら create が呼ばれないはず
  echo "\$*" >> "${gh_log}"
  echo "https://github.com/shuu5/twill/issues/888"
fi
GHSTUB
  chmod +x "$STUB_BIN/gh"

  run bash "$script" --pr-number 1234
  assert_success

  # gh issue create が呼ばれないこと（スキップ）
  if [ -f "$gh_log" ]; then
    run grep -qF 'issue create' "$gh_log"
    assert_failure
  fi
}

@test "ac2.4b: red-only-followup-create.sh は follow-up 不在の場合に gh issue create を呼ぶ" {
  # AC: idempotent — 既存なし → gh issue create を実行
  # RED: idempotent ロジック追加後の正常パスを検証
  local script="${SCRIPTS_DIR}/red-only-followup-create.sh"
  [ -f "$script" ]

  local gh_log="${SANDBOX}/gh-calls.log"
  cat > "$STUB_BIN/gh" <<GHSTUB
#!/usr/bin/env bash
if echo "\$*" | grep -qE "issue list|issue search"; then
  # follow-up 不在
  exit 0
elif echo "\$*" | grep -qF "issue create"; then
  echo "\$*" >> "${gh_log}"
  echo "https://github.com/shuu5/twill/issues/777"
fi
GHSTUB
  chmod +x "$STUB_BIN/gh"

  run bash "$script" --pr-number 5678
  assert_success

  [ -f "$gh_log" ]
  run grep -qF 'issue create' "$gh_log"
  assert_success
}

@test "ac2.4c: red-only-followup-create.sh のスキップ時に skip メッセージを出力する" {
  # AC: idempotent スキップ時は skip であることを出力する
  # RED: skip ロジックが未実装
  local script="${SCRIPTS_DIR}/red-only-followup-create.sh"
  [ -f "$script" ]

  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
if echo "$*" | grep -qE "issue list|issue search"; then
  printf "99\tfollow-up: RED-only PR #1234\n"
fi
GHSTUB
  chmod +x "$STUB_BIN/gh"

  run bash "$script" --pr-number 1234
  assert_output --partial "skip"
}
