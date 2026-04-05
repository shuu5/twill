#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: skills-migration.md
# Generated from: openspec/changes/loom-plugin-session/specs/skills-migration.md
# Coverage level: edge-cases
# Target repo: ~/projects/local-projects/loom-plugin-session/main/
# =============================================================================
set -uo pipefail

# Target repo root (loom-plugin-session)
TARGET_ROOT="${LOOM_PLUGIN_SESSION_ROOT:-/home/shuu5/projects/local-projects/loom-plugin-session/main}"

# Counters
PASS=0
FAIL=0
SKIP=0
ERRORS=()

# --- Test Helpers ---

assert_file_exists() {
  local file="$1"
  [[ -f "${TARGET_ROOT}/${file}" ]]
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${TARGET_ROOT}/${file}" ]] && grep -qP -- "$pattern" "${TARGET_ROOT}/${file}"
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${TARGET_ROOT}/${file}" ]] || return 1
  if grep -qP -- "$pattern" "${TARGET_ROOT}/${file}"; then
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

SPAWN_SKILL="skills/spawn/SKILL.md"
OBSERVE_SKILL="skills/observe/SKILL.md"
FORK_SKILL="skills/fork/SKILL.md"

# =============================================================================
# Requirement: spawn スキルの移植
# =============================================================================
echo ""
echo "--- Requirement: spawn スキルの移植 ---"

# Scenario: 引数なし spawn (line 8)
# WHEN: ユーザーが /spawn を実行する
# THEN: 現在のディレクトリで新規 tmux ウィンドウが作成され cld が起動する

test_spawn_skill_exists() {
  assert_file_exists "$SPAWN_SKILL"
}
run_test "skills/spawn/SKILL.md が存在する" test_spawn_skill_exists

test_spawn_skill_no_args_pattern() {
  assert_file_exists "$SPAWN_SKILL" || return 1
  # 引数なし時の動作記述があること（即実行パターン）
  assert_file_contains "$SPAWN_SKILL" '(引数なし|no.*arg|cld-spawn.*即|immediately|instant)' || return 1
  return 0
}
run_test "spawn SKILL.md に引数なし時の即実行パターンがある" test_spawn_skill_no_args_pattern

test_spawn_skill_cld_spawn_reference() {
  assert_file_exists "$SPAWN_SKILL" || return 1
  # cld-spawn スクリプトへの参照があること
  assert_file_contains "$SPAWN_SKILL" 'cld-spawn' || return 1
  return 0
}
run_test "spawn SKILL.md が cld-spawn を参照している" test_spawn_skill_cld_spawn_reference

# Scenario: プロンプト付き spawn (line 12)
# WHEN: ユーザーが /spawn "テストを実行して" を実行する
# THEN: 初期プロンプトとしてテキストが渡された新規セッションが起動する

test_spawn_skill_prompt_pattern() {
  assert_file_exists "$SPAWN_SKILL" || return 1
  # プロンプト付き起動のパターンがあること
  assert_file_contains "$SPAWN_SKILL" '(PROMPT|prompt|"\$PROMPT"|初期プロンプト|initial.*prompt)' || return 1
  return 0
}
run_test "spawn SKILL.md にプロンプト付き起動パターンがある" test_spawn_skill_prompt_pattern

test_spawn_skill_prompt_passthrough() {
  assert_file_exists "$SPAWN_SKILL" || return 1
  # cld-spawn にプロンプトを渡す記述があること
  assert_file_contains "$SPAWN_SKILL" 'cld-spawn.*PROMPT|cld-spawn.*"\$' || return 1
  return 0
}
run_test "spawn SKILL.md がプロンプトを cld-spawn に渡す" test_spawn_skill_prompt_passthrough

# Scenario: --cd 付き spawn (line 16)
# WHEN: ユーザーが /spawn --cd ~/other-project を実行する
# THEN: 指定ディレクトリで新規セッションが起動する

test_spawn_skill_cd_pattern() {
  assert_file_exists "$SPAWN_SKILL" || return 1
  # --cd オプションの記述があること
  assert_file_contains "$SPAWN_SKILL" '\-\-cd|--cd' || return 1
  return 0
}
run_test "spawn SKILL.md に --cd オプションの記述がある" test_spawn_skill_cd_pattern

test_spawn_skill_cd_dir_launch() {
  assert_file_exists "$SPAWN_SKILL" || return 1
  # 指定ディレクトリでの起動記述があること
  assert_file_contains "$SPAWN_SKILL" '(TARGET_DIR|cd.*dir|--cd.*"\$)' || return 1
  return 0
}
run_test "spawn SKILL.md が指定ディレクトリで cld-spawn を起動する" test_spawn_skill_cd_dir_launch

# Edge case: tmux 外実行のエラー終了について記述があること
test_spawn_skill_tmux_required() {
  assert_file_exists "$SPAWN_SKILL" || return 1
  assert_file_contains "$SPAWN_SKILL" '(tmux.*外|tmux.*error|tmux.*not|tmux外|使用不可)' || return 1
  return 0
}
run_test "[edge: spawn SKILL.md に tmux 外使用不可の記述がある]" test_spawn_skill_tmux_required

# =============================================================================
# Requirement: observe スキルの移植
# =============================================================================
echo ""
echo "--- Requirement: observe スキルの移植 ---"

# Scenario: 単一ウィンドウ自動選択 (line 24)
# WHEN: 他に 1 つだけ Claude Code ウィンドウが存在する状態で /observe を実行する
# THEN: そのウィンドウの内容を自動的にキャプチャして要約する

test_observe_skill_exists() {
  assert_file_exists "$OBSERVE_SKILL"
}
run_test "skills/observe/SKILL.md が存在する" test_observe_skill_exists

test_observe_skill_auto_select_single() {
  assert_file_exists "$OBSERVE_SKILL" || return 1
  # 単一ウィンドウ自動選択の記述があること
  assert_file_contains "$OBSERVE_SKILL" '(1.*自動選択|auto.*select|single.*window|1 つ.*自動)' || return 1
  return 0
}
run_test "observe SKILL.md に単一ウィンドウ自動選択の記述がある" test_observe_skill_auto_select_single

test_observe_skill_cld_observe_reference() {
  assert_file_exists "$OBSERVE_SKILL" || return 1
  # cld-observe スクリプトへの参照があること
  assert_file_contains "$OBSERVE_SKILL" 'cld-observe' || return 1
  return 0
}
run_test "observe SKILL.md が cld-observe を参照している" test_observe_skill_cld_observe_reference

# Scenario: 複数ウィンドウ選択 (line 28)
# WHEN: 複数の Claude Code ウィンドウが存在する状態で /observe を実行する
# THEN: ウィンドウ選択ダイアログを表示する

test_observe_skill_multi_window_selection() {
  assert_file_exists "$OBSERVE_SKILL" || return 1
  # 複数ウィンドウ時の選択ダイアログ記述があること
  assert_file_contains "$OBSERVE_SKILL" '(AskUserQuestion|選択|select.*window|multiple.*window)' || return 1
  return 0
}
run_test "observe SKILL.md に複数ウィンドウ選択の記述がある" test_observe_skill_multi_window_selection

# Edge case: ウィンドウが 0 件の場合の記述があること
test_observe_skill_no_window_case() {
  assert_file_exists "$OBSERVE_SKILL" || return 1
  assert_file_contains "$OBSERVE_SKILL" '(0|ウィンドウがありません|no.*window|other.*window)' || return 1
  return 0
}
run_test "[edge: observe SKILL.md にウィンドウ 0 件の場合の記述がある]" test_observe_skill_no_window_case

# Scenario: 詳細モード (line 32)
# WHEN: /observe verbose または /observe 詳しく を実行する
# THEN: 100 行分のキャプチャを行う

test_observe_skill_verbose_mode() {
  assert_file_exists "$OBSERVE_SKILL" || return 1
  # 詳細モードの記述があること（100 行）
  assert_file_contains "$OBSERVE_SKILL" '(verbose|詳しく|詳細|100)' || return 1
  return 0
}
run_test "observe SKILL.md に詳細モード (100 行) の記述がある" test_observe_skill_verbose_mode

test_observe_skill_lines_100() {
  assert_file_exists "$OBSERVE_SKILL" || return 1
  # --lines 100 の記述があること
  assert_file_contains "$OBSERVE_SKILL" '\-\-lines 100|--lines 100|lines.*100' || return 1
  return 0
}
run_test "observe SKILL.md に --lines 100 の記述がある" test_observe_skill_lines_100

# Edge case: --all オプション（全スクロールバック）の記述があること
test_observe_skill_all_option() {
  assert_file_exists "$OBSERVE_SKILL" || return 1
  assert_file_contains "$OBSERVE_SKILL" '(--all|全スクロールバック|full.*scrollback)' || return 1
  return 0
}
run_test "[edge: observe SKILL.md に --all オプションの記述がある]" test_observe_skill_all_option

# =============================================================================
# Requirement: fork スキルの移植
# =============================================================================
echo ""
echo "--- Requirement: fork スキルの移植 ---"

# Scenario: 基本 fork (line 40)
# WHEN: ユーザーが /fork を実行する
# THEN: 現在のセッションのコンテキストを引き継いだ新ウィンドウが作成される

test_fork_skill_exists() {
  assert_file_exists "$FORK_SKILL"
}
run_test "skills/fork/SKILL.md が存在する" test_fork_skill_exists

test_fork_skill_cld_fork_reference() {
  assert_file_exists "$FORK_SKILL" || return 1
  # cld-fork スクリプトへの参照があること
  assert_file_contains "$FORK_SKILL" 'cld-fork' || return 1
  return 0
}
run_test "fork SKILL.md が cld-fork を参照している" test_fork_skill_cld_fork_reference

test_fork_skill_context_inherit() {
  assert_file_exists "$FORK_SKILL" || return 1
  # コンテキスト引き継ぎの記述があること
  assert_file_contains "$FORK_SKILL" '(会話履歴|コンテキスト|context|--continue|--fork-session)' || return 1
  return 0
}
run_test "fork SKILL.md にコンテキスト引き継ぎの記述がある" test_fork_skill_context_inherit

# Scenario: 監視付き fork (line 44)
# WHEN: ユーザーが /fork 監視して を実行する
# THEN: fork 後にセッション状態の非同期監視が開始される

test_fork_skill_watch_pattern() {
  assert_file_exists "$FORK_SKILL" || return 1
  # 監視付き fork の記述があること
  assert_file_contains "$FORK_SKILL" '(WITH_WATCH|監視|watch|非同期)' || return 1
  return 0
}
run_test "fork SKILL.md に監視付き fork パターンがある" test_fork_skill_watch_pattern

test_fork_skill_background_monitoring() {
  assert_file_exists "$FORK_SKILL" || return 1
  # バックグラウンド監視の記述があること（run_in_background または session-state wait）
  assert_file_contains "$FORK_SKILL" '(run_in_background|background|session-state.*wait|wait.*session)' || return 1
  return 0
}
run_test "fork SKILL.md にバックグラウンド監視の記述がある" test_fork_skill_background_monitoring

# Edge case: tmux 外実行のエラー終了について記述があること
test_fork_skill_tmux_required() {
  assert_file_exists "$FORK_SKILL" || return 1
  assert_file_contains "$FORK_SKILL" '(tmux.*外|tmux.*error|tmux.*not|使用不可)' || return 1
  return 0
}
run_test "[edge: fork SKILL.md に tmux 外使用不可の記述がある]" test_fork_skill_tmux_required

# =============================================================================
# Requirement: SKILL.md パス参照の統一
# =============================================================================
echo ""
echo "--- Requirement: SKILL.md パス参照の統一 ---"

# Scenario: パス参照の検証 (line 52)
# WHEN: 任意の SKILL.md 内でスクリプトパスを参照する
# THEN: ${CLAUDE_PLUGIN_ROOT}/scripts/<script-name> 形式で記述されている

test_spawn_skill_plugin_root_path() {
  assert_file_exists "$SPAWN_SKILL" || return 1
  # ${CLAUDE_PLUGIN_ROOT}/scripts/ 形式の参照があること
  assert_file_contains "$SPAWN_SKILL" '\${CLAUDE_PLUGIN_ROOT}/scripts' || return 1
  return 0
}
run_test "spawn SKILL.md が \${CLAUDE_PLUGIN_ROOT}/scripts/ 形式でパスを参照する" test_spawn_skill_plugin_root_path

test_observe_skill_plugin_root_path() {
  assert_file_exists "$OBSERVE_SKILL" || return 1
  assert_file_contains "$OBSERVE_SKILL" '\${CLAUDE_PLUGIN_ROOT}/scripts' || return 1
  return 0
}
run_test "observe SKILL.md が \${CLAUDE_PLUGIN_ROOT}/scripts/ 形式でパスを参照する" test_observe_skill_plugin_root_path

test_fork_skill_plugin_root_path() {
  assert_file_exists "$FORK_SKILL" || return 1
  assert_file_contains "$FORK_SKILL" '\${CLAUDE_PLUGIN_ROOT}/scripts' || return 1
  return 0
}
run_test "fork SKILL.md が \${CLAUDE_PLUGIN_ROOT}/scripts/ 形式でパスを参照する" test_fork_skill_plugin_root_path

# Edge case: ハードコードされた絶対パスがないこと（$HOME や ~ を直接使わない）
test_spawn_skill_no_hardcoded_path() {
  assert_file_exists "$SPAWN_SKILL" || return 1
  # コードブロック内の $HOME または ~ による絶対パス参照がないこと
  assert_file_not_contains "$SPAWN_SKILL" '(\$HOME/\.claude|~/\.claude)' || return 1
  return 0
}
run_test "[edge: spawn SKILL.md にハードコードされた絶対パスがない]" test_spawn_skill_no_hardcoded_path

test_observe_skill_no_hardcoded_path() {
  assert_file_exists "$OBSERVE_SKILL" || return 1
  assert_file_not_contains "$OBSERVE_SKILL" '(\$HOME/\.claude|~/\.claude)' || return 1
  return 0
}
run_test "[edge: observe SKILL.md にハードコードされた絶対パスがない]" test_observe_skill_no_hardcoded_path

test_fork_skill_no_hardcoded_path() {
  assert_file_exists "$FORK_SKILL" || return 1
  assert_file_not_contains "$FORK_SKILL" '(\$HOME/\.claude|~/\.claude)' || return 1
  return 0
}
run_test "[edge: fork SKILL.md にハードコードされた絶対パスがない]" test_fork_skill_no_hardcoded_path

# Edge case: 全 SKILL.md が skills/<name>/ ディレクトリ配下に存在すること
test_all_skills_in_correct_dirs() {
  local all_ok=true
  for skill in spawn observe fork; do
    [[ -f "${TARGET_ROOT}/skills/${skill}/SKILL.md" ]] || all_ok=false
  done
  [[ "$all_ok" == "true" ]]
}
run_test "[edge: 全 SKILL.md が skills/<name>/SKILL.md の形式で存在する]" test_all_skills_in_correct_dirs

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "============================================="
echo "loom-plugin-session-skills-migration: Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "Failed tests:"
  for err in "${ERRORS[@]}"; do
    echo "  - ${err}"
  done
fi
echo "============================================="

[[ ${FAIL} -eq 0 ]]
