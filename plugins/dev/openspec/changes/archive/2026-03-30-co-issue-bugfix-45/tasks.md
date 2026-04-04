## 1. project-board-sync: Project 検出改善

- [x] 1.1 `commands/project-board-sync.md` Step 2 のループロジックを修正: リポジトリ名と Project タイトルのマッチングを優先する条件分岐を追加
- [x] 1.2 複数 Project 検出時の警告メッセージを「タイトルマッチなし」ケースに限定

## 2. co-issue: 推奨ラベル受け渡しチェーン修復

- [x] 2.1 `skills/co-issue/SKILL.md` Phase 3.2 後に推奨ラベル抽出ステップを追加: `## 推奨ラベル` セクションから `ctx/<name>` を抽出し Issue 候補に記録
- [x] 2.2 `skills/co-issue/SKILL.md` Phase 4.2 で issue-create 呼び出し時に記録済み推奨ラベルを `--label` 引数として渡すフローを明記

## 3. project-board-sync: Context フォールバック推定

- [x] 3.1 `commands/project-board-sync.md` Step 3c に ctx/* ラベルなし時のフォールバック追加: architecture/ の context 定義と Issue 内容のキーワードマッチング
- [x] 3.2 architecture/ 未存在・マッチなしケースのスキップ処理と警告メッセージ追加

## 4. 検証

- [x] 4.1 co-issue フルフロー（Phase 1-4）のマニュアル E2E テスト: ctx/* ラベル自動付与の確認
- [x] 4.2 project-board-sync の正しい Project (#3) への同期確認
- [x] 4.3 Context フィールドが ctx/* ラベルに基づき自動設定されることの確認
