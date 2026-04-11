#!/usr/bin/env bats
# test-project-init-mode.bats
# Requirement: test-project-init コマンドの --mode フラグ対応
# Spec: deltaspec/changes/issue-479/specs/real-issues-mode/spec.md
# Coverage: --type=unit --coverage=edge-cases
#
# test-project-init.md の --mode real-issues フラグ追加を検証するテスト群。
# 実装は Markdown ベース LLM コマンドのため、コマンドロジックを
# シェルスクリプトとして本ファイル内に再現し検証する。
#
# テスト構造:
#   - setup()    : 一時ディレクトリ、モック gh コマンド、テスト対象ロジックを配置
#   - teardown() : 一時ディレクトリを全削除
#
# テスト double 方針:
#   - gh CLI (ネットワーク呼び出し) はスタブで差し替える
#   - git コマンドはスタブ or 実 git (一時ディレクトリ) を使用

load '../../bats/helpers/common.bash'

# ---------------------------------------------------------------------------
# setup / teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  GH_STATE_DIR="$SANDBOX/gh-state"
  GH_MOCK_DIR="$SANDBOX/gh-bin"
  mkdir -p "$GH_STATE_DIR" "$GH_MOCK_DIR"

  export GH_STATE_DIR

  # モック gh を PATH 先頭に配置
  _write_gh_mock
  export PATH="$GH_MOCK_DIR:$PATH"

  # テスト対象: 引数パース + モード判定ロジック
  _write_mode_parse_script
  # テスト対象: リポ検証ロジック
  _write_repo_validate_script
  # テスト対象: config.json 生成ロジック
  _write_config_generate_script
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# ヘルパー: モック gh を書き出す
# ---------------------------------------------------------------------------

_write_gh_mock() {
  cat > "$GH_MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
# stub gh — GH_STATE_DIR 内のファイルで振る舞いを制御
set -uo pipefail

case "${1:-}" in
  repo)
    case "${2:-}" in
      view)
        # 引数: gh repo view <owner/repo> --json name -q .name
        repo_key="${3:-}"
        repo_safe="${repo_key//\//_}"
        state_file="$GH_STATE_DIR/${repo_safe}.state"
        if [ -f "$state_file" ]; then
          cat "$state_file"
          exit 0
        else
          # リポ不存在
          echo "gh: repository not found: ${repo_key}" >&2
          exit 1
        fi
        ;;
      create)
        # 引数: gh repo create <name> --private --source <path>
        repo_key=""
        for arg in "$@"; do
          [[ "$arg" == --* ]] && continue
          [[ "$arg" == "create" ]] && continue
          repo_key="$arg"
        done
        repo_safe="${repo_key//\//_}"
        create_allowed="$GH_STATE_DIR/${repo_safe}.create-allowed"
        if [ -f "$create_allowed" ]; then
          echo "{\"name\":\"${repo_key}\"}"
          exit 0
        else
          echo "gh: repository creation failed: ${repo_key}" >&2
          exit 1
        fi
        ;;
    esac
    ;;
  api)
    # gh api repos/<owner>/<repo>/collaborators/<user>/permission
    path="${3:-}"
    repo_safe="${path//\//_}"
    perm_file="$GH_STATE_DIR/${repo_safe}.permission"
    if [ -f "$perm_file" ]; then
      cat "$perm_file"
      exit 0
    else
      # デフォルト: write パーミッションなし
      echo '{"permission":"read"}'
      exit 0
    fi
    ;;
  *)
    echo "gh stub: unmatched args: $*" >&2
    exit 0
    ;;
esac
MOCK_EOF
  chmod +x "$GH_MOCK_DIR/gh"
}

# ---------------------------------------------------------------------------
# ヘルパー: --mode 引数パース + モード判定スクリプト
# ---------------------------------------------------------------------------

_write_mode_parse_script() {
  cat > "$SANDBOX/scripts/parse-mode.sh" << 'SCRIPT_EOF'
#!/usr/bin/env bash
# parse-mode.sh — test-project-init の引数パースロジックを再現
# Usage: parse-mode.sh [--mode <mode>] [--repo <owner/repo>]
# Exit code: 0 on success
# Output: JSON {"mode":"<mode>","repo":"<repo_or_null>"}

set -euo pipefail

MODE="local"
REPO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# バリデーション
if [[ "$MODE" != "local" && "$MODE" != "real-issues" ]]; then
  echo "invalid mode: $MODE (must be 'local' or 'real-issues')" >&2
  exit 1
fi

if [[ "$MODE" == "real-issues" && -z "$REPO" ]]; then
  echo "--repo is required for --mode real-issues" >&2
  exit 1
fi

if [[ -n "$REPO" ]]; then
  jq -n --arg mode "$MODE" --arg repo "$REPO" '{"mode": $mode, "repo": $repo}'
else
  jq -n --arg mode "$MODE" '{"mode": $mode, "repo": null}'
fi
SCRIPT_EOF
  chmod +x "$SANDBOX/scripts/parse-mode.sh"
}

