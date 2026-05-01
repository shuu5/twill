#!/usr/bin/env bats
# step0-monitor-bootstrap-daemon-running.bats - Issue #1199 AC1/AC2/AC4/AC5 RED テスト
#
# Issue #1199: [Tech Debt Step 0] step0-monitor-bootstrap.sh の _daemon_running() を
#              pgrep のみ判定から多段確認ロジックに改修する
#
# AC coverage:
#   AC1 - _daemon_running() の多段確認ロジック（zombie/stale/grace/normal シナリオ）
#   AC2 - 4 つの mock シナリオを bats で実装（AC1 と実質同一）
#   AC3 - bats が PASS すること（bats 実行自体で確認）
#   AC4 - --check / --write / 引数なし モードの後方互換性
#   AC5 - deps.yaml に bats test entry が存在すること
#
# RED: AC1/AC2 は実装前（_daemon_running がpgrep のみ）の状態で fail する。
#      AC4 はすでに動作しているため PASS する（後方互換チェック）。
#      AC5 は deps.yaml に entry が未追加のため fail する。
#
# source guard チェック結果:
#   step0-monitor-bootstrap.sh に BASH_SOURCE guard が存在しない。
#   source すると case "$MODE" （MODE=""）まで実行されて _emit_start_commands が走る。
#   このため _daemon_running() の単体呼び出しは --check モード経由で行う。
#   実装後テストは bash <script> --check の exit code と stdout を検証する。
#
# _DAEMON_LOAD_ONLY フラグ追記要求:
#   実装者は step0-monitor-bootstrap.sh に source guard
#   （[[ "${BASH_SOURCE[0]}" == "${0}" ]] || return 0 など）または
#   _DAEMON_LOAD_ONLY=1 対応を追加することを推奨する。
#   追加されれば将来のテストで関数直接呼び出しが可能になる。
#
# テストフレームワーク: bats-core（bats-support + bats-assert）

load '../helpers/common'

BOOTSTRAP_SCRIPT=""

