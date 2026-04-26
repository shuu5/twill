#!/usr/bin/env bats
# is-session-completed.bats
# AC1+AC2: is_session_completed() のシグネチャ確認と 5 ケース
#
# 新仕様:
#   is_session_completed <autopilot_dir>
#   - issues/ dir 不在 → false (fail-closed)
#   - issues/ dir 存在 + ファイル 0 件 → false (race protection, #732 意図保持)
#   - 全 issue-*.json が status=done → true
#   - 一部が status=running/failed/merge-ready/conflict → false
#   - 全 issue が status=merge-ready → false (Pilot クラッシュ後 safety-net)
#
# テスト方式: autopilot-init.sh を SANDBOX で実行して挙動を end-to-end で検証

load '../helpers/common'

# ---------------------------------------------------------------------------
# setup / teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup
  # テスト対象スクリプトを SANDBOX に展開済み（common_setup が copy する）
  SCRIPT="$SANDBOX/scripts/autopilot-init.sh"
  export AUTOPILOT_DIR="$SANDBOX/.autopilot"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: syntax pass + 関数シグネチャ確認
# ===========================================================================

@test "ac1: bash -n autopilot-init.sh が syntax pass する" {
  # RED: 現行実装でも syntax pass するが、新実装後の確認用
  run bash -n "$SCRIPT"
  assert_success
}

@test "ac1: is_session_completed の第1引数は autopilot_dir である（ABI 変更後）" {
  # RED: 現行実装では 'session_file' が第1引数のため FAIL する
  local sig
  sig=$(grep -A2 '^is_session_completed()' "$SCRIPT" | grep 'local ' | head -1)
  # 新実装では "local autopilot_dir" となっているはず
  echo "actual signature line: $sig"
  [[ "$sig" == *"autopilot_dir"* ]]
}

@test "ac1: 呼出元 L80 付近が autopilot_dir を渡す形式になっている" {
  # RED: 現行実装では is_session_completed "$SESSION_FILE" のため FAIL する
  # 新実装では is_session_completed "$AUTOPILOT_DIR" となっているはず
  local callsite
  callsite=$(grep 'is_session_completed' "$SCRIPT" | grep -v '^is_session_completed()')
  echo "actual callsite: $callsite"
  # AUTOPILOT_DIR または autopilot_dir 変数を渡しているはず
  [[ "$callsite" == *"AUTOPILOT_DIR"* ]] || [[ "$callsite" == *"autopilot_dir"* ]]
}

# ===========================================================================
# AC2: 5 ケース（新実装で PASS、現行実装で FAIL）
# ===========================================================================

# ---------------------------------------------------------------------------
# case1: issues/ dir 不在 → false (fail-closed 維持)
# #732 race condition 意図: 新 Wave 開始直後に issues/ が存在しない場合は完了とみなさない
# ---------------------------------------------------------------------------

