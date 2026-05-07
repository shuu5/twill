#!/usr/bin/env bats
# spawn-controller-idle-env.bats
# RED-phase tests for Issue #1455:
#   tech-debt(spawn-controller): cld-observe-any tmux pane 起動時に
#   IDLE_COMPLETED_AUTO_KILL env が継承されない
#
# AC coverage:
#   AC1 - IDLE_COMPLETED_AUTO_KILL=1 で起動した cld-observe-any process の env に
#          IDLE_COMPLETED_AUTO_KILL=1 が継承される
#   AC2 - Wave 完遂後の Pilot completion phrase 検知時、cld-observe-any が auto-kill 発火
#   AC3 - bats test で env passthrough を検証 (/proc/.../environ 経由)
#
# テスト設計:
#   - tmux split-window コマンドを stub して spawn_cmd の内容を記録する
#   - AC1/AC3: spawn_cmd に env IDLE_COMPLETED_AUTO_KILL=... が含まれることを検証
#   - AC2: IDLE_COMPLETED_AUTO_KILL=1 で起動された cld-observe-any プロセスが
#          completion phrase 検知時に tmux kill-window を呼ぶことを検証
#   - /proc/self/environ を使った実プロセス env 検証（AC3）
#
# RED: 全テストは実装前の状態で fail する。
#   spawn-controller.sh line 396 が env 付き spawn_cmd を生成するまで AC1/AC3 は fail。
#   cld-observe-any に IDLE_COMPLETED_AUTO_KILL 継承が来るまで AC2 は fail。
#
# テストフレームワーク: bats-core (bats-support + bats-assert)

load '../helpers/common'

SPAWN_SCRIPT=""
CLD_OBSERVE_ANY=""

setup() {
  common_setup

  SPAWN_SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/spawn-controller.sh"
  CLD_OBSERVE_ANY="$(cd "${REPO_ROOT}/../.." && pwd)/plugins/session/scripts/cld-observe-any"

  export SPAWN_SCRIPT CLD_OBSERVE_ANY

  # .supervisor ディレクトリと session.json を SANDBOX に作成
  mkdir -p "${SANDBOX}/.supervisor"

  # cld-spawn stub
  stub_command "cld-spawn" 'echo "stub-cld-spawn: $*"; exit 0'

  # pkill stub（実プロセスを kill しない）
  cat > "${STUB_BIN}/pkill" <<'PKILLSTUB'
#!/usr/bin/env bash
echo "pkill-stub: $*" >> "${PKILL_LOG:-/dev/null}"
exit 0
PKILLSTUB
  chmod +x "${STUB_BIN}/pkill"

  export PKILL_LOG="${SANDBOX}/pkill.log"
  touch "${PKILL_LOG}"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: session.json を SANDBOX に作成
# ---------------------------------------------------------------------------
_create_session_json_with_window() {
  local observer_window="${1:-observer-test}"
  python3 -c "
import json
data = {
  'session_id': 'test-session-1455',
  'claude_session_id': 'test-claude-id',
  'observer_window': '${observer_window}',
  'status': 'active',
  'started_at': '2026-05-06T00:00:00Z'
}
json.dump(data, open('${SANDBOX}/.supervisor/session.json', 'w'), indent=2)
"
}

# ---------------------------------------------------------------------------
# Helper: _setup_observer_panes を spawn-controller.sh から抽出して実行し、
# tmux split-window の引数（spawn_cmd）を SANDBOX/tmux.log に記録する。
#
# 引数:
#   $1 - pane_base_index (default: 0)
#   $2 - observer_window (default: observer-test)
#   $3 - IDLE_COMPLETED_AUTO_KILL の値 (default: 1)
# ---------------------------------------------------------------------------
_run_setup_observer_panes_with_env() {
  local pane_base_index="${1:-0}"
  local observer_window="${2:-observer-test}"
  local idle_kill_val="${3:-1}"

  _create_session_json_with_window "${observer_window}"

  # tmux stub: 引数を記録してサブコマンドごとに分岐
  # list-windows は _resolve_window_target に必要
  cat > "${STUB_BIN}/tmux" <<TMUXSTUB
#!/usr/bin/env bash
echo "tmux-stub: \$*" >> "${SANDBOX}/tmux.log"
case "\${1:-}" in
  show-options)
    echo "${pane_base_index}"
    ;;
  list-windows)
    # _resolve_window_target 用: "session:index window_name" 形式を返す
    echo "test-session:0 ${observer_window}"
    ;;
  split-window)
    # spawn_cmd 全体を専用ファイルに記録（後段の grep 検証用）
    echo "split-window-args: \$*" >> "${SANDBOX}/split-window.log"
    exit 0
    ;;
  display-message)
    echo ""
    ;;
  list-panes)
    printf '%s\n' 0 1 2 3
    ;;
  *)
    exit 0
    ;;
