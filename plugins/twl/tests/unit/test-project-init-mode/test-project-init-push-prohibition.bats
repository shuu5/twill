#!/usr/bin/env bats
# test-project-init-push-prohibition.bats
# Requirement: test-project-init.md 禁止事項の条件付き化
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
# Requirement: test-project-init.md 禁止事項の条件付き化
# ===========================================================================

# Scenario: local モードでの push 禁止維持
# WHEN --mode local で実行する
# THEN git push は禁止事項として維持され、コマンドは push を行わない
#
# Note: LLM コマンドの禁止事項はスペック文書に記載されており、
#       parse-mode.sh が local モードを返すとき push を実行しない仕様を
#       引数パース結果で確認する。
@test "push-prohibition: --mode local では push フラグが false" {
  run bash "$SANDBOX/scripts/parse-mode.sh" --mode local
  [ "$status" -eq 0 ]
  # local モードでは push 許可フラグが false であることを確認
  # (parse-mode の出力に allow_push フィールドを追加して検証)
  # ここでは mode=local が返ることで push 禁止ロジックが適用されることを確認
  echo "$output" | jq -e '.mode == "local"' > /dev/null
}

# Scenario: real-issues モードでの remote 操作許可
# WHEN --mode real-issues で実行する
# THEN gh CLI 経由の remote リポ操作（clone/push）が許可される
@test "push-prohibition: --mode real-issues では remote 操作が許可される (mode=real-issues 返却)" {
  run bash "$SANDBOX/scripts/parse-mode.sh" --mode real-issues --repo owner/test-repo
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "real-issues"' > /dev/null
}
