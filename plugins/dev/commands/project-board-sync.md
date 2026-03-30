# /dev:project-board-sync - Project Board自動連携

Issue を GitHub Projects V2 に追加し、ラベル/Milestone からフィールドをミラーする atomic コマンド。

## 使用方法

```
/dev:project-board-sync 42
/dev:project-board-sync 42 43 44
/dev:project-board-sync https://github.com/owner/repo/issues/42
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
  THEN Issue番号 N を抽出
  ELIF arg が数値
  THEN そのまま Issue番号として使用
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
        repositories(first: 20) { nodes { nameWithOwner } }
      }
    }
  }
'

PROJECT_ID=""
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

  if echo "$LINKED" | grep -qxF "$REPO"; then
    # マッチ — PROJECT_NUM と PROJECT_ID を保持
    PROJECT_ID=$(echo "$PROJECT_DATA" | jq -r '.id')
    break
  fi
done
```

```
IF リンクされた Project が 0 件
THEN
  echo "ℹ️ リポジトリにリンクされた Project がありません。スキップします。"
  → exit 0
IF リンクされた Project が 2 件以上
THEN
  echo "⚠️ 複数の Project が検出されました。最初の Project を使用します。"
  最初の Project を使用
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
ITEM_ID=$(gh project item-add "$PROJECT_NUM" --owner "$OWNER" \
  --url "https://github.com/$REPO/issues/$ISSUE_NUM" --format json | jq -r '.id')
```

`gh project item-add` は既に追加済みの場合でも既存アイテムの ID を返す（GitHub の実装依存の挙動であり、仕様保証ではない）。

#### 3b. Issue メタデータ取得

```bash
ISSUE_DATA=$(gh issue view "$ISSUE_NUM" --json labels,milestone)
```

#### 3c. Context フィールドミラー

```
LABELS = Issue の labels から ctx/* プレフィックスのものを抽出
IF LABELS が 0 件 → スキップ
IF LABELS が 2 件以上 → アルファベット順の最初を使用 + 警告
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

| Issue | Project追加 | Context | Phase |
|-------|-----------|---------|-------|
| #42 | ✓ | payments | Phase 1: 基盤構築 |
| #43 | ✓ | - (ラベルなし) | Phase 2: 機能実装 |
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
