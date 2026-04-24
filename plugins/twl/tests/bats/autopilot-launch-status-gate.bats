#!/usr/bin/env bats
# autopilot-launch-status-gate.bats
#
# Issue #955: autopilot-launch.sh の _check_refined_status 関数内の
#             label fallback path (L234-238 と L247-252) で
#             `pipefail` + `grep -c || echo "0"` により
#             rate limit 時に has_label="0\n0" となり bash syntax error が発生するバグ
#
# AC1: L235/L248 pipeline を Option A 形式 `if gh ... | grep -Fxq 'refined'; then has_label=1; fi` に置換
# AC2: rate limit 再現テスト — has_label が単一値に固定され syntax error が発生しないこと
# AC3: 既存テストとの regression なし（テスト追加のみ）
# AC4: ログメッセージ整合性 — ALLOW_LABEL_FALLBACK / DENY_API_FAILURE / DENY_NOT_ON_BOARD
# AC5: bash -n が syntax error なく通過する
# AC6: AC2 のテストが Board 取得失敗 path と Board 未登録 path を独立にカバーする

load 'helpers/common'

SCRIPT=""

# ---------------------------------------------------------------------------
# Helper: _check_refined_status 関数定義のみを抽出して inline harness で実行
# ---------------------------------------------------------------------------

# _run_status_gate <issue_num> <bypass> [extra_env_overrides...]
# autopilot-launch.sh の _check_refined_status をインライン subshell で呼び出す
# SANDBOX, STUB_BIN, _STATUS_GATE_LOG を前提とする
_run_status_gate() {
  local issue_num="$1"
  local bypass="${2:-0}"

  # 関数定義を動的抽出（行番号ハードコード回避）
  local func_def
  func_def=$(sed -n '/^_check_refined_status()/,/^}/p' "$SCRIPT")

  run bash -c "
set -euo pipefail
export PATH='${STUB_BIN}:/usr/bin:/bin'
export _STATUS_GATE_LOG='${SANDBOX}/gate.log'

${func_def}

_check_refined_status '${issue_num}' '${bypass}'
"
}

setup() {
  common_setup

  SCRIPT="${REPO_ROOT}/scripts/autopilot-launch.sh"
  : > "$SANDBOX/gate.log"

  # git stub
  stub_command "git" 'echo "stub-git"'

  # jq: real jq をそのまま使用（stub_bin に転送しない）
  # NOTE: STUB_BIN はパス先頭にあるため、jq を stub しない場合は実 jq が使われる
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC5: bash -n が syntax error なく通過すること
# RED: 現在の実装も bash -n は通過するが、ランタイム時に syntax error が発生する
#      このテストは実装後もパスし続けるべき
# ===========================================================================

@test "ac5: bash -n が syntax error なく通過する" {
  # bash -n は静的チェック。実装前後ともに通過すべき
  run bash -n "$SCRIPT"
  assert_success
}

# ===========================================================================
# AC2 + AC6: rate limit 再現 — Board 取得失敗 path (L234-238 block)
#
# Board 取得失敗 path: board_items="" かつ status="" → L232 条件が真
# WHEN: gh project item-list が exit 1 (stdout 空)
#       gh issue view --json labels が exit 1 (rate limit: stderr のみ, stdout 空)
# THEN: _check_refined_status は syntax error (exit 2) を出さず、
#       exit 1 で DENY し、has_label が単一値であること
#
# RED: 現在の実装では has_label="0\n0" となり [[: 0\n0: syntax error が発生する
# ===========================================================================

@test "ac2+ac6: Board取得失敗path — rate limit で has_label syntax error が発生しない" {
  # gh: project item-list → exit 1 (board 取得失敗)
  #     issue view         → exit 1, stderr のみ (rate limit)
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"repo view"*)
    echo "shuu5" ;;
  *"project item-list"*)
    # Board API 失敗 (rate limit / auth error)
    echo "GraphQL: rate limit exceeded" >&2
    exit 1 ;;
  *"issue view"*"--json labels"*)
    # rate limit: stdout 空, stderr のみ
    echo "API rate limit exceeded for installation" >&2
    exit 1 ;;
  *)
    exit 1 ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  stub_command "python3" 'echo "6"'

  _run_status_gate "955" "0"

  # syntax error 発生時は bash exit code 2、かつ stderr に "syntax error" が含まれる
  # RED: 現在の実装は syntax error で失敗する
  # PASS 条件（実装後）: exit code が 1 であり、"syntax error" が出力されないこと
  refute_output --partial "syntax error"
  [ "$status" -ne 2 ] || {
    echo "FAIL: syntax error (exit 2) が発生した。has_label が複数行になっている可能性がある"
    echo "output: $output"
    return 1
  }
  # deny されること (exit 1)
  [ "$status" -eq 1 ]
}

