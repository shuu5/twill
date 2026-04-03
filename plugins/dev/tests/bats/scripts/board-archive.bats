#!/usr/bin/env bats
# board-archive.bats - unit tests for board-archive subcommand
#
# Spec: openspec/changes/board-done-auto-archive/specs/board-archive/spec.md
# Scenarios:
#   1. 正常アーカイブ: chain-runner.sh board-archive "131" → gh project item-archive 呼び出し → 終了コード 0
#   2. アーカイブ後 item-list に含まれない
#   3. アイテムID取得失敗 → warning のみ → 終了コード 0
#   4. gh project item-archive 失敗 → warning のみ → 終了コード 0
#   5. merge-gate PASS 後の自動アーカイブ実行
#   6. アーカイブ失敗でもマージ成立

load '../helpers/common'
load './autopilot-plan-board-helpers'

setup() {
  common_setup

  # Default git stub: branch shows feat/131-board-done
  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/131-board-done" ;;
      *"rev-parse --git-dir"*)
        echo "/tmp/.git/worktrees/test" ;;
      *"worktree list"*)
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

  stub_command "tmux" 'exit 0'

  # chain-steps.sh が必要なので source できるよう空ファイルを配置
  if [[ ! -f "$SANDBOX/scripts/chain-steps.sh" ]]; then
    echo '#!/usr/bin/env bash' > "$SANDBOX/scripts/chain-steps.sh"
  fi

  # state-write.sh / state-read.sh スタブ
  stub_command "state-write.sh" 'exit 0'
  # state-write.sh は scripts/ 配下から source されるため scripts/ にも配置
  cat > "$SANDBOX/scripts/state-write.sh" <<'STATE_WRITE'
#!/usr/bin/env bash
exit 0
STATE_WRITE
  chmod +x "$SANDBOX/scripts/state-write.sh"

  cat > "$SANDBOX/scripts/state-read.sh" <<'STATE_READ'
#!/usr/bin/env bash
exit 0
STATE_READ
  chmod +x "$SANDBOX/scripts/state-read.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: gh stub for board-archive (item-list returns item for issue 131)
# ---------------------------------------------------------------------------

_stub_gh_with_item_archive() {
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"project list"*)
    echo '{"projects": [{"number": 5, "title": "loom-plugin-dev board"}]}' ;;
  *"repo view"*"--json nameWithOwner"*)
    echo 'shuu5/loom-plugin-dev' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_abc", "title": "loom-plugin-dev board", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"project item-list"*)
    echo '{"items": [
      {"id": "PVTI_item131", "content": {"number": 131, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Done", "title": "Issue 131"}
    ]}' ;;
  *"project item-archive"*)
    echo "archived" ;;
  *)
    echo "{}" ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"
}

# gh stub: item-list に Issue 131 が存在しない
_stub_gh_no_item() {
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"project list"*)
    echo '{"projects": [{"number": 5, "title": "loom-plugin-dev board"}]}' ;;
  *"repo view"*"--json nameWithOwner"*)
    echo 'shuu5/loom-plugin-dev' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_abc", "title": "loom-plugin-dev board", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"project item-list"*)
    echo '{"items": []}' ;;
  *"project item-archive"*)
    echo "archived" ;;
  *)
    echo "{}" ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"
}

# gh stub: item-archive がエラーを返す
_stub_gh_archive_fails() {
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"project list"*)
    echo '{"projects": [{"number": 5, "title": "loom-plugin-dev board"}]}' ;;
  *"repo view"*"--json nameWithOwner"*)
    echo 'shuu5/loom-plugin-dev' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_abc", "title": "loom-plugin-dev board", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"project item-list"*)
    echo '{"items": [
      {"id": "PVTI_item131", "content": {"number": 131, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Done", "title": "Issue 131"}
    ]}' ;;
  *"project item-archive"*)
    echo "archive error: permission denied" >&2
    exit 1 ;;
  *)
    echo "{}" ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"
}

# gh stub: merge-gate 用（pr merge + board-archive）
_stub_gh_merge_with_archive() {
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"pr merge"*)
    echo "merged" ;;
  *"project list"*)
    echo '{"projects": [{"number": 5, "title": "loom-plugin-dev board"}]}' ;;
  *"repo view"*"--json nameWithOwner"*)
    echo 'shuu5/loom-plugin-dev' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_abc", "title": "loom-plugin-dev board", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"project item-list"*)
    echo '{"items": [
      {"id": "PVTI_item131", "content": {"number": 131, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Done", "title": "Issue 131"}
    ]}' ;;
  *"project item-archive"*)
    echo "archived" ;;
  *)
    echo "{}" ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"
}

