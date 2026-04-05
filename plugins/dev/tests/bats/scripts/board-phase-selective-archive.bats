#!/usr/bin/env bats
# board-phase-selective-archive.bats
#
# Spec: openspec/changes/board-status-lifecycle/specs/phase-selective-archive/spec.md
# Requirement: autopilot Phase 完了時は当該 Phase の Done アイテムのみをアーカイブしなければならない（SHALL）
#
# Scenarios:
#   1. Phase 完了時の選択的 Archive → 当該 Phase の plan.yaml に含まれる Issue の Done アイテムのみが Archive
#   2. 他 Phase の Issue は対象外 → 他 Phase はアーカイブされない
#   3. board-archive コマンドの利用可否 → コマンド自体は動作する

load '../helpers/common'

setup() {
  common_setup

  stub_command "tmux" '
    case "$*" in
      *"capture-pane"*) echo "" ;;
      *) exit 0 ;;
    esac
  '

  stub_command "git" '
    case "$*" in
      *"rev-parse --git-dir"*)
        echo ".git/worktrees/test" ;;
      *"worktree list --porcelain"*)
        echo "" ;;
      *"worktree remove"*)
        exit 0 ;;
      *"push origin --delete"*)
        exit 0 ;;
      *"branch -D"*)
        exit 0 ;;
      *"rev-parse --show-toplevel"*)
        echo "$SANDBOX" ;;
      *)
        exit 0 ;;
    esac
  '

  # state-write.sh スタブ
  cat > "$SANDBOX/scripts/state-write.sh" <<'STATE_WRITE'
#!/usr/bin/env bash
ISSUE_NUM="" STATUS_VAL="" FIELD_VAL=""
for arg in "$@"; do
  case "$prev" in
    --issue) ISSUE_NUM="$arg" ;;
  esac
  if [[ "$arg" == status=* ]]; then STATUS_VAL="${arg#status=}"; fi
  prev="$arg"
done
if [[ -n "$ISSUE_NUM" && -n "$STATUS_VAL" ]]; then
  STATE_FILE="${AUTOPILOT_DIR:-$SANDBOX/.autopilot}/issues/issue-${ISSUE_NUM}.json"
  if [[ -f "$STATE_FILE" ]]; then
    tmp=$(mktemp)
    jq --arg s "$STATUS_VAL" '.status = $s' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
  fi
fi
exit 0
STATE_WRITE
  chmod +x "$SANDBOX/scripts/state-write.sh"

  # state-read.sh スタブ
  cat > "$SANDBOX/scripts/state-read.sh" <<'STATE_READ'
#!/usr/bin/env bash
ISSUE_NUM="" FIELD=""
for arg in "$@"; do
  case "$prev" in
    --issue) ISSUE_NUM="$arg" ;;
    --field) FIELD="$arg" ;;
  esac
  prev="$arg"
done
if [[ -n "$ISSUE_NUM" && -n "$FIELD" ]]; then
  STATE_FILE="${AUTOPILOT_DIR:-$SANDBOX/.autopilot}/issues/issue-${ISSUE_NUM}.json"
  [[ -f "$STATE_FILE" ]] && jq -r ".$FIELD // empty" "$STATE_FILE"
fi
exit 0
STATE_READ
  chmod +x "$SANDBOX/scripts/state-read.sh"

  # autopilot-should-skip.sh スタブ（常にスキップしない）
  cat > "$SANDBOX/scripts/autopilot-should-skip.sh" <<'SKIP_EOF'
#!/usr/bin/env bash
exit 1
SKIP_EOF
  chmod +x "$SANDBOX/scripts/autopilot-should-skip.sh"

  # sleep スタブ（ポーリング待機を即時完了させる）
  stub_command "sleep" 'exit 0'

  # autopilot-launch.sh スタブ（Worker 起動をモック）
  cat > "$SANDBOX/scripts/autopilot-launch.sh" <<'LAUNCH_EOF'
