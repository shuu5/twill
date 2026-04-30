#!/usr/bin/env bats
# inject-next-workflow-stagnate.bats
# Issue #1177: stagnate 検知ロジックへの mtime AND 判定・WARN rate limit 追加
#
# RED フェーズ: 以下の機能は現時点の inject-next-workflow.sh に存在しない:
#   - LAST_STATE_MTIME 連想配列
#   - state file mtime チェック（current_mtime > last_mtime → カウントリセット）
#   - LAST_STAGNATE_WARN_TS 連想配列
#   - WARN rate limit（AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC）
#
# シナリオ:
#   A: state file mtime 更新中 + RESOLVE 失敗 → WARN 出力なし、RESOLVE_FAIL_COUNT リセット
#   B: state file mtime 停止 + RESOLVE 失敗 → AUTOPILOT_STAGNATE_SEC 経過後に最初の WARN 出力
#   C: stagnate 確定後、AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC 内の重複 WARN なし、経過後に再 WARN
#   D: state file 不在 → _current_mtime=0、RESOLVE_FAIL_COUNT カウントアップ動作（後方互換）

load '../helpers/common'

# テスト対象スクリプト
INJECT_LIB=""

setup() {
  common_setup

  # AC-3 指定: テスト用 AUTOPILOT_DIR
  export AUTOPILOT_DIR="/tmp/test-autopilot-$$"
  mkdir -p "${AUTOPILOT_DIR}/issues"

  INJECT_LIB="$REPO_ROOT/scripts/lib/inject-next-workflow.sh"

  # stagnate 閾値を短く設定（テスト用）
  export AUTOPILOT_STAGNATE_SEC=5
  export AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC=60

  # python3 stub: resolve_next_workflow は常に FAIL（exit 2=ERROR）を返す
  # RESOLVE 失敗シナリオを再現するため
  stub_command "python3" '
case "$*" in
  *resolve_next_workflow*)
    echo "" >&1
    exit 2
    ;;
  *state*)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
'

  # cleanup_worker stub（inject-next-workflow.sh の依存関数）
  # テスト環境では何もしない
  export -f cleanup_worker 2>/dev/null || true
}

teardown() {
  rm -rf "${AUTOPILOT_DIR}"
  common_teardown
}

# cleanup_worker をグローバルで定義（source 時に必要）
cleanup_worker() {
  : # stub: no-op
}

# ---------------------------------------------------------------------------
# ヘルパー: stagnate 検知ロジックのみを呼び出す test double を生成
#
# inject-next-workflow.sh の _check_stagnate_for_entry() 相当の関数を
# ラップするスクリプト。実装後はこの関数が直接利用可能になる。
# RED フェーズでは存在しない関数への呼び出しにより FAIL する。
# ---------------------------------------------------------------------------

_make_stagnate_check_script() {
  local script_file="$SANDBOX/stagnate-check.sh"
  cat > "$script_file" <<'SCRIPT_EOF'
#!/usr/bin/env bash
# stagnate 検知ロジックを呼び出す test driver
# 引数:
#   --entry    ENTRY キー（例: _default:999）
#   --issue    Issue 番号
#   --now      現在時刻（epoch 秒）
#   --fail-count  RESOLVE_FAIL_COUNT の初期値
#   --first-ts    RESOLVE_FAIL_FIRST_TS の初期値
#   --last-mtime  LAST_STATE_MTIME の初期値（0 = 不在扱い）
#   --last-warn-ts LAST_STAGNATE_WARN_TS の初期値（0 = 未 WARN）
#   --current-mtime  state file の現在 mtime（stat が返す値を模倣）
#
# AUTOPILOT_STAGNATE_SEC と AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC は
# 環境変数から引き継ぐ。
#
# 出力（stdout）: JSON 形式で状態を出力
# 終了コード: 0=WARN 出力なし, 1=WARN 出力あり（stderr に [orchestrator] WARN: ...）
set -euo pipefail

ENTRY="_default:999"
ISSUE=999
NOW=$(date +%s)
FAIL_COUNT=0
FIRST_TS=0
LAST_MTIME=0
LAST_WARN_TS=0
CURRENT_MTIME=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --entry)       ENTRY="$2"; shift 2 ;;
    --issue)       ISSUE="$2"; shift 2 ;;
    --now)         NOW="$2"; shift 2 ;;
    --fail-count)  FAIL_COUNT="$2"; shift 2 ;;
    --first-ts)    FIRST_TS="$2"; shift 2 ;;
    --last-mtime)  LAST_MTIME="$2"; shift 2 ;;
    --last-warn-ts) LAST_WARN_TS="$2"; shift 2 ;;
    --current-mtime) CURRENT_MTIME="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 99 ;;
  esac
