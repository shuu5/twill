#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: co-issue-bugfix-45
# Generated from: openspec/changes/co-issue-bugfix-45/specs/
# Coverage level: edge-cases
#
# Scenarios:
#   label-passthrough.md    (3) - co-issue 推奨ラベル受け渡しチェーン
#   project-detection.md    (3) - project-board-sync Project 検出改善
#   context-fallback.md     (3) - Context フィールドのフォールバック推定
# =============================================================================
set -uo pipefail

# Project root (relative to test file location)
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Counters
PASS=0
FAIL=0
SKIP=0
ERRORS=()

# --- Test Helpers ---

assert_file_exists() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]]
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qiP -- "$pattern" "${PROJECT_ROOT}/${file}"
}

assert_file_contains_all() {
  local file="$1"
  shift
  local patterns=("$@")
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  for pattern in "${patterns[@]}"; do
    grep -qiP -- "$pattern" "${PROJECT_ROOT}/${file}" || return 1
  done
  return 0
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  if grep -qiP -- "$pattern" "${PROJECT_ROOT}/${file}"; then
    return 1
  fi
  return 0
}

run_test() {
  local name="$1"
  local func="$2"
  local result
  result=0
  $func || result=$?
  if [[ $result -eq 0 ]]; then
    echo "  PASS: ${name}"
    ((PASS++)) || true
  else
    echo "  FAIL: ${name}"
    ((FAIL++)) || true
    ERRORS+=("${name}")
  fi
}

run_test_skip() {
  local name="$1"
  local reason="$2"
  echo "  SKIP: ${name} (${reason})"
  ((SKIP++)) || true
}

# Target files
SKILL_MD="skills/co-issue/SKILL.md"
BOARD_SYNC_MD="commands/project-board-sync.md"

# =============================================================================
# Requirement: co-issue 推奨ラベル受け渡しチェーン
# Source: openspec/changes/co-issue-bugfix-45/specs/label-passthrough.md
# =============================================================================
echo ""
echo "--- Requirement: co-issue 推奨ラベル受け渡しチェーン ---"

# Scenario: 推奨ラベルあり時のラベル自動付与 (line 7)
# WHEN: issue-structure が ## 推奨ラベル セクションに ctx/workflow を出力する
# THEN: co-issue は ctx/workflow を抽出し、issue-create の --label ctx/workflow 引数に含める

test_label_extraction_from_issue_structure() {
  # SKILL.md must mention that the ## 推奨ラベル section is read from issue-structure output
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "推奨ラベル|recommended.*label"
}