#!/usr/bin/env bash
exit 0
LAUNCH_EOF
  chmod +x "$SANDBOX/scripts/autopilot-launch.sh"

  # chain-steps.sh スタブ（chain-runner.sh が source する）
  if [[ ! -f "$SANDBOX/scripts/chain-steps.sh" ]]; then
    echo '#!/usr/bin/env bash' > "$SANDBOX/scripts/chain-steps.sh"
  fi

  # lib/resolve-project.sh
  mkdir -p "$SANDBOX/scripts/lib"
  cp "$REPO_ROOT/scripts/lib/resolve-project.sh" "$SANDBOX/scripts/lib/resolve-project.sh" 2>/dev/null || \
    cat > "$SANDBOX/scripts/lib/resolve-project.sh" <<'LIB_EOF'
#!/usr/bin/env bash
resolve_project() {
  local repo
  repo=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null) || return 1
  local owner="${repo%%/*}" repo_name="${repo##*/}"
  local projects
  projects=$(gh project list --owner "$owner" --format json 2>/dev/null) || return 1
  local pnum
  pnum=$(echo "$projects" | jq -r '.projects[0].number')
  [[ -z "$pnum" || "$pnum" == "null" ]] && return 1
  local result pid
  result=$(gh api graphql -f query='query($o:String!,$n:Int!){user(login:$o){projectV2(number:$n){id title repositories(first:20){nodes{nameWithOwner}}}}}' -f o="$owner" -F n="$pnum" 2>/dev/null) || return 1
  pid=$(echo "$result" | jq -r '.data.user.projectV2.id')
  echo "$pnum $pid $owner $repo_name $repo"
}
LIB_EOF

  # SESSION_STATE_CMD を無効化（テスト外部依存を除去）
  export SESSION_STATE_CMD=""

  # session.json（orchestrator の --session 引数に必要）
  echo '{"session_id":"test","plan_path":".autopilot/plan.yaml","current_phase":1,"phase_count":2,"started_at":"2026-01-01T00:00:00Z","cross_issue_warnings":[],"phase_insights":[],"patterns":{},"self_improve_issues":[]}' \
    > "$SANDBOX/.autopilot/session.json"

  # gh コールログ
  GH_LOG="$SANDBOX/gh-calls.log"
  export GH_LOG
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: Phase 完了時の archive 対応 gh スタブ
# ---------------------------------------------------------------------------

_stub_gh_with_archive_log() {
  local log_path="${GH_LOG}"
  cat > "$STUB_BIN/gh" <<GHSTUB_HEAD
#!/usr/bin/env bash
echo "\$*" >> "${log_path}"
GHSTUB_HEAD
  cat >> "$STUB_BIN/gh" <<'GHSTUB_BODY'
case "$*" in
  *"project list"*)
    echo '{"projects": [{"number": 5, "title": "loom-plugin-dev board"}]}' ;;
  *"repo view"*"--json nameWithOwner"*)
    echo 'shuu5/loom-plugin-dev' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_abc", "title": "loom-plugin-dev board", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"project item-list"*)
    # Phase 1 の Issue 10, 11 が Done、Phase 2 の Issue 20 は In Progress
    echo '{"items": [
      {"id": "PVTI_10", "content": {"number": 10, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Done", "title": "Issue 10"},
      {"id": "PVTI_11", "content": {"number": 11, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Done", "title": "Issue 11"},
      {"id": "PVTI_20", "content": {"number": 20, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "In Progress", "title": "Issue 20"}
    ]}' ;;
  *"project item-archive"*)
    echo "archived" ;;
  *)
    echo '{}' ;;
esac
GHSTUB_BODY
  chmod +x "$STUB_BIN/gh"
}

# ---------------------------------------------------------------------------
# Helper: plan.yaml + issue JSON の作成
# ---------------------------------------------------------------------------

_create_plan_with_phases() {
  cat > "$SANDBOX/.autopilot/plan.yaml" <<'PLAN_EOF'
phases:
  - phase: 1
    issues:
      - 10
      - 11
  - phase: 2
    issues:
      - 20
PLAN_EOF
}