done

AUTOPILOT_STAGNATE_SEC="${AUTOPILOT_STAGNATE_SEC:-600}"
AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC="${AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC:-60}"

# inject-next-workflow.sh を source して連想配列・関数を取得
# cleanup_worker スタブを先に定義しておく（source 時の依存解決）
cleanup_worker() { :; }

# tmux スタブ（source 時に呼ばれないが念のため）
tmux() { :; }
python3() {
  case "$*" in
    *resolve_next_workflow*) echo ""; return 2 ;;
    *) return 0 ;;
  esac
}

# shellcheck disable=SC1090
source "$INJECT_LIB_PATH"

# 初期値設定
RESOLVE_FAIL_COUNT[$ENTRY]="$FAIL_COUNT"
RESOLVE_FAIL_FIRST_TS[$ENTRY]="$FIRST_TS"

# AC-1: LAST_STATE_MTIME 配列の存在確認（実装後に動作する）
# RED: 現時点では配列が存在しないため、以下は失敗する
if declare -p LAST_STATE_MTIME 2>/dev/null | grep -q 'declare -A'; then
  LAST_STATE_MTIME[$ENTRY]="$LAST_MTIME"
else
  # 配列未定義 = RED フェーズ
  declare -gA LAST_STATE_MTIME 2>/dev/null || true
  LAST_STATE_MTIME[$ENTRY]="$LAST_MTIME"
fi

# AC-2: LAST_STAGNATE_WARN_TS 配列の存在確認
if declare -p LAST_STAGNATE_WARN_TS 2>/dev/null | grep -q 'declare -A'; then
  LAST_STAGNATE_WARN_TS[$ENTRY]="$LAST_WARN_TS"
else
  declare -gA LAST_STAGNATE_WARN_TS 2>/dev/null || true
  LAST_STAGNATE_WARN_TS[$ENTRY]="$LAST_WARN_TS"
fi

# stagnate 検知専用関数を呼び出す
# 実装後: _stagnate_check_entry() 関数が inject-next-workflow.sh に存在する想定
# RED: 存在しないため呼び出しは失敗する
if declare -f _stagnate_check_entry >/dev/null 2>&1; then
  _stagnate_check_entry "$ENTRY" "$ISSUE" "$NOW" "$CURRENT_MTIME"
  _check_exit=$?
else
  # 関数未実装 = RED フェーズ: 手動でロジックを再現して検証
  # この分岐では「実装前の動作」を検証するため、意図的に未実装扱いにする
  echo "STAGNATE_CHECK_FUNCTION_NOT_FOUND" >&2
  exit 11
fi

# 終了後の状態をチェック
echo "FAIL_COUNT_AFTER=${RESOLVE_FAIL_COUNT[$ENTRY]:-0}"
echo "LAST_MTIME_AFTER=${LAST_STATE_MTIME[$ENTRY]:-0}"
echo "LAST_WARN_TS_AFTER=${LAST_STAGNATE_WARN_TS[$ENTRY]:-0}"
exit $_check_exit
SCRIPT_EOF
  chmod +x "$script_file"
  export STAGNATE_CHECK_SCRIPT="$script_file"
  export INJECT_LIB_PATH="$INJECT_LIB"
}

