#!/usr/bin/env bats
# test-project-init-repo-validate.bats
# Requirement: 既存リポの検証
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
# Requirement: 既存リポの検証
# ===========================================================================

# Scenario: 既存の空リポを指定した場合
# WHEN 既存の空リポ（コミット数 == 0）を --repo で指定する
# THEN パーミッション確認を通過し、リポを紐付けて成功する
@test "repo-validate: 既存の空リポ + write パーミッション → ok" {
  local repo="owner/empty-repo"
  local repo_safe="${repo//\//_}"
  # リポ存在を示す state ファイル
  echo "empty-repo" > "$GH_STATE_DIR/${repo_safe}.state"
  # コミット数 0
  echo "0" > "$GH_STATE_DIR/${repo_safe}.commit-count"
  # write パーミッション
  echo '{"permission":"write"}' > "$GH_STATE_DIR/${repo_safe}.permission"

  run bash "$SANDBOX/scripts/validate-repo.sh" "$repo"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "ok"' > /dev/null
}

# Scenario: 既存の非空リポを指定した場合
# WHEN コミットが存在するリポを --repo で指定する
# THEN 「リポが空ではありません」エラーを表示して停止する
@test "repo-validate: コミットありリポ → 'リポが空ではありません' エラー" {
  local repo="owner/nonempty-repo"
  local repo_safe="${repo//\//_}"
  echo "nonempty-repo" > "$GH_STATE_DIR/${repo_safe}.state"
  echo "5" > "$GH_STATE_DIR/${repo_safe}.commit-count"
  echo '{"permission":"write"}' > "$GH_STATE_DIR/${repo_safe}.permission"

  run bash "$SANDBOX/scripts/validate-repo.sh" "$repo"
  [ "$status" -ne 0 ]
  echo "$output" | jq -e '.reason | contains("リポが空ではありません")' > /dev/null
}

# Scenario: push パーミッションがない場合
# WHEN push 権限のないリポを --repo で指定する
# THEN 「push パーミッションがありません」エラーを表示して停止する
@test "repo-validate: push パーミッションなし → 'push パーミッションがありません' エラー" {
  local repo="owner/nopush-repo"
  local repo_safe="${repo//\//_}"
  echo "nopush-repo" > "$GH_STATE_DIR/${repo_safe}.state"
  echo "0" > "$GH_STATE_DIR/${repo_safe}.commit-count"
  echo '{"permission":"read"}' > "$GH_STATE_DIR/${repo_safe}.permission"

  run bash "$SANDBOX/scripts/validate-repo.sh" "$repo"
  [ "$status" -ne 0 ]
  echo "$output" | jq -e '.reason | contains("push パーミッションがありません")' > /dev/null
}

# エッジケース: admin パーミッションも write 相当として通過する
@test "repo-validate: admin パーミッション → ok (write 相当)" {
  local repo="owner/admin-repo"
  local repo_safe="${repo//\//_}"
  echo "admin-repo" > "$GH_STATE_DIR/${repo_safe}.state"
  echo "0" > "$GH_STATE_DIR/${repo_safe}.commit-count"
  echo '{"permission":"admin"}' > "$GH_STATE_DIR/${repo_safe}.permission"

  run bash "$SANDBOX/scripts/validate-repo.sh" "$repo"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "ok"' > /dev/null
}

# エッジケース: コミット数がちょうど 1 (境界値) でエラーになる
@test "repo-validate: コミット数 1 (境界値) → 空ではないエラー" {
  local repo="owner/one-commit-repo"
  local repo_safe="${repo//\//_}"
  echo "one-commit-repo" > "$GH_STATE_DIR/${repo_safe}.state"
  echo "1" > "$GH_STATE_DIR/${repo_safe}.commit-count"
  echo '{"permission":"write"}' > "$GH_STATE_DIR/${repo_safe}.permission"

  run bash "$SANDBOX/scripts/validate-repo.sh" "$repo"
  [ "$status" -ne 0 ]
  echo "$output" | jq -e '.reason | contains("リポが空ではありません")' > /dev/null
}
