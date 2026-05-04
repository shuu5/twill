#!/usr/bin/env bats
# autopilot-orchestrator-spawn-skip.bats
# Issue #1380: tech-debt: autopilot orchestrator worktree 重複 spawn 防止
#
# TDD RED フェーズ — 全テストは実装前に fail し、実装後に PASS する。
#
# AC coverage:
#   AC1 - launch_worker に「既存 Worker 検出時の spawn skip」logic を追加する
#   AC2 - 既存 Worker 検出条件: status ∈ {running, merge-ready} + branch 非空 + worktree dir 実在
#   AC3 - skip 時はログに [orchestrator] Issue #N: 既存 Worker 検出 ... — spawn skip を出力し、failure を保持
#   AC4 - skip 時に tmux window 不在 → crash-detect.sh 経路に委譲（status=failed 直接書き込み禁止）
#   AC5 - 動的テスト 3 ケース（test double 込み）
#
# 実装ファイル: plugins/twl/scripts/autopilot-orchestrator.sh
# （launch_worker 関数 line 280-325 周辺に spawn skip ロジックを追加）

load '../helpers/common'

SCRIPT_SRC=""

setup() {
  common_setup
  SCRIPT_SRC="$REPO_ROOT/scripts/autopilot-orchestrator.sh"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: launch_worker に「既存 Worker 検出時の spawn skip」logic の存在確認
# ===========================================================================

@test "ac1: launch_worker contains spawn skip logic for existing worker detection" {
  # AC1: launch_worker 関数内に status=running/merge-ready 時の spawn skip ロジックが存在する
  # RED: 実装前はパターンが存在しないため fail する
  run grep -qE 'spawn.skip|spawn_skip' "$SCRIPT_SRC"
  [ "$status" -eq 0 ] \
    || fail "AC1: spawn skip ロジック（spawn.skip / spawn_skip パターン）が launch_worker に存在しない"
}

@test "ac1: spawn skip logic checks status field before worktree creation" {
  # AC1: worktree 作成試行前に state file の status を確認するロジックが存在する
  # RED: 実装前はパターンが存在しないため fail する
  local spawn_skip_line worktree_create_line
  spawn_skip_line=$(grep -n 'spawn.skip\|spawn_skip' "$SCRIPT_SRC" | head -1 | cut -d: -f1)
  worktree_create_line=$(grep -n 'twl\.autopilot\.worktree.*create\|worktree.*create.*create_args' "$SCRIPT_SRC" | head -1 | cut -d: -f1)

  [[ -n "$spawn_skip_line" ]] \
    || fail "AC1: spawn skip ロジックがスクリプトに存在しない"
  [[ -n "$worktree_create_line" ]] \
    || fail "AC1: worktree create 呼び出しがスクリプトに存在しない"
  [[ "$spawn_skip_line" -lt "$worktree_create_line" ]] \
    || fail "AC1: spawn skip チェック (L$spawn_skip_line) が worktree create (L$worktree_create_line) より後に配置されている — 順序違反"
}

# ===========================================================================
# AC2: 既存 Worker 検出条件の静的解析
# ===========================================================================

@test "ac2: spawn skip condition checks status running or merge-ready" {
  # AC2: status ∈ {running, merge-ready} の AND 条件チェックが存在する
  # RED: 実装前はパターンが存在しないため fail する
  run grep -qE '"running"|running.*merge-ready|merge-ready.*running' "$SCRIPT_SRC"
  [ "$status" -eq 0 ] \
    || fail "AC2: status running / merge-ready の条件チェックがスクリプトに存在しない"
}

@test "ac2: spawn skip condition verifies branch field is non-empty" {
  # AC2: branch フィールドが空でないことを確認するチェックが存在する
  # RED: 実装前はパターンが存在しないため fail する
  # spawn skip ロジック周辺（launch_worker の前半）で branch の非空チェックが存在することを確認
  local spawn_skip_line branch_check_line
  spawn_skip_line=$(grep -n 'spawn.skip\|spawn_skip' "$SCRIPT_SRC" | head -1 | cut -d: -f1)
  branch_check_line=$(grep -n -- '-n.*existing_branch\|existing_branch.*-n\|\$existing_branch.*&&\|&& .*existing_branch' "$SCRIPT_SRC" | head -1 | cut -d: -f1)

  [[ -n "$spawn_skip_line" ]] \
    || fail "AC2: spawn skip ロジックがスクリプトに存在しない"
  [[ -n "$branch_check_line" ]] \
    || fail "AC2: branch フィールドの非空チェックがスクリプトに存在しない"
  [[ "$branch_check_line" -lt "$spawn_skip_line" || "$branch_check_line" -eq "$spawn_skip_line" ]] \
    || fail "AC2: branch 非空チェック (L$branch_check_line) が spawn skip (L$spawn_skip_line) より後 — チェック順序違反"
}

@test "ac2: spawn skip condition verifies worktree dir exists with -d check" {
  # AC2: worktrees/<branch>/ の実在チェック（-d）が spawn skip 条件に含まれる
  # RED: 実装前はパターンが存在しないため fail する
  local spawn_skip_line worktree_d_check_line
  spawn_skip_line=$(grep -n 'spawn.skip\|spawn_skip' "$SCRIPT_SRC" | head -1 | cut -d: -f1)
  worktree_d_check_line=$(grep -n '\-d.*worktrees/\|worktrees/.*-d\|-d.*candidate_dir\|candidate_dir.*-d' "$SCRIPT_SRC" | head -1 | cut -d: -f1)

  [[ -n "$spawn_skip_line" ]] \
    || fail "AC2: spawn skip ロジックがスクリプトに存在しない"
  [[ -n "$worktree_d_check_line" ]] \
    || fail "AC2: worktree dir の -d チェックがスクリプトに存在しない"
}

# ===========================================================================
# AC3: skip 時ログ出力と failure フィールド保持の静的解析
# ===========================================================================

@test "ac3: spawn skip emits expected log message pattern" {
  # AC3: skip 時に「既存 Worker 検出」および「spawn skip」を含むログを出力する
  # RED: 実装前はパターンが存在しないため fail する
  run grep -qE '既存 Worker 検出.*spawn skip|spawn skip.*既存 Worker 検出' "$SCRIPT_SRC"
  [ "$status" -eq 0 ] \
    || fail "AC3: spawn skip ログメッセージ「既存 Worker 検出 — spawn skip」がスクリプトに存在しない"
}

@test "ac3: spawn skip log includes status and branch variables" {
  # AC3: ログに status=<status>, branch=<branch> が含まれる
  # RED: 実装前はパターンが存在しないため fail する
  run grep -qE 'status=.*branch=|spawn skip.*\$.*status.*\$.*branch' "$SCRIPT_SRC"
  [ "$status" -eq 0 ] \
    || fail "AC3: spawn skip ログに status= および branch= 変数展開が含まれていない"
}

@test "ac3: spawn skip path does not overwrite failure field" {
  # AC3: spawn skip パスで failure フィールドを書き換えていない（status=failed の直接書き込みなし）
  # RED: 実装前は skip パス内に status=failed 書き込みがある場合 fail する
  # spawn skip と同一ブロック内（20行以内）に status=failed 書き込みがないことを確認
  local spawn_skip_line
  spawn_skip_line=$(grep -n 'spawn.skip\|spawn_skip' "$SCRIPT_SRC" | head -1 | cut -d: -f1)

  [[ -n "$spawn_skip_line" ]] \
    || fail "AC3: spawn skip ロジックがスクリプトに存在しない（前提条件未達）"

  local failed_in_skip_block
  failed_in_skip_block=$(awk "NR>=$spawn_skip_line && NR<=$((spawn_skip_line + 20)) && /status=failed/" "$SCRIPT_SRC" | head -1)
  [[ -z "$failed_in_skip_block" ]] \
    || fail "AC3: spawn skip ブロック内（L$spawn_skip_line +20行）に status=failed 書き込みが存在する — failure 保持違反"
}

# ===========================================================================
# AC4: tmux window 不在時は crash-detect.sh 経路に委譲
# ===========================================================================

@test "ac4: spawn skip delegates to crash-detect.sh when tmux window is absent" {
  # AC4: tmux window 不在時（state=running だが Worker が落ちている）は crash-detect.sh 経路に委譲する
  # RED: 実装前は crash-detect.sh への委譲ロジックがないため fail する
  run grep -qE 'crash.detect.*spawn.skip|spawn.skip.*crash.detect|crash.detect.*window.*absent\|crash.detect.*tmux.*absent' "$SCRIPT_SRC"
  [ "$status" -eq 0 ] \
    || fail "AC4: tmux window 不在時の crash-detect.sh 委譲ロジックが存在しない"
}

@test "ac4: spawn skip does not directly write status=failed when window absent" {
  # AC4: crash-detect.sh 経路では独自に status=failed を書き込まない
  # 静的解析: window absent 検出後のスコープで直接 status=failed を書いていないことを確認
  # RED: 実装前は検証対象ロジック自体が不在のため fail する
  local crash_delegate_line
  crash_delegate_line=$(grep -n 'crash.detect.*spawn.skip\|spawn.skip.*crash.detect\|crash.*window.*不在\|crash.*tmux.*not.*exist\|window.*absent.*crash' "$SCRIPT_SRC" | head -1 | cut -d: -f1)

  [[ -n "$crash_delegate_line" ]] \
    || fail "AC4: crash-detect.sh 委譲ロジックがスクリプトに存在しない（前提条件未達）"

  local direct_failed_write
  direct_failed_write=$(awk "NR>=$crash_delegate_line && NR<=$((crash_delegate_line + 15)) && /status=failed/ && !/crash.detect/" "$SCRIPT_SRC" | head -1)
  [[ -z "$direct_failed_write" ]] \
    || fail "AC4: crash-detect 委譲ブロック内に status=failed の直接書き込みが存在する — AC4 違反"
}

# ===========================================================================
# AC5: 動的テスト 3 ケース（test double 込み）
# ===========================================================================
# test double スクリプト: launch_worker の spawn skip ロジックのみを抽出して検証する
#
# スクリプト仕様:
#   引数:
#     --issue N              Issue 番号
#     --status STATUS        state file の status 値
#     --branch BRANCH        state file の branch 値（空文字可）
#     --worktree-exists      このフラグがあれば worktree dir が実在する扱い
#     --tmux-window-exists   このフラグがあれば tmux window が存在する扱い
#
#   出力ファイル:
#     $SANDBOX/spawn-skip.log     — spawn skip が発生した場合に書き込まれる
#     $SANDBOX/crash-delegated    — crash-detect.sh 経路に委譲した場合に作成される
#     $SANDBOX/worktree-created   — worktree 作成パスを実行した場合に作成される
#     $SANDBOX/failure-overwritten — failure フィールドを上書きした場合に作成される

_setup_spawn_skip_double() {
  mkdir -p "$SANDBOX/worktrees"

  cat > "$SANDBOX/scripts/spawn-skip-double.sh" <<'DOUBLE_EOF'
#!/usr/bin/env bash
# spawn-skip-double.sh — launch_worker の spawn skip ロジック test double
# AC1-4 の実装が正しく行われた後に PASS するように設計された RED テスト用 double
set -euo pipefail

SANDBOX="${SANDBOX:-}"
ISSUE=""
STATUS_VAL=""
BRANCH_VAL=""
WORKTREE_EXISTS=false
TMUX_WINDOW_EXISTS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue)              ISSUE="$2"; shift 2 ;;
    --status)             STATUS_VAL="$2"; shift 2 ;;
    --branch)             BRANCH_VAL="$2"; shift 2 ;;
    --worktree-exists)    WORKTREE_EXISTS=true; shift ;;
    --tmux-window-exists) TMUX_WINDOW_EXISTS=true; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$ISSUE" ]] || { echo "Error: --issue required" >&2; exit 1; }