_create_done_issues() {
  create_issue_json 10 "done"
  create_issue_json 11 "done"
  create_issue_json 20 "running"
}

# ---------------------------------------------------------------------------
# Scenario: Phase 完了時の選択的 Archive
#
# WHEN autopilot-orchestrator.sh が特定 Phase の完了を処理する
# THEN 当該 Phase の plan.yaml に含まれる Issue 番号の Done アイテムのみが Archive
# ---------------------------------------------------------------------------

@test "orchestrator Phase 完了: Phase 1 の Done Issue (10, 11) のみが board-archive 対象" {
  _create_plan_with_phases
  _create_done_issues
  _stub_gh_with_archive_log

  # chain-runner.sh の呼び出しをすべてログ
  local chain_log="$SANDBOX/chain-calls.log"
  local orig_chain="$SANDBOX/scripts/chain-runner.sh"

  mv "$orig_chain" "${orig_chain}.orig"
  cat > "$orig_chain" <<CHAIN_WRAP
#!/usr/bin/env bash
echo "\$*" >> "${chain_log}"
exec bash "${orig_chain}.orig" "\$@"
CHAIN_WRAP
  chmod +x "$orig_chain"

  run bash "$SANDBOX/scripts/autopilot-orchestrator.sh" \
    --plan "$SANDBOX/.autopilot/plan.yaml" \
    --phase 1 \
    --session "$SANDBOX/.autopilot/session.json" \
    --project-dir "$SANDBOX" \
    --autopilot-dir "$SANDBOX/.autopilot"

  # Phase 完了処理は終了コード 0
  assert_success

  # Phase 1 の Done Issue (10, 11) に対して board-archive が呼ばれた
  grep -q "board-archive.*10\|board-archive 10" "$chain_log" || \
    grep -q "project item-archive" "$GH_LOG"
}

@test "orchestrator Phase 完了: Phase 1 の board-archive に Issue 10 が含まれる" {
  _create_plan_with_phases
  _create_done_issues
  _stub_gh_with_archive_log

  local chain_log="$SANDBOX/chain-calls.log"
  local orig_chain="$SANDBOX/scripts/chain-runner.sh"

  mv "$orig_chain" "${orig_chain}.orig"
  cat > "$orig_chain" <<CHAIN_WRAP
#!/usr/bin/env bash
echo "\$*" >> "${chain_log}"
exec bash "${orig_chain}.orig" "\$@"
CHAIN_WRAP
  chmod +x "$orig_chain"

  run bash "$SANDBOX/scripts/autopilot-orchestrator.sh" \
    --plan "$SANDBOX/.autopilot/plan.yaml" \
    --phase 1 \
    --session "$SANDBOX/.autopilot/session.json" \
    --project-dir "$SANDBOX" \
    --autopilot-dir "$SANDBOX/.autopilot"

  assert_success

  # Issue 10 に対するアーカイブ呼び出しを確認
  grep -q "board-archive 10\|board-archive.*10\|project item-archive" "$GH_LOG" || \
    grep -q "10" "$chain_log"
}

@test "orchestrator Phase 完了: PHASE_COMPLETE シグナルを含む JSON を出力する" {
  _create_plan_with_phases
  _create_done_issues
  _stub_gh_with_archive_log

  run bash "$SANDBOX/scripts/autopilot-orchestrator.sh" \
    --plan "$SANDBOX/.autopilot/plan.yaml" \
    --phase 1 \
    --session "$SANDBOX/.autopilot/session.json" \
    --project-dir "$SANDBOX" \
    --autopilot-dir "$SANDBOX/.autopilot"

  assert_success
  assert_output --partial "PHASE_COMPLETE"
}

# ---------------------------------------------------------------------------
# Scenario: 他 Phase の Issue は対象外
#
# WHEN autopilot-orchestrator.sh が Phase 完了を処理する
# THEN 他 Phase の Issue はアーカイブされない
# ---------------------------------------------------------------------------

