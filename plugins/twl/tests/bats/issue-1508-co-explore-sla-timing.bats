#!/usr/bin/env bats
# issue-1508-co-explore-sla-timing.bats
#
# RED-phase tests for Issue #1523 (tech-debt: Issue #1508 AC5 残):
#   tech-debt(su-observer): co-explore MENU-READY → observer 応答 ≤60s の動的 SLA bats test 追加
#
# AC coverage:
#   AC1 - mock tmux セッションで wt-co-explore-* window を bats 環境で模擬できる
#         （setup 関数でモック環境を構築）
#   AC2 - .supervisor/events/ ディレクトリに MENU-READY event ファイルを書き込む処理が
#         bats で実行できる
#   AC3 - cld-observe-any または dedicated Monitor が MENU-READY イベントを 60s 以内に
#         検知することを bats で time 計測して検証する
#
# 全テストは実装前（RED）状態で fail する。
#
# NOTE (baseline-bash §9): シングルクォート heredoc 内に外部変数を展開する箇所は
#   非クォート heredoc (<<EOF) を使用する。外部変数 TMPDIR_TEST 等を heredoc 内で展開。
# NOTE (baseline-bash §10): cld-observe-any は _DAEMON_LOAD_ONLY パターンを持つ（L105）。
#   source する場合は `_DAEMON_LOAD_ONLY=1 source cld-observe-any` で main を回避できる。
#   本テストでは source は行わず、サブシェル実行方式のみを使用する。
# NOTE (baseline-bash Markdown テーブル §9-10): Markdown テーブルの用語列（1列目）マッチは
#   grep -qF '| term |' パターン（左右パイプ区切り付き）を使用する。
#   BAD: grep -qF 'term'（説明列への偽陽性マッチのリスク）
#   GOOD: grep -qF '| term |'（用語列に限定）
#
# RED 確保戦略:
#   - AC1: bats 専用の分離 tmux セッションに wt-co-explore-bats-<PID> window が存在することを検証
#          → 実装なし（setup で mock session を作らない）のため fail
#   - AC2: co-explore 専用 event writer スクリプト（co-explore-menu-event-writer.sh）の存在を検証
#          → 未実装のため fail
#          また MENU-READY JSON に sla_deadline_epoch フィールドが存在することを検証
#          → cld-observe-any 標準出力にはこのフィールドがないため fail
#   - AC3: dedicated Monitor スクリプト（co-explore-menu-watcher.sh）の存在を検証
#          → 未実装のため fail
#          また bats 専用パターン wt-co-explore-bats-<PID> で 60s 以内検知を time 計測
#          → mock session 未作成のため window 不在、detected=false で fail

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  PLUGIN_TWL_ROOT="$(cd "${tests_dir}/.." && pwd)"
  # REPO_ROOT: plugins/twl/ から 2 階層上（plugins/ → worktree root）
  REPO_ROOT="$(cd "${PLUGIN_TWL_ROOT}/../.." && pwd)"
  export REPO_ROOT PLUGIN_TWL_ROOT

  # テスト対象スクリプトのパス
  CLD_OBSERVE_ANY="${REPO_ROOT}/plugins/session/scripts/cld-observe-any"
  CHANNELS_MD="${PLUGIN_TWL_ROOT}/skills/su-observer/refs/su-observer-supervise-channels.md"
  # AC3: dedicated Monitor スクリプト（未実装 → RED の根拠）
  DEDICATED_MONITOR="${PLUGIN_TWL_ROOT}/skills/su-observer/scripts/co-explore-menu-watcher.sh"
  # AC2: co-explore 専用 event writer スクリプト（未実装 → RED の根拠）
  MENU_EVENT_WRITER="${PLUGIN_TWL_ROOT}/skills/su-observer/scripts/co-explore-menu-event-writer.sh"

  export CLD_OBSERVE_ANY CHANNELS_MD DEDICATED_MONITOR MENU_EVENT_WRITER

  # テスト用一時ディレクトリ（teardown でクリーンアップ）
  TMPDIR_TEST="$(mktemp -d)"
  MOCK_SUPERVISOR="${TMPDIR_TEST}/.supervisor"
  EVENTS_DIR="${MOCK_SUPERVISOR}/events"
  mkdir -p "${EVENTS_DIR}"

  export TMPDIR_TEST MOCK_SUPERVISOR EVENTS_DIR

  # bats 専用 mock session 名（実際の tmux session とは独立した名前）
  # 実 tmux window（wt-co-explore-125835 等）と混同しないよう、
  # bats テスト実行 PID を埋め込んだ一意名を使用する
  MOCK_SESSION_NAME="bats-co-explore-test-$$"
  MOCK_WINDOW_NAME="wt-co-explore-bats-test-$$"
  # cld-observe-any で使う bats 専用パターン（実 window にはマッチしない）
  BATS_WINDOW_PATTERN="wt-co-explore-bats-${$}"
  export MOCK_SESSION_NAME MOCK_WINDOW_NAME BATS_WINDOW_PATTERN
}

