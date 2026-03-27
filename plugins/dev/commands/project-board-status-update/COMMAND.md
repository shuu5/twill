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

GraphQL で linked repositories を確認し、現在のリポジトリにリンクされた Project を特定（user → organization フォールバック）。

### Step 3: Issue を Project に追加

```bash
gh project item-add "$PROJECT_NUM" --owner "$OWNER" \
  --url "https://github.com/$REPO/issues/$ISSUE_NUM" --format json
```

### Step 4: Status を "In Progress" に更新

Status フィールドの "In Progress" オプション ID を取得し、`gh project item-edit` で更新。

成功時: `"✓ Project Board Status → In Progress (#$ISSUE_NUM)"`

## エラーハンドリング

全ての失敗パスで正常終了する（ワークフローを停止しない）。

## 禁止事項（MUST NOT）

- Project Board のフィールドやオプションを自動作成してはならない
- エラーでワークフロー全体を停止してはならない

## チェックポイント（MUST）

`/dev:crg-auto-build` を Skill tool で自動実行。

