#!/usr/bin/env bats
# session-init.bats - Issue #1459 AC1-AC4 RED テスト
#
# 問題: session-init.sh が /proc/$PPID/cmdline を参照するが、
#       bash subshell 経由で実行すると $PPID が bash を指すため
#       cld の --dangerously-skip-permissions が検出されず mode="" になる。
#
# AC1: cld を --dangerously-skip-permissions で起動した状態で session-init.sh 実行
#      → mode=bypass が記録される
# AC2: cld を --permission-mode auto で起動した状態で実行 → mode=auto が記録される
# AC3: cld 起動なし (素の bash) で実行 → mode=unknown または空 + WARN (現行動作維持)
# AC4: bats test が plugins/twl/tests/bats/scripts/session-init.bats に存在する
#
# テスト戦略（RED フェーズ）:
#   bash subshell 経由（bash -c "bash session-init.sh"）で実行すると
#   $PPID が bash を指すため現行実装では mode="" になる（バグ再現）。
#   修正実装は pgrep -f claude でプロセスツリーを辿るため、
#   pgrep スタブ + fake /proc/<PID>/cmdline でモック可能。
#   現行実装は pgrep を使わないので RED（FAIL）となる。
#
# 注意: SESSION_INIT_CMDLINE_OVERRIDE は使用しない。
#   それを使うと既存の su-observer-session-init-mode-extraction.bats と
#   同等になり、バグ再現にならないため。
#
# source guard 確認:
#   session-init.sh に BASH_SOURCE guard は存在しない（set -euo pipefail のみ）。
#   bash サブシェル経由の run bash "$SCRIPT_SRC" は問題なく動作する。
#   source ではなく bash で呼ぶため main 到達前の exit リスクはない。

load '../helpers/common'

SCRIPT_SRC=""

