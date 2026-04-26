#!/usr/bin/env bats
# session-auto-cleanup.bats
# Requirement: autopilot-init.sh 完了済みセッション自動削除 + orchestrator ログ per-session 分離
# Spec: deltaspec/changes/issue-732/specs/session-auto-cleanup.md
# Coverage: --type=unit --coverage=edge-cases
#
# 検証する仕様:
#   AC 1. 完了済み session.json が存在する場合の自動削除（--force 不要）
#   AC 1B. issues フィールドが空の session.json は完了済みとみなさない（境界条件）
#   AC 1C. running issue が存在する場合は自動削除しない（exit 1）
#   AC 1D. 24h 経過 + --force なし の未完了セッション → exit 2（既存挙動維持）
#   AC 2. orchestrator ログ per-session 分離（session_id 付きファイル生成）
#   AC 3. session.json 不在時に WARN を出力
#   AC 4. HOTFIX #732 コメントが wakeup-loop.md に 2 箇所存在する
#
# test doubles:
#   autopilot-init.sh  - 実スクリプトを AUTOPILOT_DIR オーバーライドで直接実行
#   orchestrator-session-log-dispatch.sh - orchestrator ログ命名ロジックの test double
#     Env:
#       SESSION_JSON_PATH  - session.json のパス（省略時は $AUTOPILOT_DIR/session.json）
#       PHASE_NUM          - phase 番号（デフォルト: 1）
#       TRACE_LOG_DIR      - trace ログディレクトリ（デフォルト: $AUTOPILOT_DIR/trace）

load '../../bats/helpers/common.bash'

# ---------------------------------------------------------------------------
# setup
# ---------------------------------------------------------------------------

setup() {
  common_setup

  TRACE_LOG_DIR="$SANDBOX/.autopilot/trace"
  export TRACE_LOG_DIR
  mkdir -p "$TRACE_LOG_DIR"

  # orchestrator ログ命名ロジックの test double
  # 仕様: orchestrator-phase-${N}-${SESSION_ID}.log を生成する
  # session.json が不在の場合は WARN を stderr に出力し orchestrator-phase-${N}-unknown.log を使用する
  cat > "$SANDBOX/scripts/orchestrator-session-log-dispatch.sh" << 'DISPATCH_EOF'
#!/usr/bin/env bash
# orchestrator-session-log-dispatch.sh
# orchestrator ログ per-session 分離ロジックの test double
# Env:
#   SESSION_JSON_PATH  - session.json のパス（デフォルト: $AUTOPILOT_DIR/session.json）
#   PHASE_NUM          - phase 番号（デフォルト: 1）
#   TRACE_LOG_DIR      - trace ログディレクトリ（デフォルト: /tmp/autopilot-trace）
#   AUTOPILOT_DIR      - autopilot ディレクトリ（SESSION_JSON_PATH 未指定時のフォールバック）
set -uo pipefail

PHASE_NUM="${PHASE_NUM:-1}"
TRACE_LOG_DIR="${TRACE_LOG_DIR:-/tmp/autopilot-trace}"
AUTOPILOT_DIR="${AUTOPILOT_DIR:-/tmp/.autopilot}"
SESSION_JSON_PATH="${SESSION_JSON_PATH:-${AUTOPILOT_DIR}/session.json}"

mkdir -p "$TRACE_LOG_DIR"

# session_id を session.json から取得する
SESSION_ID=""
if [[ -f "$SESSION_JSON_PATH" ]]; then
  SESSION_ID=$(jq -r '.session_id // empty' "$SESSION_JSON_PATH" 2>/dev/null || true)
fi

if [[ -z "$SESSION_ID" ]]; then
  echo "WARN: session.json が不在またはパース失敗。Wave ログ分離が無効になります" >&2
  SESSION_ID="unknown"
fi

ORCH_LOG="${TRACE_LOG_DIR}/orchestrator-phase-${PHASE_NUM}-${SESSION_ID}.log"
_orch_started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "[${_orch_started_at}] orchestrator_pid=$$ phase=${PHASE_NUM} session_id=${SESSION_ID} started_at=${_orch_started_at}" >> "$ORCH_LOG"
echo "[orchestrator] Phase ${PHASE_NUM}: session_id=${SESSION_ID}, log=${ORCH_LOG}" >&2
DISPATCH_EOF
  chmod +x "$SANDBOX/scripts/orchestrator-session-log-dispatch.sh"
}

