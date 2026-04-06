## Why

Worker（Sonnet 200k）が 22 ステップの chain を 1 セッションで実行する際、compaction 後にワークフロー進行位置を復元できず、chain が最初から再実行されるか中断する問題がある。Worker モデルを Opus→Sonnet に変更したことで compaction が確実に発生するようになった。

## What Changes

- `chain-runner.sh`: 各ステップ実行前に `state-write.sh --set "current_step=<step>"` を呼び出し進行位置を記録
- `state-write.sh`: Worker ロールでの `current_step` 書き込みを許可（ホワイトリスト追加）
- `scripts/hooks/pre-compact-checkpoint.sh`: 新規作成（PreCompact hook - compaction 前に chain 進行位置を保存）
- `hooks/hooks.json`: PreCompact hook を登録
- `compactPrompt` 設定: compaction サマリに chain 進行位置・issue 番号・重要ファイルパスの保持を指示
- `scripts/compaction-resume.sh`: 新規作成（復帰判定ロジック - 完了済みステップの自動スキップ）
- `workflow-setup/SKILL.md`, `workflow-test-ready/SKILL.md`, `workflow-pr-cycle/SKILL.md`: compaction 復帰プロトコル追記

## Capabilities

### New Capabilities

- **PreCompact チェックポイント**: compaction 直前に chain 進行位置（current_step）を issue-{N}.json に保存する hook
- **compaction 復帰判定**: `compaction-resume.sh` が `current_step` を読み取り、完了済みステップをスキップして正しいステップから再開できる
- **compactPrompt 設定**: LLM が compaction 後も chain コンテキスト（issue 番号・現在ステップ・重要ファイル）を保持できるようにサマリ指示を設定

### Modified Capabilities

- **chain-runner.sh の進行位置記録**: 既存の chain 実行に `current_step` 記録を追加（冪等性保証）
- **state-write.sh のロール制限**: Worker ロールが `current_step` を書き込めるよう許可リストを更新
- **workflow SKILL.md の復帰プロトコル**: 各 workflow の chain 実行指示に compaction 後の再開手順を追記

## Impact

- **影響ファイル**: `scripts/chain-runner.sh`, `scripts/state-write.sh`, `hooks/hooks.json`, `settings.json`（compactPrompt）, 3つの workflow SKILL.md
- **新規ファイル**: `scripts/hooks/pre-compact-checkpoint.sh`, `scripts/compaction-resume.sh`
- **後方互換性**: current_step は既に issue-{N}.json スキーマに定義済みだが未使用のため、既存の動作に影響しない
- **依存関係**: PostCompact hook（既存）との協調動作が必要
