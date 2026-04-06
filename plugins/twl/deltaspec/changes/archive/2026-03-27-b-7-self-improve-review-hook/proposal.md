## Why

会話中の Bash エラーを機械的に記録し、ユーザー主導で問題を Issue 化できるフローが存在しない。現状ではエラーは流れて消え、再発パターンの検出や改善提案の起点がない。

## What Changes

- PostToolUse hook を追加し、Bash tool の exit_code != 0 を `.self-improve/errors.jsonl` に自動記録
- `self-improve-review` atomic コマンドを新設し、記録されたエラーのサマリー表示・選択・構造化を提供
- co-issue との接続点（`.controller-issue/explore-summary.md`）を定義し、既存 Issue 化フローを再利用
- SessionEnd hook でセッションスコープのクリーンアップを実行

## Capabilities

### New Capabilities

- **Bash エラー自動記録**: PostToolUse hook により exit_code != 0 の Bash 実行を JSONL に追記。サイレント・ノンブロッキング
- **self-improve-review コマンド**: エラーログの集計・サマリー表示・ユーザー選択・問題構造化を提供する atomic コマンド
- **co-issue 接続**: explore-summary.md 経由で co-issue Phase 2 にシームレスに接続

### Modified Capabilities

- **hooks.json**: PostToolUse（Bash エラー記録）と SessionEnd（クリーンアップ）の 2 hook を追加
- **co-issue**: 起動時に `.controller-issue/explore-summary.md` の存在を検出し、前回の探索結果からの続行を提案

## Impact

- **新規ファイル**: `commands/self-improve-review/` (atomic コマンド)、hook スクリプト
- **変更ファイル**: `hooks.json`（hook 追加）、`deps.yaml`（コマンド登録）、co-issue SKILL.md（explore-summary 検出ロジック追加）
- **依存関係**: #4 (B-2: hooks.json 基盤) に依存。co-issue (#8) との統合点あり
- **リスク**: テスト実行のエラーも記録されるが、選別は人間が行うため許容（設計判断）