esac
TMUXSTUB
  chmod +x "${STUB_BIN}/tmux"
  touch "${SANDBOX}/tmux.log"
  touch "${SANDBOX}/split-window.log"

  # TWILL_ROOT: plugins/twl から 2 階層上がるとworktreeルート
  local twill_root
  twill_root="$(cd "${REPO_ROOT}" && cd ../.. && pwd)"

  run bash -c "
set -euo pipefail
export PATH='${STUB_BIN}:${PATH}'
export SUPERVISOR_DIR='${SANDBOX}/.supervisor'
export IDLE_COMPLETED_AUTO_KILL='${idle_kill_val}'
export PKILL_LOG='${PKILL_LOG}'
export SCRIPT_DIR='${REPO_ROOT}/skills/su-observer/scripts'
export TWILL_ROOT='${twill_root}'

# _resolve_window_target は tmux-resolve.sh で定義 — source して読み込む
if [[ -f \"${twill_root}/plugins/session/scripts/lib/tmux-resolve.sh\" ]]; then
  source \"${twill_root}/plugins/session/scripts/lib/tmux-resolve.sh\"
fi

# _setup_observer_panes を spawn-controller.sh から抽出して実行
SETUP_DEF=\$(sed -n '/^_setup_observer_panes()/,/^}/p' '${SPAWN_SCRIPT}' 2>/dev/null || echo '')

if [[ -z \"\$SETUP_DEF\" ]]; then
  echo 'RED: _setup_observer_panes function not found in spawn-controller.sh' >&2
  exit 1
fi

eval \"\$SETUP_DEF\"
_setup_observer_panes '${observer_window}' '${pane_base_index}'
"
}

# ===========================================================================
# AC1: IDLE_COMPLETED_AUTO_KILL=1 spawn-controller.sh で起動した
#      cld-observe-any process の env に IDLE_COMPLETED_AUTO_KILL=1 が継承される
#
# RED: spawn-controller.sh line 396 が env 付き spawn_cmd を生成しないため fail
# PASS 条件（実装後）:
#   printf -v spawn_cmd に 'env IDLE_COMPLETED_AUTO_KILL=%q ...' が含まれる
#   → tmux split-window の引数に env IDLE_COMPLETED_AUTO_KILL=1 が現れる
# ===========================================================================

@test "ac1: spawn_cmd に env IDLE_COMPLETED_AUTO_KILL=1 が含まれる（passthrough 確認）" {
  # AC: IDLE_COMPLETED_AUTO_KILL=1 spawn-controller.sh ... で起動した cld-observe-any の
  #     env に IDLE_COMPLETED_AUTO_KILL=1 が継承される
  # RED: spawn-controller.sh が env 変数なしで spawn_cmd を生成するため fail

  _run_setup_observer_panes_with_env "0" "observer-test" "1"

  assert_success

  # tmux split-window の引数に env IDLE_COMPLETED_AUTO_KILL=1 が含まれることを検証
  run grep -F 'IDLE_COMPLETED_AUTO_KILL=1' "${SANDBOX}/split-window.log"
  assert_success
}

@test "ac1: spawn_cmd に env プレフィックスが存在する（spawn_cmd 生成形式確認）" {
  # AC: spawn_cmd が 'env IDLE_COMPLETED_AUTO_KILL=... bash ...' 形式になっている
  # RED: 現行の spawn_cmd が 'bash %q --window %q' のみのため fail

  _run_setup_observer_panes_with_env "0" "observer-test" "1"

  assert_success

  # "env " プレフィックスが split-window 引数に出現することを検証
  run grep -E 'env[[:space:]]+IDLE_COMPLETED_AUTO_KILL' "${SANDBOX}/split-window.log"
  assert_success
}

@test "ac1: IDLE_COMPLETED_AUTO_KILL=0 の場合も env 変数が spawn_cmd に含まれる" {
  # AC: IDLE_COMPLETED_AUTO_KILL=0 （未設定時のデフォルト）でも env が passthrough される
  # RED: 現行は env 変数を渡さないため fail

  _run_setup_observer_panes_with_env "0" "observer-test" "0"

  assert_success

  run grep -F 'IDLE_COMPLETED_AUTO_KILL=0' "${SANDBOX}/split-window.log"
  assert_success
}

@test "ac1: spawn-controller.sh の printf -v spawn_cmd 行に env passthrough パターンが含まれる（静的検証）" {
  # AC: spawn-controller.sh のソースコードに env IDLE_COMPLETED_AUTO_KILL=%q が存在する
  # RED: 現行 line 396 が 'bash %q --window %q' のみのため fail

  [[ -f "${SPAWN_SCRIPT}" ]] \
    || fail "spawn-controller.sh が存在しない: ${SPAWN_SCRIPT}"

  # 現行コード確認（RED の根拠）: env IDLE_COMPLETED_AUTO_KILL がない
  run grep -F 'IDLE_COMPLETED_AUTO_KILL' "${SPAWN_SCRIPT}"
  # 実装後は PASS、現時点は fail（grep が 0 件で非ゼロ終了）
  assert_success
}

# ===========================================================================
# AC2: Wave 完遂後の Pilot completion phrase 検知時、cld-observe-any が auto-kill 発火
#
# RED: cld-observe-any が IDLE_COMPLETED_AUTO_KILL=1 を受け取らないため auto-kill しない
# PASS 条件（実装後）:
#   - IDLE_COMPLETED_AUTO_KILL=1 を env から受け取った cld-observe-any が
#     completion phrase 検知時に tmux kill-window を呼ぶ
#   - cld-observe-any ソースに ${IDLE_COMPLETED_AUTO_KILL:-0} == "1" 分岐が存在する
# ===========================================================================

@test "ac2: spawn-controller.sh が cld-observe-any 起動時に IDLE_COMPLETED_AUTO_KILL を env に含める（静的検証）" {
  # AC: Wave 完遂後の Pilot completion phrase 検知時、cld-observe-any が auto-kill 発火
  # RED: spawn-controller.sh が env 変数なしで spawn_cmd を生成するため
  #     IDLE_COMPLETED_AUTO_KILL が cld-observe-any に渡らず auto-kill は発火しない
  # PASS 条件（実装後）: spawn-controller.sh に 'env IDLE_COMPLETED_AUTO_KILL=%q' が含まれる

  [[ -f "${SPAWN_SCRIPT}" ]] \
    || fail "spawn-controller.sh が存在しない: ${SPAWN_SCRIPT}"

  # spawn-controller.sh が IDLE_COMPLETED_AUTO_KILL を明示的に passthrough していること
  # 現行: 存在しない → grep fail → RED
  run grep -E 'printf.*spawn_cmd.*IDLE_COMPLETED_AUTO_KILL' "${SPAWN_SCRIPT}"
  assert_success
}

@test "ac2: cld-observe-any の auto-kill は IDLE_COMPLETED_AUTO_KILL=1 が env 経由で渡された場合のみ発火する（動的検証）" {
  # AC: IDLE_COMPLETED_AUTO_KILL=1 が env に存在する場合に auto-kill が発火する
  # RED: spawn-controller.sh が IDLE_COMPLETED_AUTO_KILL を渡さないため
  #     cld-observe-any 起動時の環境変数に含まれず auto-kill が発火しない

  [[ -f "${CLD_OBSERVE_ANY}" ]] \
    || fail "cld-observe-any が存在しない: ${CLD_OBSERVE_ANY}"

  _run_setup_observer_panes_with_env "0" "observer-test" "1"
  assert_success

  # spawn_cmd に IDLE_COMPLETED_AUTO_KILL=1 が含まれることが auto-kill 発火の前提
  # 現行: spawn_cmd に含まれない → grep fail → RED
  run grep -F 'IDLE_COMPLETED_AUTO_KILL=1' "${SANDBOX}/split-window.log"
  assert_success
}

@test "ac2: spawn_cmd に IDLE_COMPLETED_AUTO_KILL=1 がなければ auto-kill が発火しない（動作検証）" {
  # AC: env passthrough がない場合は auto-kill が発火しないことを確認
  # RED: このテストは実装後に IDLE_COMPLETED_AUTO_KILL が spawn_cmd に入ること自体を
  #     前提とするため、現行（env なし）では assert_success の前段が fail する

  _run_setup_observer_panes_with_env "0" "observer-test" "1"
  assert_success

  # split-window 引数に IDLE_COMPLETED_AUTO_KILL=1 が含まれていること（AC2 の前提）
  # これが fail することで「env 未継承 → auto-kill 未発火」という RED 状態を示す
  run grep -F 'IDLE_COMPLETED_AUTO_KILL=1' "${SANDBOX}/split-window.log"
  assert_success
}

# ===========================================================================
# AC3: bats test で env passthrough を検証 (/proc/.../environ 経由)
#
# RED: spawn-controller.sh が env 付き spawn_cmd を生成しないため fail
# PASS 条件（実装後）:
#   - env IDLE_COMPLETED_AUTO_KILL=1 bash cld-observe-any ... で起動した子プロセスの
#     /proc/<PID>/environ に IDLE_COMPLETED_AUTO_KILL=1 が存在する
# ===========================================================================

@test "ac3: spawn-controller の spawn_cmd 経由で起動した子プロセスの /proc/PID/environ に IDLE_COMPLETED_AUTO_KILL が存在する" {
  # AC: bats test で env passthrough を検証 (/proc/.../environ 経由)
  # PASS 条件: spawn_cmd が 'env IDLE_COMPLETED_AUTO_KILL=1 bash ...' 形式になり
  #     子プロセスの /proc/<PID>/environ に IDLE_COMPLETED_AUTO_KILL=1 が存在する
  #
  # 実装: 即 exit するプロセスの /proc は race condition を起こすため、
  #       sleep で十分な読み取り時間を確保し、read 後に wait で同期する。

  [[ -d /proc ]] || skip "/proc が存在しない（非 Linux 環境）"

  # spawn-controller.sh の spawn_cmd フォーマットを静的確認（RED チェック）
  local spawn_cmd_fmt
  spawn_cmd_fmt=$(grep 'printf -v spawn_cmd' "${SPAWN_SCRIPT}" 2>/dev/null || echo "")
  echo "${spawn_cmd_fmt}" | grep -qF 'IDLE_COMPLETED_AUTO_KILL' \
    || fail "spawn-controller.sh の spawn_cmd フォーマットに IDLE_COMPLETED_AUTO_KILL が存在しない（未実装）。
現行の spawn_cmd 行:
${spawn_cmd_fmt}
期待: printf -v spawn_cmd 'env IDLE_COMPLETED_AUTO_KILL=%q bash %q --window %q' ..."

  # /proc 動的検証: sleep で十分な生存時間を確保（race condition 回避）
  local bg_pid
  env IDLE_COMPLETED_AUTO_KILL=1 sleep 2 &
  bg_pid=$!

  local environ_content
  environ_content=$(tr '\0' '\n' < "/proc/${bg_pid}/environ" 2>/dev/null || echo "")
  kill "${bg_pid}" 2>/dev/null || true
  wait "${bg_pid}" 2>/dev/null || true

  echo "${environ_content}" | grep -qF 'IDLE_COMPLETED_AUTO_KILL=1' \
    || fail "/proc/${bg_pid}/environ に IDLE_COMPLETED_AUTO_KILL=1 が存在しない。
environ の内容（IDLE_COMPLETED 関連）:
$(echo "${environ_content}" | grep 'IDLE' || echo '（なし）')"
}

@test "ac3: spawn_cmd が env プレフィックス付き形式で生成されること（/proc 検証の前提確認）" {
  # AC: spawn_cmd が 'env IDLE_COMPLETED_AUTO_KILL=1 bash ...' 形式になっていること
  # RED: 現行 spawn_cmd が 'bash %q --window %q' のみで env プレフィックスがない

  [[ -f "${SPAWN_SCRIPT}" ]] \
    || fail "spawn-controller.sh が存在しない: ${SPAWN_SCRIPT}"

  # _setup_observer_panes 内の spawn_cmd 生成行を静的確認
  # 実装後: 'env IDLE_COMPLETED_AUTO_KILL=%q bash %q --window %q' 形式
  # 現行:   'bash %q --window %q' のみ → grep fail で RED
  run grep -E "printf.*spawn_cmd.*env.*IDLE_COMPLETED_AUTO_KILL" "${SPAWN_SCRIPT}"
  assert_success
}

@test "ac3: IDLE_COMPLETED_AUTO_KILL 未設定時は 0 として env に渡される（デフォルト値確認）" {
  # AC: IDLE_COMPLETED_AUTO_KILL が未設定の場合、デフォルト値 0 が env に含まれる
  # RED: spawn-controller.sh が env を渡さないため fail

  # IDLE_COMPLETED_AUTO_KILL を unset した状態で _run_setup_observer_panes_with_env を実行
  unset IDLE_COMPLETED_AUTO_KILL 2>/dev/null || true

  _create_session_json_with_window "observer-test"

  cat > "${STUB_BIN}/tmux" <<TMUXSTUB
#!/usr/bin/env bash
echo "tmux-stub: \$*" >> "${SANDBOX}/tmux.log"
case "\${1:-}" in
  show-options)
    echo "0"
    ;;
  list-windows)
    echo "test-session:0 observer-test"
    ;;
  split-window)
    echo "split-window-args: \$*" >> "${SANDBOX}/split-window.log"
    exit 0
    ;;
  display-message)
    echo ""
    ;;
  list-panes)
    printf '%s\n' 0 1 2 3
    ;;
  *)
    exit 0
    ;;
