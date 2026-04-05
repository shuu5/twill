## 1. co-issue: Step 1.5 glossary 照合追加

- [x] 1.1 `skills/co-issue/SKILL.md` を読み、Phase 1 完了後の位置を特定する
- [x] 1.2 Step 1.5 を追加: `architecture/domain/glossary.md` の存在チェック（非存在時はスキップ）
- [x] 1.3 glossary の MUST 用語パース処理を実装（Markdown テーブルから用語抽出）
- [x] 1.4 explore-summary.md の主要用語と MUST 用語の照合ロジックを実装
- [x] 1.5 完全不一致用語が 1 件以上で INFO 通知「この概念は architecture spec に未定義です: [用語]」を出力
- [x] 1.6 通知後 Phase 2 に継続することを確認（フロー停止なし）

## 2. worker-architecture: drift 検出ロジック追加

- [x] 2.1 `agents/worker-architecture.md` を読み、PR diff モードの評価セクションを特定する
- [x] 2.2 `architecture/` 存在チェックを追加（非存在時は drift 検出全スキップ）
- [x] 2.3 新状態値検出: PR diff から IssueState/SessionState 外の状態値を検出
- [x] 2.4 未定義エンティティ検出: `domain/model.md` に定義されていない新エンティティを検出
- [x] 2.5 glossary 未登録用語検出: MUST 用語にない新用語のコード内使用を検出
- [x] 2.6 検出結果を `severity: WARNING`, `category: architecture-drift` として出力フォーマットに追加

## 3. autopilot-retrospective: Step 4.5 追加

- [x] 3.1 `commands/autopilot-retrospective.md` を読み、Step 4 の位置を特定する
- [x] 3.2 Step 4.5 を追加: `architecture/` 存在チェック（非存在時はスキップ）
- [x] 3.3 Phase で変更されたファイルの収集ロジックを実装
- [x] 3.4 変更ファイルと architecture/ コンテキストの対応マッピングを実装
- [x] 3.5 乖離候補リストを「以下の architecture 項目の更新を検討してください:」形式で提示
- [x] 3.6 自動 Issue 化を行わないことを確認（提示のみ）

## 4. deps.yaml 更新

- [x] 4.1 `deps.yaml` を読み、worker-architecture エントリを特定する
- [x] 4.2 参照ファイルに `architecture/domain/glossary.md` を追加
- [x] 4.3 参照ファイルに `architecture/domain/model.md` を追加
- [x] 4.4 参照ファイルに `architecture/vision.md` を追加
- [x] 4.5 `loom check` で deps.yaml の整合性を確認
- [x] 4.6 `loom update-readme` で README を更新