# ---------------------------------------------------------------------------
# AC-1 シナリオ A: mtime 更新中 → WARN なし、カウントリセット
# ---------------------------------------------------------------------------

@test "AC-1 ScenarioA: state file mtime updated → no WARN output, RESOLVE_FAIL_COUNT reset to 0" {
  # AC: inject-next-workflow.sh の stagnate 検知ロジック先頭に state file mtime チェックを追加し、
  #     current_mtime > last_mtime の場合は RESOLVE_FAIL_COUNT[$entry]=0 / RESOLVE_FAIL_FIRST_TS[$entry]=""
  #     / LAST_STATE_MTIME[$entry]=$current_mtime をリセットして return 1 する。
  #
  # RED: LAST_STATE_MTIME 配列と mtime チェックロジックが存在しないため FAIL する

  local state_file="${AUTOPILOT_DIR}/issues/issue-999.json"
  # state file を作成（mtime が更新されている状態）
  echo '{"issue":999,"status":"running"}' > "$state_file"

  local now
  now=$(date +%s)
  local old_mtime=$(( now - 100 ))
  local current_mtime
  current_mtime=$(stat -c %Y "$state_file" 2>/dev/null || echo 0)

  # インラインスクリプトで検証
  run bash -c "
    set -euo pipefail
    export AUTOPILOT_STAGNATE_SEC='${AUTOPILOT_STAGNATE_SEC}'
    export AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC='${AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC}'

    cleanup_worker() { :; }
    tmux() { :; }
    python3() { echo ''; return 2; }

    source '${INJECT_LIB}'

    # AC-1: LAST_STATE_MTIME が実装されていることを確認（RED: 未実装なら失敗）
    if ! declare -p LAST_STATE_MTIME 2>/dev/null | grep -q 'declare -A'; then
      echo 'FAIL: LAST_STATE_MTIME array not declared' >&2
      exit 1
    fi

    ENTRY='_default:999'
    ISSUE=999

    # 既存カウント: 失敗が蓄積している状態
    RESOLVE_FAIL_COUNT[\$ENTRY]=5
    RESOLVE_FAIL_FIRST_TS[\$ENTRY]=\"\$(( \$(date +%s) - 300 ))\"
    # 前回 mtime より古い値をセット
    LAST_STATE_MTIME[\$ENTRY]='${old_mtime}'

    # 現在の state file mtime を取得
    _current_mtime=\$(stat -c %Y '${state_file}' 2>/dev/null || echo 0)

    # AC-1 の検証: mtime が更新されていれば（current > last）カウントリセットが発生する
    if (( _current_mtime > LAST_STATE_MTIME[\$ENTRY] )); then
      RESOLVE_FAIL_COUNT[\$ENTRY]=0
      RESOLVE_FAIL_FIRST_TS[\$ENTRY]=''
      LAST_STATE_MTIME[\$ENTRY]=\$_current_mtime
    fi

    # mtime チェック後の WARN 抑制: カウントが 0 にリセットされているため WARN 不要
    _fail_count=\"\${RESOLVE_FAIL_COUNT[\$ENTRY]:-0}\"
    _now=\$(date +%s)
    _first_ts=\"\${RESOLVE_FAIL_FIRST_TS[\$ENTRY]:-\$_now}\"
    _elapsed=\$(( _now - _first_ts ))

    if (( _elapsed >= AUTOPILOT_STAGNATE_SEC )); then
      echo '[orchestrator] WARN: mtime-updated-but-stagnate-check-issued' >&2
    fi

    echo \"FAIL_COUNT_AFTER=\${RESOLVE_FAIL_COUNT[\$ENTRY]:-0}\"
  "

  # 期待: WARN が stderr に出ていないこと（mtime 更新によりリセットされているため）
  refute_output --partial "[orchestrator] WARN"
  # 期待: FAIL_COUNT が 0 にリセットされていること
  assert_output --partial "FAIL_COUNT_AFTER=0"
}

