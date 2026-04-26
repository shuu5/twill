#!/usr/bin/env bats
# autopilot-init-cleanup.bats
# AC4: integration test - autopilot-init.sh の実環境再現
#
# RED フェーズ: 現行実装（session.json の issues[] を参照）では FAIL する。
# 新実装（per-issue file .autopilot/issues/issue-*.json を参照）に切り替えると PASS する。
#
# テスト戦略:
#   - .autopilot/issues/issue-*.json を持つ実環境を sandbox で再現する
#   - autopilot-init.sh を実行して session.json と issue-*.json の両方が削除されることを確認する
#   - archive/ の residual session.json フィクスチャ構造を参考に fixture を構築する

# bats では BATS_TEST_FILENAME が実ファイルの絶対パスを持つ
_INTEGRATION_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
_TESTS_DIR="$(cd "$_INTEGRATION_DIR/.." && pwd)"
REPO_ROOT="$(cd "$_TESTS_DIR/.." && pwd)"
_LIB_DIR="$_TESTS_DIR/lib"

load "${_LIB_DIR}/bats-support/load"
load "${_LIB_DIR}/bats-assert/load"

# ---------------------------------------------------------------------------
# setup / teardown
# ---------------------------------------------------------------------------

setup() {
  SANDBOX="$(mktemp -d)"
  export SANDBOX

  mkdir -p "$SANDBOX/scripts"
  mkdir -p "$SANDBOX/.autopilot/issues"
  mkdir -p "$SANDBOX/.autopilot/archive"

  # スクリプトをコピー
  cp "$REPO_ROOT/scripts/"*.sh "$SANDBOX/scripts/" 2>/dev/null || true

  export AUTOPILOT_DIR="$SANDBOX/.autopilot"
  export PROJECT_ROOT="$SANDBOX"

  SCRIPT="$SANDBOX/scripts/autopilot-init.sh"
}

teardown() {
  if [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]]; then
    rm -rf "$SANDBOX"
  fi
}

# ---------------------------------------------------------------------------
# Helper: issue-*.json fixture を作成する
# ---------------------------------------------------------------------------

_create_issue_file() {
  local issue_num="$1"
  local status="$2"
  local file="$SANDBOX/.autopilot/issues/issue-${issue_num}.json"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$file" <<JSON
{
  "issue": ${issue_num},
  "status": "${status}",
  "branch": "feat/${issue_num}-test",
  "pr": null,
  "started_at": "${now}",
  "current_step": "",
  "retry_count": 0,
  "merged_at": null
}
JSON
}

# ---------------------------------------------------------------------------
# Integration Scenario 1: 全 issue done → 実環境再現で自動削除が発火する
# GIVEN: .autopilot/issues/ に issue-*.json が複数存在し、全て status=done
# WHEN: autopilot-init.sh を実行する
# THEN: session.json と issues/issue-*.json が両方削除される
# ---------------------------------------------------------------------------

@test "integration[ac4]: 全 issue done → session.json が自動削除される" {
  # RED: 現行実装は session.json の issues[] を参照するため、
  #      issues[] を持たない session.json では is_session_completed が false を返す
  local started_at
  started_at=$(date -u -d '5 hours ago' +"%Y-%m-%dT%H:%M:%SZ")

  # session.json は新仕様: issues[] フィールドを持たない（per-issue file に移行済み）
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "integration-done-001",
  "plan_path": ".autopilot/plan.yaml",
  "current_phase": 1,
  "phase_count": 1,
  "started_at": "${started_at}"
}
JSON

  # per-issue file を配置（全て status=done）
  _create_issue_file 978 "done"
  _create_issue_file 979 "done"
  _create_issue_file 980 "done"

  run bash "$SCRIPT"

  assert_success
  [[ ! -f "$SANDBOX/.autopilot/session.json" ]]
}

@test "integration[ac4]: 全 issue done → issues/issue-*.json が全て削除される" {
  local started_at
  started_at=$(date -u -d '3 hours ago' +"%Y-%m-%dT%H:%M:%SZ")

  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "integration-done-002",
  "started_at": "${started_at}"
}
JSON

  _create_issue_file 100 "done"
  _create_issue_file 200 "done"

  run bash "$SCRIPT"

  assert_success
  [[ ! -f "$SANDBOX/.autopilot/issues/issue-100.json" ]]
  [[ ! -f "$SANDBOX/.autopilot/issues/issue-200.json" ]]
}

@test "integration[ac4]: 全 issue done → 自動削除後に .autopilot/ 初期化が続行する" {
  local started_at
  started_at=$(date -u -d '2 hours ago' +"%Y-%m-%dT%H:%M:%SZ")

  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "integration-done-003",
  "started_at": "${started_at}"
}
JSON

  _create_issue_file 301 "done"

  run bash "$SCRIPT"

  assert_success
  assert_output --partial "OK"
  # 初期化後にディレクトリ構造が再作成されていること
  [[ -d "$SANDBOX/.autopilot/issues" ]]
  [[ -d "$SANDBOX/.autopilot/archive" ]]
}

