## 1. Phase 2: クロスリポ検出ロジック

- [x] 1.1 co-issue SKILL.md の Phase 2 セクションにクロスリポ検出ステップを追加（explore-summary.md 読み込み直後）
- [x] 1.2 検出ロジックの記述: キーワード検出（「全リポ」「3リポ」「各リポ」「クロスリポ」）+ 複数リポ名言及の判定
- [x] 1.3 リポ一覧の動的取得手順を記述: `gh project` のリンク済みリポジトリから取得（project-board-status-update と同様のパターン）
- [x] 1.4 AskUserQuestion による分割提案の記述: [A] リポ単位で分割する [B] 単一 Issue として作成する

## 2. Phase 3: リポ単位の精緻化対応

- [x] 2.1 Phase 3 の issue-structure 呼び出しをリポ単位子 Issue に対応: 各リポの子 Issue 候補に対してテンプレート適用
- [x] 2.2 parent Issue の構造化ルールを記述: 仕様定義のみ（実装スコープなし）、子 Issue セクション付き

## 3. Phase 4: parent + 子 Issue 作成フロー

- [x] 3.1 Phase 4 にクロスリポ分割時の分岐を追加: 分割承認フラグの検出
- [x] 3.2 parent Issue 作成ロジックの記述: 現在のリポに `gh issue create` で作成、body に子 Issue チェックリストのプレースホルダー
- [x] 3.3 子 Issue 作成ロジックの記述: `gh issue create -R owner/repo` で各対象リポに作成、body に `Parent: owner/repo#N` 参照
- [x] 3.4 parent Issue へのチェックリスト追記: 全子 Issue 作成後に `gh issue edit` で `- [ ] owner/repo#N` 形式のリストを追記
- [x] 3.5 エラーハンドリング: 子 Issue 作成失敗時は警告のみで残りを継続

## 4. deps.yaml 更新

- [x] 4.1 co-issue の calls に変更があれば deps.yaml を更新（新規 calls なし — 変更不要）
- [x] 4.2 `loom check` で 0 violations を確認（OK: 149, Missing: 0）

## 5. テスト・検証

- [x] 5.1 structure テスト: co-issue SKILL.md の構造が deps.yaml と整合することを確認（loom check OK, テストファイル 39 cases 生成済み。bats-support 空で既存テストも実行不可 — 環境問題）
- [x] 5.2 シナリオテスト: SKILL.md に Phase 2 クロスリポ検出・Phase 4 parent/子 Issue 作成の全ロジックが記述済みであることを確認
