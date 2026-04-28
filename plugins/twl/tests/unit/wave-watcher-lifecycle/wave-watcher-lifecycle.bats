#!/usr/bin/env bats
# wave-watcher-lifecycle.bats — RED tests for Issue #1052
#
# tech-debt(observer): Wave 完遂後の watcher/Monitor 自動停止不在 +
#                      STAGNATE 過剰 emit で 960k token 膨張
#
# 検証する AC:
#   AC1: wave-collect 後の watcher/Monitor 自動停止
#        - .supervisor/wave-<N>-task-ids.json に記録された Monitor task ID を TaskStop で停止
#        - .supervisor/wave-<N>-watcher-pids.json に記録された PID を kill -TERM で停止
#        - spawn-controller.sh が起動時に task ID と PID を上記ファイルに記録する
#   AC2: STAGNATE-600 suppress 条件の追加
#        - Pilot pane の最終 capture に [PHASE-COMPLETE] または >>> 実装完了: が含まれる場合 suppress
#        - .autopilot/session.json の status が completed または archived の場合 suppress
#        - session-end ファイルが存在する場合 suppress
#   AC3: events/ クリーンアップを wave-collect で実施
#        - wave-collect 完了後に rm -f .supervisor/events/* を実行する
#   AC4: context 80% 到達時の自動 stop 提案
#        - observer の自己 context 消費量を監視し、80% 到達時に watcher/Monitor を一時停止
#        - ユーザーへ AskUserQuestion で外部化 + compaction を提案する
#        - ccusage または同等 API 経由で消費量取得し閾値監視スクリプトを追加する
#
# Coverage: --type=unit --coverage=red-phase
#
# テスト対象スクリプト（実装前のため存在しない — RED テスト）:
#   - plugins/twl/commands/wave-collect.md (AC1, AC3 の bash ブロック追加)
#   - scripts/stagnate-suppress-check.sh   (AC2 新規作成予定)
#   - scripts/context-budget-monitor.sh    (AC4 新規作成予定)
#   - skills/su-observer/scripts/spawn-controller.sh (AC1 記録ロジック追加予定)

load '../../bats/helpers/common.bash'

# ---------------------------------------------------------------------------
# setup / teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  WAVE_COLLECT_MD="${REPO_ROOT}/commands/wave-collect.md"
  SPAWN_CONTROLLER="${REPO_ROOT}/skills/su-observer/scripts/spawn-controller.sh"

  # AC2 対象スクリプト（未実装 — RED 前提）
  STAGNATE_SUPPRESS_SCRIPT="${REPO_ROOT}/scripts/stagnate-suppress-check.sh"

  # AC4 対象スクリプト（未実装 — RED 前提）
  CONTEXT_BUDGET_MONITOR="${REPO_ROOT}/scripts/context-budget-monitor.sh"

  # Sandbox にテスト用ディレクトリ構造を作成
  mkdir -p "$SANDBOX/.supervisor/events"
  mkdir -p "$SANDBOX/.supervisor/captures"
  mkdir -p "$SANDBOX/.autopilot/issues"
  mkdir -p "$SANDBOX/.autopilot"

  WAVE_NUM=1
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: wave-collect.md から bash ブロックを抽出して実行可能スクリプトを生成
# Step 1-3 + AC1/AC3 の新規ブロック（Step 5/6 相当）を抽出する
# ---------------------------------------------------------------------------

_extract_wave_collect_full() {
  local md_file="${WAVE_COLLECT_MD}"
  local out="$SANDBOX/scripts/wave-collect-full.sh"

  mkdir -p "$SANDBOX/scripts"

  if [[ ! -f "$md_file" ]]; then
    return 1
  fi

  python3 - "$md_file" "$out" <<'PYEOF'
import sys, re

src = sys.argv[1]
dst = sys.argv[2]

with open(src) as f:
    content = f.read()

blocks = re.findall(r'```bash\n(.*?)```', content, re.DOTALL)

with open(dst, 'w') as f:
    f.write('#!/usr/bin/env bash\nset -euo pipefail\n\n')
    for block in blocks:
        f.write(block)
        f.write('\n')
PYEOF
  chmod +x "$out"
}

# ---------------------------------------------------------------------------
# Helper: wave-N-task-ids.json フィクスチャを作成する
# ---------------------------------------------------------------------------