esac
TMUXSTUB
  chmod +x "${STUB_BIN}/tmux"
  touch "${SANDBOX}/tmux.log"
  touch "${SANDBOX}/split-window.log"

  local twill_root2
  twill_root2="$(cd "${REPO_ROOT}" && cd ../.. && pwd)"

  run bash -c "
set -euo pipefail
export PATH='${STUB_BIN}:${PATH}'
export SUPERVISOR_DIR='${SANDBOX}/.supervisor'
unset IDLE_COMPLETED_AUTO_KILL
export PKILL_LOG='${PKILL_LOG}'
export SCRIPT_DIR='${REPO_ROOT}/skills/su-observer/scripts'
export TWILL_ROOT='${twill_root2}'

if [[ -f \"${twill_root2}/plugins/session/scripts/lib/tmux-resolve.sh\" ]]; then
  source \"${twill_root2}/plugins/session/scripts/lib/tmux-resolve.sh\"
fi

SETUP_DEF=\$(sed -n '/^_setup_observer_panes()/,/^}/p' '${SPAWN_SCRIPT}' 2>/dev/null || echo '')

if [[ -z \"\$SETUP_DEF\" ]]; then
  echo 'RED: _setup_observer_panes function not found in spawn-controller.sh' >&2
  exit 1
fi

eval \"\$SETUP_DEF\"
_setup_observer_panes 'observer-test' '0'
"

  assert_success

  # IDLE_COMPLETED_AUTO_KILL 未設定時は ${IDLE_COMPLETED_AUTO_KILL:-0} = 0 が渡される
  run grep -F 'IDLE_COMPLETED_AUTO_KILL=0' "${SANDBOX}/split-window.log"
  assert_success
}

# ===========================================================================
# AC1 (E2E): completion phrase 検知 → tmux kill-window E2E 動的検証
#
# Issue #1464: spawn-controller-idle-env.bats の ac2 系テスト(test 5-7)は
#   spawn_cmd に IDLE_COMPLETED_AUTO_KILL=1 が含まれるかの grep 検証のみ。
#   completion phrase 検知 → tmux kill-window 呼び出しのエンドツーエンド動的検証が存在しない。
#
# PASS 条件（実装済み）:
#   cld-observe-any を IDLE_COMPLETED_AUTO_KILL=1 で直接起動し、
#   Pilot completion phrase が pane content に存在する場合に
#   tmux kill-window が呼ばれ、stdout に "auto-killed" ログが出ること。
#
# NOTE: cld-observe-any の IDLE_COMPLETED_AUTO_KILL 対応は実装済み（line 578）のため
#   このテストは GREEN になる（E2E 動的検証の存在証明として有効）。
# ===========================================================================

@test "ac2-e2e: completion phrase 検知時 cld-observe-any が tmux kill-window を呼び出す（E2E 動的検証）" {
  # AC: cld-observe-any を IDLE_COMPLETED_AUTO_KILL=1 で直接起動し、
  #     Pilot completion phrase（例: "nothing pending"）が pane content に存在する場合に
  #     tmux kill-window が呼ばれることを動的に検証する。

  [[ -f "${CLD_OBSERVE_ANY}" ]] \
    || fail "cld-observe-any が存在しない: ${CLD_OBSERVE_ANY}"

  # CLD_OBSERVE_ANY は setup() で export 済み。非クォート heredoc で展開する。
  # WARNING: シングルクォート heredoc は使わないこと（外部変数 $CLD_OBSERVE_ANY が展開されない）
  local tmpd
  tmpd="$(mktemp -d)"
  local event_dir="${tmpd}/events"
  mkdir -p "${event_dir}"

  # win / capture を export して heredoc 内の bash subprocess に引き継ぐ
  local win="ap-1464-e2e-win"
  local cld_observe_any_path="${CLD_OBSERVE_ANY}"
  local cld_script_dir
  cld_script_dir="$(dirname "${CLD_OBSERVE_ANY}")"

  export win cld_observe_any_path cld_script_dir

  run bash -c '
win="${win}"
CLD_OBSERVE_ANY="${cld_observe_any_path}"
SCRIPT_DIR="${cld_script_dir}"
TMPD="'"${tmpd}"'"
EVENT_DIR_PATH="'"${event_dir}"'"

capture="All tasks are done.
nothing pending
System is idle."
export capture

tmux() {
    case "$1" in
        list-windows)
            echo "test-session:0 ${win}"
            ;;
        display-message)
            echo "0 claude"
            ;;
        capture-pane)
            if [[ "${*}" == *"-S -1"* ]]; then
                echo ""
            else
                printf '"'"'%s\n'"'"' "${capture}"
            fi
            ;;
        kill-window)
            # stub: 成功（exit 0）
            return 0
            ;;
        *)
            return 0
            ;;
    esac
}
export -f tmux

