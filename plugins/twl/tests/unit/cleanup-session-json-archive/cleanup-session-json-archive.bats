#!/usr/bin/env bats
# cleanup-session-json-archive.bats
# Issue #999: autopilot-cleanup.sh が session.json を archive しない問題の修正
#
# AC:
#   1: cleanup後 session.json が存在しない — is_session_completed=true の場合
#   3: archive ディレクトリ (.autopilot/archive/SESSION_ID/session.json) に保存される
#   4: is_session_completed=false の場合は session.json を archive せず警告
#   5: 既存 issue state file archive 動作は影響なし (regression)
#   6+: Wave完了→archive(positive), in-progress→archive されない(negative)
#
# RED フェーズ: 現行 autopilot-cleanup.sh は session.json を archive しないため FAIL する。
# 修正後 (session.json mv 追加 + is_session_completed ガード) で PASS する。
#
# 前提: #978 (is_session_completed 修正) CLOSED 確認済み

load '../../bats/helpers/common.bash'

# ---------------------------------------------------------------------------
# setup / teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  # git worktree list のスタブ（Phase 2 孤立 worktree 検出を無効化）
  stub_command "git" 'if [[ "$1" == "worktree" ]]; then echo ""; exit 0; fi; exit 0'

  CLEANUP_SCRIPT="$SANDBOX/scripts/autopilot-cleanup.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: session.json を sandbox に作成する
# ---------------------------------------------------------------------------

_create_session_json() {
  local session_id="${1:-test-session-999}"
  local file="$SANDBOX/.autopilot/session.json"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$file" <<JSON
{
  "session_id": "${session_id}",
  "plan_path": ".autopilot/plan.yaml",
  "current_phase": 1,
  "phase_count": 1,
  "started_at": "${now}"
}
JSON
}

# ---------------------------------------------------------------------------
# AC1: cleanup後 session.json が存在しない — is_session_completed=true
# RED: 現行実装は session.json を archive しないため FAIL する
# ---------------------------------------------------------------------------

@test "ac1: all issues done → session.json が archive へ移動され存在しない" {
  _create_session_json "wave-999-session"
  create_issue_json 100 "done"
  create_issue_json 101 "done"

  run bash "$CLEANUP_SCRIPT" --autopilot-dir "$SANDBOX/.autopilot"

  assert_success
  [[ ! -f "$SANDBOX/.autopilot/session.json" ]]
}

# ---------------------------------------------------------------------------
# AC3: archive ディレクトリに session.json が保存される
# RED: 現行実装は session.json を archive しないため FAIL する
# ---------------------------------------------------------------------------

@test "ac3: all issues done → archive ディレクトリに session.json が保存される" {
  _create_session_json "wave-999-session"
  create_issue_json 200 "done"

  run bash "$CLEANUP_SCRIPT" --autopilot-dir "$SANDBOX/.autopilot"

  assert_success
  # archive/SESSION_ID/session.json が存在すること
  [[ -f "$SANDBOX/.autopilot/archive/wave-999-session/session.json" ]]
}

# ---------------------------------------------------------------------------
# AC4: is_session_completed=false → session.json を archive せず警告
# RED: 現行実装は警告を出さないため FAIL する
# ---------------------------------------------------------------------------

@test "ac4: running issue あり → session.json は archive せず保持、警告を出す" {
  _create_session_json "wave-999-inprogress"
  create_issue_json 300 "done"
  create_issue_json 301 "running"

  run bash "$CLEANUP_SCRIPT" --autopilot-dir "$SANDBOX/.autopilot"

  assert_success
  # session.json は残存すること
  [[ -f "$SANDBOX/.autopilot/session.json" ]]
  # 警告ログが出力されること
  assert_output --partial "WARN"
}

# ---------------------------------------------------------------------------
# AC4 (negative): failed issue のみ (TTL 未到達) → session.json 保持
# ---------------------------------------------------------------------------

@test "ac4-failed: failed issue (TTL 未到達) → session.json 保持" {
  _create_session_json "wave-999-failed"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$SANDBOX/.autopilot/issues/issue-400.json" <<JSON
{
  "issue": 400,
  "status": "failed",
  "branch": "feat/400-test",
  "started_at": "${now}"
}
JSON

  # TTL=99999 (未到達) で実行
  run bash "$CLEANUP_SCRIPT" --autopilot-dir "$SANDBOX/.autopilot" --ttl 99999

  assert_success
  # session.json は残存すること（TTL 未到達 failed は完了とみなさない）
  [[ -f "$SANDBOX/.autopilot/session.json" ]]
}

# ---------------------------------------------------------------------------
# AC5 (regression): 既存 issue state file archive 動作は影響なし
# 現行動作: done → 即 archive、running → スキップ
# GREEN になるはず（既存動作の確認）
# ---------------------------------------------------------------------------

@test "ac5-regression: done issue は引き続き archive される" {
  _create_session_json "wave-999-regression"
  create_issue_json 500 "done"
  create_issue_json 501 "running"

  run bash "$CLEANUP_SCRIPT" --autopilot-dir "$SANDBOX/.autopilot"

  assert_success
  # done issue は archive されること
  [[ -f "$SANDBOX/.autopilot/archive/wave-999-regression/issue-500.json" ]]
  # running issue は残存すること
  [[ -f "$SANDBOX/.autopilot/issues/issue-501.json" ]]
}

@test "ac5-regression: dry-run 時は issue state file を移動しない" {
  _create_session_json "wave-999-dryrun"
  create_issue_json 600 "done"

  run bash "$CLEANUP_SCRIPT" --autopilot-dir "$SANDBOX/.autopilot" --dry-run

  assert_success
  # dry-run では issue file は残存すること
  [[ -f "$SANDBOX/.autopilot/issues/issue-600.json" ]]
  # dry-run では session.json も残存すること
  [[ -f "$SANDBOX/.autopilot/session.json" ]]
}

# ---------------------------------------------------------------------------
# AC6 (integration-style): Wave完了 → session.json archive、in-progress → されない
# Wave完了シミュレーション: 全 issue done
# ---------------------------------------------------------------------------

@test "ac6-positive: Wave 完了後 cleanup → session.json が archive される" {
  _create_session_json "wave-final-999"
  create_issue_json 700 "done"
  create_issue_json 701 "done"
  create_issue_json 702 "done"

  run bash "$CLEANUP_SCRIPT" --autopilot-dir "$SANDBOX/.autopilot"

  assert_success
  [[ ! -f "$SANDBOX/.autopilot/session.json" ]]
  [[ -f "$SANDBOX/.autopilot/archive/wave-final-999/session.json" ]]
}

@test "ac6-negative: in-progress Wave の cleanup → session.json は archive されない" {
  _create_session_json "wave-inprogress-999"
  create_issue_json 800 "done"
  create_issue_json 801 "running"

  run bash "$CLEANUP_SCRIPT" --autopilot-dir "$SANDBOX/.autopilot"

  assert_success
  [[ -f "$SANDBOX/.autopilot/session.json" ]]
  [[ ! -f "$SANDBOX/.autopilot/archive/wave-inprogress-999/session.json" ]]
}
