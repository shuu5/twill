#!/usr/bin/env bats
# auto-resume-integration-1577.bats - TDD RED phase tests for Issue #1577 AC4 / AC8-c
#
# AC4: plugins/twl/scripts/pilot-fallback-monitor.sh に
#      expected_reset_at + 5min での auto-resume trigger を実装
#
# 検証方針:
#   - pilot-fallback-monitor.sh が budget-pause.json の expected_reset_at を読み込む
#     コードが存在することを static grep で確認
#   - budget-pause.json に expected_reset_at を設定し、経過時刻を超えた場合に
#     paused worker に対して resume 処理が発動することを実行テストで確認
#
# NOTE (baseline-bash §10):
#   pilot-fallback-monitor.sh には BASH_SOURCE guard が存在する（set -uo pipefail, L27）。
#   ただし main ロジック（_scan_all_workers / _process_worker）は guard されていないため、
#   source による副作用を避け、直接実行（bash <script>）でテストする。
#
# RED: 全テストは実装前の状態で fail する
#      現時点で pilot-fallback-monitor.sh は expected_reset_at を参照しない

load '../helpers/common'

setup() {
  common_setup

  FALLBACK_MONITOR="${REPO_ROOT}/scripts/pilot-fallback-monitor.sh"
  export FALLBACK_MONITOR

  # tmux スタブ（list-windows, send-keys 等をスタブ化）
  stub_command "tmux" '
args=("$@")
if [[ "${args[0]}" == "list-windows" ]]; then
  echo "test-worker-window"
elif [[ "${args[0]}" == "send-keys" ]]; then
  exit 0
elif [[ "${args[0]}" == "capture-pane" ]]; then
  echo ""
else
  exit 0
fi
'
  # python3 / twl モジュールの呼び出しをスタブ化
  stub_command "python3" '
# resolve_next_workflow スタブ
if echo "$*" | grep -qF "resolve_next_workflow"; then
  echo "/twl:workflow-issue-lifecycle"
  exit 0
fi
# state read スタブ
if echo "$*" | grep -qF "state read"; then
  if echo "$*" | grep -qF "status"; then
    echo "in-progress"
  elif echo "$*" | grep -qF "window"; then
    echo "test-worker-window"
  elif echo "$*" | grep -qF "pr"; then
    echo ""
  fi
  exit 0
fi
exit 0
'
  # session-comm.sh スタブ
  stub_command "session-comm.sh" 'exit 0'

  # sandbox に .supervisor と budget-pause.json の初期セットアップ
  mkdir -p "${SANDBOX}/.supervisor"
  mkdir -p "${SANDBOX}/.autopilot/issues"

  # テスト用 issue-9999.json
  cat > "${SANDBOX}/.autopilot/issues/issue-9999.json" <<EOF
{"issue": 9999, "status": "in-progress", "window": "test-worker-window"}
EOF
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC4: pilot-fallback-monitor.sh に expected_reset_at 読み込みコードが存在する（static grep）
# RED: 現時点で expected_reset_at を参照するコードが存在しないため fail する
# ===========================================================================

@test "ac4: pilot-fallback-monitor.sh に expected_reset_at の読み込みコードが存在する" {
  # AC: expected_reset_at + 5min での auto-resume trigger を実装
  # RED: 実装前は fail する — pilot-fallback-monitor.sh に expected_reset_at が存在しない
  grep -qF 'expected_reset_at' "${FALLBACK_MONITOR}"
}

@test "ac4: pilot-fallback-monitor.sh に auto_resume_via の参照コードが存在する" {
  # AC: budget-pause.json の auto_resume_via フィールドを参照して resume 方法を決定する
  # RED: 実装前は fail する — pilot-fallback-monitor.sh に auto_resume_via が存在しない
  grep -qF 'auto_resume_via' "${FALLBACK_MONITOR}"
}

@test "ac4: pilot-fallback-monitor.sh に budget-pause.json 読み込みロジックが存在する" {
  # AC: budget-pause.json の expected_reset_at を読み込む関数 or ロジックが存在すること
  # RED: 実装前は fail する — budget-pause.json を参照するロジックが存在しない
  grep -qE 'budget-pause\.json|budget_pause' "${FALLBACK_MONITOR}"
}

# ===========================================================================
# AC4: expected_reset_at + 5min 経過後に auto-resume が発動する（integration）
# RED: 機能未実装のため実行テストで fail する
# ===========================================================================

@test "ac4: expected_reset_at が 5min 以上前の budget-pause.json で auto-resume が発動する" {
  # AC: expected_reset_at + 5分経過後に paused worker の resume が trigger される
  # RED: 実装前は fail する — auto-resume ロジックが存在しない

  # 10 分前の expected_reset_at を持つ budget-pause.json を配置（十分に期限超過）
  local reset_at
  reset_at=$(python3 -c "
import datetime
dt = datetime.datetime.utcnow() - datetime.timedelta(minutes=10)
print(dt.isoformat() + 'Z')
" 2>/dev/null || echo "2000-01-01T00:00:00Z")

  cat > "${SANDBOX}/.supervisor/budget-pause.json" <<EOF
{
  "status": "paused",
  "paused_at": "2000-01-01T00:00:00Z",
  "estimated_recovery": "2000-01-01T01:30:00Z",
  "expected_reset_at": "${reset_at}",
  "cycle_reset_minutes_at_pause": 5,
  "auto_resume_via": "pilot-fallback-monitor",
  "paused_workers": ["test-worker-window"],
  "orchestrator_pid": null
}
EOF

  # AUTOPILOT_DIR と CWD を sandbox に向けて実行
  run bash -c "
    export AUTOPILOT_DIR='${SANDBOX}/.autopilot'
    export WORKER_WINDOW='test-worker-window'
    export ISSUE_NUM='9999'
    cd '${SANDBOX}'
    bash '${FALLBACK_MONITOR}' \
      --once \
      --no-orchestrator-check \
      --worker test-worker-window \
      --issue 9999 \
      --autopilot-dir '${SANDBOX}/.autopilot' \
      2>&1
  "

  # auto-resume が発動した場合、budget-pause.json の status が resumed に更新されるか
  # または stdout に auto-resume 関連メッセージが出力されること
  local resumed=false
  if [ -f "${SANDBOX}/.supervisor/budget-pause.json" ]; then
    if grep -qF '"resumed"' "${SANDBOX}/.supervisor/budget-pause.json" 2>/dev/null; then
      resumed=true
    fi
  fi
  if echo "$output" | grep -qiE 'resume|auto.resume'; then
    resumed=true
  fi

  [ "$resumed" = "true" ] || {
    echo "auto-resume が発動しなかった。status: $(cat "${SANDBOX}/.supervisor/budget-pause.json" 2>/dev/null || echo 'no file')"
    echo "stdout: $output"
    return 1
  }
}

@test "ac4: expected_reset_at が未来の budget-pause.json では auto-resume が発動しない" {
  # AC: 時刻が到達していない場合は auto-resume しないこと（早期発動防止）
  # RED: 実装前は fail する — 判定ロジックが存在しない

  # 1 時間後の expected_reset_at（未到達）
  local reset_at
  reset_at=$(python3 -c "
import datetime
dt = datetime.datetime.utcnow() + datetime.timedelta(hours=1)
print(dt.isoformat() + 'Z')
" 2>/dev/null || echo "9999-12-31T23:59:59Z")

  cat > "${SANDBOX}/.supervisor/budget-pause.json" <<EOF
{
  "status": "paused",
  "paused_at": "9999-01-01T00:00:00Z",
  "estimated_recovery": "9999-01-01T01:30:00Z",
  "expected_reset_at": "${reset_at}",
  "cycle_reset_minutes_at_pause": 5,
  "auto_resume_via": "pilot-fallback-monitor",
  "paused_workers": ["test-worker-window"],
  "orchestrator_pid": null
}
EOF

  run bash -c "
    export AUTOPILOT_DIR='${SANDBOX}/.autopilot'
    cd '${SANDBOX}'
    bash '${FALLBACK_MONITOR}' \
      --once \
      --no-orchestrator-check \
      --worker test-worker-window \
      --issue 9999 \
      --autopilot-dir '${SANDBOX}/.autopilot' \
      2>&1
  "

  # budget-pause.json の status が paused のままであること
  # （resume されていない = 早期発動なし）
  # RED: 実装前はこのチェックが実施されないので resume されてしまう可能性があり fail する
  if [ -f "${SANDBOX}/.supervisor/budget-pause.json" ]; then
    if grep -qF '"resumed"' "${SANDBOX}/.supervisor/budget-pause.json" 2>/dev/null; then
      echo "FAIL: 未到達の expected_reset_at にも関わらず auto-resume が発動した"
      return 1
    fi
  fi
  # この検証が実装前に pass してしまう場合（budget-pause.json を全く読まない場合）、
  # 上の ac4: expected_reset_at が 5min 以上前 のテストが fail して RED 状態を保証する
  true
}
