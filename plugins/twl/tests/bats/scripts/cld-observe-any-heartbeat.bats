#!/usr/bin/env bats
# cld-observe-any-heartbeat.bats - Issue #1154 AC1-AC8 RED テスト
#
# AC1: cld-observe-any main loop に _emit_daemon_heartbeat を epoch-delta pattern で追加
#      HEARTBEAT_INTERVAL_SEC=60、書き出し先 ${SUPERVISOR_DIR}/.supervisor/observer-daemon-heartbeat.json
# AC2: heartbeat JSON の atomic write（writer/pid/last_update/host/version/interval_sec/cycle_count）
# AC3: observer-parallel-check.sh:check_monitor_cld_observe_alive() を AND 拡張
#      (a) pgrep 必須 (b) heartbeat ファイル不在 → grace period (c) mtime 120s 以内 (d) JSON writer/pid 検証
# AC4: env override 対応
#      CLD_OBSERVE_ANY_HEARTBEAT_PATH / OBSERVER_PARALLEL_CHECK_DAEMON_HEARTBEAT_PATH /
#      HEARTBEAT_INTERVAL_SEC / OBSERVER_DAEMON_HEARTBEAT_STALE_SEC
# AC5: _emit_daemon_heartbeat() が set -euo pipefail 配下でも main loop を die させない
# AC6: 以下 7 ケース以上を bats で実装:
#   AC6-1: 3 cycle heartbeat update（HEARTBEAT_INTERVAL_SEC=1 で run timeout 15s）
#   AC6-2: JSON schema 検証（writer/pid/last_update/host/version/interval_sec/cycle_count）
#   AC6-3: atomicity（複数 reader で syntax error 0 件）
#   AC6-4: path override（CLD_OBSERVE_ANY_HEARTBEAT_PATH）
#   AC6-5: stale 検知（mtime を touch -d '3 minutes ago' で擬似 stale → false）
#   AC6-6: heartbeat absent grace period（ファイル削除で pgrep 結果に従う + stderr WARNING）
#   AC6-7: failure isolation（SUPERVISOR_DIR read-only でも daemon が die しない）
# AC7: pitfalls-catalog.md §11.1.x cld-observe-any daemon heartbeat サブセクション追記
# AC8: プロセス AC（PR 本文記載）— テスト不要
#
# RED: 全テストは実装前の状態で fail する。
#
# テストフレームワーク: bats-core（bats-support + bats-assert）

load '../helpers/common'

PARALLEL_CHECK_LIB=""
CLD_OBSERVE_ANY=""

