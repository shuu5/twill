#!/usr/bin/env bats
# archive-fail-closed.bats — Issue #138
#
# archive_done_issues / step_board_archive / project-board-archive.sh の
# fail-closed ガード（ローカル status=done かつ GitHub state=CLOSED の両方を満たす場合のみ archive）を検証する。
#
# Scenarios:
#   step_board_archive:
#     1. GitHub CLOSED → archive 実行 (成功メッセージ)
#     2. GitHub OPEN → skip (OPEN メッセージ)
#     3. GitHub state 取得失敗 (空文字) → skip (取得失敗メッセージ)
#   project-board-archive.sh:
#     4. 全 CLOSED → 全 archive
#     5. 一部 OPEN → OPEN の Issue を skip + warning
#     6. state 取得失敗 → skip + warning
#     7. --no-verify → 取得失敗を無視して archive 実行 (従来挙動)

load '../helpers/common'

setup() {
  common_setup

  stub_command "git" '
    case "$*" in
      *"branch --show-current"*) echo "feat/131-test" ;;
      *"rev-parse --show-toplevel"*) echo "$SANDBOX" ;;
      *"rev-parse --git-dir"*) echo ".git" ;;
      *) exit 0 ;;
    esac
  '

  stub_command "tmux" 'exit 0'
  stub_command "sleep" 'exit 0'

  # chain-steps.sh placeholder
  if [[ ! -f "$SANDBOX/scripts/chain-steps.sh" ]]; then
    echo '#!/usr/bin/env bash' > "$SANDBOX/scripts/chain-steps.sh"
  fi

  stub_command "state-write.sh" 'exit 0'
  cat > "$SANDBOX/scripts/state-write.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$SANDBOX/scripts/state-write.sh"

  cat > "$SANDBOX/scripts/state-read.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$SANDBOX/scripts/state-read.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: gh stub builders
# ---------------------------------------------------------------------------

# _stub_gh_issue_state_closed: gh issue view → CLOSED
_stub_gh_issue_state_closed() {
  local log_path="$SANDBOX/gh-calls.log"
  cat > "$STUB_BIN/gh" <<GHSTUB
#!/usr/bin/env bash
echo "\$*" >> "${log_path}"
case "\$*" in
  *"issue view"*"--json state"*)
    echo "CLOSED" ;;
  *"project list"*)
    echo '{"projects": [{"number": 5, "title": "board"}]}' ;;
  *"repo view"*"--json nameWithOwner"*)
    echo '{"nameWithOwner": "shuu5/loom-plugin-dev", "owner": {"login": "shuu5"}}' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_abc", "title": "board", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"project item-list"*)
    echo '{"items": [{"id": "PVTI_1", "content": {"number": 131, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Done", "title": "Issue 131"}]}' ;;
  *"project item-archive"*)
    echo "archived" ;;
  *)
    echo "{}" ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"
}

# _stub_gh_issue_state_open: gh issue view → OPEN
_stub_gh_issue_state_open() {
  local log_path="$SANDBOX/gh-calls.log"
  cat > "$STUB_BIN/gh" <<GHSTUB
#!/usr/bin/env bash
echo "\$*" >> "${log_path}"
case "\$*" in
  *"issue view"*"--json state"*)
    echo "OPEN" ;;
  *"project list"*)
    echo '{"projects": [{"number": 5, "title": "board"}]}' ;;
  *"repo view"*"--json nameWithOwner"*)
    echo '{"nameWithOwner": "shuu5/loom-plugin-dev", "owner": {"login": "shuu5"}}' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_abc", "title": "board", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"project item-list"*)
    echo '{"items": [{"id": "PVTI_1", "content": {"number": 131, "type": "Issue"}, "status": "Done", "title": "Issue 131"}]}' ;;
  *"project item-archive"*)
    echo "archived" ;;
  *)
    echo "{}" ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"
}

# _stub_gh_issue_state_fail: gh issue view → 非ゼロ exit (state 取得失敗)
_stub_gh_issue_state_fail() {
  local log_path="$SANDBOX/gh-calls.log"
  cat > "$STUB_BIN/gh" <<GHSTUB
#!/usr/bin/env bash
echo "\$*" >> "${log_path}"
case "\$*" in
  *"issue view"*"--json state"*)
    echo "network error" >&2
    exit 1 ;;
  *"project list"*)
    echo '{"projects": [{"number": 5, "title": "board"}]}' ;;
  *"repo view"*"--json nameWithOwner"*)
    echo '{"nameWithOwner": "shuu5/loom-plugin-dev", "owner": {"login": "shuu5"}}' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_abc", "title": "board", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"project item-list"*)
    echo '{"items": [{"id": "PVTI_1", "content": {"number": 131, "type": "Issue"}, "status": "Done", "title": "Issue 131"}]}' ;;
  *"project item-archive"*)
    echo "archived" ;;
  *)
    echo "{}" ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"
}

# ---------------------------------------------------------------------------
# step_board_archive (chain-runner.sh)
# ---------------------------------------------------------------------------

@test "step_board_archive: GitHub CLOSED → archive を実行（fail-closed 成立）" {
  _stub_gh_issue_state_closed

  run bash "$SANDBOX/scripts/chain-runner.sh" board-archive "131"

  assert_success
  assert_output --partial "✓ board-archive"
  # gh project item-archive が呼ばれる
  grep -q "project item-archive" "$SANDBOX/gh-calls.log"
}

