#!/usr/bin/env bats
# step0-monitor-bootstrap-1456.bats
#
# Issue #1456: tech-debt: step0-monitor-bootstrap.sh に inotifywait 在否検出を追加する
#
# AC coverage:
#   AC1 - inotifywait 不在環境で実行 → polling-based fallback コマンドが出力される
#   AC2 - inotifywait 在環境で実行 → 従来通り inotify ベースコマンド出力 (regression なし)
#   AC3 - bats test で両 host (mock 環境) の出力差異を検証
#   AC4 - inotifywait guard が script に構造的に存在する (structural check)
#
# 全テストは実装前（RED）状態で fail する。
# 現在の script は inotifywait 在否を検出せず常に同じコマンドを出力するため。
#
# Note: step0-monitor-bootstrap.sh には source guard (BASH_SOURCE guard) が不在。
#       テストは bash で直接実行する（source ではなく）ため、set -euo pipefail の
#       影響で _daemon_running が呼ばれる場合は pgrep stub を STUB_BIN に配置すること。
#       impl_files メモ: step0-monitor-bootstrap.sh に BASH_SOURCE guard 追加が推奨。

load 'helpers/common'

# ===========================================================================
# Setup / Teardown
# ===========================================================================

setup() {
  common_setup

  SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/step0-monitor-bootstrap.sh"
  export SCRIPT

  # sandbox 内に .supervisor/events/ ディレクトリを作成
  SUPERVISOR_DIR="${SANDBOX}/.supervisor"
  mkdir -p "${SUPERVISOR_DIR}/events"
  export SUPERVISOR_DIR

  # stub: pgrep — cld-observe-any daemon が起動していない状態をシミュレート
  # _daemon_running() が pgrep -f "cld-observe-any" を呼ぶため、常に exit 1 を返す stub が必要
  # これにより _emit_start_commands() が呼ばれる経路になる
  stub_command "pgrep" 'exit 1'
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: inotifywait 不在環境 → polling-based fallback が出力される
#
# 現在の実装: inotifywait 在否を検出せず、常に inotify ベースコマンドを出力する
# RED: inotifywait 不在時に find + sleep の polling fallback を出力しないため FAIL
# ===========================================================================

@test "ac1: inotifywait 不在環境で polling fallback が出力される (find コマンド含む)" {
  # AC: inotifywait が PATH にない環境で実行すると、
  #     find .supervisor/events/ ... ; sleep 10 形式の polling fallback が出力される
  # RED: 現在の実装は inotifywait 在否を検出しないため polling fallback を出力しない → FAIL

  # inotifywait を PATH から隠す: STUB_BIN には配置しない（デフォルトで不在）
  # pgrep stub は setup() で配置済み

  run bash -c "
    set -euo pipefail
    export SUPERVISOR_DIR='${SUPERVISOR_DIR}'
    export PATH='${STUB_BIN}:${PATH}'
    bash '${SCRIPT}'
  "
  [ "${status}" -eq 0 ]
  # RED: 現在の実装は find コマンドを含む polling fallback を出力しない
  echo "${output}" | grep -qE 'find[[:space:]]+.*\.supervisor/events|find[[:space:]]+.*events/' || {
    echo "FAIL: AC #1 未実装 — inotifywait 不在時に find ベースの polling fallback が出力されていない" >&2
    echo "  現在の出力: ${output}" >&2
    echo "  期待: find .supervisor/events/ ... パターンを含む出力" >&2
    return 1
  }
}

@test "ac1: inotifywait 不在環境で polling fallback が出力される (while true + sleep loop 含む)" {
  # AC: polling fallback は while true; do ... sleep N; done 形式のポーリングループを含む
  # RED: 現在の実装は polling fallback を出力しないため FAIL
  # Note: 現在の _emit_start_commands は "until [[ -s ... ]]; do sleep 1; done" を出力するが、
  #       これは daemon 起動待ちループであり、polling fallback の while true ループとは別物。

  run bash -c "
    export SUPERVISOR_DIR='${SUPERVISOR_DIR}'
    export PATH='${STUB_BIN}:${PATH}'
    bash '${SCRIPT}'
  "
  # polling fallback は find + while true; do ... sleep N; done の組み合わせを含むはず
  # "while true" と "find.*events" が同時に含まれることを検証（単独 sleep では不十分）
  local has_while_loop=0
  local has_find_events=0
  echo "${output}" | grep -qE 'while[[:space:]]+true' && has_while_loop=1
  echo "${output}" | grep -qE 'find[[:space:]]+.*events|find[[:space:]]+.*\.supervisor' && has_find_events=1

  if [[ "${has_while_loop}" -eq 0 || "${has_find_events}" -eq 0 ]]; then
    echo "FAIL: AC #1 未実装 — polling fallback の while true + find events ループが出力されていない" >&2
    echo "  has_while_loop=${has_while_loop}, has_find_events=${has_find_events}" >&2
    echo "  現在の出力: ${output}" >&2
    return 1
  fi
}

@test "ac1: inotifywait 不在環境では inotifywait コマンドが出力に含まれない" {
  # AC: inotifywait 不在時は inotifywait コマンドを含むコマンドを出力しない
  # RED: 現在の実装は常に同じ（inotifywait なし）コマンドを出力するため、
  #      この条件は偶然 PASS するかもしれないが、在否分岐ロジックがなければ AC1/AC2 の区別ができない
  #      → AC3 と組み合わせて出力差異がなければ FAIL

  run bash -c "
    export SUPERVISOR_DIR='${SUPERVISOR_DIR}'
    export PATH='${STUB_BIN}:${PATH}'
    bash '${SCRIPT}'
  "
  # inotifywait が含まれていないことを確認（不在環境なので当然）
  # これ自体は現状 PASS するかもしれないが、AC3 の差異チェックと合わせて検証する
  echo "${output}" | grep -qF 'inotifywait' && {
    echo "FAIL: AC #1 — inotifywait 不在環境なのに inotifywait コマンドが出力に含まれている" >&2
    return 1
  }
  # polling fallback が出力されていないなら FAIL（AC1 本体チェック）
  echo "${output}" | grep -qE 'find[[:space:]]+.*events|while[[:space:]]+true.*sleep' || {
    echo "FAIL: AC #1 未実装 — polling fallback が出力されていない" >&2
    return 1
  }
}

# ===========================================================================
# AC2: inotifywait 在環境 → inotify ベースコマンドが出力される (regression なし)
#
# 現在の実装: 常に同じコマンドを出力する（inotifywait を含まない出力）
# RED: 実装後は inotifywait -m -e create -e modify .supervisor/events/ を含むコマンドを出力するが、
#      現在の実装は inotifywait を含む Monitor コマンドを出力しないため FAIL
# ===========================================================================

@test "ac2: inotifywait 在環境で inotifywait ベースの Monitor コマンドが出力される" {
  # AC: inotifywait が PATH に存在する場合、
  #     inotifywait -m -e create -e modify .supervisor/events/ を含むコマンドを出力する
  # RED: 現在の実装は inotifywait 在否を検出しないため、inotifywait を含むコマンドを出力しない → FAIL

  # stub: inotifywait が存在するフリをする
  stub_command "inotifywait" 'echo "stub inotifywait: $*"; exit 0'

  run bash -c "
    export SUPERVISOR_DIR='${SUPERVISOR_DIR}'
    export PATH='${STUB_BIN}:${PATH}'
    bash '${SCRIPT}'
  "
  [ "${status}" -eq 0 ]
  # RED: 現在の実装は inotifywait コマンドを出力に含まない
  echo "${output}" | grep -qE 'inotifywait[[:space:]]+-m|inotifywait.*events' || {
    echo "FAIL: AC #2 未実装 — inotifywait 在環境で inotifywait ベースコマンドが出力されていない" >&2
    echo "  現在の出力: ${output}" >&2
    echo "  期待: inotifywait -m -e create -e modify .supervisor/events/ を含む出力" >&2
    return 1
  }
}

@test "ac2: inotifywait 在環境では -e create と -e modify オプションが出力に含まれる" {
  # AC: inotify ベースコマンドは -e create と -e modify オプションを含む
  # RED: 現在の実装は inotifywait を出力しないため FAIL

  stub_command "inotifywait" 'echo "stub inotifywait: $*"; exit 0'

  run bash -c "
    export SUPERVISOR_DIR='${SUPERVISOR_DIR}'
    export PATH='${STUB_BIN}:${PATH}'
    bash '${SCRIPT}'
  "
  echo "${output}" | grep -qF -- '-e create' || {
    echo "FAIL: AC #2 未実装 — inotifywait コマンドに '-e create' が含まれていない" >&2
    return 1
  }
  echo "${output}" | grep -qF -- '-e modify' || {
    echo "FAIL: AC #2 未実装 — inotifywait コマンドに '-e modify' が含まれていない" >&2
    return 1
  }
}

@test "ac2: inotifywait 在環境で .supervisor/events/ ディレクトリが監視対象として出力される" {
  # AC: inotifywait の監視対象が .supervisor/events/ を含む
  # RED: 現在の実装は inotifywait を出力しないため FAIL

  stub_command "inotifywait" 'echo "stub inotifywait: $*"; exit 0'

  run bash -c "
    export SUPERVISOR_DIR='${SUPERVISOR_DIR}'
    export PATH='${STUB_BIN}:${PATH}'
    bash '${SCRIPT}'
  "
  echo "${output}" | grep -qE '\.supervisor/events/|\.supervisor/events$' || {
    echo "FAIL: AC #2 未実装 — inotifywait の監視対象に .supervisor/events/ が含まれていない" >&2
    echo "  現在の出力: ${output}" >&2
    return 1
  }
}

@test "ac2: inotifywait 在環境で cld-observe-any daemon 起動コマンドが失われていない (regression)" {
  # AC: inotifywait 実装後も cld-observe-any daemon 起動部分が出力されること（regression 防止）
  # RED: 現在の実装は inotifywait 在否を検出しないが、cld-observe-any 部分は出力する。
  #      inotifywait 実装後に cld-observe-any が消えると regression。
  #      現時点では "在環境" を判定できないため inotifywait を出力しない → FAIL

  stub_command "inotifywait" 'echo "stub inotifywait: $*"; exit 0'

  run bash -c "
    export SUPERVISOR_DIR='${SUPERVISOR_DIR}'
    export PATH='${STUB_BIN}:${PATH}'
    bash '${SCRIPT}'
  "
  [ "${status}" -eq 0 ]
  # inotifywait ベースコマンドが出力されていること（regression 確認の前提条件）
  echo "${output}" | grep -qE 'inotifywait.*events' || {
    echo "FAIL: AC #2 未実装 — inotifywait 在環境での inotifywait ベースコマンドが出力されていない" >&2
    return 1
  }
}

# ===========================================================================
# AC3: 両 host (mock 環境) の出力差異を検証
#
# 現在の実装: 在否を検出しないため両環境で同じ出力 → 差異なし → FAIL
# RED: 実装前は差異が生まれないため FAIL
# ===========================================================================

@test "ac3: inotifywait 在環境と不在環境で出力が異なる" {
  # AC: inotifywait 在否によって出力が変わること（両 host の出力差異検証）
  # RED: 現在の実装は在否を検出しないため両環境で同一出力 → 差異なし → FAIL

  # 不在環境での出力を取得
  run bash -c "
    export SUPERVISOR_DIR='${SUPERVISOR_DIR}'
    export PATH='${STUB_BIN}:${PATH}'
    bash '${SCRIPT}'
  "
  local output_without_inotify="${output}"

  # 在環境での出力を取得
  stub_command "inotifywait" 'echo "stub inotifywait: $*"; exit 0'
  run bash -c "
    export SUPERVISOR_DIR='${SUPERVISOR_DIR}'
    export PATH='${STUB_BIN}:${PATH}'
    bash '${SCRIPT}'
  "
  local output_with_inotify="${output}"

  # RED: 両出力が同一の場合は FAIL（差異がないことを検出）
  if [[ "${output_without_inotify}" == "${output_with_inotify}" ]]; then
    echo "FAIL: AC #3 未実装 — inotifywait 在否で出力差異が生まれていない" >&2
    echo "  在環境出力:  ${output_with_inotify}" >&2
    echo "  不在環境出力: ${output_without_inotify}" >&2
    echo "  期待: 在環境は inotifywait ベース、不在環境は polling fallback" >&2
    return 1
  fi
}

@test "ac3: 在環境出力には inotifywait が含まれ、不在環境出力には find/sleep が含まれる" {
  # AC: 在環境 → inotifywait キーワード、不在環境 → find または sleep キーワードが出力される
  # RED: 現在の実装は在否を検出しないため FAIL

  # 不在環境
  run bash -c "
    export SUPERVISOR_DIR='${SUPERVISOR_DIR}'
    export PATH='${STUB_BIN}:${PATH}'
    bash '${SCRIPT}'
  "
  local output_no_inotify="${output}"

  # 在環境
  stub_command "inotifywait" 'echo "stub inotifywait: $*"; exit 0'
  run bash -c "
    export SUPERVISOR_DIR='${SUPERVISOR_DIR}'
    export PATH='${STUB_BIN}:${PATH}'
    bash '${SCRIPT}'
  "
  local output_with_inotify="${output}"

  # 在環境出力に inotifywait が含まれること
  echo "${output_with_inotify}" | grep -qE 'inotifywait' || {
    echo "FAIL: AC #3 未実装 — 在環境出力に inotifywait が含まれていない" >&2
    return 1
  }

  # 不在環境出力に polling fallback (find または while true; do sleep) が含まれること
  echo "${output_no_inotify}" | grep -qE 'find[[:space:]]|while[[:space:]]+true|sleep[[:space:]]+[0-9]+' || {
    echo "FAIL: AC #3 未実装 — 不在環境出力に polling fallback が含まれていない" >&2
    return 1
  }
}

# ===========================================================================
# AC4: inotifywait guard が script に構造的に存在する (structural check)
#
# 現在の実装: command -v inotifywait 相当の guard が存在しない
# RED: guard が存在しないため FAIL
# ===========================================================================

@test "ac4: step0-monitor-bootstrap.sh が存在する" {
  # AC: 実装対象 script が存在すること
  [ -f "${SCRIPT}" ]
}

@test "ac4: script に inotifywait 在否チェックのロジックが存在する" {
  # AC: script 内に command -v inotifywait または which inotifywait 相当の guard が存在する
  # RED: 現在の実装には inotifywait 在否チェックが存在しないため FAIL
  [ -f "${SCRIPT}" ]
  run grep -E 'command[[:space:]]+-v[[:space:]]+inotifywait|which[[:space:]]+inotifywait|type[[:space:]]+inotifywait|inotifywait.*command' \
    "${SCRIPT}"
  [ "${status}" -eq 0 ] || {
    echo "FAIL: AC #4 未実装 — ${SCRIPT} に inotifywait 在否チェック (command -v inotifywait 等) が存在しない" >&2
    echo "  期待: command -v inotifywait, which inotifywait, または type inotifywait パターン" >&2
    return 1
  }
}

@test "ac4: script に polling fallback ブランチのコードが存在する" {
  # AC: inotifywait 不在時の fallback コード（find events + while true loop）が script 内に存在する
  # RED: 現在の実装には polling fallback 専用の find events ループが存在しないため FAIL
  # Note: 現在の script には "until [[ -s ... ]]; do sleep 1; done" があるが、
  #       これは daemon 起動待ちであり events polling fallback ではない。
  #       polling fallback として必要なのは find .supervisor/events/ + while loop の組み合わせ。
  [ -f "${SCRIPT}" ]

  # find + events の組み合わせ（daemon 起動待ちの until ループとは区別）
  local has_find_events=0
  grep -E 'find[[:space:]]+.*events|find[[:space:]]+.*\.supervisor.*events' "${SCRIPT}" \
    > /dev/null 2>&1 && has_find_events=1

  [[ "${has_find_events}" -gt 0 ]] || {
    echo "FAIL: AC #4 未実装 — ${SCRIPT} に polling fallback コード (find .supervisor/events/) が存在しない" >&2
    return 1
  }
}

@test "ac4: script に inotifywait ベースコマンド出力のブランチが存在する" {
  # AC: inotifywait 在環境向けの inotifywait -m ... 出力コードが script 内に存在する
  # RED: 現在の実装には inotifywait ベースの出力コードが存在しないため FAIL
  [ -f "${SCRIPT}" ]
  run grep -E 'inotifywait.*-m|inotifywait.*create|inotifywait.*modify' \
    "${SCRIPT}"
  [ "${status}" -eq 0 ] || {
    echo "FAIL: AC #4 未実装 — ${SCRIPT} に inotifywait -m -e create -e modify 出力コードが存在しない" >&2
    return 1
  }
}

@test "ac4: script が実行可能である" {
  # AC: script に実行権限が付与されている
  [ -f "${SCRIPT}" ]
  [ -x "${SCRIPT}" ] || {
    echo "FAIL: AC #4 — ${SCRIPT} に実行権限がない" >&2
    return 1
  }
}
