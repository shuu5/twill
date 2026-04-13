#!/usr/bin/env bats
# test-project-init-repo-create.bats
# Requirement: 新規リポの自動作成
# Coverage: --type=unit --coverage=edge-cases

load '../../bats/helpers/common.bash'
load '_helpers'

# ---------------------------------------------------------------------------
# setup / teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup
  _setup_dirs
  _setup_gh_mock
  _write_repo_validate_script
}

teardown() {
  common_teardown
}

# ===========================================================================
# Requirement: 新規リポの自動作成
# ===========================================================================

# Scenario: 存在しないリポを指定した場合
# WHEN 存在しないリポ名を --repo で指定する
# THEN validate-repo が not_found を返す（作成フローへ移行）
@test "repo-create: 存在しないリポ → not_found ステータス返却" {
  local repo="owner/nonexistent-repo"
  # state ファイルを作らない → not found

  run bash "$SANDBOX/scripts/validate-repo.sh" "$repo"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "not_found"' > /dev/null
}

# Scenario: gh repo create が成功する場合
# WHEN 存在しないリポ名を --repo で指定し、create-allowed マーカーあり
# THEN gh repo create が成功する
@test "repo-create: create-allowed マーカーありで gh repo create が成功する" {
  local repo="owner/new-repo"
  local repo_safe="${repo//\//_}"
  # create 許可マーカーを配置
  touch "$GH_STATE_DIR/${repo_safe}.create-allowed"

  run gh repo create "$repo" --private
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.name == "owner/new-repo"' > /dev/null
}

# Scenario: 名前衝突でリポ作成失敗
# WHEN create-allowed マーカーなし (別ユーザーが同名リポ保有等)
# THEN gh repo create が失敗して exit code != 0
@test "repo-create: create-allowed マーカーなし → gh repo create が失敗" {
  local repo="other/conflict-repo"
  # create-allowed マーカーを作らない

  run gh repo create "$repo" --private
  [ "$status" -ne 0 ]
  [[ "$output" =~ "repository creation failed" ]]
}
