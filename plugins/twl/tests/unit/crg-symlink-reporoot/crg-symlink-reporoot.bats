#!/usr/bin/env bats
# crg-symlink-reporoot.bats
# Requirement: CRG symlink を TWILL_REPO_ROOT 環境変数方式に移行
# Spec: deltaspec/changes/issue-576/specs/crg-symlink-reporoot/spec.md
# Coverage: --type=unit --coverage=edge-cases
#
# 検証する仕様:
#   1. TWILL_REPO_ROOT が PROJECT_DIR から export される
#   2. ISSUE_REPO_PATH 設定時も TWILL_REPO_ROOT は twill モノリポルートを指す
#   3. CRG symlink が ${TWILL_REPO_ROOT}/main/.code-review-graph を参照する
#   4. main worktree への自己参照 symlink が作成されない（文字列比較による判定）
#   5. realpath ではなく文字列比較で _is_main を判定する
#
# test double: crg-symlink-dispatch.sh
#   Env:
#     PROJECT_DIR      - twill モノリポルート
#     ISSUE_REPO_PATH  - クロスリポジトリ時のリポパス（省略可）
#     WORKTREE_DIR     - 対象 worktree パス
#     CALLS_LOG        - 呼び出し記録ファイル

load '../../bats/helpers/common.bash'

# ---------------------------------------------------------------------------
# setup: テスト double を生成
# ---------------------------------------------------------------------------

setup() {
  common_setup

  CALLS_LOG="$SANDBOX/calls.log"
  export CALLS_LOG

  # テスト用のフィクスチャディレクトリ構造
  FAKE_REPO_ROOT="$SANDBOX/twill"
  mkdir -p "$FAKE_REPO_ROOT/main/.code-review-graph"
  mkdir -p "$FAKE_REPO_ROOT/worktrees/feat/576-test"
  export FAKE_REPO_ROOT

  # CRG symlink 作成ロジックの test double（新方式: TWILL_REPO_ROOT ベース）
  cat > "$SANDBOX/scripts/crg-symlink-dispatch.sh" << 'DISPATCH_EOF'
#!/usr/bin/env bash
# crg-symlink-dispatch.sh
# CRG symlink 作成ロジックの test double（issue-576 新方式）
# Env:
#   PROJECT_DIR      - twill モノリポルート
#   ISSUE_REPO_PATH  - クロスリポジトリ時のリポパス（省略可）
#   WORKTREE_DIR     - 対象 worktree パス
#   CALLS_LOG        - 呼び出し記録ファイル
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-}"
ISSUE_REPO_PATH="${ISSUE_REPO_PATH:-}"
WORKTREE_DIR="${WORKTREE_DIR:-}"
CALLS_LOG="${CALLS_LOG:-/dev/null}"

# --- TWILL_REPO_ROOT export（PROJECT_DIR から常に設定、ISSUE_REPO_PATH とは独立）---
export TWILL_REPO_ROOT="${PROJECT_DIR}"
echo "export TWILL_REPO_ROOT=${TWILL_REPO_ROOT}" >> "$CALLS_LOG"

# --- _is_main 判定（文字列比較 + 末尾スラッシュ strip）---
local_normalized_wt="${WORKTREE_DIR%/}"
local_normalized_main="${TWILL_REPO_ROOT%/}/main"
_is_main=0
[[ "$local_normalized_wt" == "$local_normalized_main" ]] && _is_main=1
echo "_is_main=${_is_main}" >> "$CALLS_LOG"

# --- CRG symlink 作成（TWILL_REPO_ROOT ベース）---
_crg_main="${TWILL_REPO_ROOT}/main/.code-review-graph"
if [[ -d "$_crg_main" && "$_is_main" -eq 0 && ! -e "$WORKTREE_DIR/.code-review-graph" ]]; then
  ln -sf "$_crg_main" "$WORKTREE_DIR/.code-review-graph"
  echo "symlink_created=${WORKTREE_DIR}/.code-review-graph -> ${_crg_main}" >> "$CALLS_LOG"
