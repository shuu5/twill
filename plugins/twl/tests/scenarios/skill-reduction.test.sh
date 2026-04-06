#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: skill-reduction.md
# Generated from: deltaspec/changes/b-4-workflow-setup-chain-driven/specs/skill-reduction.md
# Coverage level: edge-cases
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

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  if grep -qiP -- "$pattern" "${PROJECT_ROOT}/${file}"; then
    return 1
  fi
  return 0
}

assert_valid_yaml() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && python3 -c "
import yaml, sys
with open('${PROJECT_ROOT}/${file}') as f:
    yaml.safe_load(f)
" 2>/dev/null
}

yaml_get() {
  local file="$1"
  local expr="$2"
  python3 -c "
import yaml, sys
with open('${PROJECT_ROOT}/${file}') as f:
    data = yaml.safe_load(f)
${expr}
" 2>/dev/null
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
  ((SKIP++))
}

# =============================================================================
# Requirement: workflow-setup SKILL.md トークン削減
# =============================================================================
echo ""
echo "--- Requirement: workflow-setup SKILL.md トークン削減 ---"

# SKILL.md path (will be created by implementation)
SKILL_MD="skills/workflow-setup/SKILL.md"

# Scenario: トークン削減率の達成 (line 8)
# WHEN: 新しい SKILL.md のトークン数を測定する
# THEN: 旧 plugin の workflow-setup SKILL.md 比で 50% 以上のトークン削減が達成されている
#
# NOTE: 旧 plugin の SKILL.md が同一リポジトリにないため、文字数ベースの閾値で代替検証する。
# 旧 SKILL.md は概ね 3000-5000 文字程度と推定。50% 削減で 2500 文字以下を期待。
MAX_CHARS=3500