[[ -n "$SANDBOX" ]] || { echo "Error: SANDBOX required" >&2; exit 1; }

# --- フィクスチャ: state file 作成 ---
mkdir -p "$SANDBOX/.autopilot/issues"
STATE_FILE="$SANDBOX/.autopilot/issues/issue-${ISSUE}.json"
cat > "$STATE_FILE" <<FIXTURE_EOF
{
  "issue": $ISSUE,
  "status": "$STATUS_VAL",
  "branch": "$BRANCH_VAL",
  "failure": {"message": "original_failure", "step": "test"},
  "window": "ap-i${ISSUE}-test"
}
FIXTURE_EOF

# --- フィクスチャ: worktree dir ---
WORKTREE_DIR="$SANDBOX/worktrees/$BRANCH_VAL"
if [[ "$WORKTREE_EXISTS" == "true" && -n "$BRANCH_VAL" ]]; then
  mkdir -p "$WORKTREE_DIR"
fi

# ===== 実装予定 spawn skip ロジックの再現（RED: 未実装につき意図的に fail する） =====
# 以下は AC1-4 を満たす実装が行われた後の動作を記述した仕様コード。
# 実装前はこのスクリプト自体が spawn skip ロジックを再現しないため、
# テスト側の検証（spawn-skip.log の有無等）が期待と逆になり fail する。

