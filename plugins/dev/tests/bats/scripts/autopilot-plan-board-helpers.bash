# autopilot-plan-board-helpers.bash - shared stubs for --board mode tests

# _write_board_items <json>
# JSON を $SANDBOX/board-items.json に書き出す。
_write_board_items() {
  printf '%s\n' "$1" > "$SANDBOX/board-items.json"
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
    echo '{"nameWithOwner": "shuu5/loom-plugin-dev"}' ;;
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