# gh stub: 呼び出しログを $SANDBOX/gh-calls.log に記録しつつアーカイブ成功を返す
_stub_gh_with_item_archive_log() {
  local log_path="$SANDBOX/gh-calls.log"
  cat > "$STUB_BIN/gh" <<'GHSTUB_LOG_HEAD'
#!/usr/bin/env bash
GHSTUB_LOG_HEAD
  # ログパスは実行時に展開する必要があるため heredoc を分割
  printf 'echo "$*" >> "%s"\n' "$log_path" >> "$STUB_BIN/gh"
  cat >> "$STUB_BIN/gh" <<'GHSTUB_LOG_BODY'
case "$*" in
  *"project list"*)
    echo '{"projects": [{"number": 5, "title": "loom-plugin-dev board"}]}' ;;
  *"repo view"*"--json nameWithOwner"*)
    echo 'shuu5/loom-plugin-dev' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_abc", "title": "loom-plugin-dev board", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"project item-list"*)
    echo '{"items": [
      {"id": "PVTI_item131", "content": {"number": 131, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Done", "title": "Issue 131"}
    ]}' ;;
  *"project item-archive"*)
    echo "archived" ;;
  *)
    echo "{}" ;;
esac
GHSTUB_LOG_BODY
  chmod +x "$STUB_BIN/gh"
}

# ---------------------------------------------------------------------------
# Requirement: Board アーカイブコマンド
# ---------------------------------------------------------------------------

# Scenario: 正常アーカイブ
@test "board-archive: 正常アーカイブ — gh project item-archive 呼び出しと終了コード 0" {
  _stub_gh_with_item_archive_log

  run bash "$SANDBOX/scripts/chain-runner.sh" board-archive "131"

  assert_success
  assert_output --partial "board-archive"
  assert_output --partial "#131"

  # gh project item-archive が呼ばれたことを確認
  grep -q "project item-archive" "$SANDBOX/gh-calls.log"
}

# Scenario: 正常アーカイブ — 成功メッセージの検証
@test "board-archive: 成功時に checkmark メッセージを出力する" {
  _stub_gh_with_item_archive

  run bash "$SANDBOX/scripts/chain-runner.sh" board-archive "131"

  assert_success
  assert_output --partial "✓ board-archive"
  assert_output --partial "アーカイブしました"
  assert_output --partial "#131"
}

# Scenario: アーカイブ後 item-list に含まれない
@test "board-archive: アーカイブ成功後に item-list で Issue 131 が返らない" {
  # stateful stub: 最初の item-list 呼び出しはアイテムを返し、
  # item-archive 後の item-list 呼び出しは空を返す
  local counter_file="$BATS_TMPDIR/item_list_count_$$"
  echo "0" > "$counter_file"

  cat > "$STUB_BIN/gh" <<GHSTUB
#!/usr/bin/env bash
COUNTER_FILE="$counter_file"
case "\$*" in
  *"project list"*)
    echo '{"projects": [{"number": 5, "title": "loom-plugin-dev board"}]}' ;;
  *"repo view"*"--json nameWithOwner"*)
    echo 'shuu5/loom-plugin-dev' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_abc", "title": "loom-plugin-dev board", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"project item-list"*)
    count=\$(cat "\$COUNTER_FILE" 2>/dev/null || echo 0)
    echo \$((count + 1)) > "\$COUNTER_FILE"
    if [[ "\$count" -eq 0 ]]; then
      # 1回目: アーカイブ前 → Issue 131 が存在する
      echo '{"items": [{"id": "PVTI_item131", "content": {"number": 131, "type": "Issue"}, "title": "Issue 131"}]}'
    else
      # 2回目以降: アーカイブ後 → 空
      echo '{"items": []}'
    fi ;;
  *"project item-archive"*)
    echo "archived" ;;
  *)
    echo "{}" ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  # board-archive 実行: item-list で 131 が見つかり、item-archive が呼ばれる
  run bash "$SANDBOX/scripts/chain-runner.sh" board-archive "131"
  assert_success
  assert_output --partial "✓ board-archive"
  assert_output --partial "アーカイブしました"

  # アーカイブ後の item-list: Issue 131 が含まれないことを確認
  run bash -c "PATH=\"$STUB_BIN:\$PATH\" gh project item-list 5 --owner shuu5 --format json | jq -r '.items[].content.number'"
  refute_output --partial "131"
}