@test "ac2+ac6: Board取得失敗path — rate limit でも DENY_API_FAILURE がログに記録される" {
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"repo view"*) echo "shuu5" ;;
  *"project item-list"*)
    echo "rate limit exceeded" >&2
    exit 1 ;;
  *"issue view"*"--json labels"*)
    echo "rate limit exceeded" >&2
    exit 1 ;;
  *) exit 1 ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  stub_command "python3" 'echo "6"'

  _run_status_gate "955" "0"

  # RED: 現在の実装は syntax error で abort するため gate.log に何も書かれないか、
  #      または DENY_API_FAILURE の前に abort する
  # PASS 条件（実装後）: gate.log に DENY_API_FAILURE が記録される
  run grep -F "DENY_API_FAILURE" "$SANDBOX/gate.log"
  assert_success
}

# ===========================================================================
# AC2 + AC6: rate limit 再現 — Board 未登録 path (L247-252 block)
#
# Board 未登録 path: board_items 非空 だが status="" → L245 条件が真
# WHEN: gh project item-list が空 JSON（Issue が Board 未登録）
#       gh issue view --json labels が exit 1 (rate limit)
# THEN: syntax error なし、exit 1 で DENY
#
# RED: 現在の実装では L248 でも同じ has_label="0\n0" 問題が発生する
# ===========================================================================

@test "ac2+ac6: Board未登録path — rate limit で has_label syntax error が発生しない" {
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"repo view"*) echo "shuu5" ;;
  *"project item-list"*)
    # Board 取得成功だが issue が含まれていない（未登録）
    echo '{"items": []}'
    exit 0 ;;
  *"issue view"*"--json labels"*)
    # label fetch 時に rate limit
    echo "API rate limit exceeded for installation" >&2
    exit 1 ;;
  *) exit 1 ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  stub_command "python3" 'echo "6"'

  _run_status_gate "42" "0"

  # RED: 現在の実装は syntax error で失敗する
  refute_output --partial "syntax error"
  [ "$status" -ne 2 ] || {
    echo "FAIL: syntax error (exit 2) が発生した。has_label が複数行になっている可能性がある"
    echo "output: $output"
    return 1
  }
  [ "$status" -eq 1 ]
}

@test "ac2+ac6: Board未登録path — rate limit でも DENY_NOT_ON_BOARD がログに記録される" {
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"repo view"*) echo "shuu5" ;;
  *"project item-list"*)
    echo '{"items": []}'
    exit 0 ;;
  *"issue view"*"--json labels"*)
    echo "rate limit exceeded" >&2
    exit 1 ;;
  *) exit 1 ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  stub_command "python3" 'echo "6"'

  _run_status_gate "42" "0"

  # RED: 現在の実装では syntax error で abort するため DENY_NOT_ON_BOARD が記録されない
  run grep -F "DENY_NOT_ON_BOARD" "$SANDBOX/gate.log"
  assert_success
}

# ===========================================================================
# AC1: Option A 形式への置換確認
# `grep -c` + `|| echo "0"` の複合パターンが残っていないこと
# RED: 現在の実装にはこのパターンが存在する（L235, L248）
# ===========================================================================

@test "ac1: L235 に grep -c パターンが残っていない (Option A 形式に置換済み)" {
  # 現在の実装: has_label=\$(... | grep -c ... || echo "0")
  # 実装後: if ... | grep -Fxq 'refined'; then has_label=1; fi
  #
  # RED: 現在のファイルにはこのパターンが存在するためテストが fail する
  run grep -n 'grep -c.*refined\|grep -c.*\^refined' "$SCRIPT"
  # Option A 形式では grep -c が使われないため、マッチ数が 0 であること
  [ "${#lines[@]}" -eq 0 ] || {
    echo "FAIL: grep -c パターンがまだ残っている:"
    for line in "${lines[@]}"; do
      echo "  $line"
    done
    return 1
  }
}

@test "ac1: L248 にも grep -c パターンが残っていない (Board 未登録 path)" {
  # Board 未登録 path (L247-252) も同様に修正される必要がある
  # count(): has_label pipeline での grep -c 使用箇所を数える
  local count
  count=$(grep -c 'has_label.*grep -c\|grep -c.*has_label' "$SCRIPT" 2>/dev/null || true)
  [ "$count" -eq 0 ] || {
    echo "FAIL: has_label=\$(... | grep -c ...) パターンが ${count} 箇所残っている"
    grep -n 'has_label.*grep -c\|grep -c.*has_label' "$SCRIPT"
    return 1
  }
}

# ===========================================================================
# AC4: ログメッセージ整合性
# ALLOW_LABEL_FALLBACK / DENY_API_FAILURE / DENY_NOT_ON_BOARD の
# サフィックスが既存実装と完全一致すること
# RED: 実装後にメッセージが変わった場合に検知する（現在は syntax error で到達不可なため RED）
# ===========================================================================