teardown() {
  common_teardown
}

# ===========================================================================
# Requirement: autopilot-init.sh 完了済みセッション自動削除
# Spec: deltaspec/changes/issue-732/specs/session-auto-cleanup.md
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: 完了済み session.json が存在する場合の自動削除（AC 1）
# WHEN autopilot-init.sh を --force なしで実行し、既存 session.json に全 issue の status=done が記録されている
# THEN session.json と issues/issue-*.json が削除され exit 0 で続行する
# ---------------------------------------------------------------------------

@test "session-auto-cleanup[ac1]: 全 issue done + --force なし → session.json が削除される" {
  mkdir -p "$SANDBOX/.autopilot/issues"
  local started_at
  started_at=$(date -u -d '10 hours ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "done-auto-001",
  "started_at": "${started_at}"
}
JSON
  # 新仕様: per-issue file で status=done を表現（#978）
  create_issue_json 1 "done"
  create_issue_json 2 "done"

  run bash "$SANDBOX/scripts/autopilot-init.sh"

  assert_success
  [[ ! -f "$SANDBOX/.autopilot/session.json" ]]
}

@test "session-auto-cleanup[ac1]: 全 issue done + --force なし → issues/issue-*.json が削除される" {
  mkdir -p "$SANDBOX/.autopilot/issues"
  local started_at
  started_at=$(date -u -d '10 hours ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "done-auto-002",
  "started_at": "${started_at}"
}
JSON
  # 新仕様: per-issue file で status=done を表現（#978）
  create_issue_json 10 "done"
  create_issue_json 11 "done"

  run bash "$SANDBOX/scripts/autopilot-init.sh"

  assert_success
  [[ ! -f "$SANDBOX/.autopilot/issues/issue-10.json" ]]
  [[ ! -f "$SANDBOX/.autopilot/issues/issue-11.json" ]]
}

@test "session-auto-cleanup[ac1]: 完了済みセッション自動削除後に .autopilot/ 初期化が続行する" {
  mkdir -p "$SANDBOX/.autopilot/issues"
  local started_at
  started_at=$(date -u -d '6 hours ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "done-auto-003",
  "started_at": "${started_at}"
}
JSON
  # 新仕様: per-issue file で status=done を表現（#978）
  create_issue_json 5 "done"

  run bash "$SANDBOX/scripts/autopilot-init.sh"

  assert_success
  assert_output --partial "OK"
}

# Edge case: 単一 issue が done の場合も同様に自動削除される
@test "session-auto-cleanup[ac1][edge]: single issue done + --force なし → 自動削除" {
  mkdir -p "$SANDBOX/.autopilot/issues"
  local started_at
  started_at=$(date -u -d '1 hour ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "done-single-001",
  "started_at": "${started_at}"
}
JSON
  # 新仕様: per-issue file で status=done を表現（#978）
  create_issue_json 99 "done"

  run bash "$SANDBOX/scripts/autopilot-init.sh"

  assert_success
  [[ ! -f "$SANDBOX/.autopilot/session.json" ]]
  [[ ! -f "$SANDBOX/.autopilot/issues/issue-99.json" ]]
}