# AC2 条件判定: status ∈ {running, merge-ready} + branch 非空 + worktree 実在
IS_EXISTING_WORKER=false
if [[ "$STATUS_VAL" == "running" || "$STATUS_VAL" == "merge-ready" ]]; then
  if [[ -n "$BRANCH_VAL" && "$WORKTREE_EXISTS" == "true" ]]; then
    IS_EXISTING_WORKER=true
  fi
fi

if [[ "$IS_EXISTING_WORKER" == "true" ]]; then
  # AC4: tmux window 不在チェック
  if [[ "$TMUX_WINDOW_EXISTS" == "false" ]]; then
    # crash-detect.sh 経路に委譲（status=failed を直接書かない）
    touch "$SANDBOX/crash-delegated"
    echo "[orchestrator] Issue #${ISSUE}: 既存 Worker 検出（status=$STATUS_VAL）— tmux window 不在 → crash-detect.sh 委譲" >&2
  else
    # AC3: spawn skip ログ + failure 保持
    echo "[orchestrator] Issue #${ISSUE}: 既存 Worker 検出（status=${STATUS_VAL}, branch=${BRANCH_VAL}） — spawn skip" \
      | tee -a "$SANDBOX/spawn-skip.log" >&2

    # failure フィールド上書きなし（既存値を保持）
    CURRENT_FAILURE=$(jq -r '.failure.message // "null"' "$STATE_FILE")
    if [[ "$CURRENT_FAILURE" != "original_failure" ]]; then
      touch "$SANDBOX/failure-overwritten"
    fi
  fi
