# Project Board Status 更新

Issue の Project Board Status を "In Progress" に更新する。

## 引数

| 引数 | 必須 | 説明 |
|------|------|------|
| ISSUE_NUM | Yes | Issue 番号（正の整数） |

## 処理フロー（MUST）

### Step 0: 引数バリデーション

ISSUE_NUM が未設定 or 正の整数でない → 何も出力せず正常終了。

### Step 1: project スコープ確認

```bash
gh project list --owner @me --limit 1 >/dev/null 2>&1
```

失敗 → `gh auth refresh -s project` を案内、正常終了。

### Step 2: Project 検出

```bash
REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner')
OWNER="${REPO%%/*}"
REPO_NAME="${REPO##*/}"
PROJECTS=$(gh project list --owner "$OWNER" --format json)
```

各 Project について GraphQL で linked repositories を確認し、リポジトリにリンクされた Project を特定する。user → organization フォールバックで両方に対応。

```bash
GRAPHQL_QUERY='
  query($owner: String!, $num: Int!) {
    user(login: $owner) {
      projectV2(number: $num) {
        id
        title
        repositories(first: 20) { nodes { nameWithOwner } }
      }
    }
  }
'
GRAPHQL_QUERY_ORG='
  query($owner: String!, $num: Int!) {
    organization(login: $owner) {
      projectV2(number: $num) {
        id
        title
        repositories(first: 20) { nodes { nameWithOwner } }
      }
    }
  }
'

MATCHED_PROJECTS=()
TITLE_MATCH_PROJECT=""

PROJECT_NUMBERS=$(echo "$PROJECTS" | jq -r '.projects[].number')

for PROJECT_NUM in $PROJECT_NUMBERS; do
  # まず user() で試行
  RESULT=$(gh api graphql -f query="$GRAPHQL_QUERY" -f owner="$OWNER" -F num="$PROJECT_NUM" 2>/dev/null)
  PROJECT_DATA=$(echo "$RESULT" | jq -r '.data.user.projectV2 // empty')

  # user() が null なら organization() にフォールバック
  if [ -z "$PROJECT_DATA" ]; then
    RESULT=$(gh api graphql -f query="$GRAPHQL_QUERY_ORG" -f owner="$OWNER" -F num="$PROJECT_NUM" 2>/dev/null)
    PROJECT_DATA=$(echo "$RESULT" | jq -r '.data.organization.projectV2 // empty')
  fi

  if [ -z "$PROJECT_DATA" ]; then
    continue
  fi

  LINKED=$(echo "$PROJECT_DATA" | jq -r '.repositories.nodes[].nameWithOwner')
  PROJECT_TITLE=$(echo "$PROJECT_DATA" | jq -r '.title // empty')

  if echo "$LINKED" | grep -qxF "$REPO"; then
    PROJECT_ID=$(echo "$PROJECT_DATA" | jq -r '.id')
    MATCHED_PROJECTS+=("$PROJECT_NUM:$PROJECT_ID")

    # Project タイトルがリポジトリ名を含む場合、優先候補として記録
    if [[ "$PROJECT_TITLE" == *"$REPO_NAME"* ]] && [ -z "$TITLE_MATCH_PROJECT" ]; then
      TITLE_MATCH_PROJECT="$PROJECT_NUM:$PROJECT_ID"
    fi
  fi
done

# 優先選択: タイトルマッチ > 最初のマッチ
if [ -n "$TITLE_MATCH_PROJECT" ]; then
  PROJECT_NUM="${TITLE_MATCH_PROJECT%%:*}"
  PROJECT_ID="${TITLE_MATCH_PROJECT#*:}"
elif [ ${#MATCHED_PROJECTS[@]} -gt 0 ]; then
  PROJECT_NUM="${MATCHED_PROJECTS[0]%%:*}"
  PROJECT_ID="${MATCHED_PROJECTS[0]#*:}"
fi
```

| 条件 | 動作 |
|------|------|
| MATCHED_PROJECTS が 0 件 | 正常終了（ワークフロー停止しない） |
| MATCHED_PROJECTS が 2 件以上 AND TITLE_MATCH_PROJECT が空 | `"⚠️ 複数の Project が検出されました。最初の Project を使用します。"` |

### Step 3: Issue を Project に追加

```bash
ITEM_ID=$(gh project item-add "$PROJECT_NUM" --owner "$OWNER" \
  --url "https://github.com/$REPO/issues/$ISSUE_NUM" --format json | jq -r '.id')
```

### Step 4: Status を "In Progress" に更新

Status フィールドの "In Progress" オプション ID を取得し、`gh project item-edit` で更新。

```bash
FIELDS=$(gh project field-list "$PROJECT_NUM" --owner "$OWNER" --format json)
# Status フィールドから "In Progress" オプション ID を取得
# gh project item-edit --id "$ITEM_ID" --project-id "$PROJECT_ID" \
#   --field-id "$STATUS_FIELD_ID" --single-select-option-id "$IN_PROGRESS_OPTION_ID"
```

成功時: `"✓ Project Board Status → In Progress (#$ISSUE_NUM)"`

## エラーハンドリング

全ての失敗パスで正常終了する（ワークフローを停止しない）。

## 禁止事項（MUST NOT）

- Project Board のフィールドやオプションを自動作成してはならない
- エラーでワークフロー全体を停止してはならない

## チェックポイント（MUST）

`/dev:crg-auto-build` を Skill tool で自動実行。