else
  echo "symlink_skipped reason=_is_main=${_is_main}" >> "$CALLS_LOG"
fi

exit 0
DISPATCH_EOF
  chmod +x "$SANDBOX/scripts/crg-symlink-dispatch.sh"
}

teardown() {
  common_teardown
}

# ===========================================================================
# Requirement: TWILL_REPO_ROOT export
# Spec: deltaspec/changes/issue-576/specs/crg-symlink-reporoot/spec.md
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: worktree 作成時に TWILL_REPO_ROOT が設定される
# WHEN launch_worker() が呼び出され、effective_project_dir が確定した後
# THEN TWILL_REPO_ROOT 環境変数が ${PROJECT_DIR} の値で export される
# ---------------------------------------------------------------------------

@test "crg-reporoot[export]: TWILL_REPO_ROOT が PROJECT_DIR で export される" {
  PROJECT_DIR="$FAKE_REPO_ROOT" \
  WORKTREE_DIR="$FAKE_REPO_ROOT/worktrees/feat/576-test" \
    run bash "$SANDBOX/scripts/crg-symlink-dispatch.sh"

  assert_success
  grep -q "export TWILL_REPO_ROOT=${FAKE_REPO_ROOT}" "$CALLS_LOG"
}

@test "crg-reporoot[export]: TWILL_REPO_ROOT が空でない" {
  PROJECT_DIR="$FAKE_REPO_ROOT" \
  WORKTREE_DIR="$FAKE_REPO_ROOT/worktrees/feat/576-test" \
    run bash "$SANDBOX/scripts/crg-symlink-dispatch.sh"

  assert_success
  local val
  val=$(grep "export TWILL_REPO_ROOT=" "$CALLS_LOG" | head -1 | sed 's/export TWILL_REPO_ROOT=//')
  [[ -n "$val" ]]
}

# ---------------------------------------------------------------------------
# Scenario: ISSUE_REPO_PATH 設定時も TWILL_REPO_ROOT は twill モノリポルートを指す
# WHEN クロスリポジトリ実行で ISSUE_REPO_PATH が設定されている
# THEN TWILL_REPO_ROOT は PROJECT_DIR（twill モノリポルート）を指し、ISSUE_REPO_PATH とは独立している
# ---------------------------------------------------------------------------

@test "crg-reporoot[cross-repo]: ISSUE_REPO_PATH 設定時も TWILL_REPO_ROOT は PROJECT_DIR を指す" {
  OTHER_REPO="$SANDBOX/other-repo"
  mkdir -p "$OTHER_REPO"

  PROJECT_DIR="$FAKE_REPO_ROOT" \
  ISSUE_REPO_PATH="$OTHER_REPO" \
  WORKTREE_DIR="$FAKE_REPO_ROOT/worktrees/feat/576-test" \
    run bash "$SANDBOX/scripts/crg-symlink-dispatch.sh"

  assert_success
  grep -q "export TWILL_REPO_ROOT=${FAKE_REPO_ROOT}" "$CALLS_LOG"
  # ISSUE_REPO_PATH の値（other-repo）は TWILL_REPO_ROOT に使われない
  ! grep -q "export TWILL_REPO_ROOT=${OTHER_REPO}" "$CALLS_LOG"
}

# ===========================================================================
# Requirement: CRG symlink 参照先を TWILL_REPO_ROOT ベースに変更
# Spec: deltaspec/changes/issue-576/specs/crg-symlink-reporoot/spec.md
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: feature worktree への CRG symlink 作成
# WHEN worktree_dir が main worktree でない feature worktree を指す
# THEN ${TWILL_REPO_ROOT}/main/.code-review-graph へのシンボリックリンクが作成される
# ---------------------------------------------------------------------------

@test "crg-reporoot[symlink]: feature worktree に CRG symlink が作成される" {
  PROJECT_DIR="$FAKE_REPO_ROOT" \
  WORKTREE_DIR="$FAKE_REPO_ROOT/worktrees/feat/576-test" \
    run bash "$SANDBOX/scripts/crg-symlink-dispatch.sh"

  assert_success
  [[ -L "$FAKE_REPO_ROOT/worktrees/feat/576-test/.code-review-graph" ]]
}