setup() {
  common_setup

  # REPO_ROOT = plugins/twl/
  SCRIPT_SRC="${REPO_ROOT}/skills/su-observer/scripts/session-init.sh"

  # SUPERVISOR_DIR をサンドボックス内に設定
  export SUPERVISOR_DIR="${SANDBOX}/.supervisor"
  mkdir -p "${SUPERVISOR_DIR}"

  # tmux stub: session-init.sh が呼ぶが AC と無関係
  stub_command "tmux" 'echo "test-window"'

  # twl stub: audit on は AC と無関係
  stub_command "twl" 'exit 0'

  # SESSION_INIT_CMDLINE_OVERRIDE を明示的にリセット（既存テストの env 混入防止）
  unset SESSION_INIT_CMDLINE_OVERRIDE
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: bash subshell 経由 + pgrep スタブで --dangerously-skip-permissions
#      を持つ claude プロセスをモック → mode=bypass が記録される
#
# RED 理由: 現行実装は pgrep を使わず $PPID/cmdline のみを参照するため、
#           bash subshell から実行すると PPID=bash となり
#           --dangerously-skip-permissions が検出されず mode="" になる。
# ===========================================================================

@test "ac1: bash subshell 経由でも --dangerously-skip-permissions が検出され mode=bypass が記録される" {
  # fake claude プロセスの cmdline を /proc 風の一時ファイルとして作成
  # 修正実装が pgrep -f claude → PID → /proc/<PID>/cmdline を参照する場合に使用
  local fake_claude_pid="99991"
  local fake_proc_dir="${SANDBOX}/proc/${fake_claude_pid}"
  mkdir -p "${fake_proc_dir}"
  # null 区切りの cmdline（実際の /proc/<PID>/cmdline 形式）
  printf 'node\0/usr/local/bin/claude\0--dangerously-skip-permissions\0' \
    > "${fake_proc_dir}/cmdline"

  # pgrep スタブ: "claude" または "cld" を検索すると fake_claude_pid を返す
  # 修正実装が使う想定の pgrep 呼び出し形式（-f claude 等）に対応
  stub_command "pgrep" "echo ${fake_claude_pid}"

  # SESSION_INIT_PGREP_PROC_DIR で fake /proc ルートを注入
  # （修正実装がこの env var を参照することを期待）
  export SESSION_INIT_PGREP_PROC_DIR="${SANDBOX}/proc"

  # bash subshell 経由で実行し PPID=bash 状態を再現
  # （SESSION_INIT_CMDLINE_OVERRIDE を使わない点が既存テストと異なる）
  run bash "${SCRIPT_SRC}"

  assert_success

  local session_file="${SUPERVISOR_DIR}/session.json"
  [[ -f "${session_file}" ]] \
    || fail "session.json が作成されていない: ${session_file}"

  local actual_mode
  actual_mode=$(jq -r '.mode // empty' "${session_file}" 2>/dev/null || echo "")

  [[ "${actual_mode}" == "bypass" ]] \
    || fail "AC1 FAIL: mode は 'bypass' であるべきだが '${actual_mode}' だった。
原因: 現行実装は \$PPID/cmdline のみ参照するため bash subshell 経由で PPID=bash となり
      --dangerously-skip-permissions が検出されない（#1459 バグ再現）。
修正: pgrep -f claude でプロセスツリーを辿る実装が必要。"
}

# ---------------------------------------------------------------------------
# AC1 サブシナリオ: pgrep が複数 PID を返す場合も正しく処理される
# RED 理由: 同上
# ---------------------------------------------------------------------------

@test "ac1-multi-pid: pgrep が複数 PID を返す場合も最初の bypass プロセスが検出される" {
  local fake_pid_bypass="99991"
  local fake_pid_auto="99992"

  # bypass プロセス
  local proc_dir_bypass="${SANDBOX}/proc/${fake_pid_bypass}"
  mkdir -p "${proc_dir_bypass}"
  printf 'node\0/usr/local/bin/claude\0--dangerously-skip-permissions\0' \
    > "${proc_dir_bypass}/cmdline"

  # auto プロセス（存在するが bypass が優先されるべき）
  local proc_dir_auto="${SANDBOX}/proc/${fake_pid_auto}"
  mkdir -p "${proc_dir_auto}"
  printf 'node\0/usr/local/bin/claude\0--permission-mode\0auto\0' \
    > "${proc_dir_auto}/cmdline"

  # pgrep が複数 PID を返す
  stub_command "pgrep" "printf '${fake_pid_bypass}\n${fake_pid_auto}\n'"

  export SESSION_INIT_PGREP_PROC_DIR="${SANDBOX}/proc"

  run bash "${SCRIPT_SRC}"

  assert_success

  local actual_mode
  actual_mode=$(jq -r '.mode // empty' "${SUPERVISOR_DIR}/session.json" 2>/dev/null || echo "")

  [[ "${actual_mode}" == "bypass" ]] \
    || fail "AC1-multi-pid FAIL: mode は 'bypass' であるべきだが '${actual_mode}' だった。
修正実装は複数 PID から bypass を持つプロセスを検出できる必要がある。"
}

# ===========================================================================
# AC2: bash subshell 経由 + pgrep スタブで --permission-mode auto を持つ
#      claude プロセスをモック → mode=auto が記録される
#
# RED 理由: 現行実装は pgrep を使わず $PPID/cmdline のみを参照するため、
#           bash subshell から実行すると PPID=bash となり
#           --permission-mode auto が検出されず mode="" になる。
# ===========================================================================

@test "ac2: bash subshell 経由でも --permission-mode auto が検出され mode=auto が記録される" {
  local fake_claude_pid="99993"
  local fake_proc_dir="${SANDBOX}/proc/${fake_claude_pid}"
  mkdir -p "${fake_proc_dir}"
  printf 'node\0/usr/local/bin/claude\0--permission-mode\0auto\0' \
    > "${fake_proc_dir}/cmdline"

  stub_command "pgrep" "echo ${fake_claude_pid}"

  export SESSION_INIT_PGREP_PROC_DIR="${SANDBOX}/proc"

  run bash "${SCRIPT_SRC}"

  assert_success

  local session_file="${SUPERVISOR_DIR}/session.json"
  [[ -f "${session_file}" ]] \
    || fail "session.json が作成されていない: ${session_file}"

  local actual_mode
  actual_mode=$(jq -r '.mode // empty' "${session_file}" 2>/dev/null || echo "")

  [[ "${actual_mode}" == "auto" ]] \
    || fail "AC2 FAIL: mode は 'auto' であるべきだが '${actual_mode}' だった。
原因: 現行実装は \$PPID/cmdline のみ参照するため bash subshell 経由で PPID=bash となり
      --permission-mode auto が検出されない（#1459 バグ再現）。
修正: pgrep -f claude でプロセスツリーを辿る実装が必要。"
}

# ---------------------------------------------------------------------------
# AC2 サブシナリオ: --permission-mode acceptEdits も mode=auto に normalize される
# RED 理由: 同上
# ---------------------------------------------------------------------------

@test "ac2-acceptEdits: bash subshell 経由で acceptEdits が mode=auto に normalize される" {
  local fake_claude_pid="99994"
  local fake_proc_dir="${SANDBOX}/proc/${fake_claude_pid}"
  mkdir -p "${fake_proc_dir}"
  printf 'node\0/usr/local/bin/claude\0--permission-mode\0acceptEdits\0' \
    > "${fake_proc_dir}/cmdline"

  stub_command "pgrep" "echo ${fake_claude_pid}"

  export SESSION_INIT_PGREP_PROC_DIR="${SANDBOX}/proc"

  run bash "${SCRIPT_SRC}"

  assert_success

  local actual_mode
  actual_mode=$(jq -r '.mode // empty' "${SUPERVISOR_DIR}/session.json" 2>/dev/null || echo "")

  [[ "${actual_mode}" == "auto" ]] \
    || fail "AC2-acceptEdits FAIL: mode は 'auto' であるべきだが '${actual_mode}' だった。
acceptEdits → auto normalize が bash subshell 経由でも機能する必要がある。"
}

# ===========================================================================
# AC3: cld 起動なし (素の bash) で実行 → mode=unknown または空 + WARN
#      現行動作維持（regression テスト）
#
# このテストは現行実装でも GREEN であるべき。
# ただし修正実装でも壊れないことを保証するため、regression として含める。
#
# RED 理由の補足: AC3 自体は現行実装で PASS するが、
#   修正実装が pgrep ヒットなし時に現行動作を維持することを保証する目的。
# ===========================================================================

@test "ac3: cld プロセスなし（素の bash）で実行 → mode 空または unknown + WARN が出力される" {
  # pgrep が claude/cld プロセスを見つけられない状態をモック
  stub_command "pgrep" 'exit 1'

  # SESSION_INIT_PGREP_PROC_DIR も空ディレクトリを指す
  local empty_proc_dir="${SANDBOX}/proc-empty"
  mkdir -p "${empty_proc_dir}"
  export SESSION_INIT_PGREP_PROC_DIR="${empty_proc_dir}"

  run bash "${SCRIPT_SRC}"

  # exit 0 であること（WARN は出すが abort しない）
  assert_success

  local session_file="${SUPERVISOR_DIR}/session.json"
  [[ -f "${session_file}" ]] \
    || fail "AC3 FAIL: session.json が作成されていない: ${session_file}"

  local actual_mode
  actual_mode=$(jq -r '.mode // empty' "${session_file}" 2>/dev/null || echo "PARSE_ERROR")

  # mode は空文字 or "unknown" のいずれかを許容
  [[ "${actual_mode}" == "" || "${actual_mode}" == "unknown" ]] \
    || fail "AC3 FAIL: mode は '' または 'unknown' であるべきだが '${actual_mode}' だった。
素の bash（cld なし）実行時の現行動作が維持されていない。"

  # WARN が stderr に出力されていること
  echo "${output}${stderr:-}" | grep -q 'WARN\|warn\|warning' \
    || [[ "${output}" == *"WARN"* ]] \
    || fail "AC3 FAIL: WARN メッセージが出力されていない。
素の bash 実行時は mode 空文字 + WARN の fail-loud 動作が必要（#1459 AC3）。"
}

# ===========================================================================
# AC4: bats test が plugins/twl/tests/bats/scripts/session-init.bats に存在する
#      （このファイル自体の存在確認）
# ===========================================================================

@test "ac4: session-init.bats が plugins/twl/tests/bats/scripts/ に存在する" {
  # REPO_ROOT = plugins/twl/
  local expected_path="${REPO_ROOT}/tests/bats/scripts/session-init.bats"

  [[ -f "${expected_path}" ]] \
    || fail "AC4 FAIL: session-init.bats が存在しない: ${expected_path}
このファイル自体が存在することで AC4 を満たす。"

  # ファイルに AC1〜AC3 のテストが含まれること（最低限の構造チェック）
  grep -q '@test.*ac1' "${expected_path}" \
    || fail "AC4 FAIL: session-init.bats に ac1 テストが含まれていない。"

  grep -q '@test.*ac2' "${expected_path}" \
    || fail "AC4 FAIL: session-init.bats に ac2 テストが含まれていない。"

  grep -q '@test.*ac3' "${expected_path}" \
    || fail "AC4 FAIL: session-init.bats に ac3 テストが含まれていない。"
}
