## Why

loom-plugin-dev は B-1 でアーキテクチャ設計を完了したが、実際のプラグインディレクトリ構造・deps.yaml・CLAUDE.md がまだ存在しない。Claude Code がこのリポジトリを dev plugin として認識し、loom CLI で検証可能な状態にするためのプロジェクト基盤構築が必要。

## What Changes

- bare repo + main worktree の正規ディレクトリ構造を作成（skills/, commands/, agents/, refs/, scripts/ 等）
- deps.yaml v3.0 skeleton を作成（controller 4つ + 型ルール定義）
- .claude-plugin/plugin.json を配置し Claude Code のプラグイン認識を有効化
- CLAUDE.md に bare repo 構造検証ルールとセッション起動ルールを追記
- .gitignore を配置
- hooks.json + PostToolUse hook（loom validate on Edit/Write）+ SessionEnd hook を配置
- PostToolUse hook（Bash）: エラー記録（exit_code != 0 → .self-improve/errors.jsonl）を配置（B-7 の基盤）

## Capabilities

### New Capabilities

- **プラグイン認識**: Claude Code が loom-plugin-dev を dev plugin として認識し、skills/commands/agents をロード可能になる
- **loom CLI 検証**: `loom check` / `loom validate` がこのプラグインに対して実行可能になる
- **Bash エラー自動記録**: PostToolUse hook により Bash 失敗が .self-improve/errors.jsonl に蓄積される（B-7 Self-Improve Review の基盤）

### Modified Capabilities

- **CLAUDE.md 拡張**: 既存の設計哲学・構成情報に加え、bare repo 検証ルール・セッション起動ルール・編集フローを追記

## Impact

- **新規ファイル**: deps.yaml, .claude-plugin/plugin.json, .gitignore, hooks.json, scripts/hooks/（PostToolUse hooks）
- **変更ファイル**: CLAUDE.md（bare repo ルール追記）
- **依存**: B-1 の architecture/ 成果物（ADR-001〜005、component-mapping）を参照
- **後続への影響**: B-3（chain generate スクリプト）、C-1〜C-3（コンポーネント移植）が deps.yaml skeleton を前提とする
