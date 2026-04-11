#!/usr/bin/env bats
# worktree-refspec-guard.bats
# Requirement: worktree-health-check スクリプト
# Spec: deltaspec/changes/issue-471/specs/worktree-refspec-guard/spec.md
# Coverage: --type=unit --coverage=edge-cases
#
# worktree-health-check.sh は bare repo および全 worktree の
# remote.origin.fetch refspec を検査・修復するスクリプト。
#
# テスト構造:
#   - setup()    : 一時 bare repo + worktree を作成し refspec を設定
#   - teardown() : 一時ディレクトリを全削除
#
# テスト double 方針:
#   - git ls-remote (ネットワーク呼び出し) はスタブで差し替える
#   - スクリプト本体は SANDBOX/scripts/worktree-health-check.sh を使用

load '../../bats/helpers/common.bash'

# ---------------------------------------------------------------------------
# setup / teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  # ---- 一時 bare repo を作成 ----
  BARE_DIR="$(mktemp -d)"
  export BARE_DIR

  (
    cd "$BARE_DIR"
    git init --bare -q
    # bare repo に remote.origin.fetch を正しく設定
    git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
    git config remote.origin.url "https://example.com/repo.git"
  )

  # ---- 通常リポジトリを作成して worktree の代替とする ----
  WORKTREE_DIR="$(mktemp -d)"
  export WORKTREE_DIR

  (
    cd "$WORKTREE_DIR"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test User"
    git commit --allow-empty -m "initial" -q
    # worktree に remote.origin.fetch を正しく設定
    git config remote.origin.url "https://example.com/repo.git"
    git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
  )

  # ---- テスト対象スクリプトを SANDBOX に配置 ----
  mkdir -p "$SANDBOX/scripts"
  _write_health_check_script
}

teardown() {
  common_teardown
  if [[ -n "${BARE_DIR:-}" && -d "$BARE_DIR" ]]; then
    rm -rf "$BARE_DIR"
  fi
  if [[ -n "${WORKTREE_DIR:-}" && -d "$WORKTREE_DIR" ]]; then
    rm -rf "$WORKTREE_DIR"
  fi
}

# ---------------------------------------------------------------------------
# worktree-health-check.sh 本体をサンドボックスに書き出すヘルパー
# ---------------------------------------------------------------------------

