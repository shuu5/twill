#!/usr/bin/env bats
# test-project-init-mode-flag.bats
# Requirement: test-project-init コマンドの --mode フラグ対応 + bats テスト明示確認
# Coverage: --type=unit --coverage=edge-cases

load '../../bats/helpers/common.bash'
load '_helpers'

# ---------------------------------------------------------------------------
# setup / teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup
  _setup_dirs
  _write_mode_parse_script
}

teardown() {
  common_teardown
}

# ===========================================================================
# Requirement: real-issues モードフラグ
# ===========================================================================

# Scenario: real-issues モードで引数を受け付ける
# WHEN /twl:test-project-init --mode real-issues --repo owner/test-repo を実行する
# THEN real-issues モードフローが起動し、owner/test-repo を対象リポとして処理する
@test "mode-flag: --mode real-issues --repo を受け付けて JSON を返す" {
  run bash "$SANDBOX/scripts/parse-mode.sh" --mode real-issues --repo owner/test-repo
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "real-issues"' > /dev/null
  echo "$output" | jq -e '.repo == "owner/test-repo"' > /dev/null
}

# Scenario: --mode 未指定時は local モードで動作
# WHEN /twl:test-project-init を引数なしで実行する
# THEN 既存の local モード動作と同一の結果になる
@test "mode-flag: --mode 未指定時は local がデフォルト" {
  run bash "$SANDBOX/scripts/parse-mode.sh"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "local"' > /dev/null
  echo "$output" | jq -e '.repo == null' > /dev/null
}

# エッジケース: --mode local を明示指定しても動作する
@test "mode-flag: --mode local を明示しても動作する" {
  run bash "$SANDBOX/scripts/parse-mode.sh" --mode local
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "local"' > /dev/null
}

# エッジケース: --mode real-issues で --repo 省略時はエラー
@test "mode-flag: --mode real-issues で --repo 省略時はエラー終了" {
  run bash "$SANDBOX/scripts/parse-mode.sh" --mode real-issues
  [ "$status" -ne 0 ]
  [[ "$output" =~ "--repo is required" ]]
}

# エッジケース: 不正な --mode 値を渡すとエラー
@test "mode-flag: 不正な --mode 値を渡すとエラー終了" {
  run bash "$SANDBOX/scripts/parse-mode.sh" --mode invalid-mode
  [ "$status" -ne 0 ]
  [[ "$output" =~ "invalid mode" ]]
}

# ===========================================================================
# Requirement: 既存 bats テストへの --mode local 明示
# ===========================================================================

# Scenario: bats テストが --mode local を明示して通過
# WHEN co-self-improve-smoke.bats と co-self-improve-regression.bats を実行する
# THEN 全テストが --mode local 引数付きで通過する
#
# Note: 既存の E2E bats ファイルに --mode local が明示されているかを静的検証する
@test "bats-mode-local: co-self-improve-smoke.bats に --mode local が明示されている" {
  local bats_file
  bats_file="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/../../bats/e2e/co-self-improve-smoke.bats"
  [ -f "$bats_file" ]

  # test-project-init 呼び出し行に --mode local が存在するか確認
  grep -q -- '--mode local' "$bats_file"
}

@test "bats-mode-local: co-self-improve-regression.bats に --mode local が明示されている" {
  local bats_file
  bats_file="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/../../bats/e2e/co-self-improve-regression.bats"
  [ -f "$bats_file" ]

  grep -q -- '--mode local' "$bats_file"
}
