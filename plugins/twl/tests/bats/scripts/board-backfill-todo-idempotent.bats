#!/usr/bin/env bats
# board-backfill-todo-idempotent.bats
#
# Spec: openspec/changes/board-status-lifecycle/specs/backfill-todo-idempotent/spec.md
# Requirement: backfill は新規 Issue を Todo で追加し、既存アイテムをスキップしなければならない（SHALL）
#
# Scenarios:
#   1. 未登録 Issue のバックフィル → Status=Todo で Board に追加
#   2. 登録済み Issue のスキップ → アイテムの Status は変更されずスキップ

load '../helpers/common'

setup() {
  common_setup

  stub_command "tmux" 'exit 0'
  stub_command "sleep" 'exit 0'

  # scripts/ に lib/ を作成して resolve-project.sh を配置
  mkdir -p "$SANDBOX/scripts/lib"
  cp "$REPO_ROOT/scripts/lib/resolve-project.sh" "$SANDBOX/scripts/lib/resolve-project.sh" 2>/dev/null || \
    cat > "$SANDBOX/scripts/lib/resolve-project.sh" <<'LIB_EOF'
#!/usr/bin/env bash
resolve_project() {
  local repo owner repo_name
  repo=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null) || return 1
  owner="${repo%%/*}"
  repo_name="${repo##*/}"
  local projects
  projects=$(gh project list --owner "$owner" --format json 2>/dev/null) || return 1
  local project_nums
  mapfile -t project_nums < <(echo "$projects" | jq -r '.projects[].number')
  [[ ${#project_nums[@]} -eq 0 ]] && return 1
  local pnum="${project_nums[0]}"
  local result
  result=$(gh api graphql -f query='query($owner:String!,$num:Int!){user(login:$owner){projectV2(number:$num){id title repositories(first:20){nodes{nameWithOwner}}}}}' \
    -f owner="$owner" -F num="$pnum" 2>/dev/null) || return 1
  local pid
  pid=$(echo "$result" | jq -r '.data.user.projectV2.id')
  echo "$pnum $pid $owner $repo_name $repo"
}
LIB_EOF

  # gh コールログファイルパス
  GH_LOG="$SANDBOX/gh-calls.log"
  export GH_LOG
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: デフォルト gh スタブ（Todo オプションを含む field-list 応答）
# ---------------------------------------------------------------------------

_stub_gh_with_todo_support() {
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
  *"api graphql"*"nodeId"*)
    # FIELDS_JSON query: resolve_project の graphql は nodeId なし
    echo '{"id": "FIELD_STATUS", "name": "Status", "options": [{"id": "OPT_TODO", "name": "Todo"}, {"id": "OPT_INPROG", "name": "In Progress"}, {"id": "OPT_DONE", "name": "Done"}]}' ;;
  *"api graphql"*)
    # resolve_project 向けのGraphQL応答
    echo '{"data": {"user": {"projectV2": {"id": "PVT_abc", "title": "loom-plugin-dev board", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"issue view"*)
    # Issue が存在する（番号 10）
    echo '{"number": 10}' ;;
  *"project item-add"*)
    echo '{"id": "PVTI_newitem10"}' ;;
  *"project field-list"*)
    # Status フィールドに Todo / In Progress / Done オプションを持つ
    echo '{"fields": [{"id": "FIELD_STATUS", "name": "Status", "options": [{"id": "OPT_TODO", "name": "Todo"}, {"id": "OPT_INPROG", "name": "In Progress"}, {"id": "OPT_DONE", "name": "Done"}]}]}' ;;
  *"project item-edit"*)
    echo '{}' ;;
  *"project item-list"*)
    # 既存アイテムなし（空）
    echo '{"items": []}' ;;
  *)
    echo '{}' ;;
esac
GHSTUB_BODY
  chmod +x "$STUB_BIN/gh"
}

# ---------------------------------------------------------------------------
# Scenario: 未登録 Issue のバックフィル → Status=Todo で Board に追加
# ---------------------------------------------------------------------------