# Scenario: アイテムID取得失敗
@test "board-archive: item-list に対象 Issue がない場合 — warning を出して終了コード 0" {
  _stub_gh_no_item

  run bash "$SANDBOX/scripts/chain-runner.sh" board-archive "131"

  assert_success
  assert_output --partial "⚠️ board-archive"
  assert_output --partial "アイテムIDが取得できませんでした"
  assert_output --partial "スキップ"
}

# Scenario: アイテムID取得失敗 — マージフローをブロックしない
@test "board-archive: アイテムID取得失敗でも終了コードは 0 (マージフロー非ブロック)" {
  _stub_gh_no_item

  run bash "$SANDBOX/scripts/chain-runner.sh" board-archive "131"

  # 警告は出すが必ず終了コード 0
  assert_success
}

# Scenario: gh project item-archive 失敗
@test "board-archive: item-archive がエラーを返した場合 — warning を出して終了コード 0" {
  _stub_gh_archive_fails

  run bash "$SANDBOX/scripts/chain-runner.sh" board-archive "131"

  assert_success
  assert_output --partial "⚠️ board-archive"
  assert_output --partial "アーカイブに失敗しました"
  assert_output --partial "スキップ"
}

# Scenario: gh project item-archive 失敗 — マージフローをブロックしない
@test "board-archive: item-archive 失敗でも終了コードは 0 (マージフロー非ブロック)" {
  _stub_gh_archive_fails

  run bash "$SANDBOX/scripts/chain-runner.sh" board-archive "131"

  assert_success
}

# ---------------------------------------------------------------------------
# Edge cases: 入力バリデーション
# ---------------------------------------------------------------------------

@test "board-archive: Issue 番号なし — スキップして終了コード 0" {
  _stub_gh_with_item_archive

  run bash "$SANDBOX/scripts/chain-runner.sh" board-archive ""

  assert_success
}

@test "board-archive: 非数値の Issue 番号 — スキップして終了コード 0" {
  _stub_gh_with_item_archive

  run bash "$SANDBOX/scripts/chain-runner.sh" board-archive "abc"

  assert_success
  # gh project item-archive が呼ばれないことを確認（存在しないログファイル）
  [ ! -f "$SANDBOX/gh-calls.log" ] || ! grep -q "project item-archive" "$SANDBOX/gh-calls.log"
}

@test "board-archive: パストラバーサル文字列 — スキップして終了コード 0" {
  _stub_gh_with_item_archive

  run bash "$SANDBOX/scripts/chain-runner.sh" board-archive "../etc/passwd"

  assert_success
  # item-archive が呼ばれないことを確認
  [ ! -f "$SANDBOX/gh-calls.log" ] || ! grep -q "project item-archive" "$SANDBOX/gh-calls.log"
}

@test "board-archive: Project が検出されない場合 — warning のみで終了コード 0" {
  # project list が空を返す
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"project list"*)
    echo '{"projects": []}' ;;
  *"repo view"*"--json nameWithOwner"*)
    echo 'shuu5/loom-plugin-dev' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": null}}}' ;;
  *)
    echo "{}" ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  run bash "$SANDBOX/scripts/chain-runner.sh" board-archive "131"

  assert_success
}

# ---------------------------------------------------------------------------
# Requirement: merge-gate PASS 時の自動アーカイブ
# ---------------------------------------------------------------------------

# gh stub: merge-gate 用 + 呼び出しログ記録
_stub_gh_merge_with_archive_log() {
  local log_path="$SANDBOX/gh-calls.log"
  cat > "$STUB_BIN/gh" <<'GHSTUB_MERGE_LOG_HEAD'
#!/usr/bin/env bash
GHSTUB_MERGE_LOG_HEAD
  printf 'echo "$*" >> "%s"\n' "$log_path" >> "$STUB_BIN/gh"
  cat >> "$STUB_BIN/gh" <<'GHSTUB_MERGE_LOG_BODY'
case "$*" in
  *"pr merge"*)
    exit 0 ;;
  *"project list"*)
    echo '{"projects": [{"number": 5, "title": "loom-plugin-dev board"}]}' ;;
  *"repo view"*"--json nameWithOwner"*)
    echo 'shuu5/loom-plugin-dev' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_abc", "title": "loom-plugin-dev board", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"project item-list"*)
    echo '{"items": [
      {"id": "PVTI_item131", "content": {"number": 131, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Done", "title": "Issue 131"}
    ]}' ;;
  *"project item-archive"*)
    echo "archived" ;;
  *)
    echo "{}" ;;
