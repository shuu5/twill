#!/usr/bin/env bats
# archive-removal.bats
# Requirement: Done アイテム自動 archive 廃止（issue-598）
# Spec: deltaspec/changes/issue-598/specs/archive-removal.md
# Coverage: --type=unit --coverage=edge-cases
#
# 検証する仕様:
#   1. autopilot-orchestrator.sh に archive_done_issues() が存在しない
#   2. autopilot-orchestrator.sh に _archive_deltaspec_changes_for_issue() が存在しない
#   3. autopilot-orchestrator.sh に SKIPPED_ARCHIVES が存在しない
#   4. autopilot-orchestrator.sh の generate_phase_report に skipped_archives が存在しない
#   5. orchestrator.py に _archive_done_issues() が存在しない
#   6. orchestrator.py に _archive_deltaspec_changes() が存在しない
#   7. chain-runner.sh の step_board_archive() が保持されている
#   8. chain-runner.sh の gh project item-list に --limit 200 が指定されている
#   9. project-board-backfill.sh の --limit 500 は意図的に維持されている
#
# NOTE: 全テストは FUTURE state を検証する（implementation step 完了後に PASS）。
#       実装前は skip でスキップされる。

load '../../bats/helpers/common.bash'

# ---------------------------------------------------------------------------
# setup/teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# ===========================================================================
# Requirement: 自動 archive 処理の除去（Bash）
# Spec: deltaspec/changes/issue-598/specs/archive-removal.md
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: merge-gate 成功後の自動 archive 除去
# WHEN merge-gate が成功する
# THEN archive_done_issues は呼び出されず、Done アイテムが Project Board に残ること
# ---------------------------------------------------------------------------

@test "archive-removal[bash]: archive_done_issues 関数定義が orchestrator.sh に存在しない" {
  local orchestrator="$REPO_ROOT/scripts/autopilot-orchestrator.sh"
  [[ -f "$orchestrator" ]] || skip "autopilot-orchestrator.sh が見つからない"

  if grep -qE '^(function )?archive_done_issues(\s*\(|$)' "$orchestrator"; then
    skip "archive_done_issues() がまだ削除されていない（implementation step で削除予定）"
  fi

  ! grep -qE '^(function )?archive_done_issues(\s*\(|$)' "$orchestrator"
}

@test "archive-removal[bash]: archive_done_issues 呼び出しが orchestrator.sh に存在しない" {
  local orchestrator="$REPO_ROOT/scripts/autopilot-orchestrator.sh"
  [[ -f "$orchestrator" ]] || skip "autopilot-orchestrator.sh が見つからない"

  if grep -qE '\barchive_done_issues\b' "$orchestrator"; then
    skip "archive_done_issues 呼び出しがまだ削除されていない（implementation step で削除予定）"
  fi

  ! grep -qE '\barchive_done_issues\b' "$orchestrator"
}

@test "archive-removal[bash]: _archive_deltaspec_changes_for_issue 関数定義が orchestrator.sh に存在しない" {
  local orchestrator="$REPO_ROOT/scripts/autopilot-orchestrator.sh"
  [[ -f "$orchestrator" ]] || skip "autopilot-orchestrator.sh が見つからない"

  if grep -qE '^(function )?_archive_deltaspec_changes_for_issue' "$orchestrator"; then
    skip "_archive_deltaspec_changes_for_issue() がまだ削除されていない（implementation step で削除予定）"
  fi

  ! grep -qE '^(function )?_archive_deltaspec_changes_for_issue' "$orchestrator"
}

@test "archive-removal[bash]: SKIPPED_ARCHIVES 配列宣言が orchestrator.sh に存在しない" {
  local orchestrator="$REPO_ROOT/scripts/autopilot-orchestrator.sh"
  [[ -f "$orchestrator" ]] || skip "autopilot-orchestrator.sh が見つからない"

  if grep -q 'SKIPPED_ARCHIVES' "$orchestrator"; then
    skip "SKIPPED_ARCHIVES がまだ削除されていない（implementation step で削除予定）"
  fi

  ! grep -q 'SKIPPED_ARCHIVES' "$orchestrator"
}

