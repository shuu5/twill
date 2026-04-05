#!/usr/bin/env bats
# poll-phase-cleanup.bats
# Requirement: poll_phase done/failed 時の cleanup
# Requirement: poll タイムアウト時の cleanup
# Spec: openspec/changes/worker-tmux-cleanup/specs/orchestrator-cleanup/spec.md
#
# poll_phase() はオーケストレーター本体に埋め込まれているため、
# 状態遷移 + cleanup_worker 呼び出しロジックを抽出した test double で検証する。
#
# test double: scripts/poll-phase-dispatch.sh
#   Usage: poll-phase-dispatch.sh <issue1> [<issue2> ...]
#   - MOCK_STATUS_<N> 環境変数で各 issue の状態をシミュレート
#   - cleanup_worker の呼び出しを SANDBOX/cleanup.log に記録

load '../../bats/helpers/common'

setup() {
  common_setup

  # cleanup_worker の呼び出しを記録するスクリプト
  cat > "$SANDBOX/scripts/cleanup-worker-dispatch.sh" << 'DISPATCH_EOF'
#!/usr/bin/env bash
issue="$1"
echo "cleanup_worker $issue" >> "${CLEANUP_LOG:-/dev/null}"
tmux kill-window -t "ap-#${issue}" 2>/dev/null || true
DISPATCH_EOF
  chmod +x "$SANDBOX/scripts/cleanup-worker-dispatch.sh"

  # poll_phase の状態遷移 + cleanup ロジックを抽出した test double
  # 実際のポーリングループは行わず、各 issue の状態を1回だけ評価する
  cat > "$SANDBOX/scripts/poll-phase-dispatch.sh" << 'DISPATCH_EOF'
#!/usr/bin/env bash
# poll-phase-dispatch.sh - poll_phase() の done/failed 検知 + cleanup 呼び出し test double
# Usage: poll-phase-dispatch.sh <issue1> [<issue2> ...]
# 環境変数 MOCK_STATUS_<N> で各 issue の状態をシミュレート
set -uo pipefail

SCRIPTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
issues=("$@")

for issue in "${issues[@]}"; do
  # 環境変数 MOCK_STATUS_<issue> から状態取得
  var="MOCK_STATUS_${issue}"
  status="${!var:-running}"

  case "$status" in
    done)
      echo "[poll_phase] Issue #${issue}: 完了" >&2
      bash "$SCRIPTS_ROOT/cleanup-worker-dispatch.sh" "$issue"
      ;;
    failed)
      echo "[poll_phase] Issue #${issue}: 失敗" >&2
      bash "$SCRIPTS_ROOT/cleanup-worker-dispatch.sh" "$issue"
      ;;
    merge-ready)
      echo "[poll_phase] Issue #${issue}: merge-ready" >&2
      # cleanup_worker は呼ばない
      ;;
    running)
      echo "[poll_phase] Issue #${issue}: 実行中" >&2
      ;;
  esac
done
DISPATCH_EOF
  chmod +x "$SANDBOX/scripts/poll-phase-dispatch.sh"

  # タイムアウト時のロジックを抽出した test double
  # running 状態の issue を failed に変換し、cleanup_worker を実行する
  cat > "$SANDBOX/scripts/poll-phase-timeout-dispatch.sh" << 'DISPATCH_EOF'
#!/usr/bin/env bash
# poll-phase-timeout-dispatch.sh - タイムアウト時の failed 変換 + cleanup 呼び出し test double
# Usage: poll-phase-timeout-dispatch.sh <issue1> [<issue2> ...]
# 環境変数 MOCK_STATUS_<N> で各 issue の状態をシミュレート
set -uo pipefail

SCRIPTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
issues=("$@")

echo "[poll_phase] タイムアウト — 未完了 Issue を failed に変換" >&2

for issue in "${issues[@]}"; do
  var="MOCK_STATUS_${issue}"
  status="${!var:-running}"

  if [[ "$status" == "running" ]]; then
    echo "[poll_phase] Issue #${issue}: running → failed (timeout)" >&2
    # state-write 相当（テスト用に state JSON を直接更新）
    issue_file="${AUTOPILOT_DIR}/issues/issue-${issue}.json"
    if [[ -f "$issue_file" ]]; then
      jq '.status = "failed" | .failure = {"message":"poll_timeout","step":"polling"}' \
        "$issue_file" > "${issue_file}.tmp" && mv "${issue_file}.tmp" "$issue_file"
    fi
    bash "$SCRIPTS_ROOT/cleanup-worker-dispatch.sh" "$issue"
  fi
done
DISPATCH_EOF
  chmod +x "$SANDBOX/scripts/poll-phase-timeout-dispatch.sh"

  # 呼び出し記録ファイル
  CLEANUP_LOG="$SANDBOX/cleanup.log"
  export CLEANUP_LOG

  stub_command "tmux" "exit 0"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: poll_phase done/failed 時の cleanup
# ---------------------------------------------------------------------------