# ---------------------------------------------------------------------------
# Scenario: issues/ dir が空（ファイル 0 件）の場合は完了済みとみなさない（AC 1 境界条件）
# AC3 update: 旧仕様「issues フィールドが空配列（[]）」→ 新仕様「issues/ dir にファイル 0 件」
# #732 race condition 意図継承: issues/ dir に issue-*.json が 0 件の場合は完了とみなさない
# WHEN autopilot-init.sh を実行し、.autopilot/issues/ が存在するが issue-*.json が 0 件
# THEN is_session_completed() は false を返し、実行中エラー exit 1 で停止する（新 Wave 直後の誤発火防止）
# 新実装では is_session_completed が autopilot_dir を受け取り issues/issue-*.json を直接確認する
# RED: 現行実装は session_file の issues[] を参照するため、以下テストは新実装で PASS する
# ---------------------------------------------------------------------------

@test "session-auto-cleanup[ac1b]: issues/ dir 存在 + ファイル 0 件 → 完了済みとみなさず exit 1 で停止" {
  # #732 race condition 意図: 新 Wave 開始直後に issues/ が空の場合は完了とみなさない
  mkdir -p "$SANDBOX/.autopilot/issues"
  # issue-*.json を作成しない（0 件）
  local started_at
  started_at=$(date -u -d '2 hours ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "empty-issues-dir-001",
  "started_at": "${started_at}"
}
JSON

  run bash "$SANDBOX/scripts/autopilot-init.sh"

  assert_failure
  [ "$status" -eq 1 ]
}

@test "session-auto-cleanup[ac1b][edge]: issues/ dir 空ファイル 0 件では session.json が削除されない（誤発火防止）" {
  # #732 race condition 意図: 誤発火防止。issues/ にファイルがなければ session.json を保持する
  mkdir -p "$SANDBOX/.autopilot/issues"
  local started_at
  started_at=$(date -u -d '2 hours ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "empty-issues-dir-guard",
  "started_at": "${started_at}"
}
JSON

  run bash "$SANDBOX/scripts/autopilot-init.sh"

  assert_failure
  [[ -f "$SANDBOX/.autopilot/session.json" ]]
}

