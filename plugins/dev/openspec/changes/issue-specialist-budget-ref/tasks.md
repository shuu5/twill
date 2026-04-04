## 1. refs/ref-investigation-budget.md 作成

- [x] 1.1 `agents/issue-critic.md` の調査バジェット制御セクション（L62-69）を確認し、内容を記録
- [x] 1.2 `refs/ref-investigation-budget.md` を新規作成し、セクション内容を行単位一致でコピー

## 2. agents/issue-critic.md 更新

- [x] 2.1 frontmatter `skills:` に `ref-investigation-budget` を追加
- [x] 2.2 本文の調査バジェット制御セクションを削除し、ref 参照指示に置換（`**/refs/ref-investigation-budget.md` を Glob/Read して調査バジェットを確認すること）

## 3. agents/issue-feasibility.md 更新

- [x] 3.1 frontmatter `skills:` に `ref-investigation-budget` を追加
- [x] 3.2 本文の調査バジェット制御セクションを削除し、ref 参照指示に置換

## 4. deps.yaml 更新

- [x] 4.1 `refs` セクションに `ref-investigation-budget` を追加
- [x] 4.2 `agents/issue-critic` と `agents/issue-feasibility` の `skills:` フィールドに `ref-investigation-budget` を追加

## 5. テスト更新

- [x] 5.1 `tests/scenarios/co-issue-specialist-maxturns-fix.test.sh` の `assert_file_contains` を確認（agent 本文の「調査バジェット制御」文言チェック箇所）
- [x] 5.2 assert を ref ファイルの存在確認または agent frontmatter の skills 参照チェックに変更

## 6. 検証

- [x] 6.1 `loom check` を実行してエラーがないことを確認
- [x] 6.2 `loom update-readme` を実行
- [x] 6.3 `tests/scenarios/co-issue-specialist-maxturns-fix.test.sh` を実行して PASS を確認