_create_task_ids_json() {
  local wave_num="${1:-1}"
  local file="$SANDBOX/.supervisor/wave-${wave_num}-task-ids.json"
  cat > "$file" <<JSON
{
  "wave": ${wave_num},
  "monitor_task_ids": ["task-abc123", "task-def456"]
}
JSON
}

# ---------------------------------------------------------------------------
# Helper: wave-N-watcher-pids.json フィクスチャを作成する
# ---------------------------------------------------------------------------

_create_watcher_pids_json() {
  local wave_num="${1:-1}"
  local file="$SANDBOX/.supervisor/wave-${wave_num}-watcher-pids.json"
  cat > "$file" <<JSON
{
  "wave": ${wave_num},
  "watcher_pids": [12345, 67890]
}
JSON
}

# ---------------------------------------------------------------------------
# Helper: plan.yaml フィクスチャを作成する（wave-collect の Step 1 が要求）
# ---------------------------------------------------------------------------

_create_plan_yaml() {
  local issues=("$@")
  {
    echo "session_id: \"test-1052\""
    echo "repo_mode: \"worktree\""
    echo "project_dir: \"$SANDBOX\""
    echo "phases:"
    echo "  - phase: 1"
    for iss in "${issues[@]}"; do
      echo "    - $iss"
    done
    echo "dependencies:"
  } > "$SANDBOX/.autopilot/plan.yaml"
}

# ===========================================================================
# AC1: wave-collect 後の watcher/Monitor 自動停止
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: wave-collect 完了後に wave-N-task-ids.json が読み込まれ
#           Monitor task ID が TaskStop 相当で処理される
# WHEN: wave-collect.md が AC1 stop ロジックを実装した後に実行する
# THEN: wave-N-task-ids.json の monitor_task_ids が全て処理される
#       （RED: 現行 wave-collect.md に stop ロジックが存在しないため fail）
# ---------------------------------------------------------------------------

@test "ac1: wave-collect.md に watcher/Monitor 自動停止ブロックが存在する" {
  # AC: wave-collect の最後で task-ids.json を読んで Monitor task を停止する
  # RED: 実装前は fail する（wave-collect.md に該当ブロックが存在しない）
  [[ -f "$WAVE_COLLECT_MD" ]] \
    || skip "wave-collect.md が存在しない"

  # wave-collect.md に task-ids stop ロジックが含まれることを確認
  grep -qE "wave-.*-task-ids\.json|task_ids|TaskStop" "$WAVE_COLLECT_MD" \
    || fail "AC #1 未実装: wave-collect.md に task-ids.json 読み込みロジックが存在しない"
}

@test "ac1: wave-collect.md に watcher-pids.json kill -TERM ロジックが存在する" {
  # AC: wave-collect の最後で watcher-pids.json を読んで PID を kill -TERM する
  # RED: 実装前は fail する
  [[ -f "$WAVE_COLLECT_MD" ]] \
    || skip "wave-collect.md が存在しない"

  grep -qE "watcher-pids\.json|kill.*TERM" "$WAVE_COLLECT_MD" \
    || fail "AC #1 未実装: wave-collect.md に watcher-pids.json kill -TERM ロジックが存在しない"
}

@test "ac1: wave-N-task-ids.json が存在するとき wave-collect が Monitor task 停止ログを出力する" {
  # AC: wave-N-task-ids.json に記録された task ID を TaskStop で停止する
  # RED: 実装が存在しないため wave-collect 実行後も停止ログが出力されない
  _create_plan_yaml 100
  _create_task_ids_json 1

  cat > "$SANDBOX/.autopilot/issues/issue-100.json" <<JSON
{"issue": 100, "status": "done", "pr": null, "retry_count": 0, "failure": null}
JSON

  _extract_wave_collect_full || skip "wave-collect.md が存在しない"

  run env \
    AUTOPILOT_DIR="$SANDBOX/.autopilot" \
    WAVE_NUM=1 \
    bash "$SANDBOX/scripts/wave-collect-full.sh"

  # RED: AC1 実装前は "task-stop" または "TaskStop" をログに出力しない
  echo "$output" | grep -qiE "task.stop|TaskStop|Monitor.*stop|停止" \
    || fail "AC #1 未実装: wave-collect が Monitor task 停止ログを出力しない"
}