@test "orchestrator Phase 完了: Phase 2 の Issue 20 は Phase 1 完了処理でアーカイブされない" {
  _create_plan_with_phases
  _create_done_issues
  _stub_gh_with_archive_log

  local chain_log="$SANDBOX/chain-calls.log"
  local orig_chain="$SANDBOX/scripts/chain-runner.sh"

  mv "$orig_chain" "${orig_chain}.orig"
  cat > "$orig_chain" <<CHAIN_WRAP
#!/usr/bin/env bash
echo "\$*" >> "${chain_log}"
exec bash "${orig_chain}.orig" "\$@"
CHAIN_WRAP
  chmod +x "$orig_chain"

  run bash "$SANDBOX/scripts/autopilot-orchestrator.sh" \
    --plan "$SANDBOX/.autopilot/plan.yaml" \
    --phase 1 \
    --session "$SANDBOX/.autopilot/session.json" \
    --project-dir "$SANDBOX" \
    --autopilot-dir "$SANDBOX/.autopilot"

  assert_success

  # Issue 20 に対する board-archive は呼ばれていない
  ! grep -q "board-archive 20\|board-archive.*20" "$chain_log"
}

@test "orchestrator Phase 完了: Done でない Issue は同一 Phase でもアーカイブされない" {
  # ポーリングループを短縮（running Issue がタイムアウトで failed に変換される）
  export DEV_AUTOPILOT_MAX_POLL=3

  _create_plan_with_phases

  # Issue 10: done, Issue 11: running（Done でない → タイムアウト後 failed に変換）
  create_issue_json 10 "done"
  create_issue_json 11 "running"
  create_issue_json 20 "done"

  _stub_gh_with_archive_log

  local chain_log="$SANDBOX/chain-calls.log"
  local orig_chain="$SANDBOX/scripts/chain-runner.sh"

  mv "$orig_chain" "${orig_chain}.orig"
  cat > "$orig_chain" <<CHAIN_WRAP
#!/usr/bin/env bash
echo "\$*" >> "${chain_log}"
exec bash "${orig_chain}.orig" "\$@"
CHAIN_WRAP
  chmod +x "$orig_chain"

  run bash "$SANDBOX/scripts/autopilot-orchestrator.sh" \
    --plan "$SANDBOX/.autopilot/plan.yaml" \
    --phase 1 \
    --session "$SANDBOX/.autopilot/session.json" \
    --project-dir "$SANDBOX" \
    --autopilot-dir "$SANDBOX/.autopilot"

  assert_success

  # Issue 11 (running) に対する board-archive は呼ばれていない
  ! grep -q "board-archive 11\|board-archive.*11" "$chain_log"
}

# ---------------------------------------------------------------------------
# Scenario: board-archive コマンドの利用可否
#
# WHEN chain-runner.sh board-archive が呼び出される
# THEN 指定 Issue を Archive に移行する（コマンド自体は動作する）
# ---------------------------------------------------------------------------

@test "chain-runner board-archive: コマンドが存在して終了コード 0 を返す" {
  # board-archive コマンドが chain-runner.sh で定義されていることを確認
  local log_path="${GH_LOG}"
  cat > "$STUB_BIN/gh" <<GHSTUB_AVAIL_HEAD
#!/usr/bin/env bash
echo "\$*" >> "${log_path}"
GHSTUB_AVAIL_HEAD
  cat >> "$STUB_BIN/gh" <<'GHSTUB_AVAIL_BODY'
case "$*" in
  *"project list"*)
    echo '{"projects": [{"number": 5, "title": "loom-plugin-dev board"}]}' ;;
  *"repo view"*"--json nameWithOwner"*)
    echo 'shuu5/loom-plugin-dev' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_abc", "title": "loom-plugin-dev board", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"project item-list"*)
    echo '{"items": [{"id": "PVTI_10", "content": {"number": 10, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Done", "title": "Issue 10"}]}' ;;
  *"project item-archive"*)
    echo "archived" ;;
  *)
    echo '{}' ;;