@test "crg-reporoot[symlink]: CRG symlink が TWILL_REPO_ROOT/main/.code-review-graph を指す" {
  PROJECT_DIR="$FAKE_REPO_ROOT" \
  WORKTREE_DIR="$FAKE_REPO_ROOT/worktrees/feat/576-test" \
    run bash "$SANDBOX/scripts/crg-symlink-dispatch.sh"

  assert_success
  local target
  target=$(readlink "$FAKE_REPO_ROOT/worktrees/feat/576-test/.code-review-graph")
  [[ "$target" == "${FAKE_REPO_ROOT}/main/.code-review-graph" ]]
}

@test "crg-reporoot[symlink]: calls.log に symlink_created が記録される" {
  PROJECT_DIR="$FAKE_REPO_ROOT" \
  WORKTREE_DIR="$FAKE_REPO_ROOT/worktrees/feat/576-test" \
    run bash "$SANDBOX/scripts/crg-symlink-dispatch.sh"

  assert_success
  grep -q "symlink_created=" "$CALLS_LOG"
}

# ---------------------------------------------------------------------------
# Scenario: main worktree への自己参照 symlink を作成しない
# WHEN worktree_dir が ${TWILL_REPO_ROOT}/main と等しい（末尾スラッシュ strip 後の文字列比較）
# THEN CRG symlink が作成されない（自己参照防止）
# ---------------------------------------------------------------------------

@test "crg-reporoot[no-self-ref]: main worktree に CRG symlink が作成されない" {
  PROJECT_DIR="$FAKE_REPO_ROOT" \
  WORKTREE_DIR="$FAKE_REPO_ROOT/main" \
    run bash "$SANDBOX/scripts/crg-symlink-dispatch.sh"

  assert_success
  # symlink が作成されていないことを厳密に検証（-L は symlink のみ真、-d は symlink 先まで辿る）
  [[ ! -L "$FAKE_REPO_ROOT/main/.code-review-graph" ]]
}

@test "crg-reporoot[no-self-ref]: main worktree で _is_main=1 と判定される" {
  PROJECT_DIR="$FAKE_REPO_ROOT" \
  WORKTREE_DIR="$FAKE_REPO_ROOT/main" \
    run bash "$SANDBOX/scripts/crg-symlink-dispatch.sh"

  assert_success
  grep -q "_is_main=1" "$CALLS_LOG"
}

@test "crg-reporoot[no-self-ref]: main worktree で symlink_skipped が記録される" {
  PROJECT_DIR="$FAKE_REPO_ROOT" \
  WORKTREE_DIR="$FAKE_REPO_ROOT/main" \
    run bash "$SANDBOX/scripts/crg-symlink-dispatch.sh"

  assert_success
  grep -q "symlink_skipped" "$CALLS_LOG"
}

# ===========================================================================
# Requirement: _is_main 判定を文字列比較に変更
# Spec: deltaspec/changes/issue-576/specs/crg-symlink-reporoot/spec.md
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: main worktree の正確な判定
# WHEN worktree_dir が /path/to/twill/main または /path/to/twill/main/ の形式
# THEN _is_main=1 と判定され、CRG symlink が作成されない
# ---------------------------------------------------------------------------

@test "crg-reporoot[is-main]: 末尾スラッシュ付きの main パスも _is_main=1 と判定される" {
  PROJECT_DIR="$FAKE_REPO_ROOT" \
  WORKTREE_DIR="${FAKE_REPO_ROOT}/main/" \
    run bash "$SANDBOX/scripts/crg-symlink-dispatch.sh"

  assert_success
  grep -q "_is_main=1" "$CALLS_LOG"
}

@test "crg-reporoot[is-main]: main パスで CRG symlink が作成されない" {
  PROJECT_DIR="$FAKE_REPO_ROOT" \
  WORKTREE_DIR="${FAKE_REPO_ROOT}/main" \
    run bash "$SANDBOX/scripts/crg-symlink-dispatch.sh"

  assert_success
  # main/.code-review-graph はディレクトリ（既存）であり symlink ではない
  [[ ! -L "$FAKE_REPO_ROOT/main/.code-review-graph" ]]
}

