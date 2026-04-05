#!/bin/bash
# branch-create.sh
# フィーチャーブランチを作成（通常repo用）
# worktree-create.sh と同じ引数形式・バリデーションルール

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Issue番号からブランチ名を生成する関数
generate_branch_name_from_issue() {
    local issue_number="$1"

    # gh CLI でIssue情報取得
    local issue_json
    issue_json=$(gh issue view "$issue_number" --json title,labels 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "エラー: Issue #$issue_number が見つかりません" >&2
        return 1
    fi

    # タイトル取得
    local title
    title=$(echo "$issue_json" | jq -r '.title')

    # ラベルからプレフィックス判定
    local prefix="feat"
    local labels
    labels=$(echo "$issue_json" | jq -r '.labels[].name' 2>/dev/null || echo "")

    if echo "$labels" | grep -qi "bug"; then
        prefix="fix"
    elif echo "$labels" | grep -qi "documentation"; then
        prefix="docs"
    elif echo "$labels" | grep -qi "refactor"; then
        prefix="refactor"
    fi

    # タイトルをslug化
    # 1. [Feature] や [Bug] などのプレフィックスを削除
    # 2. 小文字化
    # 3. スペースをハイフンに
    # 4. 英数字とハイフン以外を削除
    # 5. 連続ハイフンを単一に
    # 6. 先頭・末尾のハイフン削除
    local slug
    slug=$(echo "$title" | \
        sed 's/^\[[^]]*\] *//' | \
        tr '[:upper:]' '[:lower:]' | \
        sed 's/ /-/g' | \
        sed 's/[^a-z0-9-]//g' | \
        sed 's/-\+/-/g' | \
        sed 's/^-//' | \
        sed 's/-$//')

    # 50文字制限（プレフィックス+番号+ハイフン分を考慮）
    local max_slug_len=$((45 - ${#prefix} - ${#issue_number}))
    if [ ${#slug} -gt $max_slug_len ]; then
        slug="${slug:0:$max_slug_len}"
        # 途中で切れたハイフンを削除
        slug=$(echo "$slug" | sed 's/-$//')
    fi

    echo "${prefix}/${issue_number}-${slug}"
}

# 引数解析
BRANCH_NAME=""
BASE_BRANCH="main"
ISSUE_NUMBER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --from)
            BASE_BRANCH="$2"
            shift 2
            ;;
        *)
            if [ -z "$BRANCH_NAME" ]; then
                BRANCH_NAME="$1"
            fi
            shift
            ;;
    esac
done

if [ -z "$BRANCH_NAME" ]; then
    echo "エラー: ブランチ名を指定してください"
    echo "使用方法: branch-create.sh <branch-name | #issue-number> [--from <base-branch>]"
    exit 1
fi

# Issue番号形式（#123）の検出と変換
if [[ "$BRANCH_NAME" =~ ^#([0-9]+)$ ]]; then
    ISSUE_NUMBER="${BASH_REMATCH[1]}"
    echo "Issue #$ISSUE_NUMBER からブランチ名を生成中..."
    BRANCH_NAME=$(generate_branch_name_from_issue "$ISSUE_NUMBER")
    if [ $? -ne 0 ]; then
        exit 1
    fi
    echo "生成されたブランチ名: $BRANCH_NAME"
fi

# ブランチ名のバリデーション
ALLOWED_PREFIXES="feat/|fix/|refactor/|docs/|test/|chore/"
RESERVED_NAMES="^(main|master|HEAD)$"

# 予約語チェック
if [[ "$BRANCH_NAME" =~ $RESERVED_NAMES ]]; then
    echo "エラー: '$BRANCH_NAME' は予約語です"
    exit 1
fi

# スラッシュを含む場合、許可されたプレフィックスかチェック
if [[ "$BRANCH_NAME" == */* ]]; then
    if ! [[ "$BRANCH_NAME" =~ ^($ALLOWED_PREFIXES) ]]; then
        echo "エラー: スラッシュを使用する場合は許可されたプレフィックスを使用してください"
        echo "許可されたプレフィックス: feat/, fix/, refactor/, docs/, test/, chore/"
        exit 1
    fi
fi

# 文字種チェック（英小文字、数字、ハイフン、スラッシュのみ）
if ! [[ "$BRANCH_NAME" =~ ^[a-z0-9/-]+$ ]]; then
    echo "エラー: ブランチ名には英小文字、数字、ハイフン、スラッシュのみ使用できます"
    exit 1
fi

# 50文字以下チェック
if [ ${#BRANCH_NAME} -gt 50 ]; then
    echo "エラー: ブランチ名は50文字以下にしてください"
    exit 1
fi

# gitリポジトリ確認
if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "エラー: gitリポジトリ内で実行してください"
    exit 1
fi

# 同名ブランチの既存チェック
if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    echo "エラー: ブランチ '$BRANCH_NAME' は既に存在します"
    exit 1
fi

echo "=== ブランチ作成: $BRANCH_NAME ==="
echo "派生元: $BASE_BRANCH"

# リモートから最新を取得してブランチ作成
if git remote get-url origin >/dev/null 2>&1; then
    git fetch origin
    git checkout -b "$BRANCH_NAME" "origin/$BASE_BRANCH"
    BRANCH_BASE="origin/$BASE_BRANCH"
else
    git checkout -b "$BRANCH_NAME" "$BASE_BRANCH"
    BRANCH_BASE="$BASE_BRANCH"
fi

echo ""
echo "=== ブランチ作成完了 ==="
echo "ブランチ: $BRANCH_NAME"
echo "派生元: $BRANCH_BASE"
if [ -n "$ISSUE_NUMBER" ]; then
    echo "Issue: #$ISSUE_NUMBER"
fi