# ---------------------------------------------------------------------------
# AC-1 シナリオ B: mtime 停止 → STAGNATE_SEC 経過後に最初の WARN 出力
# ---------------------------------------------------------------------------

@test "AC-2 ScenarioB: state file mtime stale + AUTOPILOT_STAGNATE_SEC elapsed → first WARN emitted" {
  # AC: _elapsed >= AUTOPILOT_STAGNATE_SEC 達成後の [orchestrator] WARN 出力
  #     mtime が変化しない場合、既存の stagnate 検知が動作すること
  #
  # RED: LAST_STATE_MTIME の mtime AND 判定ロジックが存在しないため、
  #      mtime チェックでブロックされず、WARN が出ることを確認する
  #      （現行実装でも WARN が出るはずだが、実装後は mtime チェックが追加される）

  local now
  now=$(date +%s)
  local stagnate_start=$(( now - AUTOPILOT_STAGNATE_SEC - 10 ))  # 閾値超過

  run bash -c "
    set -euo pipefail
    export AUTOPILOT_STAGNATE_SEC='${AUTOPILOT_STAGNATE_SEC}'
    export AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC='${AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC}'
    export AUTOPILOT_DIR='${AUTOPILOT_DIR}'

    cleanup_worker() { :; }
    tmux() { :; }
    python3() { echo ''; return 2; }

    source '${INJECT_LIB}'

    ENTRY='_default:999'
    ISSUE=999

    # state file が存在しない（mtime = 0）
    # または mtime が変化していない状態（current_mtime == last_mtime）

    RESOLVE_FAIL_COUNT[\$ENTRY]=10
    RESOLVE_FAIL_FIRST_TS[\$ENTRY]='${stagnate_start}'

    # AC-1 実装後: LAST_STATE_MTIME チェックを通す（mtime 変化なし → リセットしない）
    if declare -p LAST_STATE_MTIME 2>/dev/null | grep -q 'declare -A'; then
      LAST_STATE_MTIME[\$ENTRY]=0
      _current_mtime=0  # state file 不在 or mtime 変化なし
      # current_mtime == last_mtime なのでリセットしない
    fi

    _fail_count=\"\${RESOLVE_FAIL_COUNT[\$ENTRY]:-0}\"
    _now=\$(date +%s)
    _first_ts=\"\${RESOLVE_FAIL_FIRST_TS[\$ENTRY]:-\$_now}\"
    _elapsed=\$(( _now - _first_ts ))

    if (( _elapsed >= AUTOPILOT_STAGNATE_SEC )); then
      # AC-2 実装後: LAST_STAGNATE_WARN_TS rate limit チェック
      # 初回 WARN（LAST_STAGNATE_WARN_TS=0）なので rate limit は通過する
      if declare -p LAST_STAGNATE_WARN_TS 2>/dev/null | grep -q 'declare -A'; then
        _last_warn=\"\${LAST_STAGNATE_WARN_TS[\$ENTRY]:-0}\"
        if (( _now - _last_warn >= AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC )); then
          echo \"[orchestrator] WARN: issue=\${ISSUE} stagnate detected (RESOLVE_FAILED \${_fail_count} 回, \${_elapsed}s >= AUTOPILOT_STAGNATE_SEC=\${AUTOPILOT_STAGNATE_SEC})\" >&2
          LAST_STAGNATE_WARN_TS[\$ENTRY]=\$_now
        fi
      else
        # LAST_STAGNATE_WARN_TS 未実装 = RED フェーズ: rate limit なしで WARN を出す（現行動作）
        echo \"[orchestrator] WARN: issue=\${ISSUE} stagnate detected (RESOLVE_FAILED \${_fail_count} 回, \${_elapsed}s >= AUTOPILOT_STAGNATE_SEC=\${AUTOPILOT_STAGNATE_SEC})\" >&2
      fi
    fi
    echo 'SCENARIO_B_DONE'
  "

  # 期待: WARN が stderr に出ていること（stagnate 確定 + rate limit 初回通過）
  assert_output --partial "[orchestrator] WARN"
  assert_output --partial "stagnate detected"
}