setup() {
  common_setup
  BOOTSTRAP_SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/step0-monitor-bootstrap.sh"
  export SUPERVISOR_DIR="${SANDBOX}/.supervisor"
  mkdir -p "${SUPERVISOR_DIR}"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1/AC2: zombie / 同名プロセス シナリオ
# pgrep PASS（同名プロセスが別 PID で存在）だが heartbeat.json の pid が pgrep 結果に含まれない
# 多段確認ロジック: (a) PASS / (d) FAIL → false 返却
# ===========================================================================

# ---------------------------------------------------------------------------
# WHEN: pgrep は PID を返す（同名プロセス存在）が heartbeat.json の pid が異なる
# THEN: _daemon_running() は false を返す（exit 1 / NOT_RUNNING）
# RED: 現在は pgrep のみ判定のため RUNNING を返して fail する
# ---------------------------------------------------------------------------

@test "AC1/AC2-zombie: heartbeat.json の pid が pgrep 結果に含まれない場合に NOT_RUNNING を返す" {
  # RED: 実装前は pgrep のみ判定のため RUNNING を返して fail する
  [[ -f "${BOOTSTRAP_SCRIPT}" ]] \
    || fail "step0-monitor-bootstrap.sh が存在しない: ${BOOTSTRAP_SCRIPT}"

  # pgrep stub: PID 1234 を返す（同名プロセスが存在するが zombie）
  stub_command "pgrep" 'echo "1234"; exit 0'

  # heartbeat.json を配置: pid=9999（pgrep 結果 1234 に含まれない）
  local hb_json
  hb_json="${SUPERVISOR_DIR}/observer-daemon-heartbeat.json"
  cat > "${hb_json}" <<'EOF'
{"writer":"cld-observe-any","pid":9999,"last_update":1000000,"host":"test","version":"1.0","interval_sec":60,"cycle_count":1}
EOF
  # fresh mtime（120秒以内）
  touch "${hb_json}"

  run bash "${BOOTSTRAP_SCRIPT}" --check

  # 多段確認ロジック実装後: heartbeat.pid(9999) が pgrep 出力(1234) に含まれない → NOT_RUNNING
  # RED: 現在は RUNNING を返して以下の assert が fail する
  assert_failure
  assert_output "NOT_RUNNING"
}

# ===========================================================================
# AC1/AC2: stale heartbeat シナリオ
# pgrep PASS だが heartbeat.json の mtime が 120 秒超（stale）
# 多段確認ロジック: (a) PASS / (c) FAIL（mtime > OBSERVER_DAEMON_HEARTBEAT_STALE_SEC）→ false 返却
# ===========================================================================

# ---------------------------------------------------------------------------
# WHEN: pgrep は PASS するが heartbeat.json の mtime が 3 分前（stale）
# THEN: _daemon_running() は false を返す（exit 1 / NOT_RUNNING）
# RED: 現在は pgrep のみ判定のため RUNNING を返して fail する
# ---------------------------------------------------------------------------

@test "AC1/AC2-stale: heartbeat.json mtime が 3 分前（stale）の場合に NOT_RUNNING を返す" {
  # RED: 実装前は pgrep のみ判定のため RUNNING を返して fail する
  [[ -f "${BOOTSTRAP_SCRIPT}" ]] \
    || fail "step0-monitor-bootstrap.sh が存在しない: ${BOOTSTRAP_SCRIPT}"

  # pgrep stub: exit 0（プロセスは生存している）
  stub_command "pgrep" 'exit 0'

  # heartbeat.json を配置して mtime を 3 分前に設定（stale）
  local hb_json
  hb_json="${SUPERVISOR_DIR}/observer-daemon-heartbeat.json"
  cat > "${hb_json}" <<'EOF'
{"writer":"cld-observe-any","pid":1234,"last_update":1000000,"host":"test","version":"1.0","interval_sec":60,"cycle_count":10}
EOF
  # stale: 3 分前に mtime を設定（120 秒超）
  touch -d '3 minutes ago' "${hb_json}"

  run bash "${BOOTSTRAP_SCRIPT}" --check

  # 多段確認ロジック実装後: mtime > 120s → NOT_RUNNING
  # RED: 現在は RUNNING を返して以下の assert が fail する
  assert_failure
  assert_output "NOT_RUNNING"
}

# ---------------------------------------------------------------------------
# WHEN: OBSERVER_DAEMON_HEARTBEAT_STALE_SEC=60 で heartbeat mtime が 90 秒前
# THEN: NOT_RUNNING を返す（環境変数で stale 閾値が override されること）
# RED: 現在は mtime check 未実装のため RUNNING を返して fail する
# ---------------------------------------------------------------------------

@test "AC1/AC2-stale-env-override: OBSERVER_DAEMON_HEARTBEAT_STALE_SEC=60 で 90 秒前の heartbeat を stale と判定する" {
  # RED: 実装前は pgrep のみ判定のため RUNNING を返して fail する
  [[ -f "${BOOTSTRAP_SCRIPT}" ]] \
    || fail "step0-monitor-bootstrap.sh が存在しない: ${BOOTSTRAP_SCRIPT}"

  stub_command "pgrep" 'exit 0'

  local hb_json
  hb_json="${SUPERVISOR_DIR}/observer-daemon-heartbeat.json"
  cat > "${hb_json}" <<'EOF'
{"writer":"cld-observe-any","pid":1234,"last_update":1000000,"host":"test","version":"1.0","interval_sec":60,"cycle_count":5}
EOF
  # 90 秒前の mtime（STALE_SEC=60 の場合は stale、default=120 の場合は fresh）
  touch -d '90 seconds ago' "${hb_json}"

  # OBSERVER_DAEMON_HEARTBEAT_STALE_SEC=60 で stale 閾値を 60 秒に override
  OBSERVER_DAEMON_HEARTBEAT_STALE_SEC=60 \
    run bash "${BOOTSTRAP_SCRIPT}" --check

  # override 適用後: 90s > 60s → NOT_RUNNING
  # RED: 現在は RUNNING を返して以下の assert が fail する
  assert_failure
  assert_output "NOT_RUNNING"
}

# ===========================================================================
# AC1/AC2: heartbeat 不在 + pgrep PASS → grace period で true 返却 + stderr WARNING
# 多段確認ロジック: (a) PASS / (b) heartbeat 不在 → grace period で pgrep 結果を返却
# ===========================================================================

# ---------------------------------------------------------------------------
# WHEN: heartbeat.json が存在しない（不在）かつ pgrep が PASS
# THEN: grace period として RUNNING を返す かつ stderr に WARNING が出力される
# RED: 現在は grace period ロジックがないため WARNING が出力されず fail する
#      （RUNNING は返すが WARNING が出ないため assert_output がマッチしない）
# ---------------------------------------------------------------------------

@test "AC1/AC2-grace: heartbeat 不在 + pgrep=true で RUNNING を返し stderr に WARNING を出力する" {
  # RED: 実装前は WARNING が出力されず fail する（RUNNING は現在も返す）
  [[ -f "${BOOTSTRAP_SCRIPT}" ]] \
    || fail "step0-monitor-bootstrap.sh が存在しない: ${BOOTSTRAP_SCRIPT}"

  # pgrep stub: exit 0（プロセスは生存）
  stub_command "pgrep" 'exit 0'

  # heartbeat.json は作成しない（不在状態）

  # stderr + stdout を両方キャプチャするため 2>&1 で結合
  run bash -c "
    export PATH='${STUB_BIN}:${PATH}'
    export SUPERVISOR_DIR='${SUPERVISOR_DIR}'
    bash '${BOOTSTRAP_SCRIPT}' --check 2>&1
  "

  # grace period: pgrep=true → RUNNING を返すこと
  echo "${output}" | grep -q "RUNNING" \
    || fail "heartbeat 不在 + pgrep=true の grace period で RUNNING が返されていない（AC1 未実装）
実際の出力: ${output}"

  # stderr に WARNING が出力されること
  # RED: 実装前は WARNING が出ないため fail する
  echo "${output}" | grep -qiE "WARNING|warn|heartbeat.*absent|heartbeat.*not.found|heartbeat.*missing|grace" \
    || fail "heartbeat 不在時に stderr WARNING が出力されていない（AC1 grace period 未実装）
実際の出力: ${output}"
}

# ---------------------------------------------------------------------------
# WHEN: heartbeat.json が存在しない（不在）かつ pgrep が FAIL
# THEN: NOT_RUNNING を返す（grace period: pgrep 結果を返す）
# RED: 現在は heartbeat path 参照がないため通常通り動作し PASS してしまう場合がある
#      WARNING の有無を追加検証して RED にする
# ---------------------------------------------------------------------------

@test "AC1/AC2-grace: heartbeat 不在 + pgrep=false で NOT_RUNNING を返す" {
  # 現在の実装でも pgrep=false なら NOT_RUNNING を返すため、
  # このシナリオ単体は現在も PASS する可能性がある。
  # しかし grace period の WARNING 出力を併せて確認することで RED にする。
  [[ -f "${BOOTSTRAP_SCRIPT}" ]] \
    || fail "step0-monitor-bootstrap.sh が存在しない: ${BOOTSTRAP_SCRIPT}"

  # pgrep stub: exit 1（プロセス不在）
  stub_command "pgrep" 'exit 1'

  # heartbeat.json は作成しない（不在状態）

  run bash -c "
    export PATH='${STUB_BIN}:${PATH}'
    export SUPERVISOR_DIR='${SUPERVISOR_DIR}'
    bash '${BOOTSTRAP_SCRIPT}' --check 2>&1
  "

  # grace period: pgrep=false → NOT_RUNNING
  echo "${output}" | grep -q "NOT_RUNNING" \
    || fail "heartbeat 不在 + pgrep=false の grace period で NOT_RUNNING が返されていない
実際の出力: ${output}"

  # RED: 実装前は WARNING が出ないため fail する
  echo "${output}" | grep -qiE "WARNING|warn|heartbeat.*absent|heartbeat.*not.found|heartbeat.*missing|grace" \
    || fail "heartbeat 不在時に stderr WARNING が出力されていない（AC1 grace period 未実装）
実際の出力: ${output}"
}

# ===========================================================================
# AC1/AC2: 正常 daemon シナリオ（全段 PASS → true 返却）
# (a) pgrep PASS / (b) heartbeat.json 存在 / (c) mtime fresh / (d) writer + pid 一致
# ===========================================================================

# ---------------------------------------------------------------------------
# WHEN: 全条件が揃った正常 daemon 状態
# THEN: RUNNING を返す（exit 0）
# RED: 現在の実装は多段確認なしで pgrep のみ → RUNNING を返す
#      このテスト自体は現在も PASS する可能性があるが、
#      heartbeat.json の writer/pid 検証が追加されると正確な正常確認になる
# ---------------------------------------------------------------------------

@test "AC1/AC2-normal: 全段 PASS の正常 daemon で RUNNING を返す" {
  # 正常シナリオ: 実装後も PASS すること（GREEN テスト候補）
  # RED フェーズでは以下の pid 検証で差分を出す:
  # 現在の実装は heartbeat.json を参照しないため正常確認ができない
  [[ -f "${BOOTSTRAP_SCRIPT}" ]] \
    || fail "step0-monitor-bootstrap.sh が存在しない: ${BOOTSTRAP_SCRIPT}"

  # pgrep stub: PID 5678 を返す（daemon 正常起動中）
  stub_command "pgrep" 'echo "5678"; exit 0'

  # heartbeat.json を配置: pid=5678（pgrep 結果と一致）、fresh mtime
  local hb_json
  hb_json="${SUPERVISOR_DIR}/observer-daemon-heartbeat.json"
  cat > "${hb_json}" <<EOF
{"writer":"cld-observe-any","pid":5678,"last_update":$(date +%s),"host":"test","version":"1.0","interval_sec":60,"cycle_count":42}
EOF
  # fresh mtime（今すぐ touch）
  touch "${hb_json}"

  run bash "${BOOTSTRAP_SCRIPT}" --check

  # 全段 PASS: RUNNING を返すこと
  assert_success
  assert_output "RUNNING"
}

# ---------------------------------------------------------------------------
# WHEN: heartbeat.json の writer が "cld-observe-any" でない（別プロセスが書いた）
# THEN: NOT_RUNNING を返す（d 段: writer 不一致）
# RED: 現在は heartbeat.json を参照しないため RUNNING を返して fail する
# ---------------------------------------------------------------------------

@test "AC1/AC2-writer-mismatch: heartbeat.json の writer が 'cld-observe-any' でない場合に NOT_RUNNING を返す" {
  # RED: 実装前は heartbeat.json 未参照のため RUNNING を返して fail する
  [[ -f "${BOOTSTRAP_SCRIPT}" ]] \
    || fail "step0-monitor-bootstrap.sh が存在しない: ${BOOTSTRAP_SCRIPT}"

  # pgrep stub: exit 0（プロセスは存在）
  stub_command "pgrep" 'echo "5678"; exit 0'

  # heartbeat.json: writer が異なる（別プロセスが書いた）
  local hb_json
  hb_json="${SUPERVISOR_DIR}/observer-daemon-heartbeat.json"
  cat > "${hb_json}" <<EOF
{"writer":"some-other-process","pid":5678,"last_update":$(date +%s),"host":"test","version":"1.0","interval_sec":60,"cycle_count":1}
EOF
  touch "${hb_json}"

  run bash "${BOOTSTRAP_SCRIPT}" --check

  # d 段: writer != "cld-observe-any" → NOT_RUNNING
  # RED: 現在は RUNNING を返して以下の assert が fail する
  assert_failure
  assert_output "NOT_RUNNING"
}

# ===========================================================================
# AC4: 後方互換性チェック（--check / --write / 引数なし の各モード）
# これらのテストは実装前後で PASS する（破壊的変更禁止の確認）
# ===========================================================================

# ---------------------------------------------------------------------------
# WHEN: --check モードで daemon が起動している（pgrep PASS）
# THEN: exit 0 かつ "RUNNING" を出力する（既存挙動互換）
# NOTE: 多段確認ロジックを追加しても heartbeat 不在時は grace period で RUNNING を返すため、
#       heartbeat.json を配置して正常確認する
# ---------------------------------------------------------------------------

@test "AC4-compat: --check モードで RUNNING 時に exit 0 を返す（後方互換）" {
  [[ -f "${BOOTSTRAP_SCRIPT}" ]] \
    || fail "step0-monitor-bootstrap.sh が存在しない: ${BOOTSTRAP_SCRIPT}"

  # pgrep stub: PID を返す（プロセス存在）
  stub_command "pgrep" 'echo "9001"; exit 0'

  # heartbeat.json を配置（正常状態: 実装後の grace period 依存を避ける）
  local hb_json
  hb_json="${SUPERVISOR_DIR}/observer-daemon-heartbeat.json"
  cat > "${hb_json}" <<EOF
{"writer":"cld-observe-any","pid":9001,"last_update":$(date +%s),"host":"test","version":"1.0","interval_sec":60,"cycle_count":1}
EOF
  touch "${hb_json}"

  run bash "${BOOTSTRAP_SCRIPT}" --check

  assert_success
  assert_output "RUNNING"
}

# ---------------------------------------------------------------------------
# WHEN: --check モードで daemon が起動していない（pgrep FAIL）
# THEN: exit 1 かつ "NOT_RUNNING" を出力する（既存挙動互換）
# ---------------------------------------------------------------------------

@test "AC4-compat: --check モードで NOT_RUNNING 時に exit 1 を返す（後方互換）" {
  [[ -f "${BOOTSTRAP_SCRIPT}" ]] \
    || fail "step0-monitor-bootstrap.sh が存在しない: ${BOOTSTRAP_SCRIPT}"

  stub_command "pgrep" 'exit 1'

  run bash "${BOOTSTRAP_SCRIPT}" --check

  assert_failure
  assert_output "NOT_RUNNING"
}

# ---------------------------------------------------------------------------
# WHEN: --write モードで実行する
# THEN: exit 0 で正常終了する（noop: 互換用）
# ---------------------------------------------------------------------------

@test "AC4-compat: --write モードが exit 0 で noop 完了する（後方互換）" {
  [[ -f "${BOOTSTRAP_SCRIPT}" ]] \
    || fail "step0-monitor-bootstrap.sh が存在しない: ${BOOTSTRAP_SCRIPT}"

  # pgrep は呼ばれないが stub しておく（念のため）
  stub_command "pgrep" 'exit 1'

  run bash "${BOOTSTRAP_SCRIPT}" --write

  assert_success
  assert_output ""
}

# ---------------------------------------------------------------------------
# WHEN: 引数なしで実行する（daemon 未起動時）
# THEN: exit 0 かつ cld-observe-any 起動コマンドを stdout に emit する（既存挙動互換）
# ---------------------------------------------------------------------------

@test "AC4-compat: 引数なし（daemon 未起動）で cld-observe-any 起動コマンドを emit する（後方互換）" {
  [[ -f "${BOOTSTRAP_SCRIPT}" ]] \
    || fail "step0-monitor-bootstrap.sh が存在しない: ${BOOTSTRAP_SCRIPT}"

  # pgrep stub: daemon 未起動（exit 1）
  stub_command "pgrep" 'exit 1'

  run bash "${BOOTSTRAP_SCRIPT}"

  assert_success

  # --pattern フラグが emit されること（既存の AC1 互換）
  echo "${output}" | grep -q -- '--pattern' \
    || fail "引数なし実行で --pattern が emit されていない（後方互換 AC4 違反）
実際の出力: ${output}"
}

# ---------------------------------------------------------------------------
# WHEN: 引数なしで実行する（daemon 起動中）
# THEN: exit 0 かつ stdout は空（スキップメッセージは stderr のみ: 既存挙動互換）
# ---------------------------------------------------------------------------

@test "AC4-compat: 引数なし（daemon 起動中）で起動コマンドを emit しない（後方互換）" {
  [[ -f "${BOOTSTRAP_SCRIPT}" ]] \
    || fail "step0-monitor-bootstrap.sh が存在しない: ${BOOTSTRAP_SCRIPT}"

  # heartbeat.json を配置（多段確認 PASS 状態）
  local hb_json
  hb_json="${SUPERVISOR_DIR}/observer-daemon-heartbeat.json"
  cat > "${hb_json}" <<EOF
{"writer":"cld-observe-any","pid":9001,"last_update":$(date +%s),"host":"test","version":"1.0","interval_sec":60,"cycle_count":1}
EOF
  touch "${hb_json}"

  # pgrep stub: PID 9001（heartbeat.json と一致）
  stub_command "pgrep" 'echo "9001"; exit 0'

  # stdout のみキャプチャ（stderr は /dev/null へ）
  run bash -c "
    export PATH='${STUB_BIN}:${PATH}'
    export SUPERVISOR_DIR='${SUPERVISOR_DIR}'
    bash '${BOOTSTRAP_SCRIPT}' 2>/dev/null
  "

  assert_success
  # stdout は空（cld-observe-any 起動コマンドは emit しない）
  assert_output ""
}

# ===========================================================================
# AC5: deps.yaml に bats test entry が存在すること（SSOT 原則）
# ===========================================================================

# ---------------------------------------------------------------------------
# WHEN: plugins/twl/deps.yaml の内容を確認する
# THEN: step0-monitor-bootstrap-daemon-running.bats への entry が存在する
# RED: 実装前は entry が未追加のため fail する
# ---------------------------------------------------------------------------

@test "AC5: deps.yaml に step0-monitor-bootstrap-daemon-running.bats の entry が存在する" {
  # RED: 実装前は entry が未追加のため fail する
  local deps_yaml
  deps_yaml="${REPO_ROOT}/deps.yaml"

  [[ -f "${deps_yaml}" ]] \
    || fail "deps.yaml が存在しない: ${deps_yaml}"

  grep -q 'step0-monitor-bootstrap-daemon-running' "${deps_yaml}" \
    || fail "deps.yaml に step0-monitor-bootstrap-daemon-running.bats の entry が存在しない（AC5 未実装）
deps.yaml: ${deps_yaml}"
}
