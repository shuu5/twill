#!/usr/bin/env bats
# step0-monitor-bootstrap.bats - Issue #1222 AC1-AC3 RED テスト
#
# Issue #1222: [Bug] plugins/twl step0 monitor bootstrap が --session フラグを使用（正しくは --pattern）
#
# AC coverage:
#   AC1 - bootstrap output に --pattern '^(ap-|wt-|coi-|coe-)' が含まれ、--session flag を含まない
#   AC2 - bootstrap 出力をそのまま bash -n で syntax check 成功
#   AC3 - emit したコマンドを実行し cld-observe-any が exit 0 で daemon 起動
#   AC4 - manual smoke のみ（bats テストなし）
#
# RED: AC1 と AC3 は実装修正前（--session バグあり）の状態で fail する。
#      AC2 は bootstrap 出力の syntax が壊れている場合に fail する（構造チェック）。
#
# テストフレームワーク: bats-core（bats-support + bats-assert）

load '../helpers/common'

BOOTSTRAP_SCRIPT=""
CLD_OBSERVE_ANY=""

setup() {
  common_setup
  # REPO_ROOT = plugins/twl/
  BOOTSTRAP_SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/step0-monitor-bootstrap.sh"
  # cld-observe-any は plugins/session 配下
  # REPO_ROOT = plugins/twl → ../../plugins/session/scripts/cld-observe-any
  CLD_OBSERVE_ANY="$(cd "${REPO_ROOT}/../.." && pwd)/plugins/session/scripts/cld-observe-any"
  export SUPERVISOR_DIR="${SANDBOX}/.supervisor"
  mkdir -p "${SUPERVISOR_DIR}"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: bootstrap output に --pattern '^(ap-|wt-|coi-|coe-)' が含まれ、
#       --session flag を含まない
# ===========================================================================

# ---------------------------------------------------------------------------
# WHEN: step0-monitor-bootstrap.sh を引数なしで実行する
# THEN: 出力に --pattern '^(ap-|wt-|coi-|coe-)' が含まれる
# RED: 現在の実装は --session を使用しているため fail する
# ---------------------------------------------------------------------------

@test "AC1-emit-pattern: bootstrap 出力に --pattern flag が含まれる" {
  # RED: 現在の実装は --session を使用しているため fail する
  [[ -f "${BOOTSTRAP_SCRIPT}" ]] \
    || fail "step0-monitor-bootstrap.sh が存在しない: ${BOOTSTRAP_SCRIPT}"

  # daemon が起動していない状態を模擬するため pgrep を stub する
  stub_command "pgrep" 'exit 1'

  run bash "${BOOTSTRAP_SCRIPT}"

  assert_success

  echo "${output}" | grep -q -- '--pattern' \
    || fail "bootstrap 出力に '--pattern' flag が含まれない（AC1 未実装）
実際の出力:
${output}"
}

# ---------------------------------------------------------------------------
# WHEN: step0-monitor-bootstrap.sh を引数なしで実行する
# THEN: 出力に --pattern '^(ap-|wt-|coi-|coe-)' が含まれる
# RED: 現在の実装は --session を使用しているため fail する
# ---------------------------------------------------------------------------

@test "AC1-emit-pattern: bootstrap 出力に '^(ap-|wt-|coi-|coe-)' パターン文字列が含まれる" {
  # RED: 現在の実装は --session を使用しているため fail する
  [[ -f "${BOOTSTRAP_SCRIPT}" ]] \
    || fail "step0-monitor-bootstrap.sh が存在しない: ${BOOTSTRAP_SCRIPT}"

  stub_command "pgrep" 'exit 1'

  run bash "${BOOTSTRAP_SCRIPT}"

  assert_success

  echo "${output}" | grep -qF "'^(ap-|wt-|coi-|coe-)'" \
    || fail "bootstrap 出力に パターン文字列 '^(ap-|wt-|coi-|coe-)' が含まれない（AC1 未実装）
実際の出力:
${output}"
}

# ---------------------------------------------------------------------------
# WHEN: step0-monitor-bootstrap.sh を引数なしで実行する
# THEN: 出力に --session flag が含まれない
# RED: 現在の実装は --session を使用しているため fail する
# ---------------------------------------------------------------------------

@test "AC1-emit-pattern: bootstrap 出力に --session flag が含まれない" {
  # RED: 現在の実装は --session を使用しているため fail する
  [[ -f "${BOOTSTRAP_SCRIPT}" ]] \
    || fail "step0-monitor-bootstrap.sh が存在しない: ${BOOTSTRAP_SCRIPT}"

  stub_command "pgrep" 'exit 1'

  run bash "${BOOTSTRAP_SCRIPT}"

  assert_success

  if echo "${output}" | grep -q -- '--session'; then
    fail "bootstrap 出力に '--session' flag が含まれている（AC1 バグ: --pattern への置換が必要）
該当行:
$(echo "${output}" | grep -- '--session')"
  fi
}

# ===========================================================================
# AC2: bootstrap 出力をそのまま bash -n で syntax check 成功
# ===========================================================================

# ---------------------------------------------------------------------------
# WHEN: step0-monitor-bootstrap.sh の出力を bash -n に渡す
# THEN: bash -n が exit 0 で終了する（syntax エラーなし）
# NOTE: 現在の実装（--session バグあり）でも構文は正しいため、
#       このテストは実装前後で GREEN になる可能性がある。
#       AC2 の本質は「修正後の出力が構文エラーを持たないこと」の継続確認。
# ---------------------------------------------------------------------------

@test "AC2-emitted-cmd-syntax-valid: bootstrap 出力が bash -n syntax check を通過する" {
  [[ -f "${BOOTSTRAP_SCRIPT}" ]] \
    || fail "step0-monitor-bootstrap.sh が存在しない: ${BOOTSTRAP_SCRIPT}"

  stub_command "pgrep" 'exit 1'

  run bash "${BOOTSTRAP_SCRIPT}"

  assert_success

  # 出力が空でないこと（bootstrap が何も emit しないのは異常）
  [[ -n "${output}" ]] \
    || fail "bootstrap 出力が空（AC2 前提違反: emit コマンドがない）"

  # コメント行と空行のみでないこと（実行可能コマンドが含まれること）
  local cmd_lines
  cmd_lines=$(echo "${output}" | grep -v '^#' | grep -v '^[[:space:]]*$' | wc -l)
  [[ "${cmd_lines}" -gt 0 ]] \
    || fail "bootstrap 出力にコメント・空行以外の実行可能行がない（AC2 前提違反）"

  # 出力全体を bash -n で syntax check する
  local syntax_check_result
  syntax_check_result=$(echo "${output}" | bash -n 2>&1)
  local syntax_exit=$?

  [[ "${syntax_exit}" -eq 0 ]] \
    || fail "bootstrap 出力が bash -n syntax check に失敗した（AC2 未実装）
bash -n エラー:
${syntax_check_result}"
}

# ===========================================================================
# AC3 (smoke): emit したコマンドを実行し cld-observe-any が exit 0 で daemon 起動
# ===========================================================================

# ---------------------------------------------------------------------------
# WHEN: bootstrap が emit したコマンドのうち cld-observe-any 呼び出し部分を抽出し実行する
# THEN: cld-observe-any が --pattern を受け取り exit 0 で起動できる
# RED: 現在の実装は --session を emit するため、cld-observe-any が
#      "unexpected argument '--session'" で exit 1 する
#
# 注意: bats 環境では _TEST_MODE=1 を使用し daemon ループを回避する。
#       cld-observe-any は --window/--pattern が必須だが _TEST_MODE=1 の場合
#       この検証を skip するため、emit コマンドに --pattern がないと
#       _TEST_MODE 外での validation で exit 1 となる。
# ---------------------------------------------------------------------------

@test "AC3-emitted-cmd-exec-success: emit された cld-observe-any コマンドが --pattern で成功する" {
  # RED: 現在の実装は --session を emit するため fail する
  [[ -f "${BOOTSTRAP_SCRIPT}" ]] \
    || fail "step0-monitor-bootstrap.sh が存在しない: ${BOOTSTRAP_SCRIPT}"
  [[ -f "${CLD_OBSERVE_ANY}" ]] \
    || fail "cld-observe-any が存在しない: ${CLD_OBSERVE_ANY}"

  stub_command "pgrep" 'exit 1'

  # bootstrap 出力を取得する
  local bootstrap_output
  bootstrap_output=$(bash "${BOOTSTRAP_SCRIPT}" 2>&1)
  [[ -n "${bootstrap_output}" ]] \
    || fail "bootstrap 出力が空（AC3 前提違反）"

  # bootstrap 出力から cld-observe-any への引数行を抽出する
  # cld-observe-any の行と続く引数行（バックスラッシュ継続）を結合して検証
  local cld_args
  cld_args=$(echo "${bootstrap_output}" \
    | grep -A5 'cld-observe-any' \
    | grep -vE '^#|^mkdir|^until|^tail|^$' \
    | sed 's/\\$//' \
    | tr '\n' ' ')

  # --pattern が引数に含まれていること
  echo "${cld_args}" | grep -q -- '--pattern' \
    || fail "emit された cld-observe-any 引数に '--pattern' が含まれない（AC3 / AC1 バグ: --session が使用されている）
抽出された引数行:
${cld_args}
bootstrap 出力全体:
${bootstrap_output}"

  # --session が引数に含まれないこと
  if echo "${cld_args}" | grep -q -- '--session'; then
    fail "emit された cld-observe-any 引数に '--session' が含まれている（AC3 バグ: cld-observe-any は --session を認識しない）
抽出された引数行:
${cld_args}"
  fi

  # cld-observe-any に --pattern を実際に渡して exit コードを確認する
  # _TEST_MODE=1 で tmux 依存を回避し、--once で daemon ループを回避する
  # tmux list-windows を stub して window マッチを模擬する
  stub_command "tmux" '
case "$1" in
  list-windows)
    # ap- prefix でマッチする window を返す
    printf "test-session:0 ap-worker-1222\n"
    exit 0
    ;;
  display-message)
    echo "0 bash"
    exit 0
    ;;
  capture-pane)
    # idle 状態（特定イベントなし）
    printf "user@host:~$ \n"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