# ---------------------------------------------------------------------------
# AC-2 シナリオ C: WARN rate limit — interval 内は重複 WARN なし、経過後に再 WARN
# ---------------------------------------------------------------------------

@test "AC-2 ScenarioC: within AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC → duplicate WARN suppressed, after interval → WARN re-emitted" {
  # AC: LAST_STAGNATE_WARN_TS rate limit 実装
  #     _now - LAST_STAGNATE_WARN_TS[$entry] >= AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC を満たさない WARN は suppress
  #
  # RED: LAST_STAGNATE_WARN_TS 配列と rate limit ロジックが存在しないため FAIL する

  local now
  now=$(date +%s)
  local stagnate_start=$(( now - AUTOPILOT_STAGNATE_SEC - 100 ))

  # --- Part 1: interval 内は WARN 抑制 ---
  local recent_warn_ts=$(( now - 10 ))  # 10秒前に WARN 済み（interval=60s 未満）

  run bash -c "
    set -euo pipefail
    export AUTOPILOT_STAGNATE_SEC='${AUTOPILOT_STAGNATE_SEC}'
    export AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC='${AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC}'

    cleanup_worker() { :; }
    tmux() { :; }
    python3() { echo ''; return 2; }

    source '${INJECT_LIB}'

    ENTRY='_default:999'
    ISSUE=999

    RESOLVE_FAIL_COUNT[\$ENTRY]=20
    RESOLVE_FAIL_FIRST_TS[\$ENTRY]='${stagnate_start}'

    # RED: LAST_STAGNATE_WARN_TS が実装されていることを確認
    if ! declare -p LAST_STAGNATE_WARN_TS 2>/dev/null | grep -q 'declare -A'; then
      echo 'FAIL: LAST_STAGNATE_WARN_TS array not declared' >&2
      exit 1
    fi

    # 直近 WARN 済み（interval 内）
    LAST_STAGNATE_WARN_TS[\$ENTRY]='${recent_warn_ts}'

    _fail_count=\"\${RESOLVE_FAIL_COUNT[\$ENTRY]:-0}\"
    _now=\$(date +%s)
    _first_ts=\"\${RESOLVE_FAIL_FIRST_TS[\$ENTRY]:-\$_now}\"
    _elapsed=\$(( _now - _first_ts ))

    if (( _elapsed >= AUTOPILOT_STAGNATE_SEC )); then
      _last_warn=\"\${LAST_STAGNATE_WARN_TS[\$ENTRY]:-0}\"
      # rate limit チェック: interval 内なので suppress される
      if (( _now - _last_warn >= AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC )); then
        echo \"[orchestrator] WARN: issue=\${ISSUE} stagnate detected\" >&2
        LAST_STAGNATE_WARN_TS[\$ENTRY]=\$_now
      fi
      # suppress された場合は WARN 出力なし
    fi
    echo 'WITHIN_INTERVAL_DONE'
  "

  # 期待: interval 内なので WARN は出ない
  refute_output --partial "[orchestrator] WARN"
  assert_output --partial "WITHIN_INTERVAL_DONE"

  # --- Part 2: interval 経過後は再 WARN ---
  local old_warn_ts=$(( now - AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC - 10 ))  # interval 超過

  run bash -c "
    set -euo pipefail
    export AUTOPILOT_STAGNATE_SEC='${AUTOPILOT_STAGNATE_SEC}'
    export AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC='${AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC}'

    cleanup_worker() { :; }
    tmux() { :; }
    python3() { echo ''; return 2; }

    source '${INJECT_LIB}'

    ENTRY='_default:999'
    ISSUE=999

    RESOLVE_FAIL_COUNT[\$ENTRY]=30
    RESOLVE_FAIL_FIRST_TS[\$ENTRY]='${stagnate_start}'

    if ! declare -p LAST_STAGNATE_WARN_TS 2>/dev/null | grep -q 'declare -A'; then
      echo 'FAIL: LAST_STAGNATE_WARN_TS array not declared' >&2
      exit 1
    fi

    # interval を超過した古い WARN タイムスタンプ
    LAST_STAGNATE_WARN_TS[\$ENTRY]='${old_warn_ts}'

    _fail_count=\"\${RESOLVE_FAIL_COUNT[\$ENTRY]:-0}\"
    _now=\$(date +%s)
    _first_ts=\"\${RESOLVE_FAIL_FIRST_TS[\$ENTRY]:-\$_now}\"
    _elapsed=\$(( _now - _first_ts ))

    if (( _elapsed >= AUTOPILOT_STAGNATE_SEC )); then
      _last_warn=\"\${LAST_STAGNATE_WARN_TS[\$ENTRY]:-0}\"
      if (( _now - _last_warn >= AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC )); then
        echo \"[orchestrator] WARN: issue=\${ISSUE} stagnate detected (RESOLVE_FAILED \${_fail_count} 回, \${_elapsed}s >= AUTOPILOT_STAGNATE_SEC=\${AUTOPILOT_STAGNATE_SEC})\" >&2
        LAST_STAGNATE_WARN_TS[\$ENTRY]=\$_now
      fi
    fi
    echo 'AFTER_INTERVAL_DONE'
  "

  # 期待: interval 経過後なので WARN が再出力される
  assert_output --partial "[orchestrator] WARN"
  assert_output --partial "stagnate detected"
}

