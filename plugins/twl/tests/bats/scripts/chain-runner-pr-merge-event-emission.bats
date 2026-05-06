#!/usr/bin/env bats
# chain-runner-pr-merge-event-emission.bats
# Issue #1428: step_auto_merge 完了後の WAVE-PR-MERGED イベント発火
#
# Spec: Issue #1428 — chain-runner.sh step_auto_merge に post-merge hook 追加
#
# Coverage:
#   AC1: auto-merge.sh exit 0 → post-merge hook 発火、events/wave-*-pr-merged-*.json 生成
#   AC2: events ファイルが atomic write (temp→mv) で生成される
#   AC3: event JSON に必須フィールドが揃っていること
#   AC4: post-merge hook が twl_notify_supervisor_handler を呼び出すこと
#   AC5: auto-merge.sh 失敗時 (exit non-zero) → events ファイル生成なし
#   AC6: events/notify 失敗時も step_auto_merge は ok 判定 (exit 0) を維持
#   AC7: wave-queue.json の current_wave 取得 / 不在時 wave=-1 フォールバック
#   AC9: 技術メモに mailbox push 失敗時フォールバック挙動が明文化されていること

load '../helpers/common'

SUPERVISOR_DIR_PATH=""

setup() {
  common_setup

  SUPERVISOR_DIR_PATH="$SANDBOX/.supervisor"

  mkdir -p "$SUPERVISOR_DIR_PATH/events"

  export WORKER_ISSUE_NUM=1428
  export SUPERVISOR_DIR="$SUPERVISOR_DIR_PATH"
  export AUTOPILOT_DIR="$SANDBOX/.autopilot"

  create_issue_json 1428 "running"

  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/1428-chain-runner-pr-merge-event-emission" ;;
      *"rev-parse --show-toplevel"*)
        echo "$SANDBOX" ;;
      *"rev-parse --git-dir"*)
        echo "$SANDBOX/.git" ;;
      *"status --porcelain"*)
        echo "" ;;
      *"worktree list --porcelain"*)
        printf "worktree %s\nbranch refs/heads/main\n" "$SANDBOX" ;;
      *)
        exit 0 ;;
    esac
  '

  stub_command "gh" '
    case "$*" in
      *"pr view"*"--json number"*)
        echo "42" ;;
      *"pr view"*)
        printf "{\"number\":42,\"headRefName\":\"feat/1428-test\"}\n" ;;
      *"issue view"*"labels"*)
        echo "" ;;
      *)
        exit 0 ;;
    esac
  '

  cat > "$STUB_BIN/python3" <<'PYSTUB'
#!/usr/bin/env bash
case "$*" in
  *"state read"*"--field status"*)       echo "running" ;;
  *"state read"*"--field is_quick"*)     echo "false" ;;
  *"state read"*"--field current_step"*) echo "" ;;
  *"state read"*"--field window"*)       echo "" ;;
  *"state write"*)                       exit 0 ;;
  *"audit"*)                             exit 0 ;;
  *)                                     exit 0 ;;
esac
PYSTUB
  chmod +x "$STUB_BIN/python3"

  # auto-merge.sh stub: デフォルト成功
  cat > "$SANDBOX/scripts/auto-merge.sh" <<'AUTOMERGE'
#!/usr/bin/env bash
exit 0
AUTOMERGE
  chmod +x "$SANDBOX/scripts/auto-merge.sh"

  # wave-queue.json: デフォルト current_wave=3
  cat > "$SUPERVISOR_DIR_PATH/wave-queue.json" <<'WAVE_JSON'
{
  "current_wave": 3
}
WAVE_JSON
}