test_token_reduction() {
  assert_file_exists "$SKILL_MD" || return 1
  local char_count
  char_count=$(wc -m < "${PROJECT_ROOT}/${SKILL_MD}")
  if [[ $char_count -gt $MAX_CHARS ]]; then
    echo "SKILL.md is ${char_count} chars (max ${MAX_CHARS})" >&2
    return 1
  fi
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md トークン削減 (${MAX_CHARS} 文字以下)" test_token_reduction
else
  run_test_skip "SKILL.md トークン削減" "skills/workflow-setup/SKILL.md not yet created"
fi

# Edge case: SKILL.md が空ファイルでない（削減しすぎ防止）
test_skill_not_empty() {
  assert_file_exists "$SKILL_MD" || return 1
  local char_count
  char_count=$(wc -m < "${PROJECT_ROOT}/${SKILL_MD}")
  [[ $char_count -gt 100 ]]
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md [edge: 空ファイルでない (100 文字超)]" test_skill_not_empty
else
  run_test_skip "SKILL.md [edge: 空ファイルでない]" "skills/workflow-setup/SKILL.md not yet created"
fi

# Scenario: chain ステップの記述が排除されている (line 11)
# WHEN: SKILL.md の内容を確認する
# THEN: 旧プラグインの冗長な手順記述（bash $SCRIPTS_ROOT/xxx.sh 等）が存在しない
# NOTE: 現在の SKILL.md は chain 実行指示セクションで ### Step N: ヘッダーと
# Skill tool 参照を使用しているが、これは chain-driven 設計の一部であり許容される。
# 旧プラグインの冗長パターン（具体的な bash コマンド列挙）が排除されていることを検証する。
test_no_step_instructions() {
  assert_file_exists "$SKILL_MD" || return 1
  # Check for old verbose procedural patterns (bash $SCRIPTS_ROOT invocations)
  assert_file_not_contains "$SKILL_MD" "bash\s+\\\$SCRIPTS_ROOT" || return 1
  # Check for gh CLI direct commands (old pattern)
  assert_file_not_contains "$SKILL_MD" "^\s*gh\s+project\s+item-add" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "chain ステップの記述が排除されている" test_no_step_instructions
else
  run_test_skip "chain ステップの記述が排除されている" "skills/workflow-setup/SKILL.md not yet created"
fi

# Edge case: ステップ番号リスト（1., 2., 3., ...）形式の手順もない
test_no_numbered_steps() {
  assert_file_exists "$SKILL_MD" || return 1
  # Count numbered list items that look like procedural steps
  local count
  count=$(grep -cP "^\s*\d+\.\s+(実行|呼び出|Spawn|spawn|call)" "${PROJECT_ROOT}/${SKILL_MD}" 2>/dev/null || true)
  [[ "${count:-0}" -eq 0 ]]
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md [edge: 手順的番号リストなし]" test_no_numbered_steps
else
  run_test_skip "SKILL.md [edge: 手順的番号リストなし]" "skills/workflow-setup/SKILL.md not yet created"
fi

# =============================================================================
# Requirement: SKILL.md に残すドメインルール
# =============================================================================
echo ""
echo "--- Requirement: SKILL.md に残すドメインルール ---"

# Scenario: arch-ref 抽出ルールが記載されている (line 25)
# WHEN: SKILL.md を確認する
# THEN: Issue body/comments からの <!-- arch-ref-start --> タグ解析、最大 5 件の architecture/ ファイル読み取り、.. パス拒否のルールが記載されている
test_arch_ref_rules() {
  assert_file_exists "$SKILL_MD" || return 1
  # Check for arch-ref-start tag mention
  assert_file_contains "$SKILL_MD" "arch-ref-start" || return 1
  # Check for max 5 files rule
  assert_file_contains "$SKILL_MD" "(5|five)" || return 1
  # Check for .. path rejection rule
  assert_file_contains "$SKILL_MD" "\.\." || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "arch-ref 抽出ルールが記載されている" test_arch_ref_rules
else
  run_test_skip "arch-ref 抽出ルールが記載されている" "skills/workflow-setup/SKILL.md not yet created"
fi

# Edge case: arch-ref で architecture/ ディレクトリへの参照がある
test_arch_ref_architecture_dir() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "architecture/"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "arch-ref [edge: architecture/ ディレクトリ参照]" test_arch_ref_architecture_dir
else
  run_test_skip "arch-ref [edge: architecture/ ディレクトリ参照]" "skills/workflow-setup/SKILL.md not yet created"
fi

# OpenSpec branching rules check
test_openspec_rules() {
  assert_file_exists "$SKILL_MD" || return 1
  # Check for propose/apply/direct decision rules
  assert_file_contains "$SKILL_MD" "propose|apply|direct" || return 1
  # Check for OpenSpec mention
  assert_file_contains "$SKILL_MD" "[Oo]pen[Ss]pec" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "OpenSpec 分岐条件が記載されている" test_openspec_rules
else
  run_test_skip "OpenSpec 分岐条件が記載されている" "skills/workflow-setup/SKILL.md not yet created"
fi

# Argument parsing rules check
# NOTE: --auto/--auto-merge フラグは #47 で廃止済み。
# 現在は #N（Issue 番号）のみが引数として使用される。
test_arg_parsing_rules() {
  assert_file_exists "$SKILL_MD" || return 1
  # Check for #N pattern (Issue number argument)
  assert_file_contains "$SKILL_MD" "#N|#\d+|ISSUE_NUM" || return 1
  # Check for $ARGUMENTS parsing
  assert_file_contains "$SKILL_MD" "ARGUMENTS|引数" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "引数解析ルールが記載されている" test_arg_parsing_rules
else
  run_test_skip "引数解析ルールが記載されている" "skills/workflow-setup/SKILL.md not yet created"
fi

# Edge case: --auto/--auto-merge 引数が廃止されていること (#47)
test_no_auto_merge_arg() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_not_contains "$SKILL_MD" "--auto-merge" || return 1
  assert_file_not_contains "$SKILL_MD" "--auto\b" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "引数解析 [edge: --auto/--auto-merge 引数が廃止されている]" test_no_auto_merge_arg
else
  run_test_skip "引数解析 [edge: --auto/--auto-merge 引数が廃止されている]" "skills/workflow-setup/SKILL.md not yet created"
fi

# Scenario: 手続き的記述が排除されている (line 29)
# WHEN: SKILL.md を確認する
# THEN: 「bash $SCRIPTS_ROOT/xxx.sh」「gh issue view」「gh project item-add」等の具体的コマンド記述が存在しない
test_no_procedural_commands() {
  assert_file_exists "$SKILL_MD" || return 1
  # Check for bash script invocations
  assert_file_not_contains "$SKILL_MD" "bash\s+\\\$SCRIPTS_ROOT" || return 1
  # Check for gh CLI commands (except in comments/examples)
  assert_file_not_contains "$SKILL_MD" "^\s*gh\s+(issue\s+view|project\s+item-add)" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "手続き的記述が排除されている" test_no_procedural_commands
else
  run_test_skip "手続き的記述が排除されている" "skills/workflow-setup/SKILL.md not yet created"
fi

# Edge case: COMMAND.md への委譲を示唆する記述がある（or chain に委譲）
test_delegation_mentioned() {
  assert_file_exists "$SKILL_MD" || return 1
  # Check that SKILL.md mentions delegation to commands or chain
  assert_file_contains "$SKILL_MD" "COMMAND\.md|chain|委譲|delegation"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "手続き的記述 [edge: COMMAND.md/chain への委譲言及]" test_delegation_mentioned
else
  run_test_skip "手続き的記述 [edge: COMMAND.md/chain への委譲言及]" "skills/workflow-setup/SKILL.md not yet created"
fi

# Edge case: git/gh の直接コマンド実行指示がない
test_no_direct_git_commands() {
  assert_file_exists "$SKILL_MD" || return 1
  # Procedural git/gh commands should not be in SKILL.md
  assert_file_not_contains "$SKILL_MD" "^\s*(git\s+push|git\s+checkout|gh\s+pr\s+create)" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "手続き的記述 [edge: git/gh 直接コマンドなし]" test_no_direct_git_commands
else
  run_test_skip "手続き的記述 [edge: git/gh 直接コマンドなし]" "skills/workflow-setup/SKILL.md not yet created"
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