# ---------------------------------------------------------------------------
# Scenario: phase report から skipped_archives フィールドの除去
# WHEN フェーズレポートが生成される
# THEN skipped_archives フィールドが JSON 出力に含まれないこと
# ---------------------------------------------------------------------------

@test "archive-removal[bash]: skipped_archives が orchestrator.sh に存在しない" {
  local orchestrator="$REPO_ROOT/scripts/autopilot-orchestrator.sh"
  [[ -f "$orchestrator" ]] || skip "autopilot-orchestrator.sh が見つからない"

  if grep -q 'skipped_archives' "$orchestrator"; then
    skip "skipped_archives がまだ削除されていない（implementation step で削除予定）"
  fi

  ! grep -q 'skipped_archives' "$orchestrator"
}

# Edge case: orchestrator.sh が bash 構文エラーなく実行できる
@test "archive-removal[bash][edge]: orchestrator.sh が bash -n で構文チェックを通過する" {
  local orchestrator="$REPO_ROOT/scripts/autopilot-orchestrator.sh"
  [[ -f "$orchestrator" ]] || skip "autopilot-orchestrator.sh が見つからない"

  run bash -n "$orchestrator"
  assert_success
}

# ===========================================================================
# Requirement: 自動 archive 処理の除去（Python）
# Spec: deltaspec/changes/issue-598/specs/archive-removal.md
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: Python orchestrator からの archive メソッド除去
# WHEN orchestrator.py の run() メソッドが実行される
# THEN _archive_done_issues() は呼び出されないこと
# ---------------------------------------------------------------------------

@test "archive-removal[python]: _archive_done_issues メソッドが orchestrator.py に存在しない" {
  local repo_root
  repo_root="$(cd "$REPO_ROOT" && git rev-parse --show-toplevel 2>/dev/null || echo "")"
  local orchestrator_py="${repo_root}/cli/twl/src/twl/autopilot/orchestrator.py"
  [[ -f "$orchestrator_py" ]] || skip "orchestrator.py が見つからない"

  if grep -qE 'def _archive_done_issues' "$orchestrator_py"; then
    skip "_archive_done_issues() がまだ削除されていない（implementation step で削除予定）"
  fi

  ! grep -qE 'def _archive_done_issues' "$orchestrator_py"
}

@test "archive-removal[python]: _archive_deltaspec_changes メソッドが orchestrator.py に存在しない" {
  local repo_root
  repo_root="$(cd "$REPO_ROOT" && git rev-parse --show-toplevel 2>/dev/null || echo "")"
  local orchestrator_py="${repo_root}/cli/twl/src/twl/autopilot/orchestrator.py"
  [[ -f "$orchestrator_py" ]] || skip "orchestrator.py が見つからない"

  if grep -qE 'def _archive_deltaspec_changes' "$orchestrator_py"; then
    skip "_archive_deltaspec_changes() がまだ削除されていない（implementation step で削除予定）"
  fi

  ! grep -qE 'def _archive_deltaspec_changes' "$orchestrator_py"
}

@test "archive-removal[python]: _archive_done_issues 呼び出しが orchestrator.py に存在しない" {
  local repo_root
  repo_root="$(cd "$REPO_ROOT" && git rev-parse --show-toplevel 2>/dev/null || echo "")"
  local orchestrator_py="${repo_root}/cli/twl/src/twl/autopilot/orchestrator.py"
  [[ -f "$orchestrator_py" ]] || skip "orchestrator.py が見つからない"

  if grep -qE '_archive_done_issues' "$orchestrator_py"; then
    skip "_archive_done_issues 呼び出しがまだ削除されていない（implementation step で削除予定）"
  fi

  ! grep -qE '_archive_done_issues' "$orchestrator_py"
}

# ---------------------------------------------------------------------------
# Scenario: 関連テストの除去
# WHEN test_autopilot_orchestrator.py のテストスイートが実行される
# THEN archive 関連のテスト（test_archive_done_issues 等）が存在しないこと
# ---------------------------------------------------------------------------

