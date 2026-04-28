#!/usr/bin/env bats
# chain-runner-trace-abspath.bats
# Requirement: TWL_CHAIN_TRACE 絶対パス書き込み拒否（issue-1015）
# Spec: PR #1013 / issue body description
# Coverage: --type=unit --coverage=security
#
# 検証する仕様:
#   1. TWL_CHAIN_TRACE に /tmp・TMPDIR・AUTOPILOT_DIR 以外の絶対パスを設定した場合、
#      trace_event() はファイルを作成しない（ホワイトリスト外絶対パス拒否）
#   2. TWL_CHAIN_TRACE に相対パスを設定した場合、trace_event() はファイルを作成する（回帰）
#   3. TWL_CHAIN_TRACE に *..*（パストラバーサル）を含む場合、ファイルを作成しない（既存動作・回帰）
#   4. /tmp 配下の絶対パスは引き続き許可される（回帰）
#   5. AUTOPILOT_DIR 配下の絶対パスは引き続き許可される（回帰）
#
# NOTE: テスト 1（AC1）は実装前 RED 状態。
#       修正（/tmp と AUTOPILOT_DIR のホワイトリスト方式）後に GREEN になる。
#       evil path として $HOME 配下を使用する — /tmp は許可リストに含まれるため。
#
# 環境変数:
#   WORKER_ISSUE_NUM=1015 — resolve_issue_num の Priority 0 による issue 番号固定
#                           git branch / AUTOPILOT_DIR を参照せず動作する

load '../../bats/helpers/common.bash'

# ---------------------------------------------------------------------------
# setup / teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  export WORKER_ISSUE_NUM=1015

  CR="$SANDBOX/scripts/chain-runner.sh"
  export CR
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: ホワイトリスト外の絶対パスは拒否される（RED: 修正前は FAIL）
# WHEN TWL_CHAIN_TRACE に /tmp・TMPDIR・AUTOPILOT_DIR 以外の絶対パスを設定する
# THEN trace_event() はそのパスにファイルを作成しない
# Spec: issue-1015 ホワイトリスト方式
# NOTE: evil path は $HOME 配下を使用する — /tmp は許可リストに含まれる
# ===========================================================================

@test "trace-abspath[security][RED]: ホワイトリスト外絶対パス（HOME）は trace ファイルが作成されない" {
  local _home="${HOME:-/root}"
  local evil_path="${_home}/twl-test-trace-1015-abspath-$$"
  rm -f "$evil_path" 2>/dev/null || true

  run bash "$CR" --trace "$evil_path" resolve-issue-num

  local file_existed=0
  [[ -f "$evil_path" ]] && file_existed=1
  rm -f "$evil_path" 2>/dev/null || true

  assert_success
  [[ "$file_existed" -eq 0 ]] || {
    echo "FAIL: ホワイトリスト外の絶対パスに trace ファイルが書き込まれた（セキュリティ脆弱性）: $evil_path" >&2
    return 1
  }
}

@test "trace-abspath[security][RED]: HOME 配下サブディレクトリの場合も trace ファイルが作成されない" {
  local _home="${HOME:-/root}"
  local evil_dir="${_home}/twl-test-trace-1015-subdir-$$"
  local evil_path="${evil_dir}/trace.jsonl"
  rm -rf "$evil_dir" 2>/dev/null || true

  run bash "$CR" --trace "$evil_path" resolve-issue-num

  local file_existed=0
  [[ -f "$evil_path" ]] && file_existed=1
  rm -rf "$evil_dir" 2>/dev/null || true

  assert_success
  [[ "$file_existed" -eq 0 ]] || {
    echo "FAIL: ホワイトリスト外絶対パス（サブディレクトリ）に trace ファイルが書き込まれた: $evil_path" >&2
    return 1
  }
}

@test "trace-abspath[env-var][RED]: TWL_CHAIN_TRACE 環境変数でホワイトリスト外絶対パスを渡した場合も拒否される" {
  local _home="${HOME:-/root}"
  local evil_path="${_home}/twl-test-trace-1015-envvar-$$"
  rm -f "$evil_path" 2>/dev/null || true

  run env TWL_CHAIN_TRACE="$evil_path" bash "$CR" resolve-issue-num

  local file_existed=0
  [[ -f "$evil_path" ]] && file_existed=1
  rm -f "$evil_path" 2>/dev/null || true

  assert_success
  [[ "$file_existed" -eq 0 ]] || {
    echo "FAIL: TWL_CHAIN_TRACE 環境変数でホワイトリスト外絶対パスが書き込まれた: $evil_path" >&2
    return 1
  }
}

# ===========================================================================
# AC4: /tmp 配下の絶対パスは許可される（回帰テスト）
# WHEN TWL_CHAIN_TRACE に /tmp 配下の絶対パスを設定する
# THEN trace_event() はそのパスにファイルを作成する（既存テストとの互換性）
# ===========================================================================