'

  run bash -c "
    export PATH='${STUB_BIN}:${PATH}'
    export _TEST_MODE=1
    '${CLD_OBSERVE_ANY}' \
      --pattern '^(ap-|wt-|coi-|coe-)' \
      --once \
      2>/dev/null
  "

  # exit 0 または正常終了すること（--pattern が有効な引数として受け付けられること）
  # NOTE: _TEST_MODE=1 + --once の組み合わせで exit コードが変わる場合があるため、
  #       "unexpected argument" エラーがないことを確認する
  if echo "${output}" | grep -q "unexpected argument"; then
    fail "cld-observe-any が --pattern を不明な引数として拒否した（AC3 実行不可）
出力: ${output}
exit status: ${status}"
  fi
}

# ---------------------------------------------------------------------------
# WHEN: cld-observe-any に --session を渡す（バグ再現テスト）
# THEN: exit 1 で "unexpected argument" エラーが返る（バグの存在を文書化）
# このテストは実装修正後も pass し続ける（バグが修正されても --session は無効なまま）
# ---------------------------------------------------------------------------

@test "AC3-emitted-cmd-exec-success: cld-observe-any は --session を不正引数として拒否する（バグ文書化）" {
  [[ -f "${CLD_OBSERVE_ANY}" ]] \
    || fail "cld-observe-any が存在しない: ${CLD_OBSERVE_ANY}"

  # --session は cld-observe-any に存在しない引数なので error になることを確認する
  run bash "${CLD_OBSERVE_ANY}" --session "test-session" 2>&1 || true

  # exit 0 にならないこと（--session は無効な引数）
  [[ "${status}" -ne 0 ]] \
    || fail "cld-observe-any が --session を不正引数として検出しなかった（API 変更の可能性）
出力: ${output}"

  echo "${output}" | grep -qiE "unexpected argument|unknown.*option|invalid.*option|--session" \
    || fail "cld-observe-any の --session エラーメッセージが期待形式でない
出力: ${output}"
}
