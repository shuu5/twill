#!/usr/bin/env bats
# chain-runner-autopilot-dir-validate.bats
# Requirement: AUTOPILOT_DIR を任意値に設定したホワイトリスト拡張攻撃の拒否（issue-1042）
# Spec: issue-1042 / depends on issue-1015 / issue-1041 修正
# Coverage: --type=unit --coverage=security
#
# 検証する仕様:
#   1. AUTOPILOT_DIR=/etc に設定した場合、AUTOPILOT_DIR ホワイトリスト経由で /etc/* に書き込めない
#   2. AUTOPILOT_DIR=/var/log に設定した場合も同様に拒否
#   3. AUTOPILOT_DIR=$HOME 配下のサブディレクトリ（例: $HOME/custom-autopilot）は引き続き許可（regression）
#   4. AUTOPILOT_DIR=/tmp/custom-autopilot は引き続き許可（regression）
#
# NOTE: AC1, AC2 は実装前 RED 状態。
#       trace_event() に AUTOPILOT_DIR の trust 検証（/tmp、TMPDIR、HOME 配下のみ trust）
#       を追加すれば GREEN になる。

load '../../bats/helpers/common.bash'

setup() {
  common_setup

  export WORKER_ISSUE_NUM=1042

  CR="$SANDBOX/scripts/chain-runner.sh"
  export CR
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: AUTOPILOT_DIR=/etc に設定した場合、AUTOPILOT_DIR ホワイトリスト経由で書き込めない
# WHEN AUTOPILOT_DIR=/etc, TWL_CHAIN_TRACE=/etc/twl-test-evil-1042
# THEN trace_event() は /etc/twl-test-evil-1042 に書き込まない
# Spec: issue-1042 AUTOPILOT_DIR 信頼性検証
# NOTE: /etc 配下は実際には permission denied で書けないが、検証ロジックが
#       許可を出している時点で脆弱性。検証ロジックの拒否を確認する手段として
#       /var/tmp/twl-test-1042-non-trusted-XXX のような書き込み可能な path を使う
# ===========================================================================

@test "autopilot-dir-validate[security][RED]: AUTOPILOT_DIR=/var/tmp（書き込み可能だが信頼外）でホワイトリスト拡張は拒否される" {
  # /var/tmp は通常 world-writable だが /tmp・TMPDIR・HOME のいずれにも該当しない
  local evil_autopilot="/var/tmp/twl-test-1042-non-trusted-$$"
  local evil_trace="${evil_autopilot}/trace.jsonl"
  mkdir -p "$evil_autopilot"
  rm -f "$evil_trace" 2>/dev/null || true

  # AUTOPILOT_DIR を /var/tmp 配下に設定して chain-runner を起動
  run env AUTOPILOT_DIR="$evil_autopilot" bash "$CR" --trace "$evil_trace" resolve-issue-num

  local file_existed=0
  [[ -f "$evil_trace" ]] && file_existed=1
  rm -rf "$evil_autopilot" 2>/dev/null || true

  assert_success
  [[ "$file_existed" -eq 0 ]] || {
    echo "FAIL: AUTOPILOT_DIR を信頼外パス（/var/tmp/...）に設定するとホワイトリスト経由で書き込めた: $evil_trace" >&2
    return 1
  }
}

@test "autopilot-dir-validate[security][RED]: AUTOPILOT_DIR=/opt/... でホワイトリスト拡張は拒否される" {
  # /opt はホワイトリスト trust 対象外
  local evil_autopilot="/opt/twl-test-1042-non-trusted-$$"
  local evil_trace="${evil_autopilot}/trace.jsonl"

  # /opt に書き込めない場合があるので、/opt の親ディレクトリ存在チェックのみで AC を確認
  # 実際の trace_file 書き込みは拒否されるべき（mkdir も実行されないはず）
  run env AUTOPILOT_DIR="$evil_autopilot" bash "$CR" --trace "$evil_trace" resolve-issue-num

  local file_existed=0
  [[ -f "$evil_trace" ]] && file_existed=1
  # /opt 配下に何かが作成された場合の cleanup
  if [[ -e "$evil_autopilot" ]]; then
    rm -rf "$evil_autopilot" 2>/dev/null || true
  fi

  assert_success
  [[ "$file_existed" -eq 0 ]] || {
    echo "FAIL: AUTOPILOT_DIR=/opt/... でホワイトリスト経由で書き込めた: $evil_trace" >&2
    return 1
  }
}

# ===========================================================================
# AC3: AUTOPILOT_DIR=$HOME 配下のサブディレクトリは引き続き許可される（regression）
# WHEN AUTOPILOT_DIR=$HOME/twl-test-1042-trusted, TWL_CHAIN_TRACE=$HOME/twl-test-1042-trusted/trace
# THEN trace_event() は trace ファイルを作成する
# ===========================================================================

@test "autopilot-dir-validate[regression]: AUTOPILOT_DIR=\$HOME 配下サブディレクトリでは書き込みが許可される" {
  local _home="${HOME:-/root}"
  local trusted_autopilot="${_home}/twl-test-1042-trusted-autopilot-$$"
  local trace_path="${trusted_autopilot}/trace.jsonl"
  mkdir -p "$trusted_autopilot"
  rm -f "$trace_path" 2>/dev/null || true

  run env AUTOPILOT_DIR="$trusted_autopilot" bash "$CR" --trace "$trace_path" resolve-issue-num

  local file_created=0
  [[ -f "$trace_path" ]] && file_created=1
  rm -rf "$trusted_autopilot" 2>/dev/null || true

  assert_success
  [[ "$file_created" -eq 1 ]] || {
    echo "FAIL: AUTOPILOT_DIR=\$HOME 配下サブディレクトリで trace ファイルが作成されなかった: $trace_path" >&2
    return 1
  }
}

# ===========================================================================
# AC4: AUTOPILOT_DIR=/tmp/... は引き続き許可される（regression）
# ===========================================================================

@test "autopilot-dir-validate[regression]: AUTOPILOT_DIR=/tmp/... では書き込みが許可される" {
  local trusted_autopilot="/tmp/twl-test-1042-trusted-tmp-autopilot-$$"
  local trace_path="${trusted_autopilot}/trace.jsonl"
  mkdir -p "$trusted_autopilot"
  rm -f "$trace_path" 2>/dev/null || true

  run env AUTOPILOT_DIR="$trusted_autopilot" bash "$CR" --trace "$trace_path" resolve-issue-num

  local file_created=0
  [[ -f "$trace_path" ]] && file_created=1
  rm -rf "$trusted_autopilot" 2>/dev/null || true

  assert_success
  [[ "$file_created" -eq 1 ]] || {
    echo "FAIL: AUTOPILOT_DIR=/tmp/... で trace ファイルが作成されなかった: $trace_path" >&2
    return 1
  }
}