@test "ac1: wave-N-watcher-pids.json が存在するとき wave-collect が watcher PID kill ログを出力する" {
  # AC: wave-N-watcher-pids.json に記録された PID を kill -TERM で停止する
  # RED: 実装が存在しないため PID kill ログが出力されない
  _create_plan_yaml 101
  _create_watcher_pids_json 1

  cat > "$SANDBOX/.autopilot/issues/issue-101.json" <<JSON
{"issue": 101, "status": "done", "pr": null, "retry_count": 0, "failure": null}
JSON

  _extract_wave_collect_full || skip "wave-collect.md が存在しない"

  run env \
    AUTOPILOT_DIR="$SANDBOX/.autopilot" \
    WAVE_NUM=1 \
    bash "$SANDBOX/scripts/wave-collect-full.sh"

  # RED: AC1 実装前は watcher kill ログを出力しない
  echo "$output" | grep -qiE "kill|watcher.*stop|PID|pid" \
    || fail "AC #1 未実装: wave-collect が watcher PID kill ログを出力しない"
}

@test "ac1[edge]: wave-N-task-ids.json が存在しない場合でも wave-collect が異常終了しない" {
  # AC edge: task-ids.json が未作成でも wave-collect が graceful に動作する（exit 1 禁止）
  # RED: AC1 実装時に existence check が存在しなければ fail する可能性がある境界条件
  _create_plan_yaml 102

  cat > "$SANDBOX/.autopilot/issues/issue-102.json" <<JSON
{"issue": 102, "status": "done", "pr": null, "retry_count": 0, "failure": null}
JSON

  _extract_wave_collect_full || skip "wave-collect.md が存在しない"

  run env \
    AUTOPILOT_DIR="$SANDBOX/.autopilot" \
    WAVE_NUM=1 \
    bash "$SANDBOX/scripts/wave-collect-full.sh"

  # task-ids.json が存在しない場合、wave-collect が exit 1 で失敗しないことを検証
  [[ "$status" -ne 1 ]] \
    || fail "AC #1 edge: task-ids.json 不在時に wave-collect が exit 1 で失敗した（graceful 処理が必要）"
}

@test "ac1: spawn-controller.sh が Monitor task ID を wave-N-task-ids.json に記録するロジックを含む" {
  # AC: spawn-controller.sh が起動時に Monitor task ID を .supervisor/wave-<N>-task-ids.json に書き出す
  # RED: spawn-controller.sh に task ID 記録ロジックが存在しないため fail する
  [[ -f "$SPAWN_CONTROLLER" ]] \
    || fail "spawn-controller.sh が存在しない: $SPAWN_CONTROLLER"

  grep -qE "task-ids\.json|task_ids|WAVE_NUM" "$SPAWN_CONTROLLER" \
    || fail "AC #1 未実装: spawn-controller.sh に task-ids.json 記録ロジックが存在しない"
}

@test "ac1: spawn-controller.sh が watcher PID を wave-N-watcher-pids.json に記録するロジックを含む" {
  # AC: spawn-controller.sh が起動時に watcher PID を .supervisor/wave-<N>-watcher-pids.json に書き出す
  # RED: spawn-controller.sh に PID 記録ロジックが存在しないため fail する
  [[ -f "$SPAWN_CONTROLLER" ]] \
    || fail "spawn-controller.sh が存在しない: $SPAWN_CONTROLLER"

  grep -qE "watcher-pids\.json|watcher_pids" "$SPAWN_CONTROLLER" \
    || fail "AC #1 未実装: spawn-controller.sh に watcher-pids.json PID 記録ロジックが存在しない"
}

# ===========================================================================
# AC2: STAGNATE-600 suppress 条件の追加
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: stagnate-suppress-check.sh が新規作成されている
# WHEN: scripts/stagnate-suppress-check.sh を参照する
# THEN: ファイルが存在し実行可能パーミッションを持つ
# （RED: 実装前はスクリプトが存在しないため fail）
# ---------------------------------------------------------------------------

