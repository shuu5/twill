#!/usr/bin/env bats
# board-merge-done-transition.bats
#
# Spec: openspec/changes/board-status-lifecycle/specs/merge-done-transition/spec.md
# Requirement: merge 成功時は Done 遷移を経由しなければならない（SHALL）
#
# Scenarios:
#   1. PR merge 成功後の Status 遷移 → Done に更新
#   2. Done を経由せず Archive されない → board-archive コマンドは呼び出されない

load '../helpers/common'

setup() {
  common_setup

  stub_command "tmux" 'exit 0'

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

  # state-write.sh / state-read.sh スタブ
  cat > "$SANDBOX/scripts/state-write.sh" <<'STATE_WRITE'
#!/usr/bin/env bash
# 簡易スタブ: --set status=xxx の内容を状態ファイルに書き出す
ISSUE_NUM=""
STATUS_VAL=""
for arg in "$@"; do
  case "$prev" in
    --issue) ISSUE_NUM="$arg" ;;
  esac
  if [[ "$arg" == status=* ]]; then
    STATUS_VAL="${arg#status=}"
  fi
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

  # chain-runner.sh が存在することを確認（sandbox にコピー済みのはず）
  # chain-steps.sh が必要
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

  GH_LOG="$SANDBOX/gh-calls.log"
  export GH_LOG

  # CWD ガード回避: merge-gate-execute.sh は worktrees/ 配下からの実行を拒否するため
  # テスト実行ディレクトリを SANDBOX（/tmp 配下）に変更する
  cd "$SANDBOX" || true
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: merge 成功 + board-status-update 対応 gh スタブ
# ---------------------------------------------------------------------------

_stub_gh_merge_with_board_status() {
  local log_path="${GH_LOG}"
  cat > "$STUB_BIN/gh" <<GHSTUB_HEAD
#!/usr/bin/env bash
echo "\$*" >> "${log_path}"
GHSTUB_HEAD
  cat >> "$STUB_BIN/gh" <<'GHSTUB_BODY'
case "$*" in
  *"pr merge"*)
    exit 0 ;;
  *"issue view"*)
    echo "CLOSED" ;;
  *"project list"*)
    echo '{"projects": [{"number": 5, "title": "loom-plugin-dev board"}]}' ;;
  *"repo view"*"--json nameWithOwner"*)
    echo '{"nameWithOwner": "shuu5/loom-plugin-dev", "owner": {"login": "shuu5"}}' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_abc", "title": "loom-plugin-dev board", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"project item-add"*)
    echo '{"id": "PVTI_item193"}' ;;
  *"project field-list"*)
    echo '{"fields": [{"id": "FIELD_STATUS", "name": "Status", "options": [{"id": "OPT_TODO", "name": "Todo"}, {"id": "OPT_DONE", "name": "Done"}]}]}' ;;
  *"project item-edit"*)
    echo '{}' ;;
  *)
    echo '{}' ;;
esac
GHSTUB_BODY
  chmod +x "$STUB_BIN/gh"
}

# ---------------------------------------------------------------------------
# Scenario: PR merge 成功後の Status 遷移 → Done に更新
#
# WHEN merge-gate-execute.sh が PR merge 成功を検出する
# THEN 当該 Issue の Project Board Status が Done に更新される
# ---------------------------------------------------------------------------

@test "merge-gate-execute: merge 成功後に board-status-update Done が呼ばれる" {
  create_issue_json 193 "merge-ready"
  export ISSUE=193 PR_NUMBER=42 BRANCH="feat/193-test"

  _stub_gh_merge_with_board_status

  run bash "$SANDBOX/scripts/merge-gate-execute.sh"

  assert_success

  # chain-runner.sh board-status-update が呼ばれた証拠:
  # project item-add + item-edit (Status=Done) のシーケンスが存在する
  grep -q "project item-add" "$GH_LOG"
  grep -q "project item-edit" "$GH_LOG"
  # Done の OPT_DONE が渡された
  grep -q "OPT_DONE" "$GH_LOG"
}

@test "merge-gate-execute: merge 成功後に Issue の status が done に遷移する" {
  create_issue_json 193 "merge-ready"
  export ISSUE=193 PR_NUMBER=42 BRANCH="feat/193-test"

  _stub_gh_merge_with_board_status

  run bash "$SANDBOX/scripts/merge-gate-execute.sh"

  assert_success
  assert_output --partial "マージ + クリーンアップ完了"

  local status
  status=$(jq -r '.status' "$SANDBOX/.autopilot/issues/issue-193.json")
  [ "$status" = "done" ]
}