teardown() {
  # mock tmux session のクリーンアップ（作成していた場合のみ）
  if tmux has-session -t "${MOCK_SESSION_NAME}" 2>/dev/null; then
    tmux kill-session -t "${MOCK_SESSION_NAME}" 2>/dev/null || true
  fi
  # バックグラウンドプロセスのクリーンアップ
  if [[ -n "${BG_PID:-}" ]] && kill -0 "${BG_PID}" 2>/dev/null; then
    kill "${BG_PID}" 2>/dev/null || true
    wait "${BG_PID}" 2>/dev/null || true
  fi
  # 一時ディレクトリ削除
  if [[ -n "${TMPDIR_TEST:-}" ]] && [[ -d "${TMPDIR_TEST}" ]]; then
    rm -rf "${TMPDIR_TEST}"
  fi
}

# ===========================================================================
# AC1: mock tmux セッションで wt-co-explore-* window を bats 環境で模擬できる
#
# RED 根拠:
#   setup 関数は bats 専用の分離 tmux session を作成していない。
#   実装後は setup() 内で
#     tmux new-session -d -s "${MOCK_SESSION_NAME}" -x 220 -y 50
#     tmux new-window -t "${MOCK_SESSION_NAME}" -n "${MOCK_WINDOW_NAME}"
#   を実行することで GREEN になる。
# ===========================================================================

@test "ac1: bats-isolated mock tmux session exists with wt-co-explore-bats-PID window" {
  # AC: setup 関数が bats 専用の分離 tmux session を作成し、
  #     その session 内に wt-co-explore-bats-<PID> window が存在する
  # RED: setup が mock session を作成していないため fail
  tmux has-session -t "${MOCK_SESSION_NAME}" 2>/dev/null
}

@test "ac1: mock window exists only in bats session not in global window list" {
  # AC: MOCK_WINDOW_NAME が bats 専用 session のみに存在する
  # RED: mock session 未作成のため wt-co-explore-bats-* window が存在せず fail
  run tmux list-windows -t "${MOCK_SESSION_NAME}" -F '#{window_name}' 2>/dev/null
  # セッションが存在しない場合も存在してもウィンドウ名が見つからない場合も fail
  echo "${output}" | grep -qF "${MOCK_WINDOW_NAME}"
}

@test "ac1: cld-observe-any has co-explore-sla flag implemented" {
  # AC: cld-observe-any が co-explore 専用の SLA 計測フラグ --co-explore-sla を実装している
  # RED: 標準の cld-observe-any には --co-explore-sla が存在しないため fail
  grep -qF -- '--co-explore-sla' "${CLD_OBSERVE_ANY}"
}

@test "ac1: cld-observe-any with bats-only pattern finds mock window in bats session" {
  # AC: cld-observe-any が bats 専用パターン wt-co-explore-bats-<PID> で実行され、
  #     bats mock session 内の window のみを対象とする（実 window は対象外）
  # RED: mock session が未作成のため、パターンマッチ結果に bats mock window が含まれず fail
  local result
  result=$(
    SUPERVISOR_DIR="${MOCK_SUPERVISOR}" \
    bash "${CLD_OBSERVE_ANY}" \
      --pattern "${BATS_WINDOW_PATTERN}" \
      --once \
      --max-cycles 1 \
    2>&1 || true
  )
  # bats 専用 mock window 名がイベント出力に含まれることを確認
  # RED: mock session 未作成のため window が存在せず、出力に MOCK_WINDOW_NAME が含まれない
  echo "${result}" | grep -qF "${MOCK_WINDOW_NAME}"
}

# ===========================================================================
# AC2: .supervisor/events/ ディレクトリに MENU-READY event ファイルを書き込む処理が
#      bats で実行できる
#
# RED 根拠:
#   (a) co-explore-menu-event-writer.sh が未実装
#   (b) MENU-READY JSON に sla_deadline_epoch フィールドが未実装
# ===========================================================================

@test "ac2: co-explore-menu-event-writer.sh script exists" {
  # AC: co-explore 専用の MENU-READY event writer スクリプトが存在する
  # RED: スクリプトが未実装のため fail
  [ -f "${MENU_EVENT_WRITER}" ]
}