@test "trace-tmp[regression]: /tmp 配下の絶対パスは trace ファイルが作成される" {
  local trace_path="/tmp/twl-test-trace-1015-allowed-$$"
  rm -f "$trace_path" 2>/dev/null || true

  run bash "$CR" --trace "$trace_path" resolve-issue-num

  local file_created=0
  [[ -f "$trace_path" ]] && file_created=1
  rm -f "$trace_path" 2>/dev/null || true

  assert_success
  [[ "$file_created" -eq 1 ]] || {
    echo "FAIL: /tmp 配下の絶対パスに trace ファイルが作成されなかった: $trace_path" >&2
    return 1
  }
}

# ===========================================================================
# AC4b: TMPDIR 配下の絶対パスは許可される（回帰テスト — TMPDIR trailing slash 正規化）
# WHEN TMPDIR が設定されており、TWL_CHAIN_TRACE がその配下の絶対パスを指す
# THEN trace_event() はそのパスにファイルを作成する（TMPDIR%/ 正規化の回帰防止）
# ===========================================================================

@test "trace-tmpdir[regression]: TMPDIR 配下の絶対パスは trace ファイルが作成される" {
  local tmpdir_base="${TMPDIR:-/tmp}"
  local trace_path="${tmpdir_base%/}/twl-test-trace-1015-tmpdir-$$"
  rm -f "$trace_path" 2>/dev/null || true

  run env TMPDIR="${tmpdir_base}" bash "$CR" --trace "$trace_path" resolve-issue-num

  local file_created=0
  [[ -f "$trace_path" ]] && file_created=1
  rm -f "$trace_path" 2>/dev/null || true

  assert_success
  [[ "$file_created" -eq 1 ]] || {
    echo "FAIL: TMPDIR 配下の絶対パスに trace ファイルが作成されなかった: $trace_path" >&2
    return 1
  }
}

# ===========================================================================
# AC5: AUTOPILOT_DIR 配下の絶対パスは許可される（回帰テスト）
# WHEN AUTOPILOT_DIR が設定されており、TWL_CHAIN_TRACE がその配下の絶対パスを指す
# THEN trace_event() はそのパスにファイルを作成する（autopilot-launch.sh との互換性）
# ===========================================================================

@test "trace-autopilot-dir[regression]: AUTOPILOT_DIR 配下の絶対パスは trace ファイルが作成される" {
  # AUTOPILOT_DIR は common_setup が $SANDBOX/.autopilot に設定済み
  local trace_dir="${AUTOPILOT_DIR}/trace/test-session"
  local trace_path="${trace_dir}/issue-1015.jsonl"
  mkdir -p "$trace_dir"
  rm -f "$trace_path" 2>/dev/null || true

  run bash "$CR" --trace "$trace_path" resolve-issue-num

  local file_created=0
  [[ -f "$trace_path" ]] && file_created=1

  assert_success
  [[ "$file_created" -eq 1 ]] || {
    echo "FAIL: AUTOPILOT_DIR 配下の絶対パスに trace ファイルが作成されなかった: $trace_path" >&2
    return 1
  }
}

# ===========================================================================
# AC2: 相対パスは引き続き許可される（回帰テスト）
# WHEN TWL_CHAIN_TRACE に相対パスを設定して chain-runner を実行する
# THEN trace_event() はそのパスにファイルを作成する（既存動作を維持）
# ===========================================================================

@test "trace-relpath[regression]: 相対パスの場合、trace ファイルが作成される" {
  local trace_rel="twl-trace-output-$$.jsonl"
  local expected_file="$SANDBOX/$trace_rel"

  run bash -c "cd '$SANDBOX' && bash '$CR' --trace '$trace_rel' resolve-issue-num"

  assert_success
  [[ -f "$expected_file" ]] || {
    echo "FAIL: 相対パスに trace ファイルが作成されなかった: $expected_file" >&2
    return 1
  }
}

# ===========================================================================
# AC3: *..*（パストラバーサル）は引き続きブロックされる（回帰テスト）
# WHEN TWL_CHAIN_TRACE に *..*（../ を含むパス）を設定する
# THEN trace_event() はファイルを作成しない（既存の case *..*) 節）
# ===========================================================================

@test "trace-traversal[regression]: パストラバーサル（*..*）は引き続きブロックされる" {
  local traversal_path="test/../../../twl-evil-trace-1015-test"

  run bash "$CR" --trace "$traversal_path" resolve-issue-num

  assert_success
  [[ ! -f "$traversal_path" ]] || {
    echo "FAIL: パストラバーサルパスに trace ファイルが作成された: $traversal_path" >&2
    return 1
  }
}