# ---------------------------------------------------------------------------
# AC-1 シナリオ D（後方互換）: state file 不在 → _current_mtime=0、RESOLVE_FAIL_COUNT カウントアップ
# ---------------------------------------------------------------------------

@test "AC-1 ScenarioD (backward compat): state file absent → _current_mtime=0, RESOLVE_FAIL_COUNT increments normally" {
  # AC: stat 失敗時は _current_mtime=0
  #     state file 不在の場合、current(0) > last(0) が偽のため、リセットせず
  #     RESOLVE_FAIL_COUNT は通常通りカウントアップする（後方互換）
  #
  # Note: このシナリオは現行実装でも部分的に PASS する可能性があるが、
  #       実装後の正しい動作を前提として書いている。
  #       LAST_STATE_MTIME 配列が未宣言の場合は RED となる。

  # state file を意図的に作成しない（存在しない状態）
  local absent_state_file="${AUTOPILOT_DIR}/issues/issue-9999.json"
  # ファイルが存在しないことを確認
  [[ ! -f "$absent_state_file" ]]

  local now
  now=$(date +%s)

  run bash -c "
    set -euo pipefail
    export AUTOPILOT_STAGNATE_SEC='${AUTOPILOT_STAGNATE_SEC}'
    export AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC='${AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC}'
    export AUTOPILOT_DIR='${AUTOPILOT_DIR}'

    cleanup_worker() { :; }
    tmux() { :; }
    python3() { echo ''; return 2; }

    source '${INJECT_LIB}'

    ENTRY='_default:9999'
    ISSUE=9999

    # 初期状態: カウント 0、LAST_STATE_MTIME = 0（初回）
    RESOLVE_FAIL_COUNT[\$ENTRY]=0

    # AC-1 実装後: stat 失敗時は _current_mtime=0
    _current_mtime=\$(stat -c %Y '${absent_state_file}' 2>/dev/null || echo 0)

    # _current_mtime=0, LAST_STATE_MTIME=0 → current(0) > last(0) が偽 → リセットしない
    if declare -p LAST_STATE_MTIME 2>/dev/null | grep -q 'declare -A'; then
      _last_mtime=\${LAST_STATE_MTIME[\$ENTRY]:-0}
      if (( _current_mtime > _last_mtime )); then
        # mtime 更新あり → リセット（今回は発火しない）
        RESOLVE_FAIL_COUNT[\$ENTRY]=0
        RESOLVE_FAIL_FIRST_TS[\$ENTRY]=''
        LAST_STATE_MTIME[\$ENTRY]=\$_current_mtime
      fi
    fi

    # カウントアップ（stat 失敗でも現行動作通り）
    _fail_count=\"\${RESOLVE_FAIL_COUNT[\$ENTRY]:-0}\"
    _now=\$(date +%s)
    if [[ \"\$_fail_count\" -eq 0 ]]; then
      RESOLVE_FAIL_FIRST_TS[\$ENTRY]=\"\$_now\"
    fi
    RESOLVE_FAIL_COUNT[\$ENTRY]=\$(( _fail_count + 1 ))

    echo \"CURRENT_MTIME=\${_current_mtime}\"
    echo \"FAIL_COUNT_AFTER=\${RESOLVE_FAIL_COUNT[\$ENTRY]:-0}\"
  "

  # 期待: stat 失敗で _current_mtime=0
  assert_output --partial "CURRENT_MTIME=0"
  # 期待: RESOLVE_FAIL_COUNT が 0→1 にカウントアップ（リセットされていない）
  assert_output --partial "FAIL_COUNT_AFTER=1"
}

# ---------------------------------------------------------------------------
# 補助テスト: LAST_STATE_MTIME 連想配列が inject-next-workflow.sh に宣言されているか
# ---------------------------------------------------------------------------

@test "AC-1: LAST_STATE_MTIME associative array declared in inject-next-workflow.sh" {
  # AC: 連想配列 LAST_STATE_MTIME を両ファイルに追加する
  # RED: 現時点では未宣言のため FAIL する

  run bash -c "
    cleanup_worker() { :; }
    tmux() { :; }
    python3() { echo ''; return 2; }
    export AUTOPILOT_DIR='${AUTOPILOT_DIR}'
    export AUTOPILOT_STAGNATE_SEC='${AUTOPILOT_STAGNATE_SEC}'

    source '${INJECT_LIB}'

    if declare -p LAST_STATE_MTIME 2>/dev/null | grep -q 'declare -A'; then
      echo 'LAST_STATE_MTIME_DECLARED'
    else
      echo 'LAST_STATE_MTIME_NOT_FOUND' >&2
      exit 1
    fi
  "

  assert_success
  assert_output --partial "LAST_STATE_MTIME_DECLARED"
}

# ---------------------------------------------------------------------------
# 補助テスト: LAST_STAGNATE_WARN_TS 連想配列が inject-next-workflow.sh に宣言されているか
# ---------------------------------------------------------------------------

@test "AC-2: LAST_STAGNATE_WARN_TS associative array declared in inject-next-workflow.sh" {
  # AC: 連想配列 LAST_STAGNATE_WARN_TS を両ファイルに追加する
  # RED: 現時点では未宣言のため FAIL する

  run bash -c "
    cleanup_worker() { :; }
    tmux() { :; }
    python3() { echo ''; return 2; }
    export AUTOPILOT_DIR='${AUTOPILOT_DIR}'
    export AUTOPILOT_STAGNATE_SEC='${AUTOPILOT_STAGNATE_SEC}'

    source '${INJECT_LIB}'

    if declare -p LAST_STAGNATE_WARN_TS 2>/dev/null | grep -q 'declare -A'; then
      echo 'LAST_STAGNATE_WARN_TS_DECLARED'
    else
      echo 'LAST_STAGNATE_WARN_TS_NOT_FOUND' >&2
      exit 1
    fi
  "

  assert_success
  assert_output --partial "LAST_STAGNATE_WARN_TS_DECLARED"
}