# ---------------------------------------------------------------------------
# Scenario: feature worktree は main と判定されない
# WHEN worktree_dir が /path/to/twill/worktrees/feat/xxx の形式
# THEN _is_main=0 と判定され、CRG symlink 作成処理が続行される
# ---------------------------------------------------------------------------

@test "crg-reporoot[not-main]: feature worktree で _is_main=0 と判定される" {
  PROJECT_DIR="$FAKE_REPO_ROOT" \
  WORKTREE_DIR="$FAKE_REPO_ROOT/worktrees/feat/576-test" \
    run bash "$SANDBOX/scripts/crg-symlink-dispatch.sh"

  assert_success
  grep -q "_is_main=0" "$CALLS_LOG"
}

@test "crg-reporoot[not-main]: 別ブランチ worktree でも _is_main=0 と判定される" {
  mkdir -p "$FAKE_REPO_ROOT/worktrees/feat/other-branch"
  PROJECT_DIR="$FAKE_REPO_ROOT" \
  WORKTREE_DIR="$FAKE_REPO_ROOT/worktrees/feat/other-branch" \
    run bash "$SANDBOX/scripts/crg-symlink-dispatch.sh"

  assert_success
  grep -q "_is_main=0" "$CALLS_LOG"
}

@test "crg-reporoot[not-main]: main-like 名のブランチ（例: main-backup）は main と判定されない" {
  mkdir -p "$FAKE_REPO_ROOT/worktrees/main-backup"
  PROJECT_DIR="$FAKE_REPO_ROOT" \
  WORKTREE_DIR="$FAKE_REPO_ROOT/worktrees/main-backup" \
    run bash "$SANDBOX/scripts/crg-symlink-dispatch.sh"

  assert_success
  grep -q "_is_main=0" "$CALLS_LOG"
}

# ===========================================================================
# Edge cases
# ===========================================================================

# Edge case: .code-review-graph が既に存在する場合は symlink を作成しない（冪等性）
@test "crg-reporoot[edge]: 既存 .code-review-graph がある場合 symlink を上書きしない" {
  # 既存のファイルを作成
  touch "$FAKE_REPO_ROOT/worktrees/feat/576-test/.code-review-graph"

  PROJECT_DIR="$FAKE_REPO_ROOT" \
  WORKTREE_DIR="$FAKE_REPO_ROOT/worktrees/feat/576-test" \
    run bash "$SANDBOX/scripts/crg-symlink-dispatch.sh"

  assert_success
  # symlink が作られておらず元のファイルが残っている
  [[ ! -L "$FAKE_REPO_ROOT/worktrees/feat/576-test/.code-review-graph" ]]
}

# Edge case: _crg_main（main/.code-review-graph）が存在しない場合は symlink を作成しない
@test "crg-reporoot[edge]: CRG DB が存在しない場合 symlink を作成しない" {
  # .code-review-graph ディレクトリを削除
  rm -rf "$FAKE_REPO_ROOT/main/.code-review-graph"

  PROJECT_DIR="$FAKE_REPO_ROOT" \
  WORKTREE_DIR="$FAKE_REPO_ROOT/worktrees/feat/576-test" \
    run bash "$SANDBOX/scripts/crg-symlink-dispatch.sh"

  assert_success
  [[ ! -e "$FAKE_REPO_ROOT/worktrees/feat/576-test/.code-review-graph" ]]
}

# ===========================================================================
# Requirement: realpath ベースのガード削除
# Spec: deltaspec/changes/issue-576/specs/crg-symlink-reporoot/spec.md
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: realpath ガードが存在しない
# WHEN autopilot-orchestrator.sh の CRG symlink 作成ブロックを確認する
# THEN realpath を使った _is_main 判定が存在しない
# ---------------------------------------------------------------------------