@test "ac2: co-explore-menu-event-writer.sh writes MENU-READY json to events dir" {
  # AC: co-explore-menu-event-writer.sh を実行すると events/ に MENU-READY-*.json が生成される
  # RED: スクリプト未実装のため fail
  [ -f "${MENU_EVENT_WRITER}" ]

  local before_count
  before_count=$(find "${EVENTS_DIR}" -name 'MENU-READY-*.json' 2>/dev/null | wc -l)

  SUPERVISOR_DIR="${MOCK_SUPERVISOR}" \
  bash "${MENU_EVENT_WRITER}" \
    --window "${MOCK_WINDOW_NAME}" \
    --events-dir "${EVENTS_DIR}" \
  2>&1

  local after_count
  after_count=$(find "${EVENTS_DIR}" -name 'MENU-READY-*.json' 2>/dev/null | wc -l)
  [ "${after_count}" -gt "${before_count}" ]
}

@test "ac2: MENU-READY event JSON has sla_deadline_epoch field for 60s SLA tracking" {
  # AC: MENU-READY event JSON に SLA 60s 計測用の sla_deadline_epoch フィールドが含まれる
  #     （T0 + 60 の epoch 値、co-explore 専用フィールド）
  # RED: 標準の cld-observe-any emit_event() は sla_deadline_epoch を出力しない
  #      co-explore 専用フィールドが cld-observe-any に未実装のため fail

  # cld-observe-any を bats 専用パターンで実行して event file を生成させる
  SUPERVISOR_DIR="${MOCK_SUPERVISOR}" \
  bash "${CLD_OBSERVE_ANY}" \
    --pattern "${BATS_WINDOW_PATTERN}" \
    --format json \
    --event-dir "${EVENTS_DIR}" \
    --once \
    --max-cycles 1 \
  2>&1 || true

  # event ファイルが生成されていれば sla_deadline_epoch を検証
  local event_file
  event_file=$(find "${EVENTS_DIR}" -name 'MENU-READY-*.json' 2>/dev/null | head -1)
  if [[ -n "${event_file}" ]]; then
    # RED: 標準 JSON には sla_deadline_epoch がないため fail
    grep -qF '"sla_deadline_epoch"' "${event_file}"
  else
    # event ファイルが生成されない場合も fail（bats mock window 未作成のため）
    false
  fi
}

@test "ac2: MENU-READY event JSON from cld-observe-any has co_explore_sla_t0 field" {
  # AC: cld-observe-any が co-explore モードで出力する MENU-READY JSON に
  #     SLA 計測開始時刻 co_explore_sla_t0 フィールドが含まれている
  # RED: 標準 emit_event() は co_explore_sla_t0 を出力しない。未実装のため fail
  grep -qF 'co_explore_sla_t0' "${CLD_OBSERVE_ANY}"
}

# ===========================================================================
# AC3: cld-observe-any または dedicated Monitor が MENU-READY イベントを 60s 以内に
#      検知することを bats で time 計測して検証する
#
# RED 根拠:
#   (a) co-explore-menu-watcher.sh（dedicated Monitor）が未実装
#   (b) bats 分離 tmux session が未作成のため timing 計測の前提が満たされない
# ===========================================================================

@test "ac3: co-explore-menu-watcher.sh dedicated monitor script exists and is executable" {
  # AC: co-explore dedicated Monitor スクリプトが実装済みで実行可能である
  # RED: スクリプトが未実装のため fail
  [ -f "${DEDICATED_MONITOR}" ]
  [ -x "${DEDICATED_MONITOR}" ]
}

@test "ac3: dedicated monitor detects MENU-READY in bats mock session within 60s" {
  # AC: co-explore-menu-watcher.sh が bats mock session の wt-co-explore-bats-<PID> window に
  #     対し MENU-READY event を 60s 以内に検知し、events/ にファイルを書き出す
  # RED: (a) dedicated Monitor 未実装 → [ -f "${DEDICATED_MONITOR}" ] で fail

  # 前提: dedicated Monitor スクリプトが存在すること（RED: ここで fail）
  [ -f "${DEDICATED_MONITOR}" ]

  # T0 記録
  local t0
  t0=$(date +%s)

  # dedicated Monitor を起動してバックグラウンドで監視
  SUPERVISOR_DIR="${MOCK_SUPERVISOR}" \
  EVENT_DIR="${EVENTS_DIR}" \
  timeout 70 bash "${DEDICATED_MONITOR}" \
    --session "${MOCK_SESSION_NAME}" \
    --window-pattern "${BATS_WINDOW_PATTERN}" \
    --event-dir "${EVENTS_DIR}" \
  2>&1 &
  BG_PID="$!"

  # MENU-READY event ファイルが 60s 以内に生成されるまで polling
  local detected=false
  local poll_count=0
  while [[ "${poll_count}" -lt 60 ]]; do
    if find "${EVENTS_DIR}" -name 'MENU-READY-*.json' 2>/dev/null | grep -q .; then
      detected=true
      break
    fi
    sleep 1
    poll_count=$(( poll_count + 1 ))
  done

  local t1
  t1=$(date +%s)
  local elapsed=$(( t1 - t0 ))

  kill "${BG_PID}" 2>/dev/null || true
  wait "${BG_PID}" 2>/dev/null || true
  BG_PID=""

  echo "elapsed: ${elapsed}s, detected: ${detected}" >&2

  [ "${detected}" = "true" ]
  [ "${elapsed}" -le 60 ]
}