@test "ac2-case1: issues/ dir 不在 → is_session_completed が false を返す（fail-closed）" {
  # issues/ ディレクトリを削除した状態で実行
  rm -rf "$AUTOPILOT_DIR/issues"
  mkdir -p "$AUTOPILOT_DIR"

  # session.json を配置（呼出元でセッション判定に使われる）
  local started_at
  started_at=$(date -u -d '1 hour ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$AUTOPILOT_DIR/session.json" <<JSON
{
  "session_id": "no-issues-dir",
  "started_at": "${started_at}"
}
JSON

  # autopilot-init.sh を実行すると、is_session_completed が false → exit 1 で停止するはず
  run bash "$SCRIPT"
  assert_failure
  # session.json が残っていること（完了とみなされていない）
  [[ -f "$AUTOPILOT_DIR/session.json" ]]
}

# ---------------------------------------------------------------------------
# case2: issues/ dir 存在 + ファイル 0 件 → false (race protection, #732 意図保持)
# ---------------------------------------------------------------------------

@test "ac2-case2: issues/ dir 存在 + issue-*.json 0 件 → false（race protection #732）" {
  # issues/ ディレクトリは存在するがファイルが 0 件
  mkdir -p "$AUTOPILOT_DIR/issues"

  local started_at
  started_at=$(date -u -d '1 hour ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$AUTOPILOT_DIR/session.json" <<JSON
{
  "session_id": "empty-issues-dir",
  "started_at": "${started_at}"
}
JSON

  run bash "$SCRIPT"
  assert_failure
  # session.json が残っていること（完了とみなされていない）
  [[ -f "$AUTOPILOT_DIR/session.json" ]]
}

# ---------------------------------------------------------------------------
# case3: issues/ dir + 全 issue-*.json が status=done → true
# ---------------------------------------------------------------------------

@test "ac2-case3: 全 issue-*.json が status=done → is_session_completed が true（自動削除が発火）" {
  mkdir -p "$AUTOPILOT_DIR/issues"

  # 全 issue が done
  create_issue_json 101 "done"
  create_issue_json 102 "done"
  create_issue_json 103 "done"

  local started_at
  started_at=$(date -u -d '2 hours ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$AUTOPILOT_DIR/session.json" <<JSON
{
  "session_id": "all-done-issues",
  "started_at": "${started_at}"
}
JSON

  run bash "$SCRIPT"
  # is_session_completed が true → 完了済みとして session.json が削除され、init 続行 → exit 0
  assert_success
  # session.json が削除されていること
  [[ ! -f "$AUTOPILOT_DIR/session.json" ]]
}

# case3 補足: issue-*.json 削除も確認
@test "ac2-case3: 全 done → 自動削除後に issue-*.json も削除される" {
  mkdir -p "$AUTOPILOT_DIR/issues"

  create_issue_json 201 "done"
  create_issue_json 202 "done"

  local started_at
  started_at=$(date -u -d '3 hours ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$AUTOPILOT_DIR/session.json" <<JSON
{
  "session_id": "all-done-cleanup",
  "started_at": "${started_at}"
}
JSON

  run bash "$SCRIPT"
  assert_success
  [[ ! -f "$AUTOPILOT_DIR/issues/issue-201.json" ]]
  [[ ! -f "$AUTOPILOT_DIR/issues/issue-202.json" ]]
}

# ---------------------------------------------------------------------------
# case4: issues/ dir + 一部が status=running/failed/merge-ready/conflict → false
# ---------------------------------------------------------------------------

@test "ac2-case4a: 一部 issue が status=running → false（自動削除しない）" {
  mkdir -p "$AUTOPILOT_DIR/issues"

  create_issue_json 301 "done"
  create_issue_json 302 "running"

  local started_at
  started_at=$(date -u -d '1 hour ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$AUTOPILOT_DIR/session.json" <<JSON
{
  "session_id": "partial-running",
  "started_at": "${started_at}"
}
JSON

  run bash "$SCRIPT"
  assert_failure
  [[ -f "$AUTOPILOT_DIR/session.json" ]]
}

@test "ac2-case4b: 一部 issue が status=failed → false" {
  mkdir -p "$AUTOPILOT_DIR/issues"

  create_issue_json 401 "done"
  create_issue_json 402 "failed"

  local started_at
  started_at=$(date -u -d '1 hour ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$AUTOPILOT_DIR/session.json" <<JSON
{
  "session_id": "partial-failed",
  "started_at": "${started_at}"
}
JSON

  run bash "$SCRIPT"
  assert_failure
  [[ -f "$AUTOPILOT_DIR/session.json" ]]
}

@test "ac2-case4c: 一部 issue が status=merge-ready → false" {
  mkdir -p "$AUTOPILOT_DIR/issues"

  create_issue_json 501 "done"
  create_issue_json 502 "merge-ready"

  local started_at
  started_at=$(date -u -d '1 hour ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$AUTOPILOT_DIR/session.json" <<JSON
{
  "session_id": "partial-merge-ready",
  "started_at": "${started_at}"
}
JSON

  run bash "$SCRIPT"
  assert_failure
  [[ -f "$AUTOPILOT_DIR/session.json" ]]
}

@test "ac2-case4d: 一部 issue が status=conflict → false" {
  mkdir -p "$AUTOPILOT_DIR/issues"

  create_issue_json 601 "done"
  create_issue_json 602 "conflict"

  local started_at
  started_at=$(date -u -d '1 hour ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$AUTOPILOT_DIR/session.json" <<JSON
{
  "session_id": "partial-conflict",
  "started_at": "${started_at}"
}
JSON

  run bash "$SCRIPT"
  assert_failure
  [[ -f "$AUTOPILOT_DIR/session.json" ]]
}

# ---------------------------------------------------------------------------
# case5: 全 issue が status=merge-ready → false (Pilot クラッシュ後 safety-net)
# ---------------------------------------------------------------------------

@test "ac2-case5: 全 issue が status=merge-ready → false（Pilot クラッシュ後 safety-net）" {
  mkdir -p "$AUTOPILOT_DIR/issues"

  create_issue_json 701 "merge-ready"
  create_issue_json 702 "merge-ready"
  create_issue_json 703 "merge-ready"

  local started_at
  started_at=$(date -u -d '1 hour ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$AUTOPILOT_DIR/session.json" <<JSON
{
  "session_id": "all-merge-ready-safety",
  "started_at": "${started_at}"
}
JSON

  run bash "$SCRIPT"
  assert_failure
  # session.json は削除されていないこと（Pilot クラッシュ後の安全網）
  [[ -f "$AUTOPILOT_DIR/session.json" ]]
}

# case5 補足: exit code が 1（実行中エラー）であること
@test "ac2-case5: 全 merge-ready → exit 1 で停止（done 扱いしない）" {
  mkdir -p "$AUTOPILOT_DIR/issues"

  create_issue_json 801 "merge-ready"

  local started_at
  started_at=$(date -u -d '1 hour ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$AUTOPILOT_DIR/session.json" <<JSON
{
  "session_id": "single-merge-ready",
  "started_at": "${started_at}"
}
JSON

  run bash "$SCRIPT"
  assert_failure
  [ "$status" -eq 1 ]
}