# Scenario: poll_phase で done 検知（初回）
# WHEN poll_phase がポーリング中に issue の status=done を取得する
# THEN cleanup_worker "$issue" を実行する
@test "poll_phase: status=done で cleanup_worker を呼び出す" {
  MOCK_STATUS_20=done CLEANUP_LOG="$CLEANUP_LOG" \
    run bash "$SANDBOX/scripts/poll-phase-dispatch.sh" "20"

  assert_success
  grep -q "cleanup_worker 20" "$CLEANUP_LOG"
}

# Scenario: poll_phase で failed 検知（初回）
# WHEN poll_phase がポーリング中に issue の status=failed を取得する
# THEN cleanup_worker "$issue" を実行する
@test "poll_phase: status=failed で cleanup_worker を呼び出す" {
  MOCK_STATUS_21=failed CLEANUP_LOG="$CLEANUP_LOG" \
    run bash "$SANDBOX/scripts/poll-phase-dispatch.sh" "21"

  assert_success
  grep -q "cleanup_worker 21" "$CLEANUP_LOG"
}

# Edge case: merge-ready では cleanup_worker を呼ばない
@test "poll_phase: status=merge-ready では cleanup_worker を呼ばない" {
  MOCK_STATUS_22=merge-ready CLEANUP_LOG="$CLEANUP_LOG" \
    run bash "$SANDBOX/scripts/poll-phase-dispatch.sh" "22"

  assert_success
  ! grep -q "cleanup_worker 22" "$CLEANUP_LOG" 2>/dev/null
}

# Edge case: 複数 issue のうち done と failed のみ cleanup される
@test "poll_phase: 複数 issue で done/failed のみ cleanup_worker が呼ばれる" {
  # issue 30=done, issue 31=failed, issue 32=merge-ready, issue 33=running
  MOCK_STATUS_30=done MOCK_STATUS_31=failed MOCK_STATUS_32=merge-ready MOCK_STATUS_33=running \
    CLEANUP_LOG="$CLEANUP_LOG" \
    run bash "$SANDBOX/scripts/poll-phase-dispatch.sh" "30" "31" "32" "33"

  assert_success
  grep -q "cleanup_worker 30" "$CLEANUP_LOG"
  grep -q "cleanup_worker 31" "$CLEANUP_LOG"
  ! grep -q "cleanup_worker 32" "$CLEANUP_LOG" 2>/dev/null
  ! grep -q "cleanup_worker 33" "$CLEANUP_LOG" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Requirement: poll タイムアウト時の cleanup
# ---------------------------------------------------------------------------

# Scenario: タイムアウト時の cleanup
# WHEN poll_phase が MAX_POLL 回に達し、running の issue を failed に変換する
# THEN 変換した各 issue に対して cleanup_worker "$issue" を実行する
@test "poll_phase_timeout: running issue を failed に変換後に cleanup_worker を呼び出す" {
  create_issue_json 40 "running"
  MOCK_STATUS_40=running CLEANUP_LOG="$CLEANUP_LOG" \
    run bash "$SANDBOX/scripts/poll-phase-timeout-dispatch.sh" "40"

  assert_success
  grep -q "cleanup_worker 40" "$CLEANUP_LOG"

  # status が failed に変換されていること
  local status
  status=$(jq -r '.status' "$SANDBOX/.autopilot/issues/issue-40.json")
  [ "$status" = "failed" ]
}

# Edge case: タイムアウト時に done issue は cleanup されない
@test "poll_phase_timeout: done issue はタイムアウト時に cleanup_worker を呼ばない" {
  create_issue_json 41 "done"
  MOCK_STATUS_41=done CLEANUP_LOG="$CLEANUP_LOG" \
    run bash "$SANDBOX/scripts/poll-phase-timeout-dispatch.sh" "41"

  assert_success
  ! grep -q "cleanup_worker 41" "$CLEANUP_LOG" 2>/dev/null
}

# Edge case: タイムアウト時に複数 running issue が全て cleanup される
@test "poll_phase_timeout: 複数の running issue が全て cleanup される" {
  create_issue_json 50 "running"
  create_issue_json 51 "running"
  create_issue_json 52 "done"

  MOCK_STATUS_50=running MOCK_STATUS_51=running MOCK_STATUS_52=done \
    CLEANUP_LOG="$CLEANUP_LOG" \
    run bash "$SANDBOX/scripts/poll-phase-timeout-dispatch.sh" "50" "51" "52"

  assert_success
  grep -q "cleanup_worker 50" "$CLEANUP_LOG"
  grep -q "cleanup_worker 51" "$CLEANUP_LOG"
  ! grep -q "cleanup_worker 52" "$CLEANUP_LOG" 2>/dev/null
}

# Edge case: タイムアウト時に failure フィールドが設定される
@test "poll_phase_timeout: タイムアウトで failed に変換された issue に failure 情報が記録される" {
  create_issue_json 60 "running"
  MOCK_STATUS_60=running CLEANUP_LOG="$CLEANUP_LOG" \
    run bash "$SANDBOX/scripts/poll-phase-timeout-dispatch.sh" "60"

  assert_success

  local failure_msg
  failure_msg=$(jq -r '.failure.message' "$SANDBOX/.autopilot/issues/issue-60.json")
  [ "$failure_msg" = "poll_timeout" ]
}