teardown() {
  # events/ を読み取り専用にしたテスト後に権限を戻す
  chmod -R u+w "$SUPERVISOR_DIR_PATH" 2>/dev/null || true
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: step_auto_merge を chain-runner.sh auto-merge サブコマンドで実行
# ---------------------------------------------------------------------------
run_auto_merge() {
  run env \
    SUPERVISOR_DIR="$SUPERVISOR_DIR_PATH" \
    WORKER_ISSUE_NUM=1428 \
    AUTOPILOT_DIR="$SANDBOX/.autopilot" \
    bash "$SANDBOX/scripts/chain-runner.sh" auto-merge \
    --issue 1428 --pr 42 --branch feat/1428-test
}

# ===========================================================================
# AC1: auto-merge.sh exit 0 → post-merge hook 発火、events ファイル生成
# ===========================================================================

@test "#1428 AC1: auto-merge 成功後に .supervisor/events/ にイベントファイルが生成される (RED)" {
  run_auto_merge

  # RED: _fire_post_merge_hook 未実装のため events/ にファイルが存在しない
  local event_file
  event_file="$(find "$SUPERVISOR_DIR_PATH/events" -name "wave-*-pr-merged-1428.json" 2>/dev/null | head -1)"
  [[ -n "$event_file" ]] \
    || fail "events/wave-*-pr-merged-1428.json が生成されていない (AC1 RED: _fire_post_merge_hook 未実装)"
}

# ===========================================================================
# AC2: atomic write (temp file → mv)
# ===========================================================================

@test "#1428 AC2: events ファイルが atomic write (temp→mv) で生成される (RED)" {
  run_auto_merge

  local event_file
  event_file="$(find "$SUPERVISOR_DIR_PATH/events" -name "wave-*-pr-merged-1428.json" 2>/dev/null | head -1)"
  [[ -n "$event_file" ]] \
    || fail "events/wave-*-pr-merged-1428.json が生成されていない (AC2 RED: _fire_post_merge_hook 未実装)"

  # atomic write のシグネチャ: temp file (.tmp) が残っていない
  local tmp_count
  tmp_count="$(find "$SUPERVISOR_DIR_PATH/events" -name "*.tmp" 2>/dev/null | wc -l)"
  [[ "$tmp_count" -eq 0 ]] \
    || fail "temp file が残っている (non-atomic write): count=$tmp_count"
}

# ===========================================================================
# AC3: event JSON 必須フィールド確認
# ===========================================================================

@test "#1428 AC3: event JSON に必須フィールドが揃っている (RED)" {
  run_auto_merge

  local event_file
  event_file="$(find "$SUPERVISOR_DIR_PATH/events" -name "wave-*-pr-merged-1428.json" 2>/dev/null | head -1)"
  [[ -n "$event_file" ]] \
    || fail "events/wave-*-pr-merged-1428.json が生成されていない (AC3 RED: _fire_post_merge_hook 未実装)"

  local event_val wave_val issue_val pr_val branch_val ts_val host_val
  event_val="$(jq -r '.event // empty' "$event_file" 2>/dev/null)"
  wave_val="$(jq -r '.wave // empty' "$event_file" 2>/dev/null)"
  issue_val="$(jq -r '.issue // empty' "$event_file" 2>/dev/null)"
  pr_val="$(jq -r '.pr // empty' "$event_file" 2>/dev/null)"
  branch_val="$(jq -r '.branch // empty' "$event_file" 2>/dev/null)"
  ts_val="$(jq -r '.timestamp // empty' "$event_file" 2>/dev/null)"
  host_val="$(jq -r '.host // empty' "$event_file" 2>/dev/null)"

  [[ "$event_val" == "WAVE-PR-MERGED" ]] \
    || fail "event フィールドが WAVE-PR-MERGED でない: '$event_val'"
  [[ "$wave_val" =~ ^-?[0-9]+$ ]] \
    || fail "wave フィールドが int でない: '$wave_val'"
  [[ "$issue_val" =~ ^[0-9]+$ ]] \
    || fail "issue フィールドが int でない: '$issue_val'"
  [[ "$pr_val" =~ ^[0-9]+$ ]] \
    || fail "pr フィールドが int でない: '$pr_val'"
  [[ -n "$branch_val" ]] \
    || fail "branch フィールドが空"
  [[ "$ts_val" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ]] \
    || fail "timestamp が UTC ISO 8601 形式でない: '$ts_val'"
  [[ -n "$host_val" ]] \
    || fail "host フィールドが空"
}

# ===========================================================================
# AC4: post-merge hook が twl_notify_supervisor_handler を呼び出す
# ===========================================================================

@test "#1428 AC4: post-merge hook が twl_notify_supervisor_handler を呼び出す (RED)" {
  local notify_log="$SANDBOX/notify_called.log"
  export TWL_NOTIFY_SUPERVISOR_CALL_LOG="$notify_log"

  run_auto_merge

  # RED: _fire_post_merge_hook 未実装のため notify が呼ばれない
  [[ -f "$notify_log" ]] \
    || fail "twl_notify_supervisor_handler が呼び出されていない (AC4 RED: _fire_post_merge_hook 未実装)"
  grep -q "WAVE-PR-MERGED" "$notify_log" \
    || fail "notify 呼び出しに WAVE-PR-MERGED が含まれていない"
}

# ===========================================================================
# AC5: auto-merge 失敗時は event 発火しない
# ===========================================================================

@test "#1428 AC5: auto-merge 失敗時は events ファイルが生成されない" {
  cat > "$SANDBOX/scripts/auto-merge.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$SANDBOX/scripts/auto-merge.sh"

  run env \
    SUPERVISOR_DIR="$SUPERVISOR_DIR_PATH" \
    WORKER_ISSUE_NUM=1428 \
    AUTOPILOT_DIR="$SANDBOX/.autopilot" \
    bash "$SANDBOX/scripts/chain-runner.sh" auto-merge \
    --issue 1428 --pr 42 --branch feat/1428-test

  [[ "$status" -ne 0 ]] \
    || fail "auto-merge 失敗時の exit code が 0 になっている (step_auto_merge が err 判定していない)"

  local event_count
  event_count="$(find "$SUPERVISOR_DIR_PATH/events" -name "wave-*-pr-merged-*.json" 2>/dev/null | wc -l)"
  [[ "$event_count" -eq 0 ]] \
    || fail "auto-merge 失敗時に events ファイルが生成された: count=$event_count"
}

# ===========================================================================
# AC6: event/notify 失敗でも step_auto_merge は ok 判定 (exit 0) を維持
# ===========================================================================

@test "#1428 AC6: events 書き込み失敗時も step_auto_merge は exit 0 を維持し WARN を出力する (RED)" {
  # events/ を読み取り専用にして書き込みを失敗させる
  chmod 444 "$SUPERVISOR_DIR_PATH/events"

  run_auto_merge

  # best-effort: exit 0 を維持（実装後も維持されること）
  [[ "$status" -eq 0 ]] \
    || fail "step_auto_merge の exit code が非ゼロ: $status (best-effort 違反)"

  # RED: _fire_post_merge_hook 未実装のため WARN が出ない
  echo "$output" | grep -qiE "WARN|warn" \
    || fail "events 書き込み失敗時の WARN ログが出力されていない (AC6 RED: _fire_post_merge_hook 未実装)"
}

# ===========================================================================
# AC7a: wave-queue.json が存在する場合 wave=current_wave でファイル生成
# ===========================================================================

@test "#1428 AC7a: wave-queue.json の current_wave=5 で wave-5-pr-merged-1428.json が生成される (RED)" {
  cat > "$SUPERVISOR_DIR_PATH/wave-queue.json" <<'EOF'
{
  "current_wave": 5
}
EOF

  run_auto_merge

  # RED: _fire_post_merge_hook 未実装
  local event_file
  event_file="$(find "$SUPERVISOR_DIR_PATH/events" -name "wave-5-pr-merged-1428.json" 2>/dev/null | head -1)"
  [[ -n "$event_file" ]] \
    || fail "wave-5-pr-merged-1428.json が生成されていない (AC7a RED: _fire_post_merge_hook 未実装)"
}

# ===========================================================================
# AC7b: wave-queue.json が存在しない場合 wave=-1 でフォールバック
# ===========================================================================

@test "#1428 AC7b: wave-queue.json が不在の場合 wave=-1 で続行し warning フィールドを持つ (RED)" {
  rm -f "$SUPERVISOR_DIR_PATH/wave-queue.json"

  run_auto_merge

  # RED: _fire_post_merge_hook 未実装
  local event_file
  event_file="$(find "$SUPERVISOR_DIR_PATH/events" -name "wave--1-pr-merged-1428.json" 2>/dev/null | head -1)"
  [[ -n "$event_file" ]] \
    || fail "wave--1-pr-merged-1428.json が生成されていない (AC7b RED: _fire_post_merge_hook 未実装)"

  if [[ -n "$event_file" ]]; then
    jq -e '.warning // empty' "$event_file" 2>/dev/null \
      || fail "wave=-1 時に warning フィールドが存在しない"
  fi
}

# ===========================================================================
# AC9: 技術メモに mailbox push 失敗時フォールバック挙動が明文化されている
# ===========================================================================

@test "#1428 AC9: 技術メモに mailbox push 失敗時フォールバック挙動が明文化されている (RED)" {
  local found=false
  local tech_memo=""

  for path in \
    "$REPO_ROOT/refs/ref-pr-merge-event-emission.md" \
    "$REPO_ROOT/refs/ref-wave-pr-merged-event.md" \
    "$REPO_ROOT/architecture/decisions/adr-pr-merge-event.md"
  do
    if [[ -f "$path" ]]; then
      tech_memo="$path"
      found=true
      break
    fi
  done

  # RED: 技術メモがまだ作成されていない
  [[ "$found" == "true" ]] \
    || fail "技術メモが存在しない (AC9 RED): 実装時に ref-pr-merge-event-emission.md などを作成すること"

  grep -qiE "fallback|フォールバック|watchdog|SSoT|Layer 2" "$tech_memo" \
    || fail "技術メモに mailbox push 失敗時フォールバック挙動の記述がない"
}