@test "step_board_archive: GitHub OPEN → archive を skip (fail-closed)" {
  _stub_gh_issue_state_open

  run bash "$SANDBOX/scripts/chain-runner.sh" board-archive "131"

  assert_success
  assert_output --partial "⚠️ board-archive"
  assert_output --partial "OPEN"
  assert_output --partial "スキップ"
  # gh project item-archive は呼ばれない
  run grep "project item-archive" "$SANDBOX/gh-calls.log"
  assert_failure
}

@test "step_board_archive: GitHub state 取得失敗 → archive を skip (fail-closed)" {
  _stub_gh_issue_state_fail

  run bash "$SANDBOX/scripts/chain-runner.sh" board-archive "131"

  assert_success
  assert_output --partial "⚠️ board-archive"
  assert_output --partial "取得失敗"
  assert_output --partial "スキップ"
  run grep "project item-archive" "$SANDBOX/gh-calls.log"
  assert_failure
}

@test "step_board_archive: Issue 番号なし → 番号検証で早期 return（gh issue view 呼ばれない）" {
  _stub_gh_issue_state_fail

  run bash "$SANDBOX/scripts/chain-runner.sh" board-archive ""

  assert_success
  # 空引数では gh issue view も呼ばれない
  if [[ -f "$SANDBOX/gh-calls.log" ]]; then
    run grep "issue view" "$SANDBOX/gh-calls.log"
    assert_failure
  fi
}

# ---------------------------------------------------------------------------
# project-board-archive.sh
# ---------------------------------------------------------------------------

# _stub_gh_project_board_mixed: Issue 131 (CLOSED) と 132 (OPEN) が Done ステータス
_stub_gh_project_board_mixed() {
  local log_path="$SANDBOX/gh-calls.log"
  cat > "$STUB_BIN/gh" <<GHSTUB
#!/usr/bin/env bash
echo "\$*" >> "${log_path}"
case "\$*" in
  *"issue view 131"*)
    echo "CLOSED" ;;
  *"issue view 132"*)
    echo "OPEN" ;;
  *"project list"*)
    echo '{"projects": [{"number": 5, "title": "loom-plugin-dev board"}]}' ;;
  *"repo view"*"--json nameWithOwner"*)
    echo '{"nameWithOwner": "shuu5/loom-plugin-dev", "owner": {"login": "shuu5"}}' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_abc", "title": "loom-plugin-dev board", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"project item-list"*)
    echo '{"items": [
      {"id": "PVTI_131", "content": {"number": 131, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Done", "title": "Issue 131"},
      {"id": "PVTI_132", "content": {"number": 132, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Done", "title": "Issue 132"}
    ]}' ;;
  *"project item-archive"*)
    echo "archived" ;;
  *)
    echo "{}" ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"
}

@test "project-board-archive.sh: 一部 OPEN → OPEN の Issue は skip + warning" {
  _stub_gh_project_board_mixed

  run bash "$SANDBOX/scripts/project-board-archive.sh"

  assert_success
  # #132 (OPEN) は skip warning
  assert_output --partial "#132"
  assert_output --partial "OPEN"
  assert_output --partial "スキップ"
  # #131 (CLOSED) は archive
  assert_output --partial "archived: #131"
  # skip サマリー
  assert_output --partial "fail-closed"
}

# _stub_gh_project_board_fetch_fail: 131 は state 取得失敗
_stub_gh_project_board_fetch_fail() {
  local log_path="$SANDBOX/gh-calls.log"
  cat > "$STUB_BIN/gh" <<GHSTUB
#!/usr/bin/env bash
echo "\$*" >> "${log_path}"
case "\$*" in
  *"issue view"*)
    echo "network error" >&2
    exit 1 ;;
  *"project list"*)
    echo '{"projects": [{"number": 5, "title": "loom-plugin-dev board"}]}' ;;
  *"repo view"*"--json nameWithOwner"*)
    echo '{"nameWithOwner": "shuu5/loom-plugin-dev", "owner": {"login": "shuu5"}}' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_abc", "title": "loom-plugin-dev board", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"project item-list"*)
    echo '{"items": [
      {"id": "PVTI_131", "content": {"number": 131, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Done", "title": "Issue 131"}
    ]}' ;;
  *"project item-archive"*)
    echo "archived" ;;
  *)
    echo "{}" ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"
}

@test "project-board-archive.sh: state 取得失敗 → fail-closed で skip" {
  _stub_gh_project_board_fetch_fail

  run bash "$SANDBOX/scripts/project-board-archive.sh"

  assert_success
  assert_output --partial "取得失敗"
  assert_output --partial "スキップ"
  # item-archive は呼ばれない
  run grep "project item-archive" "$SANDBOX/gh-calls.log"
  assert_failure
}

@test "project-board-archive.sh: --no-verify → state 取得失敗でも archive 実行 (従来挙動)" {
  _stub_gh_project_board_fetch_fail

  run bash "$SANDBOX/scripts/project-board-archive.sh" --no-verify

  assert_success
  # --no-verify では fail-closed skip メッセージは出ない
  refute_output --partial "fail-closed で archive をスキップ"
  # item-archive は呼ばれる
  grep -q "project item-archive" "$SANDBOX/gh-calls.log"
  assert_output --partial "archived: #131"
}
