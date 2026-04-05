# /twl:project-board-sync - Project Board自動連携

Issue を GitHub Projects V2 に追加し、ラベル/Milestone からフィールドをミラーする atomic コマンド。

## 使用方法

```
/twl:project-board-sync 42
/twl:project-board-sync 42 43 44
/twl:project-board-sync https://github.com/owner/repo/issues/42
/twl:project-board-sync shuu5/twill#50       # クロスリポジトリ
```

## 引数

| 引数 | 必須 | 説明 |
|------|------|------|
| issue-number | Yes | Issue番号（複数スペース区切り可）またはIssue URL |

---

## 処理フロー（MUST）

### Step 0: スコープ検証

```bash
# project スコープの確認（exit code で判定）
if ! gh project list --owner @me --limit 1 >/dev/null 2>&1; then
  echo "⚠️ gh トークンに project スコープがありません"
  echo "以下を実行してスコープを追加してください:"
  echo "  gh auth refresh -s project"
  exit 0  # エラーにしない
fi
```

### Step 1: 引数解析

`$ARGUMENTS` から Issue 番号を抽出:

```
FOR each arg IN $ARGUMENTS:
  IF arg が URL形式（https://github.com/.../issues/N）
  THEN Issue番号 N を抽出、REPO = URLからowner/repoを抽出
  ELIF arg が owner/repo#N 形式（クロスリポジトリ）
  THEN Issue番号 N を抽出、ISSUE_REPO = "owner/repo"
  ELIF arg が数値
  THEN そのまま Issue番号として使用、ISSUE_REPO = カレントリポジトリ
  ELSE スキップ（警告出力）

  # 入力バリデーション（MUST）
  IF 抽出した番号が正の整数でない（[[ ! $N =~ ^[1-9][0-9]*$ ]]）
  THEN スキップ（"⚠️ 無効なIssue番号: $N" を出力）
```

Issue番号が1つも取得できない場合は使用方法を表示してエラー終了。

### Step 2: Project検出

```bash
# リポジトリにリンクされた Project V2 を検出
REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner')
OWNER="${REPO%%/*}"  # パラメータ展開でオーナーを抽出（echo不使用）
PROJECTS=$(gh project list --owner "$OWNER" --format json)
```

Project の中からリポジトリにリンクされたものを特定:

```bash
# 各 Project について GraphQL で linked repositories を確認
# user() → organization() フォールバックで両方に対応
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

REPO_NAME="${REPO##*/}"  # パラメータ展開でリポジトリ名を抽出（例: twill）
MATCHED_PROJECTS=()      # マッチした Project を全て収集
TITLE_MATCH_PROJECT=""   # タイトルマッチした Project

for PROJECT_NUM in <project-numbers>; do
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
    # マッチ — 収集リストに追加
    PROJECT_ID=$(echo "$PROJECT_DATA" | jq -r '.id')
    MATCHED_PROJECTS+=("$PROJECT_NUM:$PROJECT_ID")

    # Project タイトルがリポジトリ名を含む場合、優先候補として記録（最初のマッチを優先）
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

```
IF MATCHED_PROJECTS が 0 件
THEN
  echo "ℹ️ リポジトリにリンクされた Project がありません。スキップします。"
  → exit 0
IF MATCHED_PROJECTS が 2 件以上 AND TITLE_MATCH_PROJECT が空
THEN
  echo "⚠️ 複数の Project が検出されました。タイトルがリポジトリ名と一致する Project がないため、最初の Project を使用します。"
```

### Step 2.5: フィールド情報取得（ループ外）

```bash
# Project のフィールド一覧を取得（Issue ループの前に1回だけ実行）
FIELDS=$(gh project field-list "$PROJECT_NUM" --owner "$OWNER" --format json)
```

Context フィールドと Phase フィールドの ID + オプション一覧を抽出し変数に保持。

### Step 3: Issue処理ループ

各 Issue に対して以下を実行。1件の Issue が失敗しても次の Issue の処理を継続する。

#### 3a. Issue追加

```bash
# クロスリポジトリ: ISSUE_REPO が設定されている場合はその URL を使用
ISSUE_URL_REPO="${ISSUE_REPO:-$REPO}"
ISSUE_URL="https://github.com/$ISSUE_URL_REPO/issues/$ISSUE_NUM"

# 追加前に既存アイテムかチェック（新規か既存かを判定するため）
EXISTING_ITEM=$(gh project item-list "$PROJECT_NUM" --owner "$OWNER" --format json --limit 500 \
  | jq -r --arg url "$ISSUE_URL" '.items[] | select(.content.url == $url) | .id // empty')
IS_NEW_ITEM=false
[ -z "$EXISTING_ITEM" ] && IS_NEW_ITEM=true

ITEM_ID=$(gh project item-add "$PROJECT_NUM" --owner "$OWNER" \
  --url "$ISSUE_URL" --format json | jq -r '.id')
