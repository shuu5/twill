---
type: atomic
tools: [Bash, Skill, Read]
effort: low
maxTurns: 10
---
# /twl:project-board-configure - Project Board ビュー標準設定

Board 作成後にビューの表示フィールドを標準化するコマンド。
GitHub Projects V2 のビュー設定（表示フィールド・並べ替え）は API で変更不可のため、不足を検出し、ブラウザを開いてユーザーに設定を案内する。

## 使用方法

```
/twl:project-board-configure
/twl:project-board-configure --project 6 --owner shuu5
```

## 引数

| 引数 | 必須 | 説明 |
|------|------|------|
| --project N | No | Project 番号（未指定: CLAUDE.md から自動取得） |
| --owner NAME | No | Project オーナー（未指定: CLAUDE.md から自動取得） |

---

## 標準ビューフィールド定義

以下のフィールドが全ビューの `visibleFields` に含まれていることを期待する:

| フィールド | 種別 | 必須 | 用途 |
|-----------|------|------|------|
| Title | built-in | Yes | Issue タイトル |
| Assignees | built-in | Yes | 担当者 |
| Status | built-in | Yes | Todo / In Progress / Done |
| Labels | built-in | Yes | ラベルによる分類・フィルタ・グループ化 |
| Linked pull requests | built-in | Yes | 関連 PR の追跡 |
| Repository | built-in | No | クロスリポ時のみ必要 |

---

## 処理フロー（MUST）

### Step 0: Project 特定

```
IF --project と --owner が指定されている
THEN そのまま使用
ELSE
  CLAUDE.md から "Project:" 行を検索して番号とオーナーを抽出
  IF 見つからない → エラー終了: "CLAUDE.md に Project Board 情報がありません"
```

### Step 1: ビューフィールド監査

```bash
# 全ビューの visibleFields を取得
gh api graphql -f query='
  query($owner: String!, $num: Int!) {
    user(login: $owner) {
      projectV2(number: $num) {
        id url
        views(first: 10) {
          nodes {
            id name layout
            visibleFields(first: 30) {
              nodes {
                ... on ProjectV2Field { id name }
              }
            }
          }
        }
      }
    }
  }
' -f owner="$OWNER" -F num="$PROJECT_NUM"
```

各ビューについて、標準必須フィールド（Title, Assignees, Status, Labels, Linked pull requests）が `visibleFields` に含まれているかチェック。

### Step 2: 結果判定

```
MISSING_FIELDS = 各ビューで不足しているフィールドのリスト

IF MISSING_FIELDS が空
THEN
  "✅ 全ビューの表示フィールドが標準に準拠しています" と表示
  → exit 0

ELSE
  不足フィールドのテーブルを表示:

  | ビュー | レイアウト | 不足フィールド |
  |--------|----------|--------------|
  | View 1 | TABLE | Labels |
  | View 2 | BOARD | Labels |
```

### Step 3: ブラウザで開く + 設定案内

```bash
gh project view "$PROJECT_NUM" --owner "$OWNER" --web
```

```markdown
## 手動設定が必要です

GitHub Projects V2 のビューフィールド設定は API 非対応のため、
ブラウザで以下を設定してください:

### Table View
1. テーブル右端の **+** ボタンをクリック
2. 不足フィールド（例: Labels）にチェック

### Board View
1. ビュー右上の **⚙️** (View settings) をクリック
2. **Fields** セクションで不足フィールドにチェック

### 推奨: Labels でグループ化
- Board View で **Group by** → **Labels** を選択すると
  ラベル別にカラムが分かれ、視認性が向上します

設定完了後、再度 `/twl:project-board-configure` を実行して検証できます。
```

---

## 禁止事項（MUST NOT）

- **ビューフィールドを API で変更しようとしてはならない**（mutation が存在しない）
- **フィールド自体を作成してはならない**（それは project-create.sh の責務）
- **ユーザー確認なしでブラウザを開いてはならない**（不足検出時のみ開く）