# WHEN project-board-backfill.sh が未登録 Issue を処理する
# THEN Status=Todo で Board に追加される
@test "backfill: 未登録 Issue を処理すると Status=Todo で Board に追加される" {
  _stub_gh_with_todo_support

  run bash "$SANDBOX/scripts/project-board-backfill.sh" 10 10

  assert_success

  # item-add が呼ばれたことを確認
  grep -q "project item-add" "$GH_LOG"

  # item-edit で Todo オプションID が渡されたことを確認
  grep -q "project item-edit" "$GH_LOG"
  grep -q "OPT_TODO" "$GH_LOG"
}

@test "backfill: 未登録 Issue の追加後に item-edit で Status フィールドを設定する" {
  _stub_gh_with_todo_support

  run bash "$SANDBOX/scripts/project-board-backfill.sh" 10 10

  assert_success
  # api graphql が呼ばれた（Status フィールドID取得、backfill は graphql API を使用）
  grep -q "api graphql" "$GH_LOG"
  # item-edit が呼ばれた（Status 更新）
  grep -q "project item-edit" "$GH_LOG"
}

@test "backfill: 未登録 Issue の追加成功をテーブル行に出力する" {
  _stub_gh_with_todo_support

  run bash "$SANDBOX/scripts/project-board-backfill.sh" 10 10

  assert_success
  # マークダウンテーブルの成功行
  assert_output --partial "| #10 |"
}

@test "backfill: In Progress オプションではなく Todo オプションで item-edit を呼び出す" {
  _stub_gh_with_todo_support

  run bash "$SANDBOX/scripts/project-board-backfill.sh" 10 10

  assert_success
  # In Progress の OPT_INPROG は渡らない
  ! grep -q "OPT_INPROG" "$GH_LOG"
  # Todo の OPT_TODO が渡る
  grep -q "OPT_TODO" "$GH_LOG"
}

@test "backfill: 複数 Issue を処理する際に各 Issue を Todo で追加する" {
  # Issue 10, 11 の gh スタブ
  local log_path="${GH_LOG}"
  cat > "$STUB_BIN/gh" <<GHSTUB_MULTI_HEAD
#!/usr/bin/env bash
echo "\$*" >> "${log_path}"
GHSTUB_MULTI_HEAD
  cat >> "$STUB_BIN/gh" <<'GHSTUB_MULTI_BODY'
case "$*" in
  *"project list"*)
    echo '{"projects": [{"number": 5, "title": "loom-plugin-dev board"}]}' ;;
  *"repo view"*"--json nameWithOwner"*)
    echo 'shuu5/loom-plugin-dev' ;;
  *"api graphql"*"nodeId"*)
    echo '{"id": "FIELD_STATUS", "name": "Status", "options": [{"id": "OPT_TODO", "name": "Todo"}, {"id": "OPT_INPROG", "name": "In Progress"}, {"id": "OPT_DONE", "name": "Done"}]}' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_abc", "title": "loom-plugin-dev board", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"issue view 10"*)
    echo '{"number": 10}' ;;
  *"issue view 11"*)
    echo '{"number": 11}' ;;
  *"project item-add"*)
    echo '{"id": "PVTI_newitem"}' ;;
  *"project field-list"*)
    echo '{"fields": [{"id": "FIELD_STATUS", "name": "Status", "options": [{"id": "OPT_TODO", "name": "Todo"}, {"id": "OPT_INPROG", "name": "In Progress"}]}]}' ;;
  *"project item-edit"*)
    echo '{}' ;;
  *"project item-list"*)
    echo '{"items": []}' ;;
  *)
    echo '{}' ;;
esac
GHSTUB_MULTI_BODY
  chmod +x "$STUB_BIN/gh"

  run bash "$SANDBOX/scripts/project-board-backfill.sh" 10 11

  assert_success
  # 2 Issue 分の item-add
  local add_count
  add_count=$(grep -c "project item-add" "$GH_LOG" || echo 0)
  [[ "$add_count" -ge 2 ]]
}