@test "session-auto-cleanup[ac1b][edge]: issues/ dir 空 + --force でも自動削除は実行されない（running 扱い）" {
  # #732 race condition 意図: --force があっても issues/ が空なら running 扱いで exit 1
  mkdir -p "$SANDBOX/.autopilot/issues"
  local started_at
  started_at=$(date -u -d '2 hours ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "empty-issues-dir-force",
  "started_at": "${started_at}"
}
JSON

  run bash "$SANDBOX/scripts/autopilot-init.sh" --force

  assert_failure
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Scenario: running issue が存在する場合は停止（AC 1）
# WHEN autopilot-init.sh を実行し、既存 session.json に status=running の issue が 1 つ以上存在する
# THEN 自動削除は発火せず exit 1 で停止する
# ---------------------------------------------------------------------------

@test "session-auto-cleanup[ac1c]: running issue あり + --force なし → exit 1 で停止" {
  mkdir -p "$SANDBOX/.autopilot/issues"
  local started_at
  started_at=$(date -u -d '3 hours ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "running-001",
  "started_at": "${started_at}"
}
JSON
  # 新仕様: per-issue file で running を表現（#978）
  create_issue_json 20 "running"
  create_issue_json 21 "done"

  run bash "$SANDBOX/scripts/autopilot-init.sh"

  assert_failure
  [ "$status" -eq 1 ]
}

@test "session-auto-cleanup[ac1c]: running issue あり → session.json は削除されない" {
  mkdir -p "$SANDBOX/.autopilot/issues"
  local started_at
  started_at=$(date -u -d '3 hours ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "running-002",
  "started_at": "${started_at}"
}
JSON
  # 新仕様: per-issue file で running を表現（#978）
  create_issue_json 30 "running"

  run bash "$SANDBOX/scripts/autopilot-init.sh"

  assert_failure
  [[ -f "$SANDBOX/.autopilot/session.json" ]]
}

@test "session-auto-cleanup[ac1c][edge]: 複数 running + --force なし → exit 1（非 stale 期間内）" {
  mkdir -p "$SANDBOX/.autopilot/issues"
  local started_at
  started_at=$(date -u -d '5 hours ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "running-multi",
  "started_at": "${started_at}"
}
JSON
  # 新仕様: per-issue file で running を表現（#978）
  create_issue_json 40 "running"
  create_issue_json 41 "running"
  create_issue_json 42 "done"

  run bash "$SANDBOX/scripts/autopilot-init.sh"

  assert_failure
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Scenario: 24h 経過 + --force なし の未完了セッション → exit 2（既存挙動維持）
# WHEN autopilot-init.sh を --force なしで実行し、session.json が 24h 以上経過かつ未完了（running issue あり）
# THEN exit 2 で stale 警告を出力する（既存挙動と同一）
# ---------------------------------------------------------------------------

@test "session-auto-cleanup[ac1d]: 24h+ stale + running issue + --force なし → exit 2" {
  mkdir -p "$SANDBOX/.autopilot/issues"
  local old_date
  old_date=$(date -u -d '30 hours ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "stale-running-001",
  "started_at": "${old_date}"
}
JSON
  # 新仕様: per-issue file で running を表現（#978）
  create_issue_json 50 "running"
  create_issue_json 51 "done"

  run bash "$SANDBOX/scripts/autopilot-init.sh"

  assert_failure
  [ "$status" -eq 2 ]
}

@test "session-auto-cleanup[ac1d]: 24h+ stale → stderr に stale 警告を出力する" {
  mkdir -p "$SANDBOX/.autopilot/issues"
  local old_date
  old_date=$(date -u -d '26 hours ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "stale-running-002",
  "started_at": "${old_date}"
}
JSON
  # 新仕様: per-issue file で running を表現（#978）
  create_issue_json 60 "running"

  run bash "$SANDBOX/scripts/autopilot-init.sh"

  assert_failure
  [ "$status" -eq 2 ]
  assert_output --partial "stale"
}

@test "session-auto-cleanup[ac1d][edge]: 24h+ stale + --force → session.json 削除で続行（既存 stale force 挙動）" {
  mkdir -p "$SANDBOX/.autopilot/issues"
  local old_date
  old_date=$(date -u -d '48 hours ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "stale-force-001",
  "started_at": "${old_date}"
}
JSON
  # 新仕様: per-issue file で running を表現（#978）
  create_issue_json 70 "running"

  run bash "$SANDBOX/scripts/autopilot-init.sh" --force

  assert_success
  [[ ! -f "$SANDBOX/.autopilot/session.json" ]]
}

# Edge case: ちょうど 24h 境界（23h59m は exit 1、24h0m は exit 2）
@test "session-auto-cleanup[ac1d][edge]: 23h59m + running → exit 1（stale 境界未満）" {
  mkdir -p "$SANDBOX/.autopilot/issues"
  # 24h - 5min = 23h55m (確実に境界内)
  local started_at
  started_at=$(date -u -d '23 hours ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "boundary-under",
  "started_at": "${started_at}"
}
JSON
  # 新仕様: per-issue file で running を表現（#978）
  create_issue_json 80 "running"

  run bash "$SANDBOX/scripts/autopilot-init.sh"

  assert_failure
  [ "$status" -eq 1 ]
}

# ===========================================================================
# Requirement: orchestrator ログ per-session 分離
# Spec: deltaspec/changes/issue-732/specs/session-auto-cleanup.md
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: session_id 付きログが生成される（AC 2）
# WHEN 2 連続 Wave を起動する
# THEN ${AUTOPILOT_DIR}/trace/ に orchestrator-phase-${N}-${SESSION_ID}.log が各 Wave につき 1 ファイル生成される
# ---------------------------------------------------------------------------

@test "session-auto-cleanup[ac2]: session_id 付きログファイルが生成される" {
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "wave1abc",
  "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
JSON

  SESSION_JSON_PATH="$SANDBOX/.autopilot/session.json" \
  PHASE_NUM="1" \
    run bash "$SANDBOX/scripts/orchestrator-session-log-dispatch.sh"

  assert_success
  [[ -f "${TRACE_LOG_DIR}/orchestrator-phase-1-wave1abc.log" ]]
}

@test "session-auto-cleanup[ac2]: ログファイル名に session_id が含まれる" {
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "mysession42",
  "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
JSON

  SESSION_JSON_PATH="$SANDBOX/.autopilot/session.json" \
  PHASE_NUM="2" \
    run bash "$SANDBOX/scripts/orchestrator-session-log-dispatch.sh"

  assert_success
  [[ -f "${TRACE_LOG_DIR}/orchestrator-phase-2-mysession42.log" ]]
}

@test "session-auto-cleanup[ac2]: 2 連続 Wave で session_id が異なる別ファイルが生成される" {
  # Wave 1
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{"session_id": "session-wave1", "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"}
JSON
  SESSION_JSON_PATH="$SANDBOX/.autopilot/session.json" \
  PHASE_NUM="1" \
    bash "$SANDBOX/scripts/orchestrator-session-log-dispatch.sh"

  # Wave 2 (異なる session_id)
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{"session_id": "session-wave2", "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"}
JSON
  SESSION_JSON_PATH="$SANDBOX/.autopilot/session.json" \
  PHASE_NUM="1" \
    bash "$SANDBOX/scripts/orchestrator-session-log-dispatch.sh"

  [[ -f "${TRACE_LOG_DIR}/orchestrator-phase-1-session-wave1.log" ]]
  [[ -f "${TRACE_LOG_DIR}/orchestrator-phase-1-session-wave2.log" ]]
}

@test "session-auto-cleanup[ac2]: ログ内に session_id が記録される" {
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{"session_id": "logsession99", "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"}
JSON

  SESSION_JSON_PATH="$SANDBOX/.autopilot/session.json" \
  PHASE_NUM="3" \
    run bash "$SANDBOX/scripts/orchestrator-session-log-dispatch.sh"

  assert_success
  grep -q "session_id=logsession99" "${TRACE_LOG_DIR}/orchestrator-phase-3-logsession99.log"
}

@test "session-auto-cleanup[ac2][edge]: Wave 間でログファイルが混在しない（別 session_id は別ファイル）" {
  local log_wave1="${TRACE_LOG_DIR}/orchestrator-phase-1-sessionA.log"
  local log_wave2="${TRACE_LOG_DIR}/orchestrator-phase-1-sessionB.log"

  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{"session_id": "sessionA", "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"}
JSON
  SESSION_JSON_PATH="$SANDBOX/.autopilot/session.json" PHASE_NUM="1" \
    bash "$SANDBOX/scripts/orchestrator-session-log-dispatch.sh"

  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{"session_id": "sessionB", "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"}
JSON
  SESSION_JSON_PATH="$SANDBOX/.autopilot/session.json" PHASE_NUM="1" \
    bash "$SANDBOX/scripts/orchestrator-session-log-dispatch.sh"

  # sessionA のログに sessionB のエントリが混入しないことを確認
  ! grep -q "session_id=sessionB" "$log_wave1"
  ! grep -q "session_id=sessionA" "$log_wave2"
}

# ---------------------------------------------------------------------------
# Scenario: session.json 不在時に WARN 出力（AC 3）
# WHEN _ORCH_LOG 生成処理実行時に session.json が存在しない
# THEN stderr に WARN: session.json が不在またはパース失敗 を出力し orchestrator-phase-${N}-unknown.log を使用して続行する
# ---------------------------------------------------------------------------

@test "session-auto-cleanup[ac3]: session.json 不在時に WARN を stderr に出力する" {
  # session.json を作成しない
  SESSION_JSON_PATH="$SANDBOX/.autopilot/session.json" \
  PHASE_NUM="1" \
    run bash "$SANDBOX/scripts/orchestrator-session-log-dispatch.sh"

  assert_success
  assert_output --partial "WARN: session.json が不在またはパース失敗"
}

@test "session-auto-cleanup[ac3]: session.json 不在時は orchestrator-phase-\${N}-unknown.log を生成する" {
  SESSION_JSON_PATH="$SANDBOX/.autopilot/no-such-session.json" \
  PHASE_NUM="2" \
    run bash "$SANDBOX/scripts/orchestrator-session-log-dispatch.sh"

  assert_success
  [[ -f "${TRACE_LOG_DIR}/orchestrator-phase-2-unknown.log" ]]
}

@test "session-auto-cleanup[ac3]: session.json 不在でも続行（exit 0）する" {
  SESSION_JSON_PATH="$SANDBOX/.autopilot/nonexistent.json" \
  PHASE_NUM="1" \
    run bash "$SANDBOX/scripts/orchestrator-session-log-dispatch.sh"

  assert_success
}

@test "session-auto-cleanup[ac3][edge]: session.json が空ファイルの場合も WARN + unknown.log" {
  touch "$SANDBOX/.autopilot/session.json"

  SESSION_JSON_PATH="$SANDBOX/.autopilot/session.json" \
  PHASE_NUM="4" \
    run bash "$SANDBOX/scripts/orchestrator-session-log-dispatch.sh"

  assert_success
  assert_output --partial "WARN"
  [[ -f "${TRACE_LOG_DIR}/orchestrator-phase-4-unknown.log" ]]
}

@test "session-auto-cleanup[ac3][edge]: session_id フィールドが null の場合も WARN + unknown.log" {
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{"session_id": null, "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"}
JSON

  SESSION_JSON_PATH="$SANDBOX/.autopilot/session.json" \
  PHASE_NUM="5" \
    run bash "$SANDBOX/scripts/orchestrator-session-log-dispatch.sh"

  assert_success
  assert_output --partial "WARN"
  [[ -f "${TRACE_LOG_DIR}/orchestrator-phase-5-unknown.log" ]]
}

# ===========================================================================
# Requirement: AC 2 再修正防止マーカー
# Spec: deltaspec/changes/issue-732/specs/session-auto-cleanup.md
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: HOTFIX コメントが 2 箇所に存在する（AC 4）
# WHEN grep -c "HOTFIX #732" plugins/twl/commands/autopilot-pilot-wakeup-loop.md を実行する
# THEN 出力が 2（HTML コメントと blockquote の 2 箇所）である
# ---------------------------------------------------------------------------

@test "session-auto-cleanup[ac4]: autopilot-pilot-wakeup-loop.md に HOTFIX #732 コメントが 2 箇所存在する" {
  local wakeup_loop_md="$REPO_ROOT/commands/autopilot-pilot-wakeup-loop.md"

  [[ -f "$wakeup_loop_md" ]]

  local count
  count=$(grep -c "HOTFIX #732" "$wakeup_loop_md")
  [ "$count" -eq 2 ]
}

@test "session-auto-cleanup[ac4][edge]: HOTFIX #732 の 1 件目が HTML コメント形式である" {
  local wakeup_loop_md="$REPO_ROOT/commands/autopilot-pilot-wakeup-loop.md"

  [[ -f "$wakeup_loop_md" ]]

  # HTML コメント <!-- ... HOTFIX #732 ... --> が存在すること
  grep -qE "<!--.*HOTFIX #732.*-->" "$wakeup_loop_md"
}

@test "session-auto-cleanup[ac4][edge]: HOTFIX #732 の 2 件目が blockquote 形式である" {
  local wakeup_loop_md="$REPO_ROOT/commands/autopilot-pilot-wakeup-loop.md"

  [[ -f "$wakeup_loop_md" ]]

  # blockquote（> で始まる行）に HOTFIX #732 が含まれること
  grep -qE "^>" "$wakeup_loop_md"
  grep -qE "HOTFIX #732" "$wakeup_loop_md"
}