@test "ac3: cld-observe-any emits MENU-READY for bats-only window pattern within 60s" {
  # AC: cld-observe-any を bats 専用パターン wt-co-explore-bats-<PID> で起動し、
  #     bats mock session の window に対して MENU-READY が 60s 以内に emit される
  #     （date +%s で elapsed を計測）
  # RED: bats 専用 mock session（MOCK_SESSION_NAME）が未作成のため、
  #      wt-co-explore-bats-<PID> window が存在せず MENU-READY は emit されない
  #      → detected=false で fail
  #
  # 即時 fail ガード: cld-observe-any に --co-explore-sla フラグが未実装のため RED を即時確定
  # このガードにより、30秒ポーリングを待たずに即時 fail する（CI 時間節約）
  if ! grep -qF -- '--co-explore-sla' "${CLD_OBSERVE_ANY}"; then
    echo "RED: --co-explore-sla flag not implemented in cld-observe-any" >&2
    false
    return
  fi

  local t0
  t0=$(date +%s)

  local observe_log
  observe_log="${TMPDIR_TEST}/co-explore-observe.log"

  # cld-observe-any を bats 専用パターンで起動（実 wt-co-explore-* にはマッチしない）
  SUPERVISOR_DIR="${MOCK_SUPERVISOR}" \
  timeout 35 bash "${CLD_OBSERVE_ANY}" \
    --pattern "${BATS_WINDOW_PATTERN}" \
    --interval 5 \
    --event-dir "${EVENTS_DIR}" \
    --max-cycles 3 \
  2>&1 | tee "${observe_log}" &
  BG_PID="$!"

  # bats 専用パターンの MENU-READY ファイルを 30s 以内に検知
  local detected=false
  local poll_count=0
  while [[ "${poll_count}" -lt 30 ]]; do
    # ファイル名に BATS_WINDOW_PATTERN の先頭部分が含まれるものを探す
    if find "${EVENTS_DIR}" -name "MENU-READY-wt-co-explore-bats-${$}*.json" 2>/dev/null | grep -q .; then
      detected=true
      break
    fi
    sleep 1
    poll_count=$(( poll_count + 1 ))
  done

  local t1
  t1=$(date +%s)
  local elapsed=$(( t1 - t0 ))

  kill "${BG_PID}" 2>/dev/null || true
  wait "${BG_PID}" 2>/dev/null || true
  BG_PID=""

  echo "elapsed: ${elapsed}s, detected: ${detected}" >&2

  # RED: bats mock session 未作成のため detected=false → fail
  [ "${detected}" = "true" ]
  [ "${elapsed}" -le 60 ]
}

@test "ac3: channels-md SLA entry in co-explore Monitor term column and dedicated monitor exists" {
  # AC: su-observer-supervise-channels.md の co-explore dedicated Monitor テーブル行（用語列）が
  #     SLA ≤60s を記述しており、かつ bats SLA 計測を実行する dedicated Monitor が実装済みである
  # RED: dedicated Monitor スクリプトが存在しないため fail
  #
  # NOTE (Markdown テーブル用語列マッチ baseline-bash §9-10):
  #   '| **co-explore dedicated Monitor** |' は左右パイプ付きで用語列のみにマッチする。
  #   grep -qF 'co-explore dedicated Monitor' は説明列への偽陽性リスクがあるため使用しない。

  # テーブル用語列マッチ（左右パイプ必須）
  run grep -qF '| **co-explore dedicated Monitor** |' "${CHANNELS_MD}"
  [ "${status}" -eq 0 ]

  # SLA 60s 記述が channels.md に存在する
  run grep -qE '≤.*60s|60s.*以内|SLA.*60|60.*SLA' "${CHANNELS_MD}"
  [ "${status}" -eq 0 ]

  # RED: dedicated Monitor スクリプトが存在することで bats SLA テストが機能する
  #      スクリプト未実装のため fail
  [ -f "${DEDICATED_MONITOR}" ]
}
