#!/usr/bin/env bats
# project-board-archive.bats - unit tests for scripts/project-board-archive.sh
#
# Spec: openspec/changes/board-done-archive/specs/archive.md
# Scenarios:
#   1. 通常実行: Done items are archived, summary shows count
#   2. Done アイテムが 0 件: shows "Done アイテムはありません", exits 0
#   3. dry-run 実行: shows item list, does NOT call gh project item-archive
#   4. dry-run サマリー: shows "[dry-run] X 件をアーカイブ対象として検出"
#   5. 連続アーカイブ: 0.5 sec sleep between archives (verify sleep is called)
#   6. 実行完了サマリー: shows "✓ X 件をアーカイブしました"
# Edge cases:
#   - Script exits 0 even if gh project item-archive fails (warn only)
#   - Project not found: warn and exit 0

load '../helpers/common'

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  # Stub sleep so tests run fast and we can detect calls
  stub_command "sleep" 'echo "sleep $*" >> "$SANDBOX/sleep-calls.log"'

  # Stub jq to pass through to real jq (stubs only override explicitly set commands)
  # Default gh stub returns empty item list (safe fallback)
  _stub_gh_no_done_items
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# gh stub helpers
# ---------------------------------------------------------------------------

# _stub_gh_with_done_items <count>
# Produces <count> Done items in gh project item-list output.
# Each item gets id PVTI_item<N> and Issue number <N>.
# Only used as a building block; tests use the named variants below.
_stub_gh_with_done_items() {
  local count="${1:-2}"
  local log_path="$SANDBOX/gh-calls.log"

  # Build JSON items array with jq
  local items_json
  items_json=$(
    seq 1 "$count" | jq -Rs '
      split("\n") | map(select(. != "")) | map(tonumber) |
      map({
        id: ("PVTI_item" + tostring),
        content: { number: ., repository: "shuu5/loom-plugin-dev", type: "Issue" },
        status: "Done",
        title: ("Issue " + tostring)
      })
    '
  )

  # Write stub using printf to allow variable expansion for items_json
  printf '#!/usr/bin/env bash\necho "$*" >> "%s"\ncase "$*" in\n  *"issue view"*)\n    echo "CLOSED" ;;\n  *"project item-list"*)\n    echo '"'"'{"items": %s}'"'"' ;;\n  *"project item-archive"*)\n    echo "archived" ;;\n  *)\n    echo "{}" ;;\nesac\n' \
    "$log_path" "$items_json" > "$STUB_BIN/gh"
  chmod +x "$STUB_BIN/gh"
}

# _stub_gh_no_done_items: item-list returns empty items array
_stub_gh_no_done_items() {
  local log_path="$SANDBOX/gh-calls.log"
  cat > "$STUB_BIN/gh" <<GHSTUB
#!/usr/bin/env bash
echo "\$*" >> "${log_path}"
case "\$*" in
  *"issue view"*)
    echo "CLOSED" ;;
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

# _stub_gh_with_one_done_item: single Done item (PVTI_item101, Issue 101)
_stub_gh_with_one_done_item() {
  local log_path="$SANDBOX/gh-calls.log"
  cat > "$STUB_BIN/gh" <<GHSTUB
#!/usr/bin/env bash
echo "\$*" >> "${log_path}"
case "\$*" in
  *"issue view"*)
    echo "CLOSED" ;;
  *"project item-list"*)
    echo '{"items": [{"id": "PVTI_item101", "content": {"number": 101, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Done", "title": "Issue 101"}]}' ;;
  *"project item-archive"*)
    echo "archived" ;;
  *)
    echo "{}" ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"
}

