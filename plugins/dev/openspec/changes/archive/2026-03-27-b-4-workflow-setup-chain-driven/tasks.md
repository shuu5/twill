## 1. deps.yaml chains セクション追加

- [x] 1.1 deps.yaml に `chains:` セクションを追加し、`setup` chain を type A で定義する（steps リスト含む）
- [x] 1.2 `loom check` を実行し chain 構文エラーがないことを確認する

## 2. 新規コンポーネント登録

- [x] 2.1 deps.yaml commands セクションに init, worktree-create, worktree-delete, worktree-list を atomic として追加する
- [x] 2.2 deps.yaml commands セクションに project-board-status-update, crg-auto-build を atomic として追加する
- [x] 2.3 deps.yaml commands セクションに opsx-propose, opsx-apply, opsx-archive, ac-extract を atomic として追加する
- [x] 2.4 deps.yaml skills セクションに workflow-setup を workflow 型で追加し、calls フィールドで chain ステップを参照する
- [x] 2.5 deps.yaml skills セクションに workflow-test-ready を workflow 型で追加する
- [x] 2.6 全コンポーネントに chain, step_in フィールドを設定する
- [x] 2.7 `loom check` および `loom validate` を実行し全パスを確認する

## 3. COMMAND.md / SKILL.md 作成

- [x] 3.1 commands/init.md を作成する（旧 plugin の init.md からドメインロジックを移植）
- [x] 3.2 commands/worktree-create.md を作成する
- [x] 3.3 commands/worktree-delete.md, commands/worktree-list.md を作成する
- [x] 3.4 commands/project-board-status-update.md を作成する
- [x] 3.5 commands/crg-auto-build.md を作成する
- [x] 3.6 commands/opsx-propose.md を作成する
- [x] 3.7 commands/opsx-apply.md, commands/opsx-archive.md を作成する
- [x] 3.8 commands/ac-extract.md を作成する
- [x] 3.9 skills/workflow-test-ready/SKILL.md を作成する

## 4. workflow-setup SKILL.md 縮小

- [x] 4.1 skills/workflow-setup/SKILL.md を新規作成し、ドメインルールのみ記載する（arch-ref 抽出、OpenSpec 分岐条件、引数解析）
- [x] 4.2 chain generate で生成されるチェックポイント・called-by テンプレートとの整合性を確認する
- [x] 4.3 旧 plugin SKILL.md 比でのトークン削減率を測定し 50% 以上を確認する

## 5. chain generate 実行と検証

- [x] 5.1 `loom chain generate setup --write` を実行し、各コンポーネントにチェックポイント・called-by テンプレートを挿入する
- [x] 5.2 `loom check` で全項目パスを確認する
- [x] 5.3 `loom validate` で型ルール違反がないことを確認する
- [x] 5.4 `loom update-readme` で SVG グラフと README を更新する