@test "ac4: Board取得失敗path で DENY — ログに 'DENY_API_FAILURE issue=#' が含まれる" {
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"repo view"*) echo "shuu5" ;;
  *"project item-list"*)
    exit 1 ;;
  *"issue view"*"--json labels"*)
    # labels なし (refined ラベルなし)
    echo ""
    exit 0 ;;
  *) exit 1 ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  stub_command "python3" 'echo "6"'

  _run_status_gate "955" "0"

  # DENY_API_FAILURE サフィックスの確認
  run grep -F "DENY_API_FAILURE issue=#955" "$SANDBOX/gate.log"
  assert_success
}

@test "ac4: Board未登録path で DENY — ログに 'DENY_NOT_ON_BOARD issue=#' が含まれる" {
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"repo view"*) echo "shuu5" ;;
  *"project item-list"*)
    echo '{"items": []}'
    exit 0 ;;
  *"issue view"*"--json labels"*)
    # refined ラベルなし
    echo ""
    exit 0 ;;
  *) exit 1 ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  stub_command "python3" 'echo "6"'

  _run_status_gate "42" "0"

  run grep -F "DENY_NOT_ON_BOARD issue=#42" "$SANDBOX/gate.log"
  assert_success
}

@test "ac4: Board取得失敗path で refined label あり — ログに 'ALLOW_LABEL_FALLBACK issue=#' が含まれる" {
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"repo view"*) echo "shuu5" ;;
  *"project item-list"*)
    exit 1 ;;
  *"issue view"*"--json labels"*)
    # refined ラベルあり
    printf 'bug\nrefined\nenhancement\n'
    exit 0 ;;
  *) exit 1 ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  stub_command "python3" 'echo "6"'

  _run_status_gate "955" "0"

  # ALLOW_LABEL_FALLBACK サフィックスの確認
  # RED: 現在の実装では syntax error で abort するため gate.log に記録されない
  run grep -F "ALLOW_LABEL_FALLBACK issue=#955" "$SANDBOX/gate.log"
  assert_success
}

@test "ac4: Board未登録path で refined label あり — ログに 'ALLOW_LABEL_FALLBACK issue=#' が含まれる" {
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"repo view"*) echo "shuu5" ;;
  *"project item-list"*)
    echo '{"items": []}'
    exit 0 ;;
  *"issue view"*"--json labels"*)
    printf 'bug\nrefined\nenhancement\n'
    exit 0 ;;
  *) exit 1 ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  stub_command "python3" 'echo "6"'

  _run_status_gate "42" "0"

  # RED: 現在の実装は syntax error で abort するため ALLOW_LABEL_FALLBACK が記録されない
  run grep -F "ALLOW_LABEL_FALLBACK issue=#42" "$SANDBOX/gate.log"
  assert_success
}

# ===========================================================================
# AC2: has_label が単一値であること（0 or 1）
# 実装後の回帰防止テスト
# ===========================================================================

@test "ac2: Board取得失敗path — refined label なし時に exit 1 で DENY される" {
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"repo view"*) echo "shuu5" ;;
  *"project item-list"*)
    exit 1 ;;
  *"issue view"*"--json labels"*)
    echo ""
    exit 0 ;;
  *) exit 1 ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  stub_command "python3" 'echo "6"'

  _run_status_gate "955" "0"

  # RED: 現在の実装は syntax error (exit 2) を出す
  # PASS 条件（実装後）: exit 1 で DENY
  assert_failure
  [ "$status" -eq 1 ]
}

@test "ac2: Board取得失敗path — refined label あり時に exit 0 で ALLOW される" {
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"repo view"*) echo "shuu5" ;;
  *"project item-list"*)
    exit 1 ;;
  *"issue view"*"--json labels"*)
    printf 'bug\nrefined\n'
    exit 0 ;;
  *) exit 1 ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  stub_command "python3" 'echo "6"'

  _run_status_gate "955" "0"

  # RED: 現在の実装は syntax error で abort する
  # PASS 条件（実装後）: ALLOW_LABEL_FALLBACK で exit 0
  assert_success
}

@test "ac2: Board未登録path — refined label なし時に exit 1 で DENY される" {
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"repo view"*) echo "shuu5" ;;
  *"project item-list"*)
    echo '{"items": []}'
    exit 0 ;;
  *"issue view"*"--json labels"*)
    echo ""
    exit 0 ;;
  *) exit 1 ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  stub_command "python3" 'echo "6"'

  _run_status_gate "42" "0"

  # RED: 現在の実装は syntax error (exit 2) を出す
  assert_failure
  [ "$status" -eq 1 ]
}

@test "ac2: Board未登録path — refined label あり時に exit 0 で ALLOW される" {
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"repo view"*) echo "shuu5" ;;
  *"project item-list"*)
    echo '{"items": []}'
    exit 0 ;;
  *"issue view"*"--json labels"*)
    printf 'bug\nrefined\n'
    exit 0 ;;
  *) exit 1 ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  stub_command "python3" 'echo "6"'

  _run_status_gate "42" "0"

  # RED: 現在の実装は syntax error で abort する
  assert_success
}