```

`gh project item-add` は既に追加済みの場合でも既存アイテムの ID を返す（GitHub の実装依存の挙動であり、仕様保証ではない）。

#### 3a-2. Status を "Todo" にセット（新規追加時のみ）

GitHub Projects のワークフロー自動化設定に依存せず、コードレベルで Status を制御する。

```bash
IF $IS_NEW_ITEM == true THEN
  STATUS_FIELD_ID=$(echo "$FIELDS" | jq -r '.fields.nodes[] | select(.name == "Status") | .id // empty')
  TODO_OPTION_ID=$(echo "$FIELDS" | jq -r '.fields.nodes[] | select(.name == "Status") | .options[] | select(.name == "Todo") | .id // empty')

  IF STATUS_FIELD_ID が空でない AND TODO_OPTION_ID が空でない
  THEN
    gh project item-edit --id "$ITEM_ID" --project-id "$PROJECT_ID" \
      --field-id "$STATUS_FIELD_ID" --single-select-option-id "$TODO_OPTION_ID"
  ELSE
    echo "⚠️ Status フィールドまたは Todo オプションが見つかりません。スキップします。"
```

既存アイテムの場合（IS_NEW_ITEM=false）は Status を上書きしない。

#### 3b. Issue メタデータ取得

```bash
ISSUE_DATA=$(gh issue view "$ISSUE_NUM" --json labels,milestone,title,body)
```

#### 3c. Context フィールドミラー

```
LABELS = Issue の labels から ctx/* プレフィックスのものを抽出
IF LABELS が 2 件以上 → アルファベット順の最初を使用 + 警告

IF LABELS が 0 件
THEN
  # フォールバック: architecture/ から Context を推定
  GIT_ROOT = $(git rev-parse --show-toplevel)
  IF "$GIT_ROOT/architecture/domain/contexts/" が存在しない
  THEN → スキップ（既存動作を維持）
  ELSE
    CONTEXT_FILES = Glob "$GIT_ROOT/architecture/domain/contexts/*.md"
    IF CONTEXT_FILES が 0 件 → スキップ
    ISSUE_TITLE_BODY = ISSUE_DATA のタイトルと本文を連結
    各 CONTEXT_FILE について:
      CONTEXT_NAME = ファイル名（拡張子除去）
      CONTEXT_CONTENT = ファイルの責務・スコープ記述を読み込み
      ISSUE_TITLE_BODY と CONTEXT_CONTENT のキーワードマッチングでスコアリング
    最も関連性の高い CONTEXT_NAME を CTX_NAME として採用
    IF スコアが閾値未満（いずれの context とも関連性が低い） → "⚠️ Context を推定できませんでした" + スキップ
ELSE
  CTX_NAME = ラベル名から "ctx/" プレフィックスを除去

FIELD = FIELDS から name="Context" の Single Select フィールドを検索
IF FIELD が見つからない → "⚠️ Context フィールドが見つかりません" + スキップ

OPTION = FIELD.options から name=CTX_NAME を検索
IF OPTION が見つからない → "⚠️ Context オプション '$CTX_NAME' が見つかりません" + スキップ

gh project item-edit --id "$ITEM_ID" --project-id "$PROJECT_ID" --field-id "$FIELD_ID" --single-select-option-id "$OPTION_ID"
```

#### 3d. Phase フィールドミラー

```
MILESTONE = Issue の milestone.title
IF MILESTONE が空 → スキップ

FIELD = FIELDS から name="Phase" の Single Select フィールドを検索
IF FIELD が見つからない → "⚠️ Phase フィールドが見つかりません" + スキップ

OPTION = FIELD.options から name=MILESTONE を検索
IF OPTION が見つからない → "⚠️ Phase オプション '$MILESTONE' が見つかりません" + スキップ

gh project item-edit --id "$ITEM_ID" --project-id "$PROJECT_ID" --field-id "$FIELD_ID" --single-select-option-id "$OPTION_ID"
```

### Step 4: 結果出力

```markdown
## Project Board 同期完了

| Issue | Project追加 | Status | Context | Phase |
|-------|-----------|--------|---------|-------|
| #42 | ✓ (新規) | Todo | payments | Phase 1: 基盤構築 |
| #43 | ✓ (既存) | - (上書きなし) | - (ラベルなし) | Phase 2: 機能実装 |
```

---

## エラーハンドリング

| エラー | 対応 |
|--------|------|
| スコープ不足 | `gh auth refresh -s project` を案内、exit 0 |
| Project未リンク | スキップ、exit 0 |
| フィールド未検出 | 警告出力、該当フィールドのみスキップ |
| オプション未検出 | 警告出力、該当フィールドのみスキップ |
| API エラー | エラー詳細を表示、該当 Issue をスキップして次へ |

---

## 禁止事項（MUST NOT）

- **Project Board のフィールドやオプションを自動作成してはならない**: 既存のものにマッチングのみ
- **エラーで全体を停止してはならない**: Issue 単位でスキップし、処理を継続

---

## 次のステップ

| 呼び出し元 | 次 |
|-----------|-----|
| `issue-create` | 最終ステップ完了。ワークフローに制御を返す |
| `architect-issue-create` | 一括処理完了。ワークフローに制御を返す |