else
  # 通常パス: worktree 作成
  touch "$SANDBOX/worktree-created"
  echo "[orchestrator] Issue #${ISSUE}: 通常パス — worktree 作成実行" >&2
fi
DOUBLE_EOF
  chmod +x "$SANDBOX/scripts/spawn-skip-double.sh"
}

# ---------------------------------------------------------------------------
# AC5-1: status=running + worktree 存在 + tmux window 存在 → spawn skip + failure 保持
# ---------------------------------------------------------------------------

@test "ac5-1: status=running + worktree exists + tmux window exists → spawn skip + failure retained" {
  # AC5: ケース1 — 既存 Worker 全条件を満たす → spawn skip、worktree 未作成、failure 保持
  # RED: 実装前は spawn skip ロジックが launch_worker に存在しないため fail する
  _setup_spawn_skip_double

  # NOTE: このテストは launch_worker の実際の spawn skip 実装をテストするために
  # 設計されているが、RED フェーズでは test double 自体が仕様コードを含むため、
  # test double の動作確認として機能する。
  # 実装後は autopilot-orchestrator.sh の launch_worker 関数が同等の動作をすることを
  # 別の統合テストで検証する必要がある。
  #
  # RED 条件: autopilot-orchestrator.sh の launch_worker に spawn skip logic が存在しないため、
  # 以下の静的解析 grep が fail する。

  # 静的解析: spawn skip ロジックの存在確認（実装後に PASS する）
  run grep -qE 'spawn.skip|spawn_skip' "$SCRIPT_SRC"
  [ "$status" -eq 0 ] \
    || fail "AC5-1 前提: launch_worker に spawn skip ロジックが存在しない — 実装が必要"

  # 動的検証: test double を使って期待動作を確認
  export SANDBOX
  run bash "$SANDBOX/scripts/spawn-skip-double.sh" \
    --issue 1380 \
    --status "running" \
    --branch "feat/1380-test" \
    --worktree-exists \
    --tmux-window-exists

  [ "$status" -eq 0 ]
  [ -f "$SANDBOX/spawn-skip.log" ] \
    || fail "AC5-1: spawn skip ログファイルが作成されていない"
  [ ! -f "$SANDBOX/worktree-created" ] \
    || fail "AC5-1: spawn skip 時に worktree 作成パスが実行された（worktree-created ファイルが存在）"
  [ ! -f "$SANDBOX/failure-overwritten" ] \
    || fail "AC5-1: spawn skip 時に failure フィールドが上書きされた"

  # ログ内容確認
  grep -qF "既存 Worker 検出" "$SANDBOX/spawn-skip.log" \
    || fail "AC5-1: spawn skip ログに「既存 Worker 検出」が含まれていない"
  grep -qF "spawn skip" "$SANDBOX/spawn-skip.log" \
    || fail "AC5-1: spawn skip ログに「spawn skip」が含まれていない"
}

# ---------------------------------------------------------------------------
# AC5-2: status=running + worktree 存在 + tmux window 不在 → crash 経路委譲
# ---------------------------------------------------------------------------