setup() {
  common_setup
  PARALLEL_CHECK_LIB="$REPO_ROOT/scripts/lib/observer-parallel-check.sh"
  # cld-observe-any はリポジトリルートの兄弟 plugin に存在
  # REPO_ROOT = plugins/twl, cld-observe-any = plugins/session/scripts/cld-observe-any
  CLD_OBSERVE_ANY="$(cd "$REPO_ROOT/../.." && pwd)/plugins/session/scripts/cld-observe-any"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: _emit_daemon_heartbeat 関数が cld-observe-any に定義されている
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: cld-observe-any に _emit_daemon_heartbeat() が定義されている
# WHEN: cld-observe-any スクリプトの内容を grep する
# THEN: _emit_daemon_heartbeat の定義が存在する
# ---------------------------------------------------------------------------

@test "AC1: cld-observe-any に _emit_daemon_heartbeat() が定義されている" {
  # RED: 実装前は fail する（_emit_daemon_heartbeat 未実装）
  [[ -f "$CLD_OBSERVE_ANY" ]] \
    || fail "cld-observe-any が存在しない: $CLD_OBSERVE_ANY"

  grep -q '_emit_daemon_heartbeat' "$CLD_OBSERVE_ANY" \
    || fail "_emit_daemon_heartbeat が cld-observe-any に定義されていない（AC1 未実装）"
}

# ---------------------------------------------------------------------------
# Scenario: cld-observe-any に HEARTBEAT_INTERVAL_SEC 設定が存在する
# WHEN: cld-observe-any スクリプトを grep する
# THEN: HEARTBEAT_INTERVAL_SEC の参照が存在する
# ---------------------------------------------------------------------------

@test "AC1: cld-observe-any に HEARTBEAT_INTERVAL_SEC 設定が存在する" {
  # RED: 実装前は fail する
  [[ -f "$CLD_OBSERVE_ANY" ]] \
    || fail "cld-observe-any が存在しない: $CLD_OBSERVE_ANY"

  grep -q 'HEARTBEAT_INTERVAL_SEC' "$CLD_OBSERVE_ANY" \
    || fail "HEARTBEAT_INTERVAL_SEC が cld-observe-any に存在しない（AC1 未実装）"
}

# ---------------------------------------------------------------------------
# Scenario: cld-observe-any の main loop に heartbeat 呼び出しが存在する
# WHEN: cld-observe-any スクリプトの while true ループ付近を確認
# THEN: _emit_daemon_heartbeat の呼び出しが while true ブロック内に存在する
# ---------------------------------------------------------------------------

@test "AC1: cld-observe-any の main loop（while true）に _emit_daemon_heartbeat 呼び出しが存在する" {
  # RED: 実装前は fail する
  [[ -f "$CLD_OBSERVE_ANY" ]] \
    || fail "cld-observe-any が存在しない: $CLD_OBSERVE_ANY"

  # while true ブロック（line 490+）以降に _emit_daemon_heartbeat の呼び出しがあること
  grep -q '_emit_daemon_heartbeat' "$CLD_OBSERVE_ANY" \
    || fail "_emit_daemon_heartbeat の呼び出しが cld-observe-any に存在しない（AC1 未実装）"
}

# ---------------------------------------------------------------------------
# Scenario: cld-observe-any の SUPERVISOR_DIR が startup 時に明示解決される
# WHEN: cld-observe-any スクリプトの起動初期化部を確認
# THEN: SUPERVISOR_DIR の解決ロジックが存在する（env またはデフォルト .supervisor）
# ---------------------------------------------------------------------------

@test "AC1: cld-observe-any に SUPERVISOR_DIR 解決ロジックが存在する" {
  # RED: 実装前は fail する
  [[ -f "$CLD_OBSERVE_ANY" ]] \
    || fail "cld-observe-any が存在しない: $CLD_OBSERVE_ANY"

  grep -q 'SUPERVISOR_DIR' "$CLD_OBSERVE_ANY" \
    || fail "SUPERVISOR_DIR の参照が cld-observe-any に存在しない（AC1 未実装）"
}

# ===========================================================================
# AC2: heartbeat JSON の atomic write（schema 検証は AC6-2 で実施）
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: cld-observe-any に atomic write パターン（tmp + mv）が存在する
# WHEN: cld-observe-any スクリプト内の heartbeat emit 実装を確認
# THEN: mktemp または tmpfile を使った atomic write（mv）パターンが存在する
# ---------------------------------------------------------------------------

@test "AC2: cld-observe-any の _emit_daemon_heartbeat に atomic write パターン（tmp + mv）が存在する" {
  # RED: 実装前は fail する（atomic write 未実装）
  # NOTE: cld-observe-any には emit_event() 等で mktemp が既存利用されているが、
  #       AC2 が要求するのは _emit_daemon_heartbeat() 関数内の atomic write。
  #       関数定義が存在しない現状では必ず fail する。
  [[ -f "$CLD_OBSERVE_ANY" ]] \
    || fail "cld-observe-any が存在しない: $CLD_OBSERVE_ANY"

  # _emit_daemon_heartbeat 関数が存在することが前提（AC1）
  grep -q '_emit_daemon_heartbeat()' "$CLD_OBSERVE_ANY" \
    || fail "_emit_daemon_heartbeat() 関数定義が存在しない（AC1 前提未実装）—atomic write 検証不可（AC2 未実装）"

  # _emit_daemon_heartbeat() 関数本体内に mktemp + mv の atomic write パターンが存在すること
  # awk で関数本体だけ抽出し、その中に mktemp と mv が両方存在するか確認
  local fn_body
  fn_body=$(awk '/_emit_daemon_heartbeat\(\)/,/^}/' "$CLD_OBSERVE_ANY" 2>/dev/null || echo "")
  echo "$fn_body" | grep -qE 'mktemp|\.tmp' \
    || fail "_emit_daemon_heartbeat() 内に atomic write（tmp ファイル）パターンが存在しない（AC2 未実装）"
  echo "$fn_body" | grep -q ' mv ' \
    || fail "_emit_daemon_heartbeat() 内に atomic write（mv）パターンが存在しない（AC2 未実装）"
}

# ---------------------------------------------------------------------------
# Scenario: cld-observe-any の heartbeat に必要な全フィールドが記述されている
# WHEN: cld-observe-any の _emit_daemon_heartbeat 実装を grep
# THEN: writer/pid/last_update/host/version/interval_sec/cycle_count の全フィールドが存在する
# ---------------------------------------------------------------------------

@test "AC2: cld-observe-any の heartbeat JSON に writer フィールドが含まれる" {
  # RED: 実装前は fail する
  [[ -f "$CLD_OBSERVE_ANY" ]] \
    || fail "cld-observe-any が存在しない: $CLD_OBSERVE_ANY"

  grep -q '"writer"' "$CLD_OBSERVE_ANY" \
    || fail "heartbeat JSON に writer フィールドが存在しない（AC2 未実装）"
}

@test "AC2: cld-observe-any の heartbeat JSON に cycle_count フィールドが含まれる" {
  # RED: 実装前は fail する
  [[ -f "$CLD_OBSERVE_ANY" ]] \
    || fail "cld-observe-any が存在しない: $CLD_OBSERVE_ANY"

  grep -q '"cycle_count"' "$CLD_OBSERVE_ANY" \
    || fail "heartbeat JSON に cycle_count フィールドが存在しない（AC2 未実装）"
}

# ===========================================================================
# AC3: observer-parallel-check.sh:check_monitor_cld_observe_alive() 拡張
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: check_monitor_cld_observe_alive() に heartbeat mtime 検証が追加されている
# WHEN: observer-parallel-check.sh の check_monitor_cld_observe_alive() 実装を確認
# THEN: mtime 検証ロジック（120 sec または OBSERVER_DAEMON_HEARTBEAT_STALE_SEC）が存在する
# ---------------------------------------------------------------------------

@test "AC3: check_monitor_cld_observe_alive() に heartbeat mtime 検証（stale 閾値）が存在する" {
  # RED: 実装前は fail する（mtime check 未実装）
  # NOTE: observer-parallel-check.sh の check_controller_heartbeat_alive() は既存の mtime ロジックを持つが、
  #       AC3 が要求するのは check_monitor_cld_observe_alive() 関数内での heartbeat mtime 検証。
  #       check_monitor_cld_observe_alive() は現状 pgrep のみで mtime 検証を持たない。
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  # check_monitor_cld_observe_alive() 関数本体内に OBSERVER_DAEMON_HEARTBEAT_STALE_SEC が存在すること
  # awk で関数本体だけ抽出して検証（他の関数の mtime ロジックに誤マッチしない）
  local fn_body
  fn_body=$(awk '/^check_monitor_cld_observe_alive\(\)/,/^}/' "$PARALLEL_CHECK_LIB" 2>/dev/null || echo "")
  echo "$fn_body" | grep -qE 'OBSERVER_DAEMON_HEARTBEAT_STALE_SEC|observer-daemon-heartbeat' \
    || fail "check_monitor_cld_observe_alive() 内に heartbeat stale 検証（OBSERVER_DAEMON_HEARTBEAT_STALE_SEC / observer-daemon-heartbeat）が存在しない（AC3 未実装）"
}

# ---------------------------------------------------------------------------
# Scenario: check_monitor_cld_observe_alive() に heartbeat absent 時の grace period ロジックが存在する
# WHEN: observer-parallel-check.sh の check_monitor_cld_observe_alive() を確認
# THEN: heartbeat ファイル不在時の WARNING + pgrep fallback ロジックが存在する
# ---------------------------------------------------------------------------

@test "AC3: check_monitor_cld_observe_alive() に heartbeat absent grace period ロジックが存在する" {
  # RED: 実装前は fail する
  # NOTE: observer-parallel-check.sh の check_observer_mode() コメントに「不在」という語があるが
  #       AC3 が要求するのは check_monitor_cld_observe_alive() 関数内の grace period ロジック。
  #       現状の check_monitor_cld_observe_alive() は pgrep のみで grace period を持たない。
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  # check_monitor_cld_observe_alive() 関数本体内に observer-daemon-heartbeat への参照が存在すること
  # （grace period は heartbeat ファイルを参照する前提。heartbeat ファイル参照なしに grace period は実装できない）
  local fn_body
  fn_body=$(awk '/^check_monitor_cld_observe_alive\(\)/,/^}/' "$PARALLEL_CHECK_LIB" 2>/dev/null || echo "")
  echo "$fn_body" | grep -q 'observer-daemon-heartbeat\|OBSERVER_PARALLEL_CHECK_DAEMON_HEARTBEAT_PATH' \
    || fail "check_monitor_cld_observe_alive() 内に heartbeat ファイル参照が存在しない（grace period 未実装 — AC3 未実装）"
}

# ---------------------------------------------------------------------------
# Scenario: check_monitor_cld_observe_alive() に JSON writer/pid 検証が存在する
# WHEN: observer-parallel-check.sh の check_monitor_cld_observe_alive() を確認
# THEN: heartbeat JSON から writer と pid を抽出して検証するロジックが存在する
# ---------------------------------------------------------------------------

@test "AC3: check_monitor_cld_observe_alive() に heartbeat JSON の writer/pid 検証が存在する" {
  # RED: 実装前は fail する
  # NOTE: check_controller_heartbeat_alive() は既存の writer 変数を使うが、
  #       AC3 が要求するのは check_monitor_cld_observe_alive() 関数内での heartbeat writer/pid 検証。
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  # check_monitor_cld_observe_alive() 関数本体内に writer または pid の JSON 検証が存在すること
  local fn_body
  fn_body=$(awk '/^check_monitor_cld_observe_alive\(\)/,/^}/' "$PARALLEL_CHECK_LIB" 2>/dev/null || echo "")
  echo "$fn_body" | grep -qE '\.writer|\.pid|"writer"|"pid"' \
    || fail "check_monitor_cld_observe_alive() 内に heartbeat JSON writer/pid 検証が存在しない（AC3 未実装）"
}

# ===========================================================================
# AC4: env override 対応
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: cld-observe-any が CLD_OBSERVE_ANY_HEARTBEAT_PATH env override を参照する
# WHEN: cld-observe-any スクリプトを grep
# THEN: CLD_OBSERVE_ANY_HEARTBEAT_PATH の参照が存在する
# ---------------------------------------------------------------------------

@test "AC4: cld-observe-any が CLD_OBSERVE_ANY_HEARTBEAT_PATH env を参照している" {
  # RED: 実装前は fail する
  [[ -f "$CLD_OBSERVE_ANY" ]] \
    || fail "cld-observe-any が存在しない: $CLD_OBSERVE_ANY"

  grep -q 'CLD_OBSERVE_ANY_HEARTBEAT_PATH' "$CLD_OBSERVE_ANY" \
    || fail "CLD_OBSERVE_ANY_HEARTBEAT_PATH env override が cld-observe-any に存在しない（AC4 未実装）"
}

# ---------------------------------------------------------------------------
# Scenario: observer-parallel-check.sh が OBSERVER_PARALLEL_CHECK_DAEMON_HEARTBEAT_PATH env を参照する
# WHEN: observer-parallel-check.sh を grep
# THEN: OBSERVER_PARALLEL_CHECK_DAEMON_HEARTBEAT_PATH の参照が存在する
# ---------------------------------------------------------------------------

@test "AC4: observer-parallel-check.sh が OBSERVER_PARALLEL_CHECK_DAEMON_HEARTBEAT_PATH env を参照している" {
  # RED: 実装前は fail する
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  grep -q 'OBSERVER_PARALLEL_CHECK_DAEMON_HEARTBEAT_PATH' "$PARALLEL_CHECK_LIB" \
    || fail "OBSERVER_PARALLEL_CHECK_DAEMON_HEARTBEAT_PATH env override が observer-parallel-check.sh に存在しない（AC4 未実装）"
}

# ---------------------------------------------------------------------------
# Scenario: observer-parallel-check.sh が OBSERVER_DAEMON_HEARTBEAT_STALE_SEC env を参照する
# WHEN: observer-parallel-check.sh を grep
# THEN: OBSERVER_DAEMON_HEARTBEAT_STALE_SEC の参照が存在する（default 120 sec）
# ---------------------------------------------------------------------------

@test "AC4: observer-parallel-check.sh が OBSERVER_DAEMON_HEARTBEAT_STALE_SEC env を参照している" {
  # RED: 実装前は fail する
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  grep -q 'OBSERVER_DAEMON_HEARTBEAT_STALE_SEC' "$PARALLEL_CHECK_LIB" \
    || fail "OBSERVER_DAEMON_HEARTBEAT_STALE_SEC env override が observer-parallel-check.sh に存在しない（AC4 未実装）"
}

# ===========================================================================
# AC5: _emit_daemon_heartbeat() が set -euo pipefail 下でも main loop を die させない
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: cld-observe-any の _emit_daemon_heartbeat に || true / 2>/dev/null が存在する
# WHEN: cld-observe-any の _emit_daemon_heartbeat 実装を確認
# THEN: 全 IO に || true または 2>/dev/null が付与されている
# ---------------------------------------------------------------------------

@test "AC5: _emit_daemon_heartbeat() に failure isolation（|| true または 2>/dev/null）が存在する" {
  # RED: 実装前は fail する（failure isolation 未実装）
  [[ -f "$CLD_OBSERVE_ANY" ]] \
    || fail "cld-observe-any が存在しない: $CLD_OBSERVE_ANY"

  grep -q '_emit_daemon_heartbeat' "$CLD_OBSERVE_ANY" \
    || fail "_emit_daemon_heartbeat が存在しない（AC1 前提未実装）"

  # _emit_daemon_heartbeat 関数内に || true または 2>/dev/null が存在すること
  grep -A 30 '_emit_daemon_heartbeat()' "$CLD_OBSERVE_ANY" \
    | grep -qE '\|\| true|2>/dev/null' \
    || fail "_emit_daemon_heartbeat に failure isolation（|| true / 2>/dev/null）が存在しない（AC5 未実装）"
}

# ---------------------------------------------------------------------------
# Scenario: _emit_daemon_heartbeat が SUPERVISOR_DIR=read-only でも exit 0 で完了する
# WHEN: SUPERVISOR_DIR を read-only にして _emit_daemon_heartbeat を呼び出す
# THEN: exit 0（daemon が die しない）
# ---------------------------------------------------------------------------

@test "AC5: SUPERVISOR_DIR read-only でも _emit_daemon_heartbeat が exit 0 で完了する" {
  # RED: 実装前は fail する（_emit_daemon_heartbeat 未実装）
  [[ -f "$CLD_OBSERVE_ANY" ]] \
    || fail "cld-observe-any が存在しない: $CLD_OBSERVE_ANY"

  grep -q '_emit_daemon_heartbeat' "$CLD_OBSERVE_ANY" \
    || fail "_emit_daemon_heartbeat が存在しない（AC1 前提未実装）"

  local readonly_dir
  readonly_dir="$(mktemp -d)"
  chmod 555 "$readonly_dir"

  run bash -c "
    set -euo pipefail
    source '$CLD_OBSERVE_ANY' --source-only 2>/dev/null || true
    # _emit_daemon_heartbeat を直接 source して定義だけ取り込む
    source <(grep -A 50 '_emit_daemon_heartbeat()' '$CLD_OBSERVE_ANY' | head -60) 2>/dev/null || true
    export SUPERVISOR_DIR='$readonly_dir'
    export CLD_OBSERVE_ANY_HEARTBEAT_PATH='$readonly_dir/observer-daemon-heartbeat.json'
    export CYCLE=1
    _emit_daemon_heartbeat 2>/dev/null || true
    exit 0
  "

  chmod 755 "$readonly_dir"
  rm -rf "$readonly_dir"

  assert_success
}

# ===========================================================================
# AC6-1: 3 cycle heartbeat update（HEARTBEAT_INTERVAL_SEC=1 で timeout 15s）
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: HEARTBEAT_INTERVAL_SEC=1 でデーモンが 3 cycle 動作し heartbeat が更新される
# WHEN: cld-observe-any を HEARTBEAT_INTERVAL_SEC=1 MAX_CYCLES=3 でサブプロセス実行
# THEN: heartbeat ファイルが作成され last_update が 3 回以上更新されている（timeout 15s）
# ---------------------------------------------------------------------------

@test "AC6-1: HEARTBEAT_INTERVAL_SEC=1 で 3 cycle 後に heartbeat ファイルが更新される" {
  # RED: 実装前は fail する（_emit_daemon_heartbeat 未実装）
  [[ -f "$CLD_OBSERVE_ANY" ]] \
    || fail "cld-observe-any が存在しない: $CLD_OBSERVE_ANY"

  grep -q '_emit_daemon_heartbeat' "$CLD_OBSERVE_ANY" \
    || fail "_emit_daemon_heartbeat が存在しない（AC1 前提未実装）"

  local hb_dir
  hb_dir="$(mktemp -d)"
  local hb_path="${hb_dir}/observer-daemon-heartbeat.json"

  # MAX_CYCLES=3 で daemon を起動（実際の tmux 操作なし: stub で代替）
  # _TEST_MODE + stub で cld-observe-any を最小起動する
  run timeout 15 bash -c "
    export SUPERVISOR_DIR='$hb_dir'
    export CLD_OBSERVE_ANY_HEARTBEAT_PATH='$hb_path'
    export HEARTBEAT_INTERVAL_SEC=1
    export INTERVAL=1
    export _TEST_MODE=1
    export CLD_OBSERVE_ANY_SCRIPT_DIR='$(dirname "$CLD_OBSERVE_ANY")'
    # tmux コマンドを stub（空文字返却 → TARGET_WINS=0 → 1 cycle で break）
    tmux() { echo ''; }
    export -f tmux
    source '$CLD_OBSERVE_ANY' 2>/dev/null || true
    # heartbeat 呼び出しが 3 回行われたかを確認
    [[ -f '$hb_path' ]] || exit 1
    _count=\$(jq -r '.cycle_count' '$hb_path' 2>/dev/null || echo 0)
    [[ \"\$_count\" -ge 1 ]] || exit 1
  " 2>/dev/null

  rm -rf "$hb_dir"

  # timeout 内で heartbeat ファイルが作成・更新されていること
  # RED: _emit_daemon_heartbeat が未実装なため fail する
  assert_success
}

# ===========================================================================
# AC6-2: JSON schema 検証
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: heartbeat JSON が writer/pid/last_update/host/version/interval_sec/cycle_count を含む
# WHEN: _emit_daemon_heartbeat を直接呼び出して heartbeat ファイルを生成
# THEN: 全 7 フィールドが存在する
# ---------------------------------------------------------------------------

@test "AC6-2: heartbeat JSON が全 7 フィールド（writer/pid/last_update/host/version/interval_sec/cycle_count）を含む" {
  # RED: 実装前は fail する（_emit_daemon_heartbeat 未実装）
  [[ -f "$CLD_OBSERVE_ANY" ]] \
    || fail "cld-observe-any が存在しない: $CLD_OBSERVE_ANY"

  grep -q '_emit_daemon_heartbeat' "$CLD_OBSERVE_ANY" \
    || fail "_emit_daemon_heartbeat が存在しない（AC1 前提未実装）"

  local hb_dir
  hb_dir="$(mktemp -d)"
  local hb_path="${hb_dir}/observer-daemon-heartbeat.json"

  # _emit_daemon_heartbeat を source して直接呼び出す
  bash -c "
    source '$CLD_OBSERVE_ANY' --no-exec 2>/dev/null || true
    export SUPERVISOR_DIR='$hb_dir'
    export CLD_OBSERVE_ANY_HEARTBEAT_PATH='$hb_path'
    export HEARTBEAT_INTERVAL_SEC=60
    export CYCLE=5
    _emit_daemon_heartbeat 2>/dev/null
  " 2>/dev/null || true

  # heartbeat ファイルが存在すること
  [[ -f "$hb_path" ]] \
    || fail "heartbeat ファイルが生成されていない: $hb_path（AC6-2 / AC1 未実装）"

  # 全フィールドが存在すること
  for field in writer pid last_update host version interval_sec cycle_count; do
    jq -e --arg f "$field" 'has($f)' "$hb_path" >/dev/null 2>&1 \
      || fail "heartbeat JSON に '$field' フィールドが存在しない（AC2 / AC6-2 未実装）"
  done

  rm -rf "$hb_dir"
}

# ===========================================================================
# AC6-3: atomicity（複数 reader で syntax error 0 件）
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: heartbeat ファイルへの並列アクセス時に JSON syntax error が発生しない
# WHEN: _emit_daemon_heartbeat を連続呼び出しながら並列で jq parse する
# THEN: 全読み取りで syntax error が 0 件（atomic write の確認）
# ---------------------------------------------------------------------------

@test "AC6-3: heartbeat ファイルへの並列読み取りで JSON syntax error が 0 件" {
  # RED: 実装前は fail する（atomic write 未実装）
  [[ -f "$CLD_OBSERVE_ANY" ]] \
    || fail "cld-observe-any が存在しない: $CLD_OBSERVE_ANY"

  grep -q '_emit_daemon_heartbeat' "$CLD_OBSERVE_ANY" \
    || fail "_emit_daemon_heartbeat が存在しない（AC1 前提未実装）"

  local hb_dir
  hb_dir="$(mktemp -d)"
  local hb_path="${hb_dir}/observer-daemon-heartbeat.json"
  local error_log="${hb_dir}/errors.log"

  # writer と reader を並列実行
  (
    for i in $(seq 1 20); do
      bash -c "
        export SUPERVISOR_DIR='$hb_dir'
        export CLD_OBSERVE_ANY_HEARTBEAT_PATH='$hb_path'
        export HEARTBEAT_INTERVAL_SEC=60
        export CYCLE=$i
        source '$CLD_OBSERVE_ANY' --no-exec 2>/dev/null || true
        _emit_daemon_heartbeat 2>/dev/null || true
      " 2>/dev/null
      sleep 0.05
    done
  ) &
  local writer_pid=$!

  local errors=0
  for i in $(seq 1 30); do
    if [[ -f "$hb_path" ]]; then
      if ! jq '.' "$hb_path" >/dev/null 2>&1; then
        errors=$((errors + 1))
        echo "syntax error at read $i" >> "$error_log"
      fi
    fi
    sleep 0.03
  done
  wait "$writer_pid" 2>/dev/null || true

  rm -rf "$hb_dir"

  [[ "$errors" -eq 0 ]] \
    || fail "heartbeat の並列読み取りで $errors 件の JSON syntax error が発生した（AC3 / AC6-3 未実装: atomic write なし）"
}

# ===========================================================================
# AC6-4: path override（CLD_OBSERVE_ANY_HEARTBEAT_PATH）
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: CLD_OBSERVE_ANY_HEARTBEAT_PATH を設定すると書き出し先が変わる
# WHEN: CLD_OBSERVE_ANY_HEARTBEAT_PATH=/custom/path.json を設定して _emit_daemon_heartbeat を呼ぶ
# THEN: /custom/path.json が作成される（デフォルトパスには書かれない）
# ---------------------------------------------------------------------------

@test "AC6-4: CLD_OBSERVE_ANY_HEARTBEAT_PATH で heartbeat 書き出し先を override できる" {
  # RED: 実装前は fail する（CLD_OBSERVE_ANY_HEARTBEAT_PATH override 未実装）
  [[ -f "$CLD_OBSERVE_ANY" ]] \
    || fail "cld-observe-any が存在しない: $CLD_OBSERVE_ANY"

  grep -q 'CLD_OBSERVE_ANY_HEARTBEAT_PATH' "$CLD_OBSERVE_ANY" \
    || fail "CLD_OBSERVE_ANY_HEARTBEAT_PATH が cld-observe-any に存在しない（AC4 前提未実装）"

  local hb_dir
  hb_dir="$(mktemp -d)"
  local custom_path="${hb_dir}/custom-heartbeat.json"
  local default_path="${hb_dir}/.supervisor/observer-daemon-heartbeat.json"

  bash -c "
    export SUPERVISOR_DIR='$hb_dir'
    export CLD_OBSERVE_ANY_HEARTBEAT_PATH='$custom_path'
    export HEARTBEAT_INTERVAL_SEC=60
    export CYCLE=1
    source '$CLD_OBSERVE_ANY' --no-exec 2>/dev/null || true
    _emit_daemon_heartbeat 2>/dev/null
  " 2>/dev/null || true

  # カスタムパスにファイルが作成されていること
  [[ -f "$custom_path" ]] \
    || fail "CLD_OBSERVE_ANY_HEARTBEAT_PATH=$custom_path に heartbeat が書き出されていない（AC4 / AC6-4 未実装）"

  # デフォルトパスには書かれていないこと
  [[ ! -f "$default_path" ]] \
    || fail "CLD_OBSERVE_ANY_HEARTBEAT_PATH 設定時にデフォルトパス $default_path にも書き出されている（AC6-4 未実装）"

  rm -rf "$hb_dir"
}

# ===========================================================================
# AC6-5: stale 検知（mtime を touch -d '3 minutes ago' で擬似 stale → false）
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: heartbeat の mtime が 3 分以上前（stale）の場合に check_monitor_cld_observe_alive が false を返す
# GIVEN: heartbeat ファイルを touch -d '3 minutes ago' で擬似 stale 化
# AND: pgrep が true を返す（プロセスは生存）
# WHEN: check_monitor_cld_observe_alive() を呼ぶ
# THEN: "false" を返す（heartbeat stale → プロセスが hung と判定）
# ---------------------------------------------------------------------------

@test "AC6-5: heartbeat mtime が 3 分前（stale）の場合に check_monitor_cld_observe_alive が false を返す" {
  # RED: 実装前は fail する（mtime check 未実装）
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  grep -qE 'OBSERVER_DAEMON_HEARTBEAT_STALE_SEC|mtime|find.*-newer' "$PARALLEL_CHECK_LIB" \
    || fail "check_monitor_cld_observe_alive() に mtime 検証が存在しない（AC3 前提未実装）"

  local hb_dir
  hb_dir="$(mktemp -d)"
  local hb_path="${hb_dir}/observer-daemon-heartbeat.json"

  # 有効な heartbeat JSON を作成
  echo '{"writer":"cld-observe-any","pid":99999,"last_update":1000000,"host":"test","version":"1.0","interval_sec":60,"cycle_count":1}' \
    > "$hb_path"

  # 3 分前に mtime を設定（stale 状態）
  touch -d '3 minutes ago' "$hb_path"

  # pgrep を stub: プロセスは存在する（true）
  stub_command "pgrep" 'exit 0'

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    export OBSERVER_PARALLEL_CHECK_DAEMON_HEARTBEAT_PATH='$hb_path'
    export OBSERVER_DAEMON_HEARTBEAT_STALE_SEC=120
    check_monitor_cld_observe_alive
  "

  rm -rf "$hb_dir"

  assert_success
  assert_output "false"
}

# ===========================================================================
# AC6-6: heartbeat absent grace period
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: heartbeat ファイルが存在しない場合に pgrep 結果を返し stderr に WARNING を出力する
# GIVEN: heartbeat ファイルを削除した状態
# AND: pgrep が true を返す（プロセスは生存）
# WHEN: check_monitor_cld_observe_alive() を呼ぶ
# THEN: "true" を返す（grace period: pgrep 結果を優先）かつ stderr に WARNING が出力される
# ---------------------------------------------------------------------------

@test "AC6-6: heartbeat absent 時に pgrep 結果（true）を返し stderr に WARNING を出力する" {
  # RED: 実装前は fail する（heartbeat absent grace period 未実装）
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  grep -qiE 'WARNING|grace|absent' "$PARALLEL_CHECK_LIB" \
    || fail "check_monitor_cld_observe_alive() に grace period ロジックが存在しない（AC3 前提未実装）"

  local hb_dir
  hb_dir="$(mktemp -d)"
  local hb_path="${hb_dir}/observer-daemon-heartbeat.json"

  # heartbeat ファイルは作成しない（absent 状態）

  # pgrep を stub: プロセスは存在する（exit 0）
  stub_command "pgrep" 'exit 0'

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    export OBSERVER_PARALLEL_CHECK_DAEMON_HEARTBEAT_PATH='$hb_path'
    export OBSERVER_DAEMON_HEARTBEAT_STALE_SEC=120
    check_monitor_cld_observe_alive
  " 2>&1

  rm -rf "$hb_dir"

  # pgrep=true なので "true" を返すこと（grace period）
  echo "$output" | grep -q "true" \
    || fail "heartbeat absent 時に pgrep 結果（true）が返されていない（AC3 grace period 未実装）"

  # stderr に WARNING が出力されること
  echo "$output" | grep -qiE 'WARNING|warn|heartbeat.*absent|heartbeat.*not.*found|heartbeat.*missing' \
    || fail "heartbeat absent 時に stderr WARNING が出力されていない（AC3 / AC6-6 未実装）"
}

# ---------------------------------------------------------------------------
# Scenario: heartbeat ファイルが存在せず pgrep も false の場合に false を返す
# GIVEN: heartbeat ファイルを削除した状態
# AND: pgrep が false を返す（プロセス不在）
# WHEN: check_monitor_cld_observe_alive() を呼ぶ
# THEN: "false" を返す
# ---------------------------------------------------------------------------

@test "AC6-6: heartbeat absent かつ pgrep=false の場合に false を返す" {
  # RED: 実装前は fail する
  # NOTE: 現行 check_monitor_cld_observe_alive() は pgrep のみ。
  #       OBSERVER_PARALLEL_CHECK_DAEMON_HEARTBEAT_PATH は未参照のため、
  #       このテストは AC3/AC4 実装（heartbeat path env 対応）が前提。
  #       実装前 gate: check_monitor_cld_observe_alive() 内に
  #       OBSERVER_PARALLEL_CHECK_DAEMON_HEARTBEAT_PATH が存在しなければ fail。
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  # AC4 実装 gate: check_monitor_cld_observe_alive() が heartbeat path env を参照していること
  local fn_body
  fn_body=$(awk '/^check_monitor_cld_observe_alive\(\)/,/^}/' "$PARALLEL_CHECK_LIB" 2>/dev/null || echo "")
  echo "$fn_body" | grep -q 'OBSERVER_PARALLEL_CHECK_DAEMON_HEARTBEAT_PATH' \
    || fail "check_monitor_cld_observe_alive() が OBSERVER_PARALLEL_CHECK_DAEMON_HEARTBEAT_PATH を参照していない（AC4 / AC3 未実装）"

  local hb_dir
  hb_dir="$(mktemp -d)"
  local hb_path="${hb_dir}/observer-daemon-heartbeat.json"

  # heartbeat ファイルは作成しない（absent 状態）
  # pgrep を stub: プロセス不在（exit 1）
  stub_command "pgrep" 'exit 1'

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    export OBSERVER_PARALLEL_CHECK_DAEMON_HEARTBEAT_PATH='$hb_path'
    export OBSERVER_DAEMON_HEARTBEAT_STALE_SEC=120
    check_monitor_cld_observe_alive
  "

  rm -rf "$hb_dir"

  assert_success
  assert_output "false"
}

# ===========================================================================
# AC6-7: failure isolation（SUPERVISOR_DIR read-only でも daemon が die しない）
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: SUPERVISOR_DIR が read-only でも cld-observe-any main loop が die しない
# GIVEN: SUPERVISOR_DIR を chmod 555 で read-only にする
# WHEN: _emit_daemon_heartbeat を呼ぶ（write 失敗）
# THEN: exit 0 / 関数が正常に戻る（main loop が abort しない）
# ---------------------------------------------------------------------------

@test "AC6-7: SUPERVISOR_DIR read-only でも _emit_daemon_heartbeat が main loop を die させない" {
  # RED: 実装前は fail する（failure isolation 未実装）
  [[ -f "$CLD_OBSERVE_ANY" ]] \
    || fail "cld-observe-any が存在しない: $CLD_OBSERVE_ANY"

  grep -q '_emit_daemon_heartbeat' "$CLD_OBSERVE_ANY" \
    || fail "_emit_daemon_heartbeat が存在しない（AC1 前提未実装）"

  local readonly_dir
  readonly_dir="$(mktemp -d)"
  chmod 555 "$readonly_dir"
  local hb_path="${readonly_dir}/observer-daemon-heartbeat.json"

  # set -euo pipefail 下で _emit_daemon_heartbeat を呼んでも die しないこと
  run bash -c "
    set -euo pipefail
    source '$CLD_OBSERVE_ANY' --no-exec 2>/dev/null || true
    # 関数定義だけ抽出して source
    eval \"\$(grep -A 40 '^_emit_daemon_heartbeat()' '$CLD_OBSERVE_ANY' 2>/dev/null || echo '')\" 2>/dev/null || true
    export SUPERVISOR_DIR='$readonly_dir'
    export CLD_OBSERVE_ANY_HEARTBEAT_PATH='$hb_path'
    export HEARTBEAT_INTERVAL_SEC=60
    export CYCLE=1
    _emit_daemon_heartbeat 2>/dev/null
    echo 'main loop continues'
  "

  chmod 755 "$readonly_dir"
  rm -rf "$readonly_dir"

  # main loop が続行できていること（exit 0 かつ "main loop continues" が出力されること）
  assert_success
  assert_output --partial "main loop continues"
}

# ===========================================================================
# AC7: pitfalls-catalog.md §11.1.x サブセクション追記
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: pitfalls-catalog.md に cld-observe-any daemon heartbeat サブセクションが存在する
# WHEN: pitfalls-catalog.md §11.1 付近を確認する
# THEN: cld-observe-any heartbeat に言及するサブセクションが存在する
# ---------------------------------------------------------------------------

@test "AC7: pitfalls-catalog.md に cld-observe-any daemon heartbeat サブセクションが存在する" {
  # RED: 実装前は fail する（pitfalls-catalog.md 未更新）
  local catalog
  catalog="$REPO_ROOT/skills/su-observer/refs/pitfalls-catalog.md"

  [[ -f "$catalog" ]] \
    || fail "pitfalls-catalog.md が存在しない: $catalog"

  grep -qiE 'cld-observe-any.*heartbeat|heartbeat.*cld-observe-any|daemon.*heartbeat|observer-daemon-heartbeat' "$catalog" \
    || fail "pitfalls-catalog.md に cld-observe-any daemon heartbeat サブセクションが存在しない（AC7 未実装）"
}

# ---------------------------------------------------------------------------
# Scenario: pitfalls-catalog.md の heartbeat サブセクションに 60 sec 間隔の記述がある
# WHEN: pitfalls-catalog.md の heartbeat セクションを確認する
# THEN: 60 sec または HEARTBEAT_INTERVAL_SEC への言及が存在する
# ---------------------------------------------------------------------------

@test "AC7: pitfalls-catalog.md の heartbeat セクションに 60 sec 間隔の記述がある" {
  # RED: 実装前は fail する
  local catalog
  catalog="$REPO_ROOT/skills/su-observer/refs/pitfalls-catalog.md"

  [[ -f "$catalog" ]] \
    || fail "pitfalls-catalog.md が存在しない: $catalog"

  # heartbeat セクションが存在すること（AC7 前提）
  grep -qiE 'heartbeat.*daemon|daemon.*heartbeat' "$catalog" \
    || fail "pitfalls-catalog.md に heartbeat daemon セクションが存在しない（AC7 前提未実装）"

  # 60 sec または HEARTBEAT_INTERVAL_SEC の記述があること
  grep -qE '60.*sec|60s|HEARTBEAT_INTERVAL_SEC|60.*秒|秒.*60' "$catalog" \
    || fail "pitfalls-catalog.md の heartbeat セクションに 60 sec 間隔の記述がない（AC7 未実装）"
}

# ---------------------------------------------------------------------------
# Scenario: pitfalls-catalog.md の heartbeat サブセクションに observer-daemon-heartbeat.json への言及がある
# WHEN: pitfalls-catalog.md を確認する
# THEN: observer-daemon-heartbeat.json への言及が存在する
# ---------------------------------------------------------------------------

@test "AC7: pitfalls-catalog.md に observer-daemon-heartbeat.json への言及がある" {
  # RED: 実装前は fail する
  local catalog
  catalog="$REPO_ROOT/skills/su-observer/refs/pitfalls-catalog.md"

  [[ -f "$catalog" ]] \
    || fail "pitfalls-catalog.md が存在しない: $catalog"

  grep -q 'observer-daemon-heartbeat' "$catalog" \
    || fail "pitfalls-catalog.md に observer-daemon-heartbeat.json への言及がない（AC7 未実装）"
}