@test "crg-reporoot[no-realpath]: autopilot-orchestrator.sh の CRG ブロックに realpath 判定が存在しない" {
  local orchestrator="$REPO_ROOT/scripts/autopilot-orchestrator.sh"
  [[ -f "$orchestrator" ]] || skip "autopilot-orchestrator.sh が REPO_ROOT/scripts に見つからない"

  # CRG symlink セクションで realpath を使った _is_main 判定が存在しないことを確認
  # grep で realpath && _is_main の組み合わせを検索（存在しないことを検証）
  ! grep -A5 "_is_main=0" "$orchestrator" | grep -q "realpath"
}

# ===========================================================================
# Edge cases: --coverage=edge-cases
# Static analysis of actual autopilot-orchestrator.sh implementation
# ===========================================================================

@test "crg-reporoot[static]: TWILL_REPO_ROOT は launch_worker() 内で export される" {
  local orchestrator="$REPO_ROOT/scripts/autopilot-orchestrator.sh"
  [[ -f "$orchestrator" ]] || skip "autopilot-orchestrator.sh が REPO_ROOT/scripts に見つからない"

  # export TWILL_REPO_ROOT= の行が launch_worker 関数ブロック内に存在する
  # launch_worker() の開始行番号を取得し、次の関数定義行までの範囲で検索
  local lw_start lw_end
  lw_start=$(grep -n "^launch_worker()" "$orchestrator" | head -1 | cut -d: -f1)
  lw_end=$(awk "NR > $lw_start && /^[a-z_]*[a-z_]\(\)/ { print NR; exit }" "$orchestrator")
  [[ -n "$lw_start" ]]
  local found
  found=$(sed -n "${lw_start},${lw_end}p" "$orchestrator" | grep -c 'export TWILL_REPO_ROOT=')
  [ "$found" -ge 1 ]
}

@test "crg-reporoot[static]: TWILL_REPO_ROOT は PROJECT_DIR から設定される" {
  local orchestrator="$REPO_ROOT/scripts/autopilot-orchestrator.sh"
  [[ -f "$orchestrator" ]] || skip "autopilot-orchestrator.sh が REPO_ROOT/scripts に見つからない"

  # export TWILL_REPO_ROOT="${PROJECT_DIR}" のパターンが存在する
  grep -q 'export TWILL_REPO_ROOT.*PROJECT_DIR' "$orchestrator"
}

@test "crg-reporoot[static]: CRG symlink 作成は TWILL_REPO_ROOT ベース（effective_project_dir を直接使っていない）" {
  local orchestrator="$REPO_ROOT/scripts/autopilot-orchestrator.sh"
  [[ -f "$orchestrator" ]] || skip "autopilot-orchestrator.sh が REPO_ROOT/scripts に見つからない"

  # _crg_main は TWILL_REPO_ROOT を使って構成されている
  grep -q '_crg_main.*TWILL_REPO_ROOT' "$orchestrator"

  # _crg_main が effective_project_dir を直接参照していない
  ! grep '_crg_main.*effective_project_dir' "$orchestrator"
}

@test "crg-reporoot[static]: _is_main 判定は文字列比較で行われる（== 演算子使用）" {
  local orchestrator="$REPO_ROOT/scripts/autopilot-orchestrator.sh"
  [[ -f "$orchestrator" ]] || skip "autopilot-orchestrator.sh が REPO_ROOT/scripts に見つからない"

  # 文字列比較 == で _is_main を設定している行が存在する
  grep -q '_normalized_wt.*==.*_normalized_main\|_normalized_main.*==.*_normalized_wt' "$orchestrator"
}

@test "crg-reporoot[static]: _normalized_main は TWILL_REPO_ROOT/main から構成される" {
  local orchestrator="$REPO_ROOT/scripts/autopilot-orchestrator.sh"
  [[ -f "$orchestrator" ]] || skip "autopilot-orchestrator.sh が REPO_ROOT/scripts に見つからない"

  # _normalized_main が TWILL_REPO_ROOT を使って設定されている
  grep -q '_normalized_main.*TWILL_REPO_ROOT.*main' "$orchestrator"
}

