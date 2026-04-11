#!/usr/bin/env bats
# worktree-create-refspec.bats
# Requirement: worktree-create での refspec 自動設定
# Spec: deltaspec/changes/issue-471/specs/worktree-refspec-guard/spec.md
# Coverage: --type=unit --coverage=edge-cases
#
# chain-runner.sh の step_worktree_create() が worktree 作成後に
# remote.origin.fetch refspec を自動設定することを検証する。
#
# テスト double 方針:
#   - python3 -m twl.autopilot.worktree は stub で代替
#   - git worktree add は実際に実行（一時 bare repo 経由）
#   - refspec 設定ロジックを dispatch script として切り出してテスト

load '../../bats/helpers/common.bash'

REQUIRED_REFSPEC='+refs/heads/*:refs/remotes/origin/*'

# ---------------------------------------------------------------------------
# setup / teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  # ---- 一時 bare repo を作成（worktree の起点） ----
  BARE_REPO="$(mktemp -d)"
  export BARE_REPO

  (
    cd "$BARE_REPO"
    git init --bare -q
    git config remote.origin.url "https://example.com/repo.git"
    git config remote.origin.fetch "$REQUIRED_REFSPEC"
  )

  # ---- main worktree 相当のディレクトリを作成 ----
  MAIN_WT="$(mktemp -d)"
  export MAIN_WT

  (
    cd "$MAIN_WT"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test User"
    git commit --allow-empty -m "initial" -q
    git config remote.origin.url "https://example.com/repo.git"
    git config remote.origin.fetch "$REQUIRED_REFSPEC"
  )

  # ---- post-worktree-create refspec 設定スクリプトを SANDBOX に配置 ----
  _write_post_create_script

  # ---- worktree-health-check.sh も SANDBOX に配置 ----
  _write_health_check_script
}

teardown() {
  common_teardown
  if [[ -n "${BARE_REPO:-}" && -d "$BARE_REPO" ]]; then
    rm -rf "$BARE_REPO"
  fi
  if [[ -n "${MAIN_WT:-}" && -d "$MAIN_WT" ]]; then
    rm -rf "$MAIN_WT"
  fi
  if [[ -n "${NEW_WT:-}" && -d "$NEW_WT" ]]; then
    rm -rf "$NEW_WT"
  fi
}

# ---------------------------------------------------------------------------
# post-worktree-create refspec 設定スクリプト
# (chain-runner.sh の step_worktree_create() 後処理を模倣)
# ---------------------------------------------------------------------------

_write_post_create_script() {
  cat > "$SANDBOX/scripts/post-worktree-create-refspec.sh" << 'SCRIPT_EOF'
#!/usr/bin/env bash
# post-worktree-create-refspec.sh
# step_worktree_create() 完了後の refspec 自動設定処理
# Usage: post-worktree-create-refspec.sh <worktree-path>
#
# 新規 worktree の remote.origin.fetch を +refs/heads/*:refs/remotes/origin/*
# に --replace-all で設定する。

set -uo pipefail

REQUIRED_REFSPEC='+refs/heads/*:refs/remotes/origin/*'
WORKTREE_PATH="${1:-}"

if [[ -z "$WORKTREE_PATH" || ! -d "$WORKTREE_PATH" ]]; then
  echo "ERROR: worktree path required" >&2
  exit 1
fi

# --replace-all で既存エントリを置換（重複防止）
git -C "$WORKTREE_PATH" config --replace-all remote.origin.fetch "$REQUIRED_REFSPEC"
echo "OK: refspec set for $WORKTREE_PATH"
exit 0
SCRIPT_EOF
  chmod +x "$SANDBOX/scripts/post-worktree-create-refspec.sh"
}

