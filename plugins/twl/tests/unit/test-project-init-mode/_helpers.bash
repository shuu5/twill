#!/usr/bin/env bash
# _helpers.bash
# test-project-init-mode テスト群の共通ヘルパー
# 各 .bats ファイルで load '_helpers' して使用する

# ---------------------------------------------------------------------------
# サンドボックス共通セットアップ
# ---------------------------------------------------------------------------

_setup_dirs() {
  GH_STATE_DIR="$SANDBOX/gh-state"
  GH_MOCK_DIR="$SANDBOX/gh-bin"
  mkdir -p "$GH_STATE_DIR" "$GH_MOCK_DIR"
  export GH_STATE_DIR
}

_setup_gh_mock() {
  _write_gh_mock
  export PATH="$GH_MOCK_DIR:$PATH"
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