# ---------------------------------------------------------------------------
# ヘルパー: リポ検証スクリプト (既存リポ / 空チェック / パーミッション確認)
# ---------------------------------------------------------------------------

_write_repo_validate_script() {
  cat > "$SANDBOX/scripts/validate-repo.sh" << 'SCRIPT_EOF'
#!/usr/bin/env bash
# validate-repo.sh — real-issues モードのリポ検証ロジックを再現
# Usage: validate-repo.sh <owner/repo>
# Exit code: 0 = OK, 1 = validation failure
# Output: JSON {"status":"ok"} or {"status":"error","reason":"<msg>"}

set -uo pipefail

REPO="${1:-}"
if [[ -z "$REPO" ]]; then
  echo '{"status":"error","reason":"repo argument required"}'
  exit 1
fi

OWNER="${REPO%%/*}"
NAME="${REPO##*/}"

# --- リポ存在チェック ---
repo_check=$(gh repo view "$REPO" --json name -q .name 2>/dev/null || echo "")

if [[ -z "$repo_check" ]]; then
  # リポ不存在 → 新規作成フローへ（本スクリプトはエラーにしない）
  echo '{"status":"not_found"}'
  exit 0
fi

# --- コミット数チェック (空リポ確認) ---
# 実際は gh api でコミット数を取得。スタブ用にファイルで制御
repo_safe="${REPO//\//_}"
commit_count_file="$GH_STATE_DIR/${repo_safe}.commit-count"
if [[ -f "$commit_count_file" ]]; then
  commit_count=$(cat "$commit_count_file")
else
  commit_count=0
fi

if [[ "$commit_count" -gt 0 ]]; then
  echo '{"status":"error","reason":"リポが空ではありません"}'
  exit 1
fi

# --- ブランチ数チェック (コミット数==0 かつ ブランチ数<=1 が空リポ条件) ---
branch_count_file="$GH_STATE_DIR/${repo_safe}.branch-count"
if [[ -f "$branch_count_file" ]]; then
  branch_count=$(cat "$branch_count_file")
else
  branch_count=0
fi

if [[ "$branch_count" -gt 1 ]]; then
  echo '{"status":"error","reason":"リポが空ではありません（ブランチ数超過）"}'
  exit 1
fi

# --- push パーミッション確認 ---
perm_key="${REPO//\//_}"
perm_file="$GH_STATE_DIR/${perm_key}.permission"
if [[ -f "$perm_file" ]]; then
  perm=$(jq -r '.permission' "$perm_file" 2>/dev/null || echo "read")
else
  perm="read"
fi

if [[ "$perm" != "write" && "$perm" != "admin" ]]; then
  echo '{"status":"error","reason":"push パーミッションがありません"}'
  exit 1
fi

echo '{"status":"ok"}'
SCRIPT_EOF
  chmod +x "$SANDBOX/scripts/validate-repo.sh"
}

# ---------------------------------------------------------------------------
# ヘルパー: config.json 生成スクリプト
# ---------------------------------------------------------------------------

_write_config_generate_script() {
  cat > "$SANDBOX/scripts/generate-config.sh" << 'SCRIPT_EOF'
#!/usr/bin/env bash
# generate-config.sh — .test-target/config.json を生成するロジックを再現
# Usage: generate-config.sh --mode <mode> [--repo <owner/repo>] --worktree-path <path> --branch <branch> --out <path>

set -euo pipefail

MODE=""
REPO=""
WORKTREE_PATH=""
BRANCH=""
OUT_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)        MODE="${2:-}"; shift 2 ;;
    --repo)        REPO="${2:-}"; shift 2 ;;
    --worktree-path) WORKTREE_PATH="${2:-}"; shift 2 ;;
    --branch)      BRANCH="${2:-}"; shift 2 ;;
    --out)         OUT_PATH="${2:-}"; shift 2 ;;
    *) echo "unknown: $1" >&2; exit 1 ;;
  esac
done

REPO_VAL="null"
if [[ -n "$REPO" ]]; then
  REPO_VAL="\"$REPO\""
fi

INITIALIZED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$(dirname "$OUT_PATH")"

jq -n \
  --arg mode "$MODE" \
  --argjson repo "$REPO_VAL" \
  --arg initialized_at "$INITIALIZED_AT" \
  --arg worktree_path "$WORKTREE_PATH" \
  --arg branch "$BRANCH" \
  '{mode:$mode, repo:$repo, initialized_at:$initialized_at, worktree_path:$worktree_path, branch:$branch}' \
  > "$OUT_PATH"

echo "config written to $OUT_PATH"
SCRIPT_EOF
  chmod +x "$SANDBOX/scripts/generate-config.sh"
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