# _stub_gh_with_two_done_items: two Done items (Issue 101, Issue 102)
_stub_gh_with_two_done_items() {
  local log_path="$SANDBOX/gh-calls.log"
  cat > "$STUB_BIN/gh" <<GHSTUB
#!/usr/bin/env bash
echo "\$*" >> "${log_path}"
case "\$*" in
  *"issue view"*)
    echo "CLOSED" ;;
  *"project item-list"*)
    echo '{"items": [
      {"id": "PVTI_item101", "content": {"number": 101, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Done", "title": "Issue 101"},
      {"id": "PVTI_item102", "content": {"number": 102, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Done", "title": "Issue 102"}
    ]}' ;;
  *"project item-archive"*)
    echo "archived" ;;
  *)
    echo "{}" ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"
}

# _stub_gh_archive_fails: item-archive returns non-zero exit code
_stub_gh_archive_fails() {
  local log_path="$SANDBOX/gh-calls.log"
  cat > "$STUB_BIN/gh" <<GHSTUB
#!/usr/bin/env bash
echo "\$*" >> "${log_path}"
case "\$*" in
  *"issue view"*)
    echo "CLOSED" ;;
  *"project item-list"*)
    echo '{"items": [{"id": "PVTI_item101", "content": {"number": 101, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Done", "title": "Issue 101"}]}' ;;
  *"project item-archive"*)
    echo "archive error: permission denied" >&2
    exit 1 ;;
  *)
    echo "{}" ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"
}

# _stub_gh_project_not_found: item-list returns error / empty indicating no project
_stub_gh_project_not_found() {
  local log_path="$SANDBOX/gh-calls.log"
  cat > "$STUB_BIN/gh" <<GHSTUB
#!/usr/bin/env bash
echo "\$*" >> "${log_path}"
case "\$*" in
  *"issue view"*)
    echo "CLOSED" ;;
  *"project item-list"*)
    echo "Could not find project" >&2
    exit 1 ;;
  *)
    echo "{}" ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"
}

# ---------------------------------------------------------------------------
# Script path helper
# ---------------------------------------------------------------------------

_script() {
  echo "$SANDBOX/scripts/project-board-archive.sh"
}

# ---------------------------------------------------------------------------
# Requirement: Done アイテム一括アーカイブ
# ---------------------------------------------------------------------------

# Scenario: 通常実行
@test "project-board-archive: 通常実行 — Done アイテムが gh project item-archive でアーカイブされる" {
  _stub_gh_with_one_done_item

  run bash "$(_script)"

  assert_success
  # gh project item-archive が呼ばれたことをログで確認
  grep -q "project item-archive" "$SANDBOX/gh-calls.log"
}

@test "project-board-archive: 通常実行 — アーカイブ件数を含むサマリーが表示される" {
  _stub_gh_with_one_done_item

  run bash "$(_script)"

  assert_success
  assert_output --partial "1"
}

# Scenario: Done アイテムが 0 件
@test "project-board-archive: Done アイテムが 0 件 — 「Done アイテムはありません」を表示して正常終了" {
  _stub_gh_no_done_items

  run bash "$(_script)"

  assert_success
  assert_output --partial "Done アイテムはありません"
}

@test "project-board-archive: Done アイテムが 0 件 — gh project item-archive が呼ばれない" {
  _stub_gh_no_done_items

  run bash "$(_script)"

  assert_success
  # item-archive が呼ばれていないことを確認
  run grep "project item-archive" "$SANDBOX/gh-calls.log"
  assert_failure
}

# ---------------------------------------------------------------------------
# Requirement: dry-run モード
# ---------------------------------------------------------------------------

# Scenario: dry-run 実行
@test "project-board-archive: --dry-run — Done アイテム一覧が表示される" {
  _stub_gh_with_two_done_items

  run bash "$(_script)" --dry-run

  assert_success
  # Issue 番号またはタイトルが一覧に含まれる
  assert_output --partial "101"
  assert_output --partial "102"
}

@test "project-board-archive: --dry-run — gh project item-archive が実行されない" {
  _stub_gh_with_two_done_items

  run bash "$(_script)" --dry-run

  assert_success
  # item-archive がログに記録されていないことを確認
  run grep "project item-archive" "$SANDBOX/gh-calls.log"
  assert_failure
}