# ---------------------------------------------------------------------------
# Integration Scenario 2: wave-b-final 相当の残留セッション再現
# GIVEN: 前 Wave の issue-*.json が残留した状態（archive 構造を参考にした fixture）
# WHEN: 全 issue が done になった後に autopilot-init.sh を実行
# THEN: クリーンアップされて新 Wave が開始できる
# ---------------------------------------------------------------------------

@test "integration[ac4]: wave-b-final 相当の残留セッション → 全 done で自動削除" {
  # archive の wave-22b 構造を参考にした fixture
  # session.json は新仕様（issues[] なし）、issue-*.json が done 状態
  local started_at
  started_at=$(date -u -d '12 hours ago' +"%Y-%m-%dT%H:%M:%SZ")

  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "wave-b-final-fixture",
  "plan_path": ".autopilot/plan.yaml",
  "current_phase": 1,
  "phase_count": 1,
  "started_at": "${started_at}",
  "cross_issue_warnings": [],
  "phase_insights": [],
  "patterns": {},
  "self_improve_issues": [],
  "retrospectives": [
    {
      "phase": 1,
      "results": "done=3/3",
      "insights": "全 issue 完了"
    }
  ]
}
JSON

  # 複数 issue が done（実際の Wave 完了後の状態を再現）
  _create_issue_file 652 "done"
  _create_issue_file 731 "done"
  _create_issue_file 732 "done"

  run bash "$SCRIPT"

  assert_success
  [[ ! -f "$SANDBOX/.autopilot/session.json" ]]
  [[ ! -f "$SANDBOX/.autopilot/issues/issue-652.json" ]]
  [[ ! -f "$SANDBOX/.autopilot/issues/issue-731.json" ]]
  [[ ! -f "$SANDBOX/.autopilot/issues/issue-732.json" ]]
}

# ---------------------------------------------------------------------------
# Integration Scenario 3: 混在状態（running あり）では自動削除しない
# GIVEN: issues/ に done と running が混在
# WHEN: autopilot-init.sh を実行
# THEN: exit 1 で停止し、session.json と issue-*.json が保持される
# ---------------------------------------------------------------------------

@test "integration[ac4]: done + running 混在 → 自動削除しない（exit 1）" {
  local started_at
  started_at=$(date -u -d '1 hour ago' +"%Y-%m-%dT%H:%M:%SZ")

  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "integration-mixed-001",
  "started_at": "${started_at}"
}
JSON

  _create_issue_file 401 "done"
  _create_issue_file 402 "running"  # 実行中の issue が残っている

  run bash "$SCRIPT"

  assert_failure
  [ "$status" -eq 1 ]
  [[ -f "$SANDBOX/.autopilot/session.json" ]]
  [[ -f "$SANDBOX/.autopilot/issues/issue-401.json" ]]
  [[ -f "$SANDBOX/.autopilot/issues/issue-402.json" ]]
}

# ---------------------------------------------------------------------------
# Integration Scenario 4: issues/ dir 不在（新 Wave 開始直後）
# GIVEN: session.json は存在するが issues/ dir がない（新 Wave 直後の race condition）
# WHEN: autopilot-init.sh を実行
# THEN: fail-closed で exit 1 → session.json が保持される
# ---------------------------------------------------------------------------

@test "integration[ac4]: issues/ dir 不在（新 Wave race condition）→ fail-closed で exit 1" {
  # #732 race condition 意図: issues/ dir がない状態は完了とみなさない
  local started_at
  started_at=$(date -u -d '30 minutes ago' +"%Y-%m-%dT%H:%M:%SZ")

  rm -rf "$SANDBOX/.autopilot/issues"
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "integration-no-issues-dir",
  "started_at": "${started_at}"
}
JSON

  run bash "$SCRIPT"

  assert_failure
  [ "$status" -eq 1 ]
  [[ -f "$SANDBOX/.autopilot/session.json" ]]
}

# ---------------------------------------------------------------------------
# Integration Scenario 5: 全 merge-ready（Pilot クラッシュ後 safety-net）
# GIVEN: 全 issue が merge-ready（Pilot がクラッシュして merge できなかった状態）
# WHEN: autopilot-init.sh を実行
# THEN: exit 1 で停止（done ではないため自動削除しない）
# ---------------------------------------------------------------------------

@test "integration[ac4]: 全 merge-ready → Pilot クラッシュ safety-net で exit 1" {
  local started_at
  started_at=$(date -u -d '4 hours ago' +"%Y-%m-%dT%H:%M:%SZ")

  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "integration-all-merge-ready",
  "started_at": "${started_at}"
}
JSON

  _create_issue_file 501 "merge-ready"
  _create_issue_file 502 "merge-ready"

  run bash "$SCRIPT"

  assert_failure
  [ "$status" -eq 1 ]
  [[ -f "$SANDBOX/.autopilot/session.json" ]]
}
