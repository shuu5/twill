#!/usr/bin/env bats
# project-board-refined-migrate.bats - Refined label → Status field 一括 migration テスト
#
# Issue #943: AC8 - 既存 refined label 付き Issue の Status 一括 migration script
# script: plugins/twl/scripts/project-board-refined-migrate.sh
#
# AC2: Refined option ID `3d983780` の存在確認
# AC8: dry-run default、冪等、0-count 対応
#
# Scenarios:
#   M1: --dry-run + label 付き Issue あり → Status 変更なし、report のみ
#   M2: --force + 0件 + Refined option ID `3d983780` 存在確認 → 正常終了
#   M3: --force + 既に Status=Refined → 冪等（skip）

load '../helpers/common'
load './autopilot-plan-board-helpers'

setup() {
  common_setup

  # project-board-refined-migrate.sh が実装前は存在しないため RED になる

  stub_command "git" 'echo "stub-git"'
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# M1: --dry-run + label 付き Issue あり → Status 変更なし、report のみ
# ---------------------------------------------------------------------------

# WHEN: refined label 付き Issue がある状態で --dry-run を実行する
# THEN: gh project item-edit が呼ばれず、report のみ出力される
# RED: project-board-refined-migrate.sh が未実装
@test "M1: --dry-run + refined label 付き Issue あり → Status 変更なし、report のみ" {
  # AC8: dry-run default
  local gh_calls_log="$SANDBOX/gh-calls.log"

  _write_board_items '{"items": [
    {"content": {"number": 101, "repository": "shuu5/twill", "type": "Issue"}, "status": "Todo", "title": "Issue 101 with refined label"},
    {"content": {"number": 102, "repository": "shuu5/twill", "type": "Issue"}, "status": "In Progress", "title": "Issue 102 with refined label"}
  ]}'

  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
echo "gh $*" >> "${SANDBOX}/gh-calls.log"
case "$*" in
  *"project item-list"*)
    cat "${SANDBOX}/board-items.json" ;;
  *"issue view"*"--json labels"*)
    # 両 Issue に refined label あり
    echo '{"labels": [{"name": "refined"}, {"name": "enhancement"}]}' ;;
  *"issue view"*"--json projectItems"*)
    echo '{"projectItems": {"nodes": [{"id": "PVTI_abc", "status": {"name": "Todo"}, "project": {"number": 5}}]}}' ;;
  *)
    echo "{}" ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  # project-board-refined-migrate.sh が未実装 → RED
  [ -f "$SANDBOX/scripts/project-board-refined-migrate.sh" ] || {
    false
  }

  run bash "$SANDBOX/scripts/project-board-refined-migrate.sh" \
    --dry-run \
    --project-dir "$SANDBOX"

  assert_success
  assert_output --partial "dry-run"
  # Status を実際に変更する gh project item-edit が呼ばれていないこと
  run grep "project item-edit" "$gh_calls_log"
  assert_failure
}

# ---------------------------------------------------------------------------
# M2: --force + 0件 + Refined option ID `3d983780` 存在確認 → 正常終了
# ---------------------------------------------------------------------------

# WHEN: refined label 付き Issue が 0 件で --force を実行する
# THEN: 正常終了し、Refined option ID `3d983780` の存在を事前確認する
# RED: project-board-refined-migrate.sh の 0件対応 + option ID 確認が未実装
@test "M2: --force + 0件 + Refined option ID 3d983780 存在確認 → 正常終了" {
  # AC2, AC8: 0-count 対応 + Refined option ID 確認
  local gh_calls_log="$SANDBOX/gh-calls.log"

  _write_board_items '{"items": [
    {"content": {"number": 103, "repository": "shuu5/twill", "type": "Issue"}, "status": "Todo", "title": "Issue 103 no refined label"}
  ]}'

  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
echo "gh $*" >> "${SANDBOX}/gh-calls.log"
case "$*" in
  *"project item-list"*)
    cat "${SANDBOX}/board-items.json" ;;
  *"issue view"*"--json labels"*)
    # refined label なし
    echo '{"labels": [{"name": "enhancement"}]}' ;;
  *"api graphql"*"projectV2"*"fields"*)
    # Refined option ID `3d983780` を含む field 定義を返す
    echo '{"data": {"user": {"projectV2": {"fields": {"nodes": [{"name": "Status", "options": [{"id": "3d983780", "name": "Refined"}, {"id": "other-id", "name": "Todo"}]}]}}}}}' ;;
  *)
    echo "{}" ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  # project-board-refined-migrate.sh が未実装 → RED
  [ -f "$SANDBOX/scripts/project-board-refined-migrate.sh" ] || {
    false
  }

  run bash "$SANDBOX/scripts/project-board-refined-migrate.sh" \
    --force \
    --project-dir "$SANDBOX"

  assert_success
  # Refined option ID の確認が行われていること
  run grep "graphql" "$gh_calls_log"
  assert_success
  # 0件のため "移行対象 0 件" または同等のメッセージ
  assert_output --partial "0"
}

# ---------------------------------------------------------------------------
# M3: --force + 既に Status=Refined → 冪等（skip）
# ---------------------------------------------------------------------------

# WHEN: 既に Status=Refined の Issue に対して --force を実行する
# THEN: skip されて Status 変更が行われない（冪等）
# RED: project-board-refined-migrate.sh の冪等ロジックが未実装
@test "M3: --force + 既に Status=Refined → 冪等（skip）" {
  # AC8: 冪等
  local gh_calls_log="$SANDBOX/gh-calls.log"

  _write_board_items '{"items": [
    {"content": {"number": 104, "repository": "shuu5/twill", "type": "Issue"}, "status": "Refined", "title": "Issue 104 already Refined"}
  ]}'

  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
echo "gh $*" >> "${SANDBOX}/gh-calls.log"
case "$*" in
  *"project item-list"*)
    cat "${SANDBOX}/board-items.json" ;;
  *"issue view"*"--json labels"*)
    echo '{"labels": [{"name": "refined"}, {"name": "enhancement"}]}' ;;
  *"issue view"*"--json projectItems"*)
    # 既に Status=Refined
    echo '{"projectItems": {"nodes": [{"id": "PVTI_xyz", "status": {"name": "Refined"}, "project": {"number": 5}}]}}' ;;
  *"api graphql"*"projectV2"*"fields"*)
    echo '{"data": {"user": {"projectV2": {"fields": {"nodes": [{"name": "Status", "options": [{"id": "3d983780", "name": "Refined"}]}]}}}}}' ;;
  *)
    echo "{}" ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  # project-board-refined-migrate.sh が未実装 → RED
  [ -f "$SANDBOX/scripts/project-board-refined-migrate.sh" ] || {
    false
  }

  run bash "$SANDBOX/scripts/project-board-refined-migrate.sh" \
    --force \
    --project-dir "$SANDBOX"

  assert_success
  # Status=Refined は既に設定済みのため skip → item-edit は呼ばれない
  run grep "project item-edit" "$gh_calls_log"
  assert_failure
  # skip されたことを示すメッセージ
  assert_output --partial "skip"
}
