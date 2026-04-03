#!/usr/bin/env bats
# autopilot-plan-board-repo-name-validation.bats
# リポジトリ名バリデーション（`..` / `.` 拒否）の edge-case ユニットテスト
#
# Spec: openspec/changes/fix-repo-name-validation-dotdot/specs/repo-name-validation.md
# Target: scripts/autopilot-plan-board.sh  _build_cross_repo_json のバリデーション行
# Type: unit / edge-cases

load '../helpers/common'
load './autopilot-plan-board-helpers'

setup() {
  common_setup

  # _build_cross_repo_json の呼び出しに必要なグローバル変数を初期化
  export CROSS_REPO=false
  export BUILD_RESULT=""
  declare -gA REPO_OWNERS=()
  declare -gA REPO_NAMES=()
  declare -gA REPO_PATHS=()
  export REPOS_JSON="{}"

  # Board モジュールを source するため autopilot-plan-board.sh が依存する
  # _detect_project_board / _fetch_filtered_items は呼ばれないよう
  # 最小スタブを準備しておく（source 時に副作用がないことを確認）
  stub_command "jq" '
    # Pass-through to real jq for _build_cross_repo_json 内部利用
    exec /usr/bin/jq "$@"
  '
}

teardown() { common_teardown; }

# ---------------------------------------------------------------------------
# ヘルパー: _build_cross_repo_json を直接テストする薄いラッパー
#
# Board sh を source して _build_cross_repo_json を呼び出し、
# 標準エラーと BUILD_RESULT を検証する。
# ---------------------------------------------------------------------------

# _run_validation <item_repo> <current_repo>
# filtered_json には1エントリ（item_repo の Issue 99）を渡す。
_run_validation() {
  local item_repo="$1"
  local current_repo="${2:-shuu5/loom-plugin-dev}"
  local filtered
  filtered=$(printf '[{"content":{"number":99,"repository":"%s","type":"Issue"},"status":"Todo","title":"t"}]' "$item_repo")
  local script="$SANDBOX/scripts/autopilot-plan-board.sh"

  # source して関数を呼び出す。_detect_project_board などは呼ばれない。
  bash -c "
    source \"$script\"
    declare -A REPO_OWNERS=()
    declare -A REPO_NAMES=()
    declare -A REPO_PATHS=()
    CROSS_REPO=false
    BUILD_RESULT=''
    REPOS_JSON='{}'
    _build_cross_repo_json '$(printf '%s' "$filtered")' '$current_repo'
    echo \"BUILD_RESULT=\$BUILD_RESULT\"
  "
}

# ===========================================================================
# Scenario: `..` がバリデーションで拒否される
# WHEN: cross_name が `..` の場合
# THEN: バリデーションで失敗し、そのエントリをスキップする
# ===========================================================================

@test "repo name '..' is rejected and entry is skipped" {
  run _run_validation "shuu5/.."

  # スキップ警告が stderr へ出力されること
  assert_output --partial "スキップ"
  # BUILD_RESULT にエントリが追加されないこと（空 or Issue 番号のみ）
  # cross_name のエントリは issue_list に "<rid>#99" の形式で入るが、
  # 拒否された場合は rid 自体が生成されない
  refute_output --partial "..#99"
}

@test "repo name '..' produces skip warning mentioning the bad name" {
  run _run_validation "shuu5/.."

  # 不正な name として警告が出ること
  assert_output --partial "不正な name 形式"
}

@test "repo name '..' does not appear in BUILD_RESULT" {
  result=$(_run_validation "shuu5/..")
  # BUILD_RESULT= の行を取り出す
  build_result_line=$(echo "$result" | grep "^BUILD_RESULT=")
  # ..#99 が含まれていないこと
  [[ "$build_result_line" != *"..#99"* ]]
}

# ===========================================================================
# Scenario: `.` がバリデーションで拒否される
# WHEN: cross_name が `.` の場合
# THEN: バリデーションで失敗し、そのエントリをスキップする
# ===========================================================================

@test "repo name '.' is rejected and entry is skipped" {
  run _run_validation "shuu5/."

  assert_output --partial "スキップ"
  refute_output --partial ".#99"
}

@test "repo name '.' produces skip warning mentioning the bad name" {
  run _run_validation "shuu5/."

  assert_output --partial "不正な name 形式"
}

@test "repo name '.' does not appear in BUILD_RESULT" {
  result=$(_run_validation "shuu5/.")
  build_result_line=$(echo "$result" | grep "^BUILD_RESULT=")
  [[ "$build_result_line" != *".#99"* ]]
}

# ===========================================================================
# Scenario: 有効なリポジトリ名が通過する
# WHEN: cross_name が `my-repo`、`repo.js`、`repo_v2` などの有効な名前
# THEN: バリデーションを通過し、処理が継続される
# ===========================================================================

@test "valid repo name 'my-repo' passes validation" {
  result=$(_run_validation "shuu5/my-repo")

  # スキップ警告が出ないこと
  [[ "$result" != *"スキップ"* ]]
  # BUILD_RESULT に rid#issue_number が含まれること
  echo "$result" | grep -q "BUILD_RESULT=.*my-repo#99"
}

@test "valid repo name 'repo.js' passes validation" {
  result=$(_run_validation "shuu5/repo.js")

  [[ "$result" != *"スキップ"* ]]
  echo "$result" | grep -q "BUILD_RESULT=.*repo\.js#99"
}

@test "valid repo name 'repo_v2' passes validation" {
  result=$(_run_validation "shuu5/repo_v2")

  [[ "$result" != *"スキップ"* ]]
  echo "$result" | grep -q "BUILD_RESULT=.*repo_v2#99"
}

# ---------------------------------------------------------------------------
# 追加 edge-case: 先頭ドット（`.hidden`）は新正規表現で拒否される
# ---------------------------------------------------------------------------

@test "repo name starting with dot '.hidden' is rejected by new regex" {
  run _run_validation "shuu5/.hidden"

  assert_output --partial "スキップ"
}

# ---------------------------------------------------------------------------
# 追加 edge-case: `...` (3連続ドット) は拒否される
# ---------------------------------------------------------------------------

@test "repo name '...' is rejected" {
  run _run_validation "shuu5/..."

  assert_output --partial "スキップ"
}

# ===========================================================================
# Scenario: 変更範囲が `autopilot-plan-board.sh` のみに限定される
# WHEN: バリデーション修正を実施した場合
# THEN: 変更されたファイルは scripts/autopilot-plan-board.sh のみである
#
# このテストは「他ファイルにバリデーション正規表現が複製されていないこと」を
# 静的に検証することで変更範囲を保証する。
# ===========================================================================

@test "validation regex change is scoped only to autopilot-plan-board.sh" {
  local scripts_dir="$SANDBOX/scripts"

  # 対象ファイルにバリデーション正規表現が存在すること
  grep -q 'cross_name' "$scripts_dir/autopilot-plan-board.sh"

  # 他のスクリプトに cross_name バリデーションが複製されていないこと
  local other_files
  other_files=$(grep -rl 'cross_name' "$scripts_dir" \
    --include="*.sh" \
    | grep -v 'autopilot-plan-board.sh' || true)

  [[ -z "$other_files" ]]
}