# ---------------------------------------------------------------------------
# Scenario: 登録済み Issue のスキップ → アイテムの Status は変更されずスキップ
# ---------------------------------------------------------------------------

# WHEN project-board-backfill.sh が既存 Board アイテムを処理する
# THEN アイテムの Status は変更されず、スキップされる
@test "backfill: 登録済み Issue を処理しても item-edit が呼ばれない（Status 不変）" {
  local log_path="${GH_LOG}"
  # item-list が既存アイテムを返す gh スタブ
  cat > "$STUB_BIN/gh" <<GHSTUB_EXISTING_HEAD
#!/usr/bin/env bash
echo "\$*" >> "${log_path}"
GHSTUB_EXISTING_HEAD
  cat >> "$STUB_BIN/gh" <<'GHSTUB_EXISTING_BODY'
case "$*" in
  *"project list"*)
    echo '{"projects": [{"number": 5, "title": "loom-plugin-dev board"}]}' ;;
  *"repo view"*"--json nameWithOwner"*)
    echo 'shuu5/loom-plugin-dev' ;;
  *"api graphql"*"nodeId"*)
    echo '{"id": "FIELD_STATUS", "name": "Status", "options": [{"id": "OPT_TODO", "name": "Todo"}, {"id": "OPT_INPROG", "name": "In Progress"}, {"id": "OPT_DONE", "name": "Done"}]}' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_abc", "title": "loom-plugin-dev board", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"issue view"*)
    echo '{"number": 10}' ;;
  *"project item-list"*)
    # Issue 10 が既にボードに存在する
    echo '{"items": [{"id": "PVTI_existing10", "content": {"number": 10, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "In Progress", "title": "Existing Issue 10"}]}' ;;
  *"project field-list"*)
    echo '{"fields": [{"id": "FIELD_STATUS", "name": "Status", "options": [{"id": "OPT_TODO", "name": "Todo"}, {"id": "OPT_INPROG", "name": "In Progress"}]}]}' ;;
  *"project item-add"*)
    # 既存アイテムの場合 item-add は呼ばれないはず
    echo '{"id": "PVTI_existing10"}' ;;
  *"project item-edit"*)
    echo '{}' ;;
  *)
    echo '{}' ;;
esac
GHSTUB_EXISTING_BODY
  chmod +x "$STUB_BIN/gh"

  run bash "$SANDBOX/scripts/project-board-backfill.sh" 10 10

  assert_success
  # item-edit が呼ばれていない（Status は変更しない）
  ! grep -q "project item-edit" "$GH_LOG"
}

@test "backfill: 登録済み Issue をスキップしたことを出力するか、追加数が 0 である" {
  local log_path="${GH_LOG}"
  cat > "$STUB_BIN/gh" <<GHSTUB_SKIP_HEAD
#!/usr/bin/env bash
echo "\$*" >> "${log_path}"
GHSTUB_SKIP_HEAD
  cat >> "$STUB_BIN/gh" <<'GHSTUB_SKIP_BODY'
case "$*" in
  *"project list"*)
    echo '{"projects": [{"number": 5, "title": "loom-plugin-dev board"}]}' ;;
  *"repo view"*"--json nameWithOwner"*)
    echo 'shuu5/loom-plugin-dev' ;;
  *"api graphql"*"nodeId"*)
    echo '{"id": "FIELD_STATUS", "name": "Status", "options": [{"id": "OPT_TODO", "name": "Todo"}, {"id": "OPT_INPROG", "name": "In Progress"}, {"id": "OPT_DONE", "name": "Done"}]}' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_abc", "title": "loom-plugin-dev board", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"issue view"*)
    echo '{"number": 10}' ;;
  *"project item-list"*)
    # Issue 10 が既にボードに存在する
    echo '{"items": [{"id": "PVTI_existing10", "content": {"number": 10, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "In Progress", "title": "Existing Issue 10"}]}' ;;
  *"project field-list"*)
    echo '{"fields": [{"id": "FIELD_STATUS", "name": "Status", "options": [{"id": "OPT_TODO", "name": "Todo"}]}]}' ;;
  *"project item-add"*)
    echo '{"id": "PVTI_existing10"}' ;;
  *)
    echo '{}' ;;
