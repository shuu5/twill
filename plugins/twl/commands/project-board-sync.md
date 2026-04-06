# /twl:project-board-sync - Project Board自動連携

Issue を GitHub Projects V2 に追加し、Status を設定する atomic コマンド。

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
REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner')
OWNER="${REPO%%/*}"
PROJECTS=$(gh project list --owner "$OWNER" --format json)
```

各 Project について GraphQL で linked repositories を確認:
- `user(login: $owner) { projectV2(number: $num) { id, title, repositories { nodes { nameWithOwner } } } }`
- `user()` が null なら `organization()` にフォールバック

マッチロジック:
1. リポジトリにリンクされた全 Project を収集
2. タイトルにリポジトリ名を含む Project を優先（`TITLE_MATCH_PROJECT`）
3. タイトルマッチなし → 最初のマッチを使用
4. 0件 → スキップ（exit 0）、2件以上+タイトルマッチなし → 警告付きで最初を使用

### Step 2.5: フィールド情報取得（ループ外）

```bash
# Project のフィールド一覧を取得（Issue ループの前に1回だけ実行）
FIELDS=$(gh project field-list "$PROJECT_NUM" --owner "$OWNER" --format json)

# Status フィールド ID と Todo オプション ID を抽出
STATUS_FIELD_ID=$(echo "$FIELDS" | jq -r '.fields.nodes[] | select(.name == "Status") | .id // empty')
TODO_OPTION_ID=$(echo "$FIELDS" | jq -r '.fields.nodes[] | select(.name == "Status") | .options[] | select(.name == "Todo") | .id // empty')
```

### Step 3: Issue処理ループ

各 Issue を順に処理（1件失敗しても次へ継続）:
1. **Issue追加**: `gh project item-add` で追加（既存なら既存 ID 返却）。追加前に `item-list` で新規/既存判定
2. **Status設定**: 新規のみ `gh project item-edit` で "Todo" にセット（`STATUS_FIELD_ID` + `TODO_OPTION_ID` 使用）。既存は上書きしない

### Step 4: 結果出力

Issue ごとに追加状態（新規/既存）と Status 設定結果をテーブル出力。

## エラーハンドリング

スコープ不足 → `gh auth refresh -s project` 案内（exit 0）、Project未リンク → スキップ（exit 0）、Status未検出 → 警告+スキップ、API エラー → 該当 Issue スキップして継続。

## 禁止事項（MUST NOT）

- フィールド/オプションの自動作成禁止（既存マッチングのみ）
- エラーで全体停止禁止（Issue 単位でスキップ）