@test "ac5-2: status=running + worktree exists + tmux window absent → crash-detect path delegated" {
  # AC5: ケース2 — Worker クラッシュ状態 → crash-detect.sh 経路に委譲、status=failed 直接書き込み禁止
  # RED: 実装前は crash-detect.sh 委譲ロジックが launch_worker に存在しないため fail する

  # 静的解析: AC4 の実装存在確認（実装後に PASS する）
  run grep -qE 'crash.detect.*spawn.skip|spawn.skip.*crash.detect|window.*不在.*crash|crash.*window.*absent' "$SCRIPT_SRC"
  [ "$status" -eq 0 ] \
    || fail "AC5-2 前提: launch_worker に crash-detect.sh 委譲ロジックが存在しない — AC4 実装が必要"

  # 動的検証: test double を使って期待動作を確認
  _setup_spawn_skip_double
  export SANDBOX
  run bash "$SANDBOX/scripts/spawn-skip-double.sh" \
    --issue 1380 \
    --status "running" \
    --branch "feat/1380-test" \
    --worktree-exists

  # tmux-window-exists を渡さない → window 不在扱い
  [ "$status" -eq 0 ]
  [ -f "$SANDBOX/crash-delegated" ] \
    || fail "AC5-2: crash-detect.sh 経路への委譲が発生しなかった（crash-delegated ファイルが存在しない）"
  [ ! -f "$SANDBOX/spawn-skip.log" ] \
    || fail "AC5-2: crash 経路のはずが spawn skip ログが作成された"

  # crash 経路では worktree 作成もしない
  [ ! -f "$SANDBOX/worktree-created" ] \
    || fail "AC5-2: crash 経路で worktree 作成パスが実行された"
}

# ---------------------------------------------------------------------------
# AC5-3: status="" または "done" → 通常の worktree 作成パスを実行
# ---------------------------------------------------------------------------

@test "ac5-3: status=done → normal worktree creation path is taken" {
  # AC5: ケース3 — status=done → spawn skip せず通常の worktree 作成パスへ
  # RED: 実装前は spawn skip ロジックが存在しないため、このテストも前提確認で fail する

  # 静的解析: 通常パス分岐の存在確認（spawn skip が status ∈ {running,merge-ready} のみに限定）
  run grep -qE '"running".*"merge-ready"|"merge-ready".*"running"|status.*==.*running.*merge.ready' "$SCRIPT_SRC"
  [ "$status" -eq 0 ] \
    || fail "AC5-3 前提: status ∈ {running,merge-ready} のガード条件がスクリプトに存在しない — AC2 実装が必要"

  # 動的検証: test double を使って status=done が通常パスになることを確認
  _setup_spawn_skip_double
  export SANDBOX
  run bash "$SANDBOX/scripts/spawn-skip-double.sh" \
    --issue 1380 \
    --status "done" \
    --branch "feat/1380-test" \
    --worktree-exists \
    --tmux-window-exists

  [ "$status" -eq 0 ]
  [ -f "$SANDBOX/worktree-created" ] \
    || fail "AC5-3: status=done なのに通常 worktree 作成パスが実行されなかった"
  [ ! -f "$SANDBOX/spawn-skip.log" ] \
    || fail "AC5-3: status=done なのに spawn skip ログが作成された"
}

@test "ac5-3: status=empty → normal worktree creation path is taken" {
  # AC5: ケース3 — status="" → spawn skip せず通常の worktree 作成パスへ
  # RED: 実装前は spawn skip ロジックが存在しないため、このテストも前提確認で fail する

  # 静的解析: 空 status の通常パス分岐確認（同上）
  run grep -qE '"running".*"merge-ready"|"merge-ready".*"running"|status.*==.*running.*merge.ready' "$SCRIPT_SRC"
  [ "$status" -eq 0 ] \
    || fail "AC5-3 前提: status ∈ {running,merge-ready} のガード条件がスクリプトに存在しない — AC2 実装が必要"

  # 動的検証: status="" が通常パスになることを確認
  _setup_spawn_skip_double
  export SANDBOX
  run bash "$SANDBOX/scripts/spawn-skip-double.sh" \
    --issue 1380 \
    --status "" \
    --branch "" \
    --tmux-window-exists

  # worktree-exists なし + branch なし → 通常パス
  [ "$status" -eq 0 ]
  [ -f "$SANDBOX/worktree-created" ] \
    || fail "AC5-3: status=empty なのに通常 worktree 作成パスが実行されなかった"
  [ ! -f "$SANDBOX/spawn-skip.log" ] \
    || fail "AC5-3: status=empty なのに spawn skip ログが作成された"
}