esac
GHSTUB_SKIP_BODY
  chmod +x "$STUB_BIN/gh"

  run bash "$SANDBOX/scripts/project-board-backfill.sh" 10 10

  assert_success
  # スキップを示す出力（スキップ行またはスキップカウント）があること
  assert_output --partial "スキップ"
}

@test "backfill: 登録済み + 未登録 混在時は未登録のみ追加する" {
  local log_path="${GH_LOG}"
  local item_call_count=0
  local count_file="$BATS_TMPDIR/call_count_$$"
  echo "0" > "$count_file"

  cat > "$STUB_BIN/gh" <<GHSTUB_MIXED_HEAD
#!/usr/bin/env bash
echo "\$*" >> "${log_path}"
GHSTUB_MIXED_HEAD
  cat >> "$STUB_BIN/gh" <<'GHSTUB_MIXED_BODY'
case "$*" in
  *"project list"*)
    echo '{"projects": [{"number": 5, "title": "loom-plugin-dev board"}]}' ;;
  *"repo view"*"--json nameWithOwner"*)
    echo 'shuu5/loom-plugin-dev' ;;
  *"api graphql"*"nodeId"*)
    echo '{"id": "FIELD_STATUS", "name": "Status", "options": [{"id": "OPT_TODO", "name": "Todo"}, {"id": "OPT_INPROG", "name": "In Progress"}, {"id": "OPT_DONE", "name": "Done"}]}' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_abc", "title": "loom-plugin-dev board", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"issue view 20"*)
    echo '{"number": 20}' ;;
  *"issue view 21"*)
    echo '{"number": 21}' ;;
  *"project item-list"*)
    # Issue 20 は既存、21 は未登録
    echo '{"items": [{"id": "PVTI_existing20", "content": {"number": 20, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Done", "title": "Done Issue 20"}]}' ;;
  *"project field-list"*)
    echo '{"fields": [{"id": "FIELD_STATUS", "name": "Status", "options": [{"id": "OPT_TODO", "name": "Todo"}, {"id": "OPT_INPROG", "name": "In Progress"}]}]}' ;;
  *"project item-add"*)
    echo '{"id": "PVTI_newitem21"}' ;;
  *"project item-edit"*)
    echo '{}' ;;
  *)
    echo '{}' ;;
esac
GHSTUB_MIXED_BODY
  chmod +x "$STUB_BIN/gh"

  run bash "$SANDBOX/scripts/project-board-backfill.sh" 20 21

  assert_success
  # item-edit は Issue 21 分のみ（Issue 20 はスキップ）
  local edit_count
  edit_count=$(grep -c "project item-edit" "$GH_LOG" || echo 0)
  [[ "$edit_count" -le 1 ]]
}

# ---------------------------------------------------------------------------
# Edge cases: バリデーション
# ---------------------------------------------------------------------------

@test "backfill: 引数なしで使用法メッセージを出力して失敗" {
  _stub_gh_with_todo_support

  run bash "$SANDBOX/scripts/project-board-backfill.sh"

  assert_failure
  assert_output --partial "Usage:"
}

@test "backfill: start > end で失敗" {
  _stub_gh_with_todo_support

  run bash "$SANDBOX/scripts/project-board-backfill.sh" 50 10

  assert_failure
  assert_output --partial "must be <="
}

@test "backfill: 非数値引数で失敗" {
  _stub_gh_with_todo_support

  run bash "$SANDBOX/scripts/project-board-backfill.sh" abc 10

  assert_failure
  assert_output --partial "positive integers"
}