@test "ac2: stagnate-suppress-check.sh が存在する" {
  # AC: STAGNATE emit を抑止するスクリプトが新規作成される
  # RED: 実装前はスクリプト未作成のため fail する
  [[ -f "$STAGNATE_SUPPRESS_SCRIPT" ]] \
    || fail "AC #2 未実装: stagnate-suppress-check.sh が存在しない: $STAGNATE_SUPPRESS_SCRIPT"
}

@test "ac2: stagnate-suppress-check.sh が実行可能パーミッションを持つ" {
  # RED: スクリプト未作成のため fail する
  [[ -f "$STAGNATE_SUPPRESS_SCRIPT" ]] \
    || fail "AC #2 未実装: stagnate-suppress-check.sh が存在しない（前提条件）"

  [[ -x "$STAGNATE_SUPPRESS_SCRIPT" ]] \
    || fail "AC #2 未実装: stagnate-suppress-check.sh が実行可能ではない"
}

@test "ac2: Pilot pane capture に [PHASE-COMPLETE] が含まれる場合 STAGNATE を suppress する" {
  # AC: Pilot pane の最終 capture に [PHASE-COMPLETE] が含まれる場合 STAGNATE emit を抑止
  # RED: stagnate-suppress-check.sh が存在しないため fail する
  [[ -f "$STAGNATE_SUPPRESS_SCRIPT" ]] \
    || fail "AC #2 未実装: stagnate-suppress-check.sh が存在しない"

  local capture_file="$SANDBOX/.supervisor/captures/capture-test-latest.log"
  echo "[PHASE-COMPLETE] Wave 1 完了" > "$capture_file"

  run bash "$STAGNATE_SUPPRESS_SCRIPT" \
    --capture-file "$capture_file" \
    --session-json "$SANDBOX/.autopilot/session.json"

  # suppress の場合 exit 0（suppress する = STAGNATE emit しない = 0 を返す）
  assert_success
}

@test "ac2: Pilot pane capture に '>>> 実装完了:' が含まれる場合 STAGNATE を suppress する" {
  # AC: Pilot pane の最終 capture に >>> 実装完了: が含まれる場合 STAGNATE emit を抑止
  # RED: stagnate-suppress-check.sh が存在しないため fail する
  [[ -f "$STAGNATE_SUPPRESS_SCRIPT" ]] \
    || fail "AC #2 未実装: stagnate-suppress-check.sh が存在しない"

  local capture_file="$SANDBOX/.supervisor/captures/capture-test-impl.log"
  echo ">>> 実装完了: Issue #1052 対応完了" > "$capture_file"

  run bash "$STAGNATE_SUPPRESS_SCRIPT" \
    --capture-file "$capture_file" \
    --session-json "$SANDBOX/.autopilot/session.json"

  assert_success
}

@test "ac2: session.json status=completed の場合 STAGNATE を suppress する" {
  # AC: .autopilot/session.json の status が completed の場合 STAGNATE emit を抑止
  # RED: stagnate-suppress-check.sh が存在しないため fail する
  [[ -f "$STAGNATE_SUPPRESS_SCRIPT" ]] \
    || fail "AC #2 未実装: stagnate-suppress-check.sh が存在しない"

  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{"session_id": "test-1052", "status": "completed", "started_at": "2026-04-28T00:00:00Z"}
JSON

  local capture_file="$SANDBOX/.supervisor/captures/capture-nophase.log"
  echo "some normal output" > "$capture_file"

  run bash "$STAGNATE_SUPPRESS_SCRIPT" \
    --capture-file "$capture_file" \
    --session-json "$SANDBOX/.autopilot/session.json"

  assert_success
}

@test "ac2: session.json status=archived の場合 STAGNATE を suppress する" {
  # AC: .autopilot/session.json の status が archived の場合 STAGNATE emit を抑止
  # RED: stagnate-suppress-check.sh が存在しないため fail する
  [[ -f "$STAGNATE_SUPPRESS_SCRIPT" ]] \
    || fail "AC #2 未実装: stagnate-suppress-check.sh が存在しない"

  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{"session_id": "test-1052", "status": "archived", "started_at": "2026-04-28T00:00:00Z"}
JSON

  local capture_file="$SANDBOX/.supervisor/captures/capture-archived.log"
  echo "some normal output" > "$capture_file"

  run bash "$STAGNATE_SUPPRESS_SCRIPT" \
    --capture-file "$capture_file" \
    --session-json "$SANDBOX/.autopilot/session.json"

  assert_success
}

