---
type: atomic
tools: [Bash, AskUserQuestion]
effort: low
maxTurns: 10
---
# prompt-audit-apply

prompt-audit-review の結果を受け取り、PASS → refined_by 更新、WARN → 報告、FAIL → tech-debt Issue 起票を処理する。

## 引数

- `<review-result>`: prompt-audit-review が出力した JSON 結果

## 処理フロー（トランザクション順序）

### Step 0: fail-fast チェック

`twl refine --help` が失敗した場合、即エラーで終了:
```
✗ twl refine が見つかりません。Tier 1 Issue の完了を確認してください。
```

### Step 1: PASS コンポーネントの refined_by 更新（可逆）

PASS コンポーネントが 1 件以上の場合:

1. pass-list.json を生成:
   ```json
   [{"component": "name-a"}, {"component": "name-b"}]
   ```
2. `twl refine --batch pass-list.json` を実行

### Step 2: 整合性検証（可逆）

```bash
twl check && twl validate
```

失敗した場合:
```bash
git checkout -- deps.yaml
```
エラー内容を報告して終了（以降のステップは実行しない）。

### Step 3: コミット（可逆）

```bash
git add deps.yaml && git commit -m "chore(deps): update refined_by hashes"
```

### Step 4: WARN コンポーネントの報告（非可逆だが無害）

WARN コンポーネントがある場合、findings を表示:
```
⚠️ WARN コンポーネント（<count> 件）:
  <name>: <findings>
  ...
（Issue 起票なし — 軽微な指摘のため）
```

### Step 5: FAIL コンポーネントの tech-debt Issue 起票（非可逆、ユーザー確認後）

FAIL コンポーネントがある場合:

1. findings をユーザーに表示
2. AskUserQuestion で確認:
   > "FAIL コンポーネント（<count> 件）の tech-debt Issue を起票しますか？ [Y/n]"
3. Y の場合、各 FAIL コンポーネントに対して `gh issue create`:
   ```
   タイトル: tech-debt: prompt compliance FAIL — <component-name>
   ラベル: tech-debt
   本文: findings の内容
   ```
   作成成功時: 出力 URL（`https://github.com/<owner>/<repo>/issues/<N>` 形式）から issue_number を抽出し、`/twl:project-board-sync <issue_number>` を Skill tool で呼び出す（Board Status を "Todo" に設定。失敗は非ブロッキング）。

## 完了出力

```
✓ prompt-audit-apply 完了
  refined_by 更新: <PASS count> 件
  WARN 報告: <WARN count> 件
  tech-debt Issue 起票: <FAIL count> 件
```