@test "merge-gate-execute: board-status-update に 'Done' ステータスが渡される" {
  create_issue_json 193 "merge-ready"
  export ISSUE=193 PR_NUMBER=42 BRANCH="feat/193-test"

  # chain-runner.sh の呼び出しをログに記録するスタブ
  local chain_log="$SANDBOX/chain-calls.log"
  local orig_chain="$SANDBOX/scripts/chain-runner.sh"

  # chain-runner.sh をラッパーに差し替え
  mv "$orig_chain" "${orig_chain}.orig"
  cat > "$orig_chain" <<CHAIN_WRAP
#!/usr/bin/env bash
echo "\$*" >> "${chain_log}"
exec bash "${orig_chain}.orig" "\$@"
CHAIN_WRAP
  chmod +x "$orig_chain"

  _stub_gh_merge_with_board_status

  run bash "$SANDBOX/scripts/merge-gate-execute.sh"

  assert_success

  # board-status-update Done が呼ばれたことを確認
  grep -q "board-status-update" "$chain_log"
  grep -q "Done" "$chain_log"
}

# ---------------------------------------------------------------------------
# Scenario: Done を経由せず Archive されない → board-archive は呼ばれない
#
# WHEN merge-gate-execute.sh が実行される
# THEN board-archive コマンドは呼び出されない
# ---------------------------------------------------------------------------

@test "merge-gate-execute: merge 成功時に board-archive が呼ばれない" {
  create_issue_json 193 "merge-ready"
  export ISSUE=193 PR_NUMBER=42 BRANCH="feat/193-test"

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

  _stub_gh_merge_with_board_status

  run bash "$SANDBOX/scripts/merge-gate-execute.sh"

  assert_success

  # board-archive コマンドが chain-runner.sh に渡されていない
  ! grep -q "board-archive" "$chain_log"
}

@test "merge-gate-execute: merge 成功時に gh project item-archive が呼ばれない" {
  create_issue_json 193 "merge-ready"
  export ISSUE=193 PR_NUMBER=42 BRANCH="feat/193-test"

  _stub_gh_merge_with_board_status

  run bash "$SANDBOX/scripts/merge-gate-execute.sh"

  assert_success

  # gh project item-archive が呼ばれていない
  ! grep -q "project item-archive" "$GH_LOG"
}

@test "merge-gate-execute: --reject モードでは board-status-update も board-archive も呼ばれない" {
  create_issue_json 193 "merge-ready"
  export ISSUE=193 PR_NUMBER=42 BRANCH="feat/193-test"
  export FINDING_SUMMARY="Critical bug"
  export FIX_INSTRUCTIONS="Fix it"

  _stub_gh_merge_with_board_status

  run bash "$SANDBOX/scripts/merge-gate-execute.sh" --reject

  assert_success
  assert_output --partial "リジェクト"

  # リジェクト時は board 系コマンド不呼び出し
  ! grep -q "project item-edit" "$GH_LOG"
  ! grep -q "project item-archive" "$GH_LOG"
}

# ---------------------------------------------------------------------------
# Regression: 既存テストとの非干渉確認
# ---------------------------------------------------------------------------

@test "merge-gate-execute: merge 失敗時は board-status-update も呼ばれない" {
  create_issue_json 193 "merge-ready"
  export ISSUE=193 PR_NUMBER=42 BRANCH="feat/193-test"

  local log_path="${GH_LOG}"
  cat > "$STUB_BIN/gh" <<GHSTUB_FAIL_HEAD
#!/usr/bin/env bash
echo "\$*" >> "${log_path}"
GHSTUB_FAIL_HEAD
  cat >> "$STUB_BIN/gh" <<'GHSTUB_FAIL_BODY'
case "$*" in
  *"pr merge"*)
    echo "merge conflict" >&2
    exit 1 ;;
  *)
    echo '{}' ;;
esac
GHSTUB_FAIL_BODY
  chmod +x "$STUB_BIN/gh"

  run bash "$SANDBOX/scripts/merge-gate-execute.sh"

  assert_failure

  # merge 失敗 → Status 更新も Archive もなし
  ! grep -q "project item-edit" "$GH_LOG"
  ! grep -q "project item-archive" "$GH_LOG"
}