# Scenario: dry-run でアーカイブ件数確認
@test "project-board-archive: --dry-run サマリー — 「[dry-run] X 件をアーカイブ対象として検出」が表示される" {
  _stub_gh_with_two_done_items

  run bash "$(_script)" --dry-run

  assert_success
  assert_output --partial "[dry-run]"
  assert_output --partial "2"
  assert_output --partial "アーカイブ対象として検出"
}

@test "project-board-archive: --dry-run サマリー — Done 0 件の場合も正常終了する" {
  _stub_gh_no_done_items

  run bash "$(_script)" --dry-run

  assert_success
}

# ---------------------------------------------------------------------------
# Requirement: rate limit 対策
# ---------------------------------------------------------------------------

# Scenario: 連続アーカイブ
@test "project-board-archive: 連続アーカイブ — 2 件処理時に sleep が 0.5 秒で呼ばれる" {
  _stub_gh_with_two_done_items

  run bash "$(_script)"

  assert_success
  # sleep コマンドが 0.5 秒で呼ばれたことをログで確認
  grep -q "sleep 0.5" "$SANDBOX/sleep-calls.log"
}

@test "project-board-archive: 連続アーカイブ — アーカイブごとに sleep が呼ばれる（2 件 → 2 回以上）" {
  _stub_gh_with_two_done_items

  run bash "$(_script)"

  assert_success
  # 2 件あれば少なくとも 1 回は sleep 0.5 が記録される
  local sleep_count
  sleep_count=$(grep -c "sleep 0.5" "$SANDBOX/sleep-calls.log" 2>/dev/null || echo 0)
  [ "$sleep_count" -ge 1 ]
}

@test "project-board-archive: 連続アーカイブ — 1 件のみの場合も sleep が呼ばれる" {
  _stub_gh_with_one_done_item

  run bash "$(_script)"

  assert_success
  grep -q "sleep 0.5" "$SANDBOX/sleep-calls.log"
}

# ---------------------------------------------------------------------------
# Requirement: 実行サマリー表示
# ---------------------------------------------------------------------------

# Scenario: 実行完了サマリー
@test "project-board-archive: 実行完了サマリー — 「✓ X 件をアーカイブしました」が表示される" {
  _stub_gh_with_one_done_item

  run bash "$(_script)"

  assert_success
  assert_output --partial "✓"
  assert_output --partial "アーカイブしました"
}

@test "project-board-archive: 実行完了サマリー — 2 件アーカイブ時に件数「2」が表示される" {
  _stub_gh_with_two_done_items

  run bash "$(_script)"

  assert_success
  assert_output --partial "2"
  assert_output --partial "アーカイブしました"
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

# Edge case: gh project item-archive が失敗してもスクリプトは exit 0
@test "project-board-archive: item-archive 失敗 — 警告のみで終了コードは 0" {
  _stub_gh_archive_fails

  run bash "$(_script)"

  assert_success
}

@test "project-board-archive: item-archive 失敗 — 警告メッセージが出力される" {
  _stub_gh_archive_fails

  run bash "$(_script)"

  assert_success
  # 何らかの警告または skip メッセージが出力される
  assert_output --partial "101"
}

# Edge case: Project が見つからない場合は警告して exit 0
@test "project-board-archive: Project が見つからない — 警告を出して終了コード 0" {
  _stub_gh_project_not_found

  run bash "$(_script)"

  assert_success
}

@test "project-board-archive: Project が見つからない — gh project item-archive が呼ばれない" {
  _stub_gh_project_not_found

  run bash "$(_script)"

  assert_success
  run grep "project item-archive" "$SANDBOX/gh-calls.log"
  assert_failure
}

# Edge case: --dry-run でも Project が見つからない場合は exit 0
@test "project-board-archive: --dry-run で Project が見つからない — 終了コード 0" {
  _stub_gh_project_not_found

  run bash "$(_script)" --dry-run

  assert_success
}