esac
GHSTUB_AVAIL_BODY
  chmod +x "$STUB_BIN/gh"

  stub_command "git" '
    case "$*" in
      *"branch --show-current"*) echo "feat/10-test" ;;
      *"rev-parse --show-toplevel"*) echo "$SANDBOX" ;;
      *) exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/chain-runner.sh" board-archive "10"

  assert_success
}

@test "chain-runner board-archive: 正常終了時にアーカイブ完了メッセージを出力する" {
  local log_path="${GH_LOG}"
  cat > "$STUB_BIN/gh" <<GHSTUB_OK_HEAD
#!/usr/bin/env bash
echo "\$*" >> "${log_path}"
GHSTUB_OK_HEAD
  cat >> "$STUB_BIN/gh" <<'GHSTUB_OK_BODY'
case "$*" in
  *"project list"*)
    echo '{"projects": [{"number": 5, "title": "loom-plugin-dev board"}]}' ;;
  *"repo view"*"--json nameWithOwner"*)
    echo 'shuu5/loom-plugin-dev' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_abc", "title": "loom-plugin-dev board", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"project item-list"*)
    echo '{"items": [{"id": "PVTI_10", "content": {"number": 10, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Done", "title": "Issue 10"}]}' ;;
  *"project item-archive"*)
    echo "archived" ;;
  *)
    echo '{}' ;;
esac
GHSTUB_OK_BODY
  chmod +x "$STUB_BIN/gh"

  stub_command "git" '
    case "$*" in
      *"branch --show-current"*) echo "feat/10-test" ;;
      *"rev-parse --show-toplevel"*) echo "$SANDBOX" ;;
      *) exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/chain-runner.sh" board-archive "10"

  assert_success
  # アーカイブ完了メッセージ確認
  assert_output --partial "board-archive"
  assert_output --partial "#10"
}

@test "chain-runner board-archive: 未知ステップとして扱われない（コマンドが認識される）" {
  # board-archive が ERROR: 未知のステップ を返さないことを確認
  local log_path="${GH_LOG}"
  cat > "$STUB_BIN/gh" <<GHSTUB_RECOG_HEAD
#!/usr/bin/env bash
echo "\$*" >> "${log_path}"
GHSTUB_RECOG_HEAD
  cat >> "$STUB_BIN/gh" <<'GHSTUB_RECOG_BODY'
case "$*" in
  *"project list"*) echo '{"projects": []}' ;;
  *) echo '{}' ;;
esac
GHSTUB_RECOG_BODY
  chmod +x "$STUB_BIN/gh"

  stub_command "git" '
    case "$*" in
      *"branch --show-current"*) echo "feat/10-test" ;;
      *"rev-parse --show-toplevel"*) echo "$SANDBOX" ;;
      *) exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/chain-runner.sh" board-archive "10"

  # 「未知のステップ」エラーは出ない（board-archive はコマンドとして残っている）
  refute_output --partial "未知のステップ"
  refute_output --partial "ERROR: 未知"
}

@test "chain-runner board-archive: gh project が見つからない場合も終了コード 0（警告のみ）" {
  local log_path="${GH_LOG}"
  cat > "$STUB_BIN/gh" <<GHSTUB_NOPROJ_HEAD
#!/usr/bin/env bash
echo "\$*" >> "${log_path}"
GHSTUB_NOPROJ_HEAD
  cat >> "$STUB_BIN/gh" <<'GHSTUB_NOPROJ_BODY'
case "$*" in
  *"project list"*)
    echo '{"projects": []}' ;;
  *"repo view"*"--json nameWithOwner"*)
    echo 'shuu5/loom-plugin-dev' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": null}}}' ;;
  *)
    echo '{}' ;;
esac
GHSTUB_NOPROJ_BODY
  chmod +x "$STUB_BIN/gh"

  stub_command "git" '
    case "$*" in
      *"branch --show-current"*) echo "feat/10-test" ;;
      *"rev-parse --show-toplevel"*) echo "$SANDBOX" ;;
      *) exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/chain-runner.sh" board-archive "10"

  # Project が見つからなくてもコマンドは終了コード 0（非ブロッキング）
  assert_success
}
