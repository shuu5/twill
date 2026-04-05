## Context

Worker（Sonnet 200k）は workflow-setup(7) → workflow-test-ready(4) → workflow-pr-cycle(11) = 計 22 ステップの chain を 1 セッションで実行する。Sonnet の context window は 200k tokens、compaction 閾値は約 167k tokens で、22 ステップ実行中に compaction が確実に発生する。

現状の PostCompact hook は `last_compact_at` タイムスタンプを記録するのみで、復帰ロジックが存在しない。`issue-{N}.json` には `current_step` フィールドが定義済みだが未使用のため、compaction 後に Worker は進行位置を把握できない。

## Goals / Non-Goals

**Goals:**
- chain-runner.sh の各ステップ実行前に `current_step` を issue-{N}.json に自動記録する
- PreCompact hook を実装し、compaction 前に進行位置を確実に保存する
- `compaction-resume.sh` で完了済みステップのスキップ判定ロジックを提供する
- compactPrompt を設定し、LLM が compaction 後もコンテキストを保持できるようにする
- 各 workflow SKILL.md に compaction 復帰プロトコルを追記する

**Non-Goals:**
- Sonnet[1m] 対応（プラン依存、別途検討）
- Pilot 側の context 最適化
- orchestrator.sh の変更
- compaction の発生自体を防止すること

## Decisions

### D1: PreCompact hook は observability-only
Claude Code の PreCompact hook は compaction をブロックできない（PostCompact と同じ制約）。hook はチェックポイント保存のみ行い、compaction 自体を制御しない。

### D2: current_step の冪等記録
`chain-runner.sh` は各ステップの**実行前**に `current_step` を書き込む。同じステップが複数回実行されても安全（冪等性保証）。ステップ完了後ではなく実行前に記録することで、失敗時も「失敗したステップから再開」できる。

### D3: compaction-resume.sh は判定のみ（実行はしない）
`compaction-resume.sh <ISSUE_NUM> <step_id>` を呼び出すと、指定ステップが完了済みかどうか（0=要実行 / 1=スキップ可）を返す。実際のスキップ制御は chain-runner.sh 側で行う。

### D4: compactPrompt は hooks.json 経由で設定
Claude Code の compactPrompt 設定は `settings.json` の `compactPrompt` フィールドで管理。chain コンテキスト（issue 番号・current_step・重要ファイルパス）を保持するよう指示する。

### D5: state-write.sh のホワイトリスト拡張
現在 state-write.sh は Worker ロールでの書き込みを一部フィールドに制限している。`current_step` をホワイトリストに追加する。

## Risks / Trade-offs

- **hook タイミング**: PreCompact hook が発火しても compaction が即座に起こるわけではなく、hook 完了後に compaction が走る。hook 内でのファイル書き込みは十分速い（bash）ため実用上問題ない。
- **SKIP_STEP 依存**: compaction-resume.sh による自動スキップは chain-runner.sh が `current_step` を正確に読めることが前提。issue-{N}.json の書き込み競合リスクは低い（単一 Worker セッション内）。
- **SKILL.md 追記の複雑化**: 3 つの workflow SKILL.md に復帰プロトコルを追記すると SKILL.md が長くなる。Section を明確に分けてオーバーヘッドを最小化する。
