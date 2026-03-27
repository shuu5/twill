## 1. PostToolUse hook 拡張（Bash エラー記録）

- [x] 1.1 `scripts/hooks/post-tool-use-bash-error.sh` を拡張: TOOL_INPUT から command（先頭200文字）、TOOL_OUTPUT から stderr_snippet（先頭500文字）、cwd を抽出して記録
- [x] 1.2 環境変数フォールバック: TOOL_INPUT/TOOL_OUTPUT が未設定の場合は空文字列で記録
- [x] 1.3 hooks.json の PostToolUse Bash hook エントリを確認（既存のため変更不要の見込み）

## 2. self-improve-review コマンド作成

- [x] 2.1 `commands/self-improve-review/COMMAND.md` を作成: atomic コマンド定義
- [x] 2.2 エラーログ読み込み・集計ロジック: コマンド別・exit_code 別にグループ化
- [x] 2.3 サマリーテーブル表示: 頻度順でマークダウンテーブル形式
- [x] 2.4 AskUserQuestion による選択 UI: 個別選択・全選択・スキップ・クリア
- [x] 2.5 問題構造化ロジック: 選択されたエラーを会話コンテキストと照合し構造化
- [x] 2.6 `.controller-issue/explore-summary.md` 出力: co-issue Phase 1 互換形式
- [x] 2.7 co-issue 続行確認メッセージ出力

## 3. co-issue 統合

- [x] 3.1 co-issue SKILL.md に explore-summary.md 検出ロジックを追加
- [x] 3.2 検出時の提案メッセージと Phase 2 スキップロジック
- [x] 3.3 拒否時の explore-summary.md 削除と通常フロー開始

## 4. deps.yaml 更新と検証

- [x] 4.1 deps.yaml の commands セクションに self-improve-review を atomic として登録
- [x] 4.2 `loom check` でバリデーション通過を確認
- [x] 4.3 `loom update-readme` で README 反映