@test "crg-reporoot[static]: 末尾スラッシュ strip（%/ パターン）が使用されている" {
  local orchestrator="$REPO_ROOT/scripts/autopilot-orchestrator.sh"
  [[ -f "$orchestrator" ]] || skip "autopilot-orchestrator.sh が REPO_ROOT/scripts に見つからない"

  # worktree_dir%/ または TWILL_REPO_ROOT%/ パターンが CRG ブロックに存在する
  local crg_block
  crg_block=$(grep -A10 '_crg_main=' "$orchestrator" | head -20)
  echo "$crg_block" | grep -q '%/'
}

# ---------------------------------------------------------------------------
# Edge case: TWILL_REPO_ROOT が末尾スラッシュ付きの場合でも正しく動作する
# ---------------------------------------------------------------------------

@test "crg-reporoot[edge]: TWILL_REPO_ROOT が末尾スラッシュ付きでも symlink ターゲットが正しい" {
  # PROJECT_DIR に末尾スラッシュを付与してテスト
  PROJECT_DIR="${FAKE_REPO_ROOT}/" \
  WORKTREE_DIR="$FAKE_REPO_ROOT/worktrees/feat/576-test" \
    run bash "$SANDBOX/scripts/crg-symlink-dispatch.sh"

  assert_success
  # symlink ターゲットを確認（末尾スラッシュが適切に処理される）
  if [[ -L "$FAKE_REPO_ROOT/worktrees/feat/576-test/.code-review-graph" ]]; then
    local target
    target=$(readlink "$FAKE_REPO_ROOT/worktrees/feat/576-test/.code-review-graph")
    # ターゲットパスに "//" が含まれていないことを確認
    [[ "$target" != *"//"* ]]
  fi
}

@test "crg-reporoot[edge]: WORKTREE_DIR が末尾スラッシュ付きの main パスでも自己参照防止が機能する" {
  PROJECT_DIR="$FAKE_REPO_ROOT" \
  WORKTREE_DIR="${FAKE_REPO_ROOT}/main/" \
    run bash "$SANDBOX/scripts/crg-symlink-dispatch.sh"

  assert_success
  grep -q "_is_main=1" "$CALLS_LOG"
  [[ ! -L "$FAKE_REPO_ROOT/main/.code-review-graph" ]]
}

@test "crg-reporoot[edge]: PROJECT_DIR が空の場合 TWILL_REPO_ROOT も空になる" {
  PROJECT_DIR="" \
  WORKTREE_DIR="$FAKE_REPO_ROOT/worktrees/feat/576-test" \
    run bash "$SANDBOX/scripts/crg-symlink-dispatch.sh"

  # 空の PROJECT_DIR でも crash しない（symlink 作成はスキップされる）
  assert_success
  local val
  val=$(grep "export TWILL_REPO_ROOT=" "$CALLS_LOG" | head -1 | sed 's/export TWILL_REPO_ROOT=//')
  [[ -z "$val" ]]
}

@test "crg-reporoot[edge]: main-suffix パス（例: /path/to/twill/main-backup）は main 判定されない" {
  mkdir -p "$FAKE_REPO_ROOT/main-backup"
  PROJECT_DIR="$FAKE_REPO_ROOT" \
  WORKTREE_DIR="$FAKE_REPO_ROOT/main-backup" \
    run bash "$SANDBOX/scripts/crg-symlink-dispatch.sh"

  assert_success
  grep -q "_is_main=0" "$CALLS_LOG"
}

@test "crg-reporoot[edge]: main-prefix パス（例: /path/to/mainline/worktrees/...）は main 判定されない" {
  mkdir -p "$FAKE_REPO_ROOT/worktrees/mainline-feature"
  PROJECT_DIR="$FAKE_REPO_ROOT" \
  WORKTREE_DIR="$FAKE_REPO_ROOT/worktrees/mainline-feature" \
    run bash "$SANDBOX/scripts/crg-symlink-dispatch.sh"

  assert_success
  grep -q "_is_main=0" "$CALLS_LOG"
}
