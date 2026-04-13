#!/usr/bin/env bats
# test-project-init-config-json.bats
# Requirement: .test-target/config.json の生成
# Coverage: --type=unit --coverage=edge-cases

load '../../bats/helpers/common.bash'
load '_helpers'

# ---------------------------------------------------------------------------
# setup / teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup
  _setup_dirs
  _write_config_generate_script
}

teardown() {
  common_teardown
}

# ===========================================================================
# Requirement: .test-target/config.json の生成
# ===========================================================================

# Scenario: real-issues モード初期化後の config.json
# WHEN --mode real-issues --repo owner/test-repo での初期化が成功する
# THEN .test-target/config.json に mode: "real-issues", repo: "owner/test-repo" が記録される
@test "config-json: real-issues モード初期化後に mode と repo が記録される" {
  local out_path="$SANDBOX/.test-target/config.json"

  run bash "$SANDBOX/scripts/generate-config.sh" \
    --mode real-issues \
    --repo owner/test-repo \
    --worktree-path "$SANDBOX/worktrees/test-target" \
    --branch "test-target/main" \
    --out "$out_path"
  [ "$status" -eq 0 ]

  [ -f "$out_path" ]
  jq -e '.mode == "real-issues"' "$out_path" > /dev/null
  jq -e '.repo == "owner/test-repo"' "$out_path" > /dev/null
  jq -e '.initialized_at | length > 0' "$out_path" > /dev/null
  jq -e '.worktree_path | length > 0' "$out_path" > /dev/null
  jq -e '.branch == "test-target/main"' "$out_path" > /dev/null
}

# Scenario: local モード初期化後の config.json
# WHEN --mode local での初期化が成功する
# THEN .test-target/config.json に mode: "local", repo: null が記録される
@test "config-json: local モード初期化後に mode=local, repo=null が記録される" {
  local out_path="$SANDBOX/.test-target/config-local.json"

  run bash "$SANDBOX/scripts/generate-config.sh" \
    --mode local \
    --worktree-path "$SANDBOX/worktrees/test-target" \
    --branch "test-target/main" \
    --out "$out_path"
  [ "$status" -eq 0 ]

  [ -f "$out_path" ]
  jq -e '.mode == "local"' "$out_path" > /dev/null
  jq -e '.repo == null' "$out_path" > /dev/null
}

# エッジケース: config.json の全必須フィールドが存在する
@test "config-json: 全必須フィールド (mode, repo, initialized_at, worktree_path, branch) が存在する" {
  local out_path="$SANDBOX/.test-target/config-full.json"

  run bash "$SANDBOX/scripts/generate-config.sh" \
    --mode real-issues \
    --repo owner/test-repo \
    --worktree-path "/worktrees/test-target" \
    --branch "test-target/main" \
    --out "$out_path"
  [ "$status" -eq 0 ]

  # 全フィールドが存在することを確認
  local fields
  fields=$(jq 'keys | sort' "$out_path")
  echo "$fields" | jq -e 'contains(["branch","initialized_at","mode","repo","worktree_path"])' > /dev/null
}