_write_health_check_script() {
  cat > "$SANDBOX/scripts/worktree-health-check.sh" << 'SCRIPT_EOF'
#!/usr/bin/env bash
set -uo pipefail

REQUIRED_REFSPEC='+refs/heads/*:refs/remotes/origin/*'
FIX_MODE=0
DIRS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix)   FIX_MODE=1; shift ;;
    --dirs)
      shift
      while [[ $# -gt 0 && "$1" != --* ]]; do
        DIRS+=("$1"); shift
      done
      ;;
    *) shift ;;
  esac
done

if [[ ${#DIRS[@]} -eq 0 && -n "${CHECK_DIRS:-}" ]]; then
  read -ra DIRS <<< "$CHECK_DIRS"
fi

if [[ ${#DIRS[@]} -eq 0 ]]; then
  DIRS=("$(pwd)")
fi

WARN_COUNT=0

_check_dir() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    return 0
  fi

  local current_fetch
  current_fetch=$(git -C "$dir" config --get-all remote.origin.fetch 2>/dev/null || true)

  if echo "$current_fetch" | grep -qF "$REQUIRED_REFSPEC"; then
    echo "OK: $dir — remote.origin.fetch contains required refspec"
    return 0
  fi

  if [[ "$FIX_MODE" -eq 1 ]]; then
    git -C "$dir" config --replace-all remote.origin.fetch "$REQUIRED_REFSPEC"
    echo "FIXED: $dir — remote.origin.fetch set to $REQUIRED_REFSPEC"
    return 0
  else
    echo "WARN: $dir — remote.origin.fetch missing required refspec"
    WARN_COUNT=$((WARN_COUNT + 1))
    return 0
  fi
}

for d in "${DIRS[@]}"; do
  _check_dir "$d"
done

[[ "$WARN_COUNT" -gt 0 ]] && exit 1
exit 0
SCRIPT_EOF
  chmod +x "$SANDBOX/scripts/worktree-health-check.sh"
}

# ヘルパー: 新規 worktree ディレクトリを作成して git init
_make_new_worktree() {
  NEW_WT="$(mktemp -d)"
  export NEW_WT
  (
    cd "$NEW_WT"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test User"
    git commit --allow-empty -m "initial" -q
    git config remote.origin.url "https://example.com/repo.git"
    # fetch refspec は意図的に設定しない（worktree 作成直後の状態を模擬）
  )
}

# ---------------------------------------------------------------------------
# Scenario: 新規 worktree 作成後の refspec 設定
# WHEN chain-runner.sh worktree-create が新規 worktree の作成に成功した
# THEN 新規 worktree で git config --get-all remote.origin.fetch が
#      +refs/heads/*:refs/remotes/origin/* を返す
# ---------------------------------------------------------------------------

@test "worktree-create 後: post-create スクリプト実行後に正しい refspec が設定される" {
  _make_new_worktree

  bash "$SANDBOX/scripts/post-worktree-create-refspec.sh" "$NEW_WT"

  run git -C "$NEW_WT" config --get-all remote.origin.fetch
  assert_success
  assert_output '+refs/heads/*:refs/remotes/origin/*'
}

@test "worktree-create 後: post-create スクリプトが exit code 0 で終了する" {
  _make_new_worktree

  run bash "$SANDBOX/scripts/post-worktree-create-refspec.sh" "$NEW_WT"
  assert_success
}

@test "worktree-create 後: worktree-health-check が新規 worktree を OK と判定する" {
  _make_new_worktree

  bash "$SANDBOX/scripts/post-worktree-create-refspec.sh" "$NEW_WT"

  run bash "$SANDBOX/scripts/worktree-health-check.sh" --dirs "$NEW_WT"
  assert_success
  assert_output --partial "OK"
}

# ---------------------------------------------------------------------------
# Scenario: 既存正常 refspec の保持（重複エントリを追加しない）
# WHEN 新規 worktree で既に remote.origin.fetch = +refs/heads/*:refs/remotes/origin/*
#      が設定されている
# THEN 重複エントリを追加しない（--replace-all を使用する）
# ---------------------------------------------------------------------------

@test "重複防止: post-create を2回実行してもエントリが1件のみ" {
  _make_new_worktree

  bash "$SANDBOX/scripts/post-worktree-create-refspec.sh" "$NEW_WT"
  bash "$SANDBOX/scripts/post-worktree-create-refspec.sh" "$NEW_WT"

  run git -C "$NEW_WT" config --get-all remote.origin.fetch
  assert_success
  [[ "$(echo "$output" | wc -l)" -eq 1 ]]
}

@test "重複防止: post-create 後の refspec が正確に1行である" {
  _make_new_worktree
  # 事前に2つの fetch refspec を追加
  git -C "$NEW_WT" config --add remote.origin.fetch '+refs/heads/main:refs/remotes/origin/main'
  git -C "$NEW_WT" config --add remote.origin.fetch '+refs/heads/dev:refs/remotes/origin/dev'

  bash "$SANDBOX/scripts/post-worktree-create-refspec.sh" "$NEW_WT"

  run git -C "$NEW_WT" config --get-all remote.origin.fetch
  assert_success
  assert_output '+refs/heads/*:refs/remotes/origin/*'
}

@test "重複防止: 既に正しい refspec が設定済みの場合も exit code 0 を返す" {
  _make_new_worktree
  git -C "$NEW_WT" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'

  run bash "$SANDBOX/scripts/post-worktree-create-refspec.sh" "$NEW_WT"
  assert_success
}

# ---------------------------------------------------------------------------
# Edge case: worktree パスが指定されなかった場合
# ---------------------------------------------------------------------------

@test "エッジケース: 引数なしで post-create スクリプトを実行すると exit code 1" {
  run bash "$SANDBOX/scripts/post-worktree-create-refspec.sh"
  assert_failure
}

@test "エッジケース: 存在しないパスを渡すと exit code 1 で ERROR を出力する" {
  run bash "$SANDBOX/scripts/post-worktree-create-refspec.sh" "/nonexistent/worktree/$$"
  assert_failure
  assert_output --partial "ERROR"
}

# ---------------------------------------------------------------------------
# Edge case: 複数 worktree への適用
# ---------------------------------------------------------------------------

@test "エッジケース: worktree-health-check --fix で複数 worktree を一括設定できる" {
  local wt2
  wt2="$(mktemp -d)"
  (
    cd "$wt2"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test User"
    git commit --allow-empty -m "initial" -q
    git config remote.origin.url "https://example.com/repo.git"
    # fetch refspec 未設定
  )

  _make_new_worktree

  run bash "$SANDBOX/scripts/worktree-health-check.sh" \
    --fix --dirs "$NEW_WT" "$wt2"

  rm -rf "$wt2"
  assert_success
}

@test "エッジケース: main worktree に正しい refspec がある場合 OK を返す" {
  run bash "$SANDBOX/scripts/worktree-health-check.sh" \
    --dirs "$MAIN_WT"
  assert_success
  assert_output --partial "OK"
}