@test "ac2: session-end ファイルが存在する場合 STAGNATE を suppress する" {
  # AC: session-end ファイルが存在する場合 STAGNATE emit を抑止
  # RED: stagnate-suppress-check.sh が存在しないため fail する
  [[ -f "$STAGNATE_SUPPRESS_SCRIPT" ]] \
    || fail "AC #2 未実装: stagnate-suppress-check.sh が存在しない"

  touch "$SANDBOX/.supervisor/session-end"

  local capture_file="$SANDBOX/.supervisor/captures/capture-session-end.log"
  echo "some normal output" > "$capture_file"

  run bash "$STAGNATE_SUPPRESS_SCRIPT" \
    --capture-file "$capture_file" \
    --session-json "$SANDBOX/.autopilot/session.json" \
    --events-dir "$SANDBOX/.supervisor"

  assert_success
}

@test "ac2[edge]: suppress 条件が揃わない場合 stagnate-suppress-check.sh が非ゼロを返す" {
  # AC edge: suppress 条件が何も満たされない場合は STAGNATE を emit する（suppress しない）
  # suppress しない = exit 非ゼロ（呼び出し元が非ゼロを見て STAGNATE を emit する）
  # RED: stagnate-suppress-check.sh が存在しないため fail する
  [[ -f "$STAGNATE_SUPPRESS_SCRIPT" ]] \
    || fail "AC #2 未実装: stagnate-suppress-check.sh が存在しない"

  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{"session_id": "test-1052", "status": "running", "started_at": "2026-04-28T00:00:00Z"}
JSON

  local capture_file="$SANDBOX/.supervisor/captures/capture-running.log"
  echo "some normal working output without phase complete markers" > "$capture_file"

  run bash "$STAGNATE_SUPPRESS_SCRIPT" \
    --capture-file "$capture_file" \
    --session-json "$SANDBOX/.autopilot/session.json" \
    --events-dir "$SANDBOX/.supervisor"

  # suppress しない = exit 非ゼロ
  [[ "$status" -ne 0 ]] \
    || fail "AC #2 edge 未実装: suppress 条件なしで STAGNATE が suppress された（非ゼロ期待）"
}

@test "ac2: heartbeat-watcher.sh に STAGNATE suppress 条件チェックの参照が含まれる" {
  # AC: heartbeat-watcher.sh が suppress 条件を確認してから STAGNATE emit する
  # RED: heartbeat-watcher.sh に suppress ロジックが存在しないため fail する
  local heartbeat="${REPO_ROOT}/skills/su-observer/scripts/heartbeat-watcher.sh"

  [[ -f "$heartbeat" ]] \
    || fail "heartbeat-watcher.sh が存在しない: $heartbeat"

  grep -qE "PHASE.COMPLETE|suppress|session-end|実装完了|stagnate.suppress" "$heartbeat" \
    || fail "AC #2 未実装: heartbeat-watcher.sh に STAGNATE suppress 条件チェックが存在しない"
}

