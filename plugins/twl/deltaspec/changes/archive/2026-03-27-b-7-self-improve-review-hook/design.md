## Context

loom-plugin-dev は「LLM は判断のために使う。機械的にできることは機械に任せる」を設計哲学とする。Bash エラーの記録は機械的処理、問題の選別は人間、構造化は LLM が担う。

既存の基盤:
- `hooks.json` に PostToolUse Bash エラー記録 hook が定義済み（`scripts/hooks/post-tool-use-bash-error.sh`）
- `.self-improve/` が `.gitignore` 対象
- 4 controller 制約（co-autopilot, co-issue, co-project, co-architect）

## Goals / Non-Goals

**Goals:**

- Bash エラーを JSONL に自動記録（command, stderr_snippet 含む拡張版）
- ユーザー主導のエラーレビュー・選択・構造化コマンド提供
- co-issue Phase 2 への接続（explore-summary.md 経由）
- セッション終了時の自動クリーンアップ

**Non-Goals:**

- 新 controller の追加（4 controller 制約を維持）
- エラーの自動対処・自動 Issue 化（判断は人間が行う）
- 非 Bash ツールのエラー記録（スコープ外）

## Decisions

### D-1: コマンド配置と deps.yaml 登録

`self-improve-review` を `commands/self-improve-review.md` として配置。deps.yaml の `commands` に atomic として登録。co-issue の `spawnable_by` は変更しない（explore-summary.md はファイルベースの接続）。

### D-2: エラー記録フォーマットの拡張

現行 hook は `exit_code` と `timestamp` のみ記録。Issue #19 の AC に合わせ `command`（先頭200文字）と `stderr_snippet`（先頭500文字）を追加。PostToolUse hook の環境変数 `$TOOL_INPUT` と `$TOOL_OUTPUT` から抽出。

### D-3: co-issue 接続方式

ファイルベース接続: self-improve-review が `.controller-issue/explore-summary.md` を出力 → co-issue が起動時にこのファイルを検出し Phase 2 から続行。co-issue の SKILL.md に検出ロジックを追加。

### D-4: クリーンアップは手動削除で対応

SessionEnd hook は Claude Code の hook 仕様上利用不可（PostToolUse / PreToolUse のみ）。代替として self-improve-review コマンド内で「クリア」オプションを提供。errors.jsonl は .gitignore 対象のためリポジトリには影響なし。

## Risks / Trade-offs

- **テスト実行のエラーも記録される**: 想定内。選別は人間がレビュー時に行う。ノイズを減らすフィルタリングは将来検討
- **PostToolUse 環境変数の制約**: `$TOOL_INPUT` / `$TOOL_OUTPUT` が利用可能かは Claude Code のバージョンに依存。利用不可の場合は exit_code のみの記録にフォールバック
- **co-issue への変更**: SKILL.md に探索結果検出ロジックを追加するため、co-issue の振る舞いが変わる。ただし検出は提案のみで自動実行しないため安全
