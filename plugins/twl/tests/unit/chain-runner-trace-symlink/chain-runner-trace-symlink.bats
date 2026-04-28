#!/usr/bin/env bats
# chain-runner-trace-symlink.bats
# Requirement: TWL_CHAIN_TRACE symlink TOCTOU 攻撃の拒否（issue-1041）
# Spec: issue-1041 / depends on issue-1015 修正
# Coverage: --type=unit --coverage=security
#
# 検証する仕様:
#   1. /tmp 配下の symlink がホワイトリスト外の path を指す場合、書き込みを拒否する
#   2. AUTOPILOT_DIR 配下の symlink がホワイトリスト外の path を指す場合、書き込みを拒否する
#   3. /tmp 配下の通常ファイルは引き続き許可される（regression）
#   4. AUTOPILOT_DIR 配下の通常ファイルは引き続き許可される（regression）
#
# NOTE: AC1, AC2 は実装前 RED 状態。
#       trace_event() に realpath --canonicalize-missing による symlink 解決を追加すれば GREEN になる。
#
# 環境変数:
#   WORKER_ISSUE_NUM=1041 — resolve_issue_num の Priority 0 による issue 番号固定

load '../../bats/helpers/common.bash'

# ---------------------------------------------------------------------------
# setup / teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  export WORKER_ISSUE_NUM=1041

  CR="$SANDBOX/scripts/chain-runner.sh"
  export CR
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: /tmp 配下の symlink で外部 path を指す場合、書き込みを拒否する（TOCTOU 対策）
# WHEN /tmp/legit-trace.jsonl が $HOME/twl-evil-trace を指す symlink である
# THEN trace_event() は $HOME/twl-evil-trace に書き込まない
# Spec: issue-1041 symlink TOCTOU 対策
# ===========================================================================

@test "trace-symlink[security][RED]: /tmp 配下の symlink が HOME 配下の victim を指すと書き込まれない" {
  local _home="${HOME:-/root}"
  local victim="${_home}/twl-test-trace-1041-symlink-victim-$$"
  local symlink_path="/tmp/twl-test-trace-1041-symlink-$$"
  rm -f "$victim" "$symlink_path" 2>/dev/null || true
  ln -sf "$victim" "$symlink_path"

  run bash "$CR" --trace "$symlink_path" resolve-issue-num

  local victim_existed=0
  [[ -f "$victim" ]] && victim_existed=1
  rm -f "$victim" "$symlink_path" 2>/dev/null || true

  assert_success
  [[ "$victim_existed" -eq 0 ]] || {
    echo "FAIL: symlink を通じて HOME 配下の victim ファイルに trace ファイルが書き込まれた（TOCTOU）: $victim" >&2
    return 1
  }
}

# ===========================================================================
# AC2: AUTOPILOT_DIR 配下の symlink が外部 path を指す場合、書き込みを拒否する
# WHEN AUTOPILOT_DIR 配下の symlink が $HOME 配下の victim を指す
# THEN trace_event() は victim に書き込まない
# ===========================================================================

@test "trace-symlink[security][RED]: AUTOPILOT_DIR 配下の symlink が HOME 配下の victim を指すと書き込まれない" {
  local _home="${HOME:-/root}"
  local victim="${_home}/twl-test-trace-1041-autopilot-symlink-victim-$$"
  local symlink_dir="${AUTOPILOT_DIR}/trace"
  local symlink_path="${symlink_dir}/sym-trace-$$.jsonl"
  mkdir -p "$symlink_dir"
  rm -f "$victim" "$symlink_path" 2>/dev/null || true
  ln -sf "$victim" "$symlink_path"

  run bash "$CR" --trace "$symlink_path" resolve-issue-num

  local victim_existed=0
  [[ -f "$victim" ]] && victim_existed=1
  rm -f "$victim" "$symlink_path" 2>/dev/null || true

  assert_success
  [[ "$victim_existed" -eq 0 ]] || {
    echo "FAIL: AUTOPILOT_DIR 配下の symlink を通じて HOME 配下の victim ファイルに書き込まれた: $victim" >&2
    return 1
  }
}

# ===========================================================================
# AC3: /tmp 配下の通常ファイル（symlink でない）は引き続き許可される（regression）
# ===========================================================================

@test "trace-symlink[regression]: /tmp 配下の通常ファイルは引き続き trace ファイルが作成される" {
  local trace_path="/tmp/twl-test-trace-1041-regular-$$"
  rm -f "$trace_path" 2>/dev/null || true

  run bash "$CR" --trace "$trace_path" resolve-issue-num

  local file_created=0
  [[ -f "$trace_path" ]] && file_created=1
  rm -f "$trace_path" 2>/dev/null || true

  assert_success
  [[ "$file_created" -eq 1 ]] || {
    echo "FAIL: /tmp 配下の通常パスに trace ファイルが作成されなかった: $trace_path" >&2
    return 1
  }
}

# ===========================================================================
# AC4: AUTOPILOT_DIR 配下の通常ファイル（symlink でない）は引き続き許可される（regression）
# ===========================================================================

@test "trace-symlink[regression]: AUTOPILOT_DIR 配下の通常ファイルは引き続き trace ファイルが作成される" {
  local trace_dir="${AUTOPILOT_DIR}/trace"
  local trace_path="${trace_dir}/regular-trace-$$.jsonl"
  mkdir -p "$trace_dir"
  rm -f "$trace_path" 2>/dev/null || true

  run bash "$CR" --trace "$trace_path" resolve-issue-num

  local file_created=0
  [[ -f "$trace_path" ]] && file_created=1
  rm -f "$trace_path" 2>/dev/null || true

  assert_success
  [[ "$file_created" -eq 1 ]] || {
    echo "FAIL: AUTOPILOT_DIR 配下の通常パスに trace ファイルが作成されなかった: $trace_path" >&2
    return 1
  }
}