# ===========================================================================
# AC3: events/ クリーンアップを wave-collect で実施
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: wave-collect 完了後に .supervisor/events/* が削除される
# WHEN: .supervisor/events/ にファイルが存在する状態で wave-collect を実行する
# THEN: .supervisor/events/ 以下のファイルが全て削除される
# （RED: 現行 wave-collect.md に cleanup ロジックが存在しないため fail）
# ---------------------------------------------------------------------------

@test "ac3: wave-collect.md に events/ クリーンアップブロックが存在する" {
  # AC: wave-collect の最後で rm -f .supervisor/events/* を実行する
  # RED: 実装前は fail する（wave-collect.md に該当ブロックが存在しない）
  [[ -f "$WAVE_COLLECT_MD" ]] \
    || skip "wave-collect.md が存在しない"

  grep -qE "events/\*|rm.*events|cleanup.*events|events.*rm" "$WAVE_COLLECT_MD" \
    || fail "AC #3 未実装: wave-collect.md に events/ クリーンアップロジックが存在しない"
}

@test "ac3: wave-collect 完了後に .supervisor/events/ のファイルが削除される" {
  # AC: wave-collect の最後で rm -f .supervisor/events/* を実行し events/ 以下を空にする
  # RED: cleanup ロジックが存在しないため events/ ファイルが残存する
  _create_plan_yaml 103

  cat > "$SANDBOX/.autopilot/issues/issue-103.json" <<JSON
{"issue": 103, "status": "done", "pr": null, "retry_count": 0, "failure": null}
JSON

  # events/ にファイルを事前作成
  touch "$SANDBOX/.supervisor/events/heartbeat-test-session"
  touch "$SANDBOX/.supervisor/events/stagnate-emit-001"

  _extract_wave_collect_full || skip "wave-collect.md が存在しない"

  run env \
    AUTOPILOT_DIR="$SANDBOX/.autopilot" \
    WAVE_NUM=1 \
    bash "$SANDBOX/scripts/wave-collect-full.sh"

  # RED: AC3 実装前は events/ ファイルが削除されないため fail する
  local remaining
  remaining=$(find "$SANDBOX/.supervisor/events" -type f 2>/dev/null | wc -l)
  [[ "$remaining" -eq 0 ]] \
    || fail "AC #3 未実装: wave-collect 後に events/ に ${remaining} 件のファイルが残存 (期待: 0)"
}

@test "ac3[edge]: .supervisor/events/ が空の場合 wave-collect が正常完了する" {
  # AC edge: events/ が既に空の場合でも rm -f は失敗しない（glob 展開失敗の安全確認）
  _create_plan_yaml 104

  cat > "$SANDBOX/.autopilot/issues/issue-104.json" <<JSON
{"issue": 104, "status": "done", "pr": null, "retry_count": 0, "failure": null}
JSON

  _extract_wave_collect_full || skip "wave-collect.md が存在しない"

  run env \
    AUTOPILOT_DIR="$SANDBOX/.autopilot" \
    WAVE_NUM=1 \
    bash "$SANDBOX/scripts/wave-collect-full.sh"

  # events/ 空でも wave-collect が exit 0 で完了することを確認
  assert_success
}

@test "ac3[edge]: wave-collect は events/ ディレクトリ自体を削除せずファイルのみ削除する" {
  # AC edge: rm -f .supervisor/events/* でディレクトリ自体は残すこと（rmdir 誤実行防止）
  _create_plan_yaml 105

  cat > "$SANDBOX/.autopilot/issues/issue-105.json" <<JSON
{"issue": 105, "status": "done", "pr": null, "retry_count": 0, "failure": null}
JSON

  touch "$SANDBOX/.supervisor/events/heartbeat-keep-dir-test"

  _extract_wave_collect_full || skip "wave-collect.md が存在しない"

  run env \
    AUTOPILOT_DIR="$SANDBOX/.autopilot" \
    WAVE_NUM=1 \
    bash "$SANDBOX/scripts/wave-collect-full.sh"

  # events/ ディレクトリ自体が残っていることを確認
  [[ -d "$SANDBOX/.supervisor/events" ]] \
    || fail "AC #3 edge 実装エラー: events/ ディレクトリ自体が削除された（ファイルのみ削除すべき）"
}

# ===========================================================================
# AC4: context 80% 到達時の自動 stop 提案
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: context-budget-monitor.sh が新規作成されている
# WHEN: scripts/context-budget-monitor.sh を参照する
# THEN: ファイルが存在し実行可能パーミッションを持つ
# （RED: 実装前はスクリプトが存在しないため fail）
# ---------------------------------------------------------------------------

@test "ac4: context-budget-monitor.sh が存在する" {
  # AC: observer の自己 context 消費量を監視するスクリプトが新規作成される
  # RED: 実装前はスクリプト未作成のため fail する
  [[ -f "$CONTEXT_BUDGET_MONITOR" ]] \
    || fail "AC #4 未実装: context-budget-monitor.sh が存在しない: $CONTEXT_BUDGET_MONITOR"
}

@test "ac4: context-budget-monitor.sh が実行可能パーミッションを持つ" {
  # RED: スクリプト未作成のため fail する
  [[ -f "$CONTEXT_BUDGET_MONITOR" ]] \
    || fail "AC #4 未実装: context-budget-monitor.sh が存在しない（前提条件）"

  [[ -x "$CONTEXT_BUDGET_MONITOR" ]] \
    || fail "AC #4 未実装: context-budget-monitor.sh が実行可能ではない"
}

@test "ac4: context 使用率が 80% 以上のとき context-budget-monitor.sh が非ゼロを返す" {
  # AC: observer の自己 context 消費量が 80% 到達時に停止提案フラグ（非ゼロ exit）を立てる
  # RED: スクリプトが存在しないため fail する
  [[ -f "$CONTEXT_BUDGET_MONITOR" ]] \
    || fail "AC #4 未実装: context-budget-monitor.sh が存在しない"

  # 80% 以上のモック値を渡す（ccusage 出力を模倣）
  run bash "$CONTEXT_BUDGET_MONITOR" --usage-pct 82

  # 80% 以上 = 停止提案フラグ = 非ゼロ exit
  [[ "$status" -ne 0 ]] \
    || fail "AC #4 未実装: usage-pct=82 で context-budget-monitor.sh が 0 を返した（停止提案フラグ未発火）"
}

@test "ac4: context 使用率が 80% 未満のとき context-budget-monitor.sh が 0 を返す" {
  # AC: context 使用率が 80% 未満の場合は通常継続（exit 0）
  # RED: スクリプトが存在しないため fail する
  [[ -f "$CONTEXT_BUDGET_MONITOR" ]] \
    || fail "AC #4 未実装: context-budget-monitor.sh が存在しない"

  run bash "$CONTEXT_BUDGET_MONITOR" --usage-pct 75

  assert_success
}

@test "ac4: context-budget-monitor.sh が 80% 閾値定数を含む" {
  # AC: 80% という閾値が実装に明示的に存在する
  # RED: スクリプトが存在しないため fail する
  [[ -f "$CONTEXT_BUDGET_MONITOR" ]] \
    || fail "AC #4 未実装: context-budget-monitor.sh が存在しない"

  grep -qE "80|BUDGET_THRESHOLD|CONTEXT_THRESHOLD|threshold" "$CONTEXT_BUDGET_MONITOR" \
    || fail "AC #4 未実装: context-budget-monitor.sh に 80% 閾値の定義が存在しない"
}

@test "ac4: context-budget-monitor.sh が ccusage または同等 API を呼び出すロジックを含む" {
  # AC: ccusage または同等 API 経由で context 消費量を取得する
  # RED: スクリプトが存在しないため fail する
  [[ -f "$CONTEXT_BUDGET_MONITOR" ]] \
    || fail "AC #4 未実装: context-budget-monitor.sh が存在しない"

  grep -qE "ccusage|claude.*usage|context.*api|USAGE_API" "$CONTEXT_BUDGET_MONITOR" \
    || fail "AC #4 未実装: context-budget-monitor.sh に ccusage 等の消費量取得呼び出しが存在しない"
}

@test "ac4[edge]: context 使用率がちょうど 80% のとき context-budget-monitor.sh が非ゼロを返す" {
  # AC edge: 80% ちょうどは閾値到達扱い（>= 80 の境界条件）
  # RED: スクリプトが存在しないため fail する
  [[ -f "$CONTEXT_BUDGET_MONITOR" ]] \
    || fail "AC #4 未実装: context-budget-monitor.sh が存在しない"

  run bash "$CONTEXT_BUDGET_MONITOR" --usage-pct 80

  [[ "$status" -ne 0 ]] \
    || fail "AC #4 edge 未実装: usage-pct=80 で context-budget-monitor.sh が 0 を返した（境界値 80 は非ゼロ期待）"
}

@test "ac4[edge]: context-budget-monitor.sh が 80% 到達時に watcher 停止ログを出力する" {
  # AC: 80% 到達時に全 watcher/Monitor task を一時停止するログを出力する
  # RED: スクリプトが存在しないため fail する
  [[ -f "$CONTEXT_BUDGET_MONITOR" ]] \
    || fail "AC #4 未実装: context-budget-monitor.sh が存在しない"

  run bash "$CONTEXT_BUDGET_MONITOR" \
    --usage-pct 85 \
    --events-dir "$SANDBOX/.supervisor"

  # 停止アクションを示すログが出力されることを確認
  echo "$output" | grep -qiE "watcher.*stop|monitor.*pause|一時停止|pause|stop" \
    || fail "AC #4 edge 未実装: context-budget-monitor.sh が 85% 時に watcher 停止ログを出力しない"
}
