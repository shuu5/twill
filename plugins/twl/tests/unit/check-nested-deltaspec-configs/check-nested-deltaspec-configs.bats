#!/usr/bin/env bats
# check-nested-deltaspec-configs.bats
# Requirement: _check_nested_deltaspec_configs のパス動的検出（Issue #505）
# Coverage: --type=unit --coverage=happy-path,edge-cases
#
# _check_nested_deltaspec_configs() は chain-runner.sh 内で find ベースの
# 動的検出を行う。ハードコードされたパスを使わず、ローカル worktree から
# */deltaspec/config.yaml を発見することを検証する。
#
# テスト対象: plugins/twl/scripts/chain-runner.sh
#   - _check_nested_deltaspec_configs "$root"
#     - 既存 2 パス（plugins/twl, cli/twl）を検出 → WARN なし
#     - 新規モジュール（plugins/foo）を検出 → WARN なし（関数変更不要）
#     - config.yaml が 1 件もない → WARN 出力
#   - .git/ 配下の config.yaml は検出対象外
#   - symlink, directory は -type f で除外

load '../../bats/helpers/common.bash'

# ---------------------------------------------------------------------------
# helper: chain-runner.sh から _check_nested_deltaspec_configs 関数定義を
# 抽出して呼び出すラッパースクリプトを生成する。
# chain-runner.sh は末尾に main "$@" があり source できないため、
# awk で関数定義のみを取り出してテスト用スクリプトに埋め込む。
# ---------------------------------------------------------------------------

setup() {
  common_setup

  # テスト対象スクリプト: common_setup がコピーした chain-runner.sh を使用
  CR="$SANDBOX/scripts/chain-runner.sh"
  export CR

  # chain-runner.sh から関数定義だけを抽出してラッパーに埋め込む
  local func_body
  func_body="$(awk '/^_check_nested_deltaspec_configs\(\)/,/^}/' "$CR")"

  cat > "$SANDBOX/scripts/run-check-nested.sh" << WRAPPER_EOF
#!/usr/bin/env bash
# Usage: run-check-nested.sh <root>
# _check_nested_deltaspec_configs を chain-runner.sh から抽出して実行する
${func_body}
_check_nested_deltaspec_configs "\${1:-}"
WRAPPER_EOF
  chmod +x "$SANDBOX/scripts/run-check-nested.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Scenario: 既存 2 パスを引き続き検出する
# WHEN plugins/twl/deltaspec/config.yaml と cli/twl/deltaspec/config.yaml が存在する
# THEN WARN が出力されない（exit 0）
# ---------------------------------------------------------------------------

@test "既存 2 パス(plugins/twl, cli/twl)が存在する場合 WARN が出力されない" {
  local root="$SANDBOX/fake-repo"
  mkdir -p "$root/plugins/twl/deltaspec"
  mkdir -p "$root/cli/twl/deltaspec"
  touch "$root/plugins/twl/deltaspec/config.yaml"
  touch "$root/cli/twl/deltaspec/config.yaml"

  run bash "$SANDBOX/scripts/run-check-nested.sh" "$root"
  assert_success
  refute_output --partial "[WARN]"
}

# ---------------------------------------------------------------------------
# Scenario: 新規モジュール plugins/foo を追加しても関数変更不要で検出
# WHEN plugins/foo/deltaspec/config.yaml を追加する
# THEN WARN が出力されない（関数の変更なしに検出される）
# ---------------------------------------------------------------------------

@test "新規モジュール plugins/foo/deltaspec/config.yaml が関数変更なしに検出される" {
  local root="$SANDBOX/fake-repo"
  mkdir -p "$root/plugins/twl/deltaspec"
  mkdir -p "$root/plugins/foo/deltaspec"
  touch "$root/plugins/twl/deltaspec/config.yaml"
  touch "$root/plugins/foo/deltaspec/config.yaml"

  run bash "$SANDBOX/scripts/run-check-nested.sh" "$root"
  assert_success
  refute_output --partial "[WARN]"
}

# ---------------------------------------------------------------------------
# Scenario: config.yaml が 1 件もない場合 WARN を出力する
# WHEN root 配下に deltaspec/config.yaml が存在しない
# THEN WARN メッセージが stderr に出力される
# ---------------------------------------------------------------------------

@test "config.yaml が存在しない場合 WARN が出力される" {
  local root="$SANDBOX/empty-repo"
  mkdir -p "$root"

  run bash "$SANDBOX/scripts/run-check-nested.sh" "$root"
  assert_success
  assert_output --partial "[WARN]"
}

# ---------------------------------------------------------------------------
# エッジケース: .git/ 配下の config.yaml は検出対象外
# WHEN .git/modules/foo/deltaspec/config.yaml のみ存在する
# THEN WARN が出力される（.git/ 除外により検出されない）
# ---------------------------------------------------------------------------

@test ".git/ 配下の config.yaml は検出対象外 → WARN が出力される" {
  local root="$SANDBOX/git-only-repo"
  mkdir -p "$root/.git/modules/foo/deltaspec"
  touch "$root/.git/modules/foo/deltaspec/config.yaml"

  run bash "$SANDBOX/scripts/run-check-nested.sh" "$root"
  assert_success
  assert_output --partial "[WARN]"
}

# ---------------------------------------------------------------------------
# エッジケース: -maxdepth 4 の境界値（depth=4 は検出、depth=5 は対象外）
# ---------------------------------------------------------------------------

@test "depth=4 の config.yaml は検出される（-maxdepth 4 境界）" {
  local root="$SANDBOX/depth-repo"
  # depth4: root/a/b/deltaspec/config.yaml = 4 階層
  mkdir -p "$root/a/b/deltaspec"
  touch "$root/a/b/deltaspec/config.yaml"

  run bash "$SANDBOX/scripts/run-check-nested.sh" "$root"
  assert_success
  refute_output --partial "[WARN]"
}

@test "depth=5 の config.yaml は検出されない（-maxdepth 4 境界）" {
  local root="$SANDBOX/deep-repo"
  # depth5: root/a/b/c/deltaspec/config.yaml = 5 階層
  mkdir -p "$root/a/b/c/deltaspec"
  touch "$root/a/b/c/deltaspec/config.yaml"

  run bash "$SANDBOX/scripts/run-check-nested.sh" "$root"
  assert_success
  assert_output --partial "[WARN]"
}
