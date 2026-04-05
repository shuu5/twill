# autopilot-plan-board-helpers.bash - shared stubs for --board mode tests

# _write_board_items <json>
# JSON を $SANDBOX/board-items.json に書き出す。
_write_board_items() {
  printf '%s\n' "$1" > "$SANDBOX/board-items.json"
}

# _write_cross_repo_board_items
# クロスリポジトリ Board の board-items.json を書き出す。
# shuu5/loom-plugin-dev の Issue 42, 43 と shuu5/other-repo の Issue 56 を含む。
_write_cross_repo_board_items() {
  _write_board_items '{"items": [
    {"content": {"number": 42, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Todo",        "title": "Issue 42"},
    {"content": {"number": 43, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "In Progress", "title": "Issue 43"},
    {"content": {"number": 56, "repository": "shuu5/other-repo",      "type": "Issue"}, "status": "Todo",        "title": "Issue other-repo#56"}
  ]}'
}

# _stub_gh_single_project
# リポジトリに1つのプロジェクト（タイトル "loom-plugin-dev board", number 5）が
# リンクされている標準スタブ。item-list は $SANDBOX/board-items.json を返す。
_stub_gh_single_project() {
  stub_command "uuidgen" 'echo "test-uuid-board-0001"'
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"repo view"*"--json nameWithOwner"*)
    echo 'shuu5/loom-plugin-dev' ;;
  *"project list"*)
    echo '{"projects": [{"number": 5, "title": "loom-plugin-dev board"}]}' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_abc", "title": "loom-plugin-dev board", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"project item-list"*)
    cat "${SANDBOX}/board-items.json" ;;
  *"issue view"*"--json number"*)
    num=$(echo "$*" | grep -oP "\b\d+\b" | tail -1)
    echo "{\"number\": $num}" ;;
  *"issue view"*"--json body"*)
    echo "No dependencies" ;;
  *"api"*"comments"*)
    echo "[]" ;;
  *)
    echo "{}" ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"
}

# _stub_gh_cross_repo_project
# クロスリポジトリ Board スタブ。
# shuu5/loom-plugin-dev の Issue 42, 43 と shuu5/other-repo の Issue 56 を含む Board を返す。
# issue view は -R other-repo の呼び出しも処理する。
_stub_gh_cross_repo_project() {
  stub_command "uuidgen" 'echo "test-uuid-cross-repo-0001"'
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"repo view"*"--json nameWithOwner"*)
    echo 'shuu5/loom-plugin-dev' ;;
  *"project list"*)
    echo '{"projects": [{"number": 5, "title": "loom-plugin-dev board"}]}' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_abc", "title": "loom-plugin-dev board", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"project item-list"*)
    cat "${SANDBOX}/board-items.json" ;;
  *"-R shuu5/other-repo"*"issue view"*"--json number"*)
    echo '{"number": 56}' ;;
  *"-R shuu5/other-repo"*"issue view"*"--json body"*)
    echo "No dependencies" ;;
  *"issue view"*"--json number"*)
    num=$(echo "$*" | grep -oP "\b\d+\b" | tail -1)
    echo "{\"number\": $num}" ;;
  *"issue view"*"--json body"*)
    echo "No dependencies" ;;
  *"api"*"other-repo"*"comments"*)
    echo "[]" ;;
  *"api"*"comments"*)
    echo "[]" ;;
  *)
    echo "{}" ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"
}