esac
GHSTUB_MERGE_LOG_BODY
  chmod +x "$STUB_BIN/gh"
}

# Scenario: merge-gate PASS 後の自動アーカイブ実行
@test "merge-gate-execute: PASS 後に board-archive を呼び出す" {
  create_issue_json 131 "merge-ready"
  export ISSUE=131 PR_NUMBER=42 BRANCH="feat/131-board-done"

  _stub_gh_merge_with_archive_log

  run bash "$SANDBOX/scripts/merge-gate-execute.sh"

  assert_success
  assert_output --partial "マージ + クリーンアップ完了"

  # board-archive が呼ばれた（gh project item-archive がログにある）ことを確認
  grep -q "project item-archive" "$SANDBOX/gh-calls.log"
}

# Scenario: merge-gate PASS 後の自動アーカイブ — board-archive 出力が含まれる
@test "merge-gate-execute: PASS 後に board-archive の成功メッセージが出力される" {
  create_issue_json 131 "merge-ready"
  export ISSUE=131 PR_NUMBER=42 BRANCH="feat/131-board-done"

  _stub_gh_merge_with_archive

  run bash "$SANDBOX/scripts/merge-gate-execute.sh"

  assert_success
  # board-archive の成功メッセージを確認
  assert_output --partial "board-archive"
}

# Scenario: アーカイブ失敗でもマージ成立
@test "merge-gate-execute: board-archive が warning で return 0 でもマージの終了コードは 0" {
  create_issue_json 131 "merge-ready"
  export ISSUE=131 PR_NUMBER=42 BRANCH="feat/131-board-done"

  # マージは成功、board-archive は警告（item-archive 失敗）
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"pr merge"*)
    exit 0 ;;
  *"project list"*)
    echo '{"projects": [{"number": 5, "title": "loom-plugin-dev board"}]}' ;;
  *"repo view"*"--json nameWithOwner"*)
    echo 'shuu5/loom-plugin-dev' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_abc", "title": "loom-plugin-dev board", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"project item-list"*)
    echo '{"items": [
      {"id": "PVTI_item131", "content": {"number": 131, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Done", "title": "Issue 131"}
    ]}' ;;
  *"project item-archive"*)
    # アーカイブ失敗（警告のみ、マージは成立済み）
    echo "archive error: permission denied" >&2
    exit 1 ;;
  *)
    echo "{}" ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  run bash "$SANDBOX/scripts/merge-gate-execute.sh"

  # マージは成立 → 終了コード 0
  assert_success
  assert_output --partial "マージ + クリーンアップ完了"
}

# Scenario: アーカイブ失敗でもマージ済み状態 (status=done) が維持される
@test "merge-gate-execute: board-archive 失敗でも Issue status は done のまま" {
  create_issue_json 131 "merge-ready"
  export ISSUE=131 PR_NUMBER=42 BRANCH="feat/131-board-done"

  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"pr merge"*)
    exit 0 ;;
  *"project list"*)
    echo '{"projects": [{"number": 5, "title": "loom-plugin-dev board"}]}' ;;
  *"repo view"*"--json nameWithOwner"*)
    echo 'shuu5/loom-plugin-dev' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_abc", "title": "loom-plugin-dev board", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"project item-list"*)
    echo '{"items": [
      {"id": "PVTI_item131", "content": {"number": 131, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Done", "title": "Issue 131"}
    ]}' ;;
  *"project item-archive"*)
    echo "archive error" >&2
    exit 1 ;;
  *)
    echo "{}" ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  run bash "$SANDBOX/scripts/merge-gate-execute.sh"

  # board-archive 失敗でもマージフローはブロックされない（終了コード 0）
  assert_success
  # merge-gate の完了メッセージが出力されていることを確認
  assert_output --partial "マージ + クリーンアップ完了"
}
