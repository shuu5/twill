#!/bin/bash
# create-harness-issue.sh
# harness分類時にubuntu-note-systemへcross-repo Issue自動作成
# Usage: create-harness-issue.sh <snapshot-dir> [--project <name>] [--pr <number>] [--step <step-name>]

set -euo pipefail

TARGET_REPO="shuu5/ubuntu-note-system"
LABEL="harness-bug"

# --- 引数解析 ---
SNAPSHOT_DIR=""
PROJECT_NAME=""
PR_NUMBER=""
FAILED_STEP=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project) PROJECT_NAME="$2"; shift 2 ;;
        --pr) PR_NUMBER="$2"; shift 2 ;;
        --step) FAILED_STEP="$2"; shift 2 ;;
        *) SNAPSHOT_DIR="$1"; shift ;;
    esac
done

if [ -z "$SNAPSHOT_DIR" ]; then
    echo "Usage: create-harness-issue.sh <snapshot-dir> [--project <name>] [--pr <number>] [--step <step-name>]" >&2
    exit 1
fi

# パストラバーサル防止: /tmp/ 配下のみ許可
SNAPSHOT_DIR=$(realpath "$SNAPSHOT_DIR" 2>/dev/null || echo "$SNAPSHOT_DIR")
if [[ "$SNAPSHOT_DIR" != /tmp/* ]]; then
    echo "エラー: SNAPSHOT_DIR は /tmp/ 配下のみ許可されています: $SNAPSHOT_DIR" >&2
    exit 1
fi

CLASSIFICATION_FILE="$SNAPSHOT_DIR/05.5-failure-classification.json"

if [ ! -f "$CLASSIFICATION_FILE" ]; then
    echo "エラー: 分類結果ファイルが見つかりません: $CLASSIFICATION_FILE" >&2
    exit 1
fi

# --- 分類結果読み取り ---
CLASSIFICATION=$(jq -r '.classification' "$CLASSIFICATION_FILE")
CONFIDENCE=$(jq -r '.confidence' "$CLASSIFICATION_FILE")
COMPONENT=$(jq -r '.component // ""' "$CLASSIFICATION_FILE")
EVIDENCE=$(jq -r '.evidence | join(", ")' "$CLASSIFICATION_FILE")

# harness以外 or confidence不足は終了
if [ "$CLASSIFICATION" != "harness" ]; then
    echo "分類が harness ではありません ($CLASSIFICATION) — スキップ"
    exit 0
fi

if [ "$CONFIDENCE" -lt 70 ]; then
    echo "confidence不足 ($CONFIDENCE < 70) — スキップ"
    exit 0
fi

# --- プロジェクト情報の自動取得 ---
if [ -z "$PROJECT_NAME" ]; then
    if [ -f ".git" ]; then
        # worktree モード → bare repo root から取得
        PROJECT_NAME=$(basename "$(dirname "$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" && pwd)")" 2>/dev/null) || PROJECT_NAME='unknown'
    else
        PROJECT_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || echo 'unknown')")
    fi
fi

if [ -z "$PR_NUMBER" ]; then
    PR_NUMBER=$(gh pr view --json number -q '.number' 2>/dev/null || echo "")
fi

# dev plugin バージョン（git hash）
DEV_PLUGIN_VERSION=$(git -C "$HOME/.claude/plugins/twl" rev-parse --short HEAD 2>/dev/null || echo "unknown")

# --- 重複チェック ---
# 同一コンポーネントのopen Issueを検索
SEARCH_QUERY="[Harness] is:open"
if [ -n "$COMPONENT" ]; then
    # コンポーネントのファイル名部分で検索（英数字・ハイフン・ドット・アンダースコアのみ許可）
    COMPONENT_BASENAME=$(basename "$COMPONENT" | tr -cd 'a-zA-Z0-9._-')
    [ -n "$COMPONENT_BASENAME" ] && SEARCH_QUERY="[Harness] $COMPONENT_BASENAME is:open"
fi

EXISTING_ISSUE=$(gh issue list -R "$TARGET_REPO" --search "$SEARCH_QUERY" --json number,url --limit 5 2>/dev/null || echo "[]")
EXISTING_COUNT=$(echo "$EXISTING_ISSUE" | jq 'length')

if [ "$EXISTING_COUNT" -gt 0 ]; then
    EXISTING_URL=$(echo "$EXISTING_ISSUE" | jq -r '.[0].url')
    echo "重複Issue検出: $EXISTING_URL — 新規作成スキップ"

    # 既存Issue URLを分類結果に記録
    jq --arg url "$EXISTING_URL" '.issue_url = $url' "$CLASSIFICATION_FILE" > "${CLASSIFICATION_FILE}.tmp"
    mv "${CLASSIFICATION_FILE}.tmp" "$CLASSIFICATION_FILE"
    exit 0
fi

# --- ラベル確保 ---
gh label create "$LABEL" --repo "$TARGET_REPO" --color "B60205" --description "ハーネス障害自動レポート" 2>/dev/null || true

# --- エラーログ抜粋 ---
ERROR_EXCERPT=""
for f in "$SNAPSHOT_DIR"/04-test-result.md "$SNAPSHOT_DIR"/06-fix-result.md "$SNAPSHOT_DIR"/05-diagnose-result.md; do
    if [ -f "$f" ]; then
        ERROR_EXCERPT+="### $(basename "$f")"$'\n'
        ERROR_EXCERPT+=$(head -50 "$f")$'\n\n'
    fi
done

# 最大2000文字に制限
if [ ${#ERROR_EXCERPT} -gt 2000 ]; then
    ERROR_EXCERPT="${ERROR_EXCERPT:0:2000}...(truncated)"
fi

# --- Issue本文作成 ---
ISSUE_BODY_FILE="$SNAPSHOT_DIR/harness-issue-body.md"

cat > "$ISSUE_BODY_FILE" <<BODY_EOF
## ハーネス障害レポート

**発生プロジェクト**: ${PROJECT_NAME}
**発生元PR**: ${PR_NUMBER:+#$PR_NUMBER}${PR_NUMBER:-N/A}
**発生ステップ**: ${FAILED_STEP:-不明}
**分類**: harness (confidence: ${CONFIDENCE}%)

### 問題
${EVIDENCE}

### 該当コンポーネント
- \`${COMPONENT:-特定不可}\`

### エラーログ抜粋
<details>
<summary>展開</summary>

${ERROR_EXCERPT:-エラーログなし}

</details>

### 再現手順
1. ${PROJECT_NAME} で \`/twl:controller-setup --auto\`
2. PR cycle の ${FAILED_STEP:-不明なステップ} で発生

### 環境情報
- dev plugin version: ${DEV_PLUGIN_VERSION}
- project: ${PROJECT_NAME}
BODY_EOF

# --- Issue タイトル作成（安全にサニタイズ） ---
SAFE_COMPONENT=$(printf '%s' "${COMPONENT:-unknown}" | tr -d '`$"' | head -c 100)
SAFE_PROJECT=$(printf '%s' "${PROJECT_NAME}" | tr -d '`$"' | head -c 50)
ISSUE_TITLE="[Harness] ${SAFE_COMPONENT} — ${SAFE_PROJECT}"

# --- Issue作成 ---
# stdout/stderrを分離（エラー出力に認証情報が含まれる可能性を回避）
GH_ERR_FILE=$(mktemp)
ISSUE_URL=$(gh issue create \
    -R "$TARGET_REPO" \
    --title "$ISSUE_TITLE" \
    --label "$LABEL" \
    --body-file "$ISSUE_BODY_FILE" 2>"$GH_ERR_FILE") || {
    echo "Issue作成失敗" >&2
    rm -f "$GH_ERR_FILE"
    exit 1
}
rm -f "$GH_ERR_FILE"

echo "Issue作成完了: $ISSUE_URL"

# Issue URLを分類結果に記録
jq --arg url "$ISSUE_URL" '.issue_url = $url' "$CLASSIFICATION_FILE" > "${CLASSIFICATION_FILE}.tmp"
mv "${CLASSIFICATION_FILE}.tmp" "$CLASSIFICATION_FILE"