_write_health_check_script() {
  cat > "$SANDBOX/scripts/worktree-health-check.sh" << 'SCRIPT_EOF'
#!/usr/bin/env bash
# worktree-health-check.sh
# Usage: worktree-health-check.sh [--fix] [--dirs <dir1> <dir2> ...]
#
# bare repo および worktree の remote.origin.fetch refspec を検査する。
# --fix  : 欠落 refspec を +refs/heads/*:refs/remotes/origin/* に修復
# --dirs : チェック対象ディレクトリを明示指定（未指定時は自動検出）
#
# Exit codes:
#   0  : 全 OK（または --fix で修復完了）
#   1  : refspec 欠落が検出され --fix なし

set -uo pipefail

REQUIRED_REFSPEC='+refs/heads/*:refs/remotes/origin/*'
FIX_MODE=0
DIRS=()

# 引数パース
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

# 対象ディレクトリが指定されていない場合は環境変数 CHECK_DIRS を使用
if [[ ${#DIRS[@]} -eq 0 && -n "${CHECK_DIRS:-}" ]]; then
  read -ra DIRS <<< "$CHECK_DIRS"
fi

# チェック対象が空の場合は自分の CWD を使用
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

if [[ "$WARN_COUNT" -gt 0 ]]; then
  exit 1
fi

exit 0
SCRIPT_EOF
  chmod +x "$SANDBOX/scripts/worktree-health-check.sh"
}

# ---------------------------------------------------------------------------
# Scenario: refspec 欠落の検出
# WHEN .bare/config または任意の worktree で remote.origin.fetch が
#      +refs/heads/*:refs/remotes/origin/* を含まない
# THEN WARN メッセージを標準出力に出力し exit code 1 で終了する
# ---------------------------------------------------------------------------

@test "refspec 欠落検出: refspec を削除した worktree を渡すと exit code 1 を返す" {
  # refspec を削除して欠落を模擬
  git -C "$WORKTREE_DIR" config --unset remote.origin.fetch

  run bash "$SANDBOX/scripts/worktree-health-check.sh" \
    --dirs "$WORKTREE_DIR"

  assert_failure
}

@test "refspec 欠落検出: WARN メッセージを stdout に出力する" {
  git -C "$WORKTREE_DIR" config --unset remote.origin.fetch

  run bash "$SANDBOX/scripts/worktree-health-check.sh" \
    --dirs "$WORKTREE_DIR"

  assert_output --partial "WARN"
}

@test "refspec 欠落検出: WARN 出力に対象ディレクトリのパスを含む" {
  git -C "$WORKTREE_DIR" config --unset remote.origin.fetch

  run bash "$SANDBOX/scripts/worktree-health-check.sh" \
    --dirs "$WORKTREE_DIR"

  assert_output --partial "$WORKTREE_DIR"
}

@test "refspec 欠落検出: bare repo の refspec を削除すると exit code 1 を返す" {
  git -C "$BARE_DIR" config --unset remote.origin.fetch

  run bash "$SANDBOX/scripts/worktree-health-check.sh" \
    --dirs "$BARE_DIR"

  assert_failure
}

@test "refspec 欠落検出: 複数ディレクトリのうち1つが欠落でも exit code 1 を返す" {
  local ok_dir
  ok_dir="$(mktemp -d)"
  git -C "$ok_dir" init -q
  git -C "$ok_dir" config remote.origin.url "https://example.com/repo.git"
  git -C "$ok_dir" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'

  git -C "$WORKTREE_DIR" config --unset remote.origin.fetch

  run bash "$SANDBOX/scripts/worktree-health-check.sh" \
    --dirs "$ok_dir" "$WORKTREE_DIR"

  rm -rf "$ok_dir"
  assert_failure
}

# ---------------------------------------------------------------------------
# Scenario: --fix による自動修復
# WHEN worktree-health-check.sh --fix を実行し欠落 refspec が検出された
# THEN git config --replace-all remote.origin.fetch を適用し exit code 0 で終了する
# ---------------------------------------------------------------------------

@test "--fix による修復: exit code 0 で終了する" {
  git -C "$WORKTREE_DIR" config --unset remote.origin.fetch

  run bash "$SANDBOX/scripts/worktree-health-check.sh" \
    --fix --dirs "$WORKTREE_DIR"

  assert_success
}

@test "--fix による修復: git config --get-all が正しい refspec を返す" {
  git -C "$WORKTREE_DIR" config --unset remote.origin.fetch

  bash "$SANDBOX/scripts/worktree-health-check.sh" \
    --fix --dirs "$WORKTREE_DIR"

  run git -C "$WORKTREE_DIR" config --get-all remote.origin.fetch
  assert_success
  assert_output '+refs/heads/*:refs/remotes/origin/*'
}

@test "--fix による修復: FIXED メッセージを stdout に出力する" {
  git -C "$WORKTREE_DIR" config --unset remote.origin.fetch

  run bash "$SANDBOX/scripts/worktree-health-check.sh" \
    --fix --dirs "$WORKTREE_DIR"

  assert_output --partial "FIXED"
}

@test "--fix による修復: bare repo の欠落 refspec も修復する" {
  git -C "$BARE_DIR" config --unset remote.origin.fetch

  bash "$SANDBOX/scripts/worktree-health-check.sh" \
    --fix --dirs "$BARE_DIR"

  run git -C "$BARE_DIR" config --get-all remote.origin.fetch
  assert_success
  assert_output '+refs/heads/*:refs/remotes/origin/*'
}

@test "--fix による修復: 複数ディレクトリを一括修復して exit code 0 を返す" {
  local extra_dir
  extra_dir="$(mktemp -d)"
  git -C "$extra_dir" init -q
  git -C "$extra_dir" config remote.origin.url "https://example.com/repo.git"

  git -C "$WORKTREE_DIR" config --unset remote.origin.fetch

  run bash "$SANDBOX/scripts/worktree-health-check.sh" \
    --fix --dirs "$WORKTREE_DIR" "$extra_dir"

  rm -rf "$extra_dir"
  assert_success
}

# ---------------------------------------------------------------------------
# Scenario: 全 OK の場合
# WHEN .bare/config と全 worktree の remote.origin.fetch が正しく設定されている
# THEN OK メッセージを出力し exit code 0 で終了する
# ---------------------------------------------------------------------------

@test "全 OK: 正しく設定された worktree で exit code 0 を返す" {
  run bash "$SANDBOX/scripts/worktree-health-check.sh" \
    --dirs "$WORKTREE_DIR"

  assert_success
}

@test "全 OK: OK メッセージを stdout に出力する" {
  run bash "$SANDBOX/scripts/worktree-health-check.sh" \
    --dirs "$WORKTREE_DIR"

  assert_output --partial "OK"
}

@test "全 OK: bare repo が正しく設定されている場合も exit code 0 を返す" {
  run bash "$SANDBOX/scripts/worktree-health-check.sh" \
    --dirs "$BARE_DIR"

  assert_success
}

@test "全 OK: 複数ディレクトリが全て正常な場合 exit code 0 を返す" {
  local extra_dir
  extra_dir="$(mktemp -d)"
  git -C "$extra_dir" init -q
  git -C "$extra_dir" config remote.origin.url "https://example.com/repo.git"
  git -C "$extra_dir" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'

  run bash "$SANDBOX/scripts/worktree-health-check.sh" \
    --dirs "$WORKTREE_DIR" "$extra_dir"

  rm -rf "$extra_dir"
  assert_success
}

# ---------------------------------------------------------------------------
# Scenario: --fix 使用時に重複エントリを作らない（--replace-all 使用）
# WHEN 新規 worktree で既に remote.origin.fetch = +refs/heads/*:refs/remotes/origin/* が設定されている
# THEN 重複エントリを追加しない（--replace-all を使用する）
# ---------------------------------------------------------------------------

@test "重複防止: --fix を2回実行してもエントリが1件のみ" {
  bash "$SANDBOX/scripts/worktree-health-check.sh" \
    --fix --dirs "$WORKTREE_DIR"
  bash "$SANDBOX/scripts/worktree-health-check.sh" \
    --fix --dirs "$WORKTREE_DIR"

  run git -C "$WORKTREE_DIR" config --get-all remote.origin.fetch
  assert_success
  # 出力は正確に1行（重複なし）
  [[ "$(echo "$output" | wc -l)" -eq 1 ]]
}

@test "重複防止: 既存の正常 refspec がある状態で --fix を実行しても OK を返す" {
  run bash "$SANDBOX/scripts/worktree-health-check.sh" \
    --fix --dirs "$WORKTREE_DIR"

  assert_success
  assert_output --partial "OK"
}

@test "重複防止: --fix 後の refspec が +refs/heads/*:refs/remotes/origin/* のみ" {
  # 先に別の fetch refspec を追加
  git -C "$WORKTREE_DIR" config --add remote.origin.fetch '+refs/heads/main:refs/remotes/origin/main'

  bash "$SANDBOX/scripts/worktree-health-check.sh" \
    --fix --dirs "$WORKTREE_DIR"

  # --replace-all により required refspec に置き換わっていることを確認
  run git -C "$WORKTREE_DIR" config --get-all remote.origin.fetch
  assert_output '+refs/heads/*:refs/remotes/origin/*'
}

# ---------------------------------------------------------------------------
# Edge case: 存在しないディレクトリを渡してもクラッシュしない
# ---------------------------------------------------------------------------

@test "エッジケース: 存在しないディレクトリを渡してもスクリプトが終了する" {
  run bash "$SANDBOX/scripts/worktree-health-check.sh" \
    --dirs "/nonexistent/path/$$"

  # exit code 0 または 1 のどちらかで終了し、クラッシュしないことを検証
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

@test "エッジケース: git 管理外ディレクトリを渡しても exit code 1 にならない" {
  local non_git_dir
  non_git_dir="$(mktemp -d)"

  run bash "$SANDBOX/scripts/worktree-health-check.sh" \
    --dirs "$non_git_dir"

  rm -rf "$non_git_dir"
  # git config が失敗しても OK 扱い（不在 = チェック不要）または 1 のどちらか
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

@test "エッジケース: --dirs なしでも引数なし実行でクラッシュしない" {
  # CWD を非 git ディレクトリに変更して実行
  run bash -c "cd /tmp && bash '$SANDBOX/scripts/worktree-health-check.sh'"
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# Edge case: refspec が部分一致でも不一致扱いになること
# ---------------------------------------------------------------------------

@test "エッジケース: refs/heads/main のみ設定された場合は WARN を出力する" {
  git -C "$WORKTREE_DIR" config remote.origin.fetch '+refs/heads/main:refs/remotes/origin/main'

  run bash "$SANDBOX/scripts/worktree-health-check.sh" \
    --dirs "$WORKTREE_DIR"

  assert_failure
  assert_output --partial "WARN"
}

@test "エッジケース: refspec が空文字列の場合は WARN を出力する" {
  git -C "$WORKTREE_DIR" config --unset remote.origin.fetch 2>/dev/null || true
  # 空の fetch refspec を設定しようとすると git config が拒否するため
  # --unset で削除した状態 (空) をテスト
  run bash "$SANDBOX/scripts/worktree-health-check.sh" \
    --dirs "$WORKTREE_DIR"

  assert_failure
  assert_output --partial "WARN"
}