test_label_passed_to_issue_create() {
  # SKILL.md must document that --label is forwarded to issue-create
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "\-\-label"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "推奨ラベルあり: issue-structure 出力から推奨ラベルセクションを参照" test_label_extraction_from_issue_structure
  run_test "推奨ラベルあり: --label 引数として issue-create に渡す記述がある" test_label_passed_to_issue_create
else
  run_test_skip "推奨ラベルあり: issue-structure 出力から推奨ラベルセクションを参照" "${SKILL_MD} not found"
  run_test_skip "推奨ラベルあり: --label 引数として issue-create に渡す記述がある" "${SKILL_MD} not found"
fi

# Scenario: 推奨ラベルなし時のスキップ (line 11)
# WHEN: issue-structure の出力に ## 推奨ラベル セクションが存在しない
# THEN: co-issue は --label 引数を付与せず issue-create を呼び出す

test_label_absent_no_label_arg() {
  # SKILL.md must document conditional label attachment (only when section exists)
  assert_file_exists "$SKILL_MD" || return 1
  # The skill must describe conditional logic: label only when present
  assert_file_contains "$SKILL_MD" "推奨ラベル.*存在|存在.*推奨ラベル|ラベル.*ない.*スキップ|IF.*label|label.*if|ラベル.*なし|ない.*場合.*label"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "推奨ラベルなし: ラベルなし時は --label なしで issue-create を呼び出す記述がある" test_label_absent_no_label_arg
else
  run_test_skip "推奨ラベルなし: ラベルなし時は --label なしで issue-create を呼び出す記述がある" "${SKILL_MD} not found"
fi

# Scenario: 複数 Issue 一括作成時のラベル個別適用 (line 15)
# WHEN: Phase 2 で複数 Issue に分解され、各 issue-structure が異なる ctx/* ラベルを出力する
# THEN: 各 Issue に対応する推奨ラベルが個別に issue-create の --label 引数に渡される

test_label_per_issue_in_bulk() {
  # SKILL.md must describe that each issue gets its own label in bulk create path
  assert_file_exists "$SKILL_MD" || return 1
  # bulk-create or loop over issues each with label
  assert_file_contains "$SKILL_MD" "bulk-create|bulk_create|issue-bulk-create|各.*Issue|per.*issue|ループ"
}

test_label_individual_for_each_issue() {
  # SKILL.md must not apply a single global label to all issues — each issue gets its own
  assert_file_exists "$SKILL_MD" || return 1
  # Per-issue の推奨ラベル抽出が記述されている（各 Issue の構造化ループ内で recommended_labels に記録）
  assert_file_contains "$SKILL_MD" "recommended_labels"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "複数 Issue 一括作成: issue-bulk-create パスが記述されている" test_label_per_issue_in_bulk
  run_test "複数 Issue 一括作成: 各 Issue に個別ラベルを適用する記述がある [edge]" test_label_individual_for_each_issue
else
  run_test_skip "複数 Issue 一括作成: issue-bulk-create パスが記述されている" "${SKILL_MD} not found"
  run_test_skip "複数 Issue 一括作成: 各 Issue に個別ラベルを適用する記述がある [edge]" "${SKILL_MD} not found"
fi

# =============================================================================
# Requirement: project-board-sync の Project 検出改善
# Source: openspec/changes/co-issue-bugfix-45/specs/project-detection.md
# =============================================================================
echo ""
echo "--- Requirement: project-board-sync の Project 検出改善 ---"

# Scenario: リポジトリ名と Project タイトルが一致する場合 (line 7)
# WHEN: リポジトリ shuu5/loom-plugin-dev にリンクされた Project が loom-plugin-dev (#3) と
#       ipatho1 研究基盤 (#5) の2つ存在する
# THEN: Project タイトルがリポジトリ名を含む loom-plugin-dev (#3) が選択される

test_project_title_match_preferred() {
  # project-board-sync.md must document title-based matching as the primary selection strategy
  assert_file_exists "$BOARD_SYNC_MD" || return 1
  assert_file_contains "$BOARD_SYNC_MD" "タイトル.*マッチ|title.*match|リポジトリ名.*タイトル|タイトル.*リポジトリ名|name.*match|マッチング"
}

test_project_title_contains_repo_name() {
  # Must explicitly document that matching checks if title contains repo name
  assert_file_exists "$BOARD_SYNC_MD" || return 1
  assert_file_contains "$BOARD_SYNC_MD" "リポジトリ名.*含む|含む.*リポジトリ名|contains.*repo.*name|repo.*name.*contains|title.*include"
}

if [[ -f "${PROJECT_ROOT}/${BOARD_SYNC_MD}" ]]; then
  run_test "タイトルマッチ優先: タイトルマッチングによる Project 選択が記述されている" test_project_title_match_preferred
  run_test "タイトルマッチ優先: リポジトリ名をタイトルが含む場合に優先することが記述されている [edge]" test_project_title_contains_repo_name
else
  run_test_skip "タイトルマッチ優先: タイトルマッチングによる Project 選択が記述されている" "${BOARD_SYNC_MD} not found"
  run_test_skip "タイトルマッチ優先: リポジトリ名をタイトルが含む場合に優先することが記述されている [edge]" "${BOARD_SYNC_MD} not found"
fi

# Scenario: タイトルマッチなしの場合のフォールバック (line 11)
# WHEN: リポジトリにリンクされた複数の Project のいずれもタイトルがリポジトリ名と一致しない
# THEN: リポジトリがリンクされた最初の Project を使用し、警告メッセージを出力する

test_project_fallback_to_first() {
  # Must document fallback behavior when no title matches
  assert_file_exists "$BOARD_SYNC_MD" || return 1
  assert_file_contains "$BOARD_SYNC_MD" "最初.*Project|最初.*project|first.*project|フォールバック|fallback"
}

test_project_fallback_warning() {
  # Must document that a warning is emitted when falling back
  assert_file_exists "$BOARD_SYNC_MD" || return 1
  assert_file_contains "$BOARD_SYNC_MD" "警告|warning|⚠️|warn"
}

if [[ -f "${PROJECT_ROOT}/${BOARD_SYNC_MD}" ]]; then
  run_test "フォールバック: マッチなし時は最初の Project を使用することが記述されている" test_project_fallback_to_first
  run_test "フォールバック: 警告メッセージを出力することが記述されている [edge]" test_project_fallback_warning
else
  run_test_skip "フォールバック: マッチなし時は最初の Project を使用することが記述されている" "${BOARD_SYNC_MD} not found"
  run_test_skip "フォールバック: 警告メッセージを出力することが記述されている [edge]" "${BOARD_SYNC_MD} not found"
fi

# Scenario: 単一 Project の場合 (line 15)
# WHEN: リポジトリにリンクされた Project が1つのみ
# THEN: その Project がそのまま使用され、マッチングロジックはスキップされる

test_single_project_no_matching() {
  # Must document that with a single project no matching is needed
  assert_file_exists "$BOARD_SYNC_MD" || return 1
  # Either "1件" / "1つ" / "single" / "1 project" with skip/そのまま phrasing
  assert_file_contains "$BOARD_SYNC_MD" "1件|1つ|single|1.*project|project.*1"
}

test_single_project_matching_skipped() {
  # Must explicitly say matching logic is skipped for a single project
  assert_file_exists "$BOARD_SYNC_MD" || return 1
  assert_file_contains "$BOARD_SYNC_MD" "スキップ|skip|そのまま|directly"
}

if [[ -f "${PROJECT_ROOT}/${BOARD_SYNC_MD}" ]]; then
  run_test "単一 Project: 1件のみの場合がドキュメントされている" test_single_project_no_matching
  run_test "単一 Project: マッチングロジックをスキップする記述がある [edge]" test_single_project_matching_skipped
else
  run_test_skip "単一 Project: 1件のみの場合がドキュメントされている" "${BOARD_SYNC_MD} not found"
  run_test_skip "単一 Project: マッチングロジックをスキップする記述がある [edge]" "${BOARD_SYNC_MD} not found"
fi

# =============================================================================
# Requirement: Context フィールドのフォールバック推定
# Source: openspec/changes/co-issue-bugfix-45/specs/context-fallback.md
# =============================================================================
echo ""
echo "--- Requirement: Context フィールドのフォールバック推定 ---"

# Scenario: ctx/* ラベルなしで architecture/ に context 定義がある場合 (line 7)
# WHEN: Issue に ctx/* ラベルが付与されておらず、リポジトリに architecture/domain/contexts/*.md が存在する
# THEN: Issue のタイトル・本文と各 context の責務を照合し、最も関連性の高い Context オプションを設定する

test_ctx_fallback_reads_architecture() {
  # project-board-sync.md must document reading architecture/domain/contexts/*.md for fallback
  assert_file_exists "$BOARD_SYNC_MD" || return 1
  assert_file_contains "$BOARD_SYNC_MD" "architecture/|architecture.*context|context.*architecture"
}

test_ctx_fallback_keyword_match() {
  # Must document that title/body is matched against context responsibilities
  assert_file_exists "$BOARD_SYNC_MD" || return 1
  assert_file_contains "$BOARD_SYNC_MD" "タイトル.*本文|本文.*タイトル|title.*body|body.*title|キーワード|keyword|マッチ|match|照合"
}

test_ctx_fallback_sets_highest_relevance() {
  # Must document selecting the most relevant context option
  assert_file_exists "$BOARD_SYNC_MD" || return 1
  assert_file_contains "$BOARD_SYNC_MD" "最も.*関連|関連.*最も|最高.*関連|highest.*relevance|most.*relevant|最も近い"
}

if [[ -f "${PROJECT_ROOT}/${BOARD_SYNC_MD}" ]]; then
  run_test "ctx フォールバック: architecture/domain/contexts/*.md を参照する記述がある" test_ctx_fallback_reads_architecture
  run_test "ctx フォールバック: Issue タイトル・本文とキーワードマッチする記述がある" test_ctx_fallback_keyword_match
  run_test "ctx フォールバック: 最も関連性の高い Context を設定する記述がある [edge]" test_ctx_fallback_sets_highest_relevance
else
  run_test_skip "ctx フォールバック: architecture/domain/contexts/*.md を参照する記述がある" "${BOARD_SYNC_MD} not found"
  run_test_skip "ctx フォールバック: Issue タイトル・本文とキーワードマッチする記述がある" "${BOARD_SYNC_MD} not found"
  run_test_skip "ctx フォールバック: 最も関連性の高い Context を設定する記述がある [edge]" "${BOARD_SYNC_MD} not found"
fi

# Scenario: architecture/ が存在しない場合 (line 11)
# WHEN: リポジトリに architecture/ ディレクトリが存在しない
# THEN: Context フィールドの設定をスキップし、既存の動作（スキップ）を維持する

test_ctx_fallback_no_architecture_skip() {
  # Must document graceful skip when architecture/ is absent
  assert_file_exists "$BOARD_SYNC_MD" || return 1
  assert_file_contains "$BOARD_SYNC_MD" "architecture.*存在.*ない|存在しない.*architecture|architecture.*not.*exist|architecture.*なし.*スキップ|スキップ.*architecture.*なし"
}

if [[ -f "${PROJECT_ROOT}/${BOARD_SYNC_MD}" ]]; then
  run_test "architecture/ なし: architecture/ が存在しない場合はスキップする記述がある" test_ctx_fallback_no_architecture_skip
else
  run_test_skip "architecture/ なし: architecture/ が存在しない場合はスキップする記述がある" "${BOARD_SYNC_MD} not found"
fi

# Scenario: マッチする context がない場合 (line 15)
# WHEN: Issue 内容がいずれの context の責務とも一致しない
# THEN: Context フィールドの設定をスキップし、警告メッセージ「Context を推定できませんでした」を出力する

test_ctx_fallback_no_match_warning() {
  # Must document warning when no context can be inferred
  assert_file_exists "$BOARD_SYNC_MD" || return 1
  assert_file_contains "$BOARD_SYNC_MD" "Context.*推定.*できません|推定できません|cannot.*infer.*context|no.*context.*match"
}

test_ctx_fallback_no_match_skip() {
  # Must document that Context field is skipped (not set to a default) when no match
  assert_file_exists "$BOARD_SYNC_MD" || return 1
  assert_file_contains "$BOARD_SYNC_MD" "スキップ|skip"
}

if [[ -f "${PROJECT_ROOT}/${BOARD_SYNC_MD}" ]]; then
  run_test "マッチなし: 警告メッセージ「Context を推定できませんでした」が記述されている" test_ctx_fallback_no_match_warning
  run_test "マッチなし: Context フィールドをスキップする記述がある [edge]" test_ctx_fallback_no_match_skip
else
  run_test_skip "マッチなし: 警告メッセージ「Context を推定できませんでした」が記述されている" "${BOARD_SYNC_MD} not found"
  run_test_skip "マッチなし: Context フィールドをスキップする記述がある [edge]" "${BOARD_SYNC_MD} not found"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "==========================================="
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "==========================================="

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "Failed tests:"
  for err in "${ERRORS[@]}"; do
    echo "  - ${err}"
  done
fi

exit $FAIL