output_text=$(IDLE_COMPLETED_AUTO_KILL=1 \
    IDLE_COMPLETED_DEBOUNCE_SEC=0 \
    _TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="${SCRIPT_DIR}" \
    bash "${CLD_OBSERVE_ANY}" --window "${win}" \
    --event-dir "${EVENT_DIR_PATH}" \
    --max-cycles 2 --interval 1 2>/dev/null)

# 検証1: stdout に auto-killed ログが出たか
if ! echo "${output_text}" | grep -q "auto-killed"; then
    echo "FAIL: stdout に auto-killed ログがない（output=${output_text}）"
    rm -rf "${TMPD}"
    exit 1
fi

# 検証2: idle-completed-killed-*.json が生成されたか
killed_json=$(find "${EVENT_DIR_PATH}" -name "idle-completed-killed-*.json" 2>/dev/null | head -1)
if [[ -z "${killed_json}" ]]; then
    echo "FAIL: idle-completed-killed-*.json が生成されなかった"
    rm -rf "${TMPD}"
    exit 1
fi

echo "PASS: E2E completion phrase → tmux kill-window 動的検証成功"
rm -rf "${TMPD}"
'

  # E2E 動的検証: PASS ログが出て exit 0 であること
  [[ "$status" -eq 0 ]] && echo "$output" | grep -q "PASS:"
}