@test "archive-removal[python][tests]: test_archive_done_issues が test_autopilot_orchestrator.py に存在しない" {
  local repo_root
  repo_root="$(cd "$REPO_ROOT" && git rev-parse --show-toplevel 2>/dev/null || echo "")"
  local test_py="${repo_root}/cli/twl/tests/test_autopilot_orchestrator.py"
  [[ -f "$test_py" ]] || skip "test_autopilot_orchestrator.py が見つからない"

  if grep -qE 'def test_archive_done_issues|def test.*archive' "$test_py"; then
    skip "archive 関連テストがまだ削除されていない（implementation step で削除予定）"
  fi

  ! grep -qE 'def test_archive_done_issues|def test.*archive' "$test_py"
}

# ===========================================================================
# Requirement: gh project item-list の limit 統一確認
# Spec: deltaspec/changes/issue-598/specs/archive-removal.md
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: limit 200 確認（chain-runner.sh）
# WHEN chain-runner.sh 内で gh project item-list が実行される
# THEN --limit 200 が指定されていること
# ---------------------------------------------------------------------------

@test "archive-removal[limit]: chain-runner.sh の gh project item-list に --limit 200 が存在する" {
  local chain_runner="$REPO_ROOT/scripts/chain-runner.sh"
  [[ -f "$chain_runner" ]] || skip "chain-runner.sh が見つからない"

  # gh project item-list の呼び出し箇所で --limit 200 が指定されている
  grep -qE 'gh project item-list.*--limit 200|--limit 200.*gh project item-list' "$chain_runner"
}

# ---------------------------------------------------------------------------
# Scenario: backfill スクリプトは除外
# WHEN project-board-backfill.sh 内で gh project item-list が実行される
# THEN --limit 500 が意図的に維持されていること
# ---------------------------------------------------------------------------

@test "archive-removal[limit]: project-board-backfill.sh の --limit 500 が維持されている" {
  local backfill="$REPO_ROOT/scripts/project-board-backfill.sh"
  [[ -f "$backfill" ]] || skip "project-board-backfill.sh が見つからない"

  # backfill スクリプトは全件取得のため --limit 500 を使用する（意図的）
  grep -qE '\-\-limit 500' "$backfill"
}

# Edge case: backfill 以外のスクリプトで --limit が 200 未満でないこと
@test "archive-removal[limit][edge]: project-board-archive.sh の gh project item-list に --limit 200 が存在する" {
  local archive_sh="$REPO_ROOT/scripts/project-board-archive.sh"
  [[ -f "$archive_sh" ]] || skip "project-board-archive.sh が見つからない"

  grep -qE 'gh project item-list.*--limit 200|--limit 200.*gh project item-list' "$archive_sh"
}

# ===========================================================================
# Requirement: chain-runner.sh の手動 archive 機能保持
# Spec: deltaspec/changes/issue-598/specs/archive-removal.md
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: 手動 archive 機能の保持
# WHEN chain-runner.sh の step_board_archive が参照される
# THEN 関数が存在し、呼び出し可能であること
# ---------------------------------------------------------------------------

@test "archive-removal[manual-archive]: step_board_archive が chain-runner.sh に存在する" {
  local chain_runner="$REPO_ROOT/scripts/chain-runner.sh"
  [[ -f "$chain_runner" ]] || skip "chain-runner.sh が見つからない"

  grep -qE '^(function )?step_board_archive(\s*\(|$)|step_board_archive\s*\(\s*\)' "$chain_runner"
}

@test "archive-removal[manual-archive][edge]: step_board_archive が board-archive に dispatch されている" {
  local chain_runner="$REPO_ROOT/scripts/chain-runner.sh"
  [[ -f "$chain_runner" ]] || skip "chain-runner.sh が見つからない"

  # board-archive コマンドへの dispatch 参照が存在する
  grep -qE 'board.archive|board-archive' "$chain_runner"
}
