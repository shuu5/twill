## Why

Autopilot Worker の chain 遷移ポイント（setup → test-ready → pr-cycle）でプロンプトへの停止が再発する。SKILL.md の「停止するな」指示が LLM の attention に依存しており、compaction やコンテキスト長の影響で無視されるため、機械的な継続保証がない。

## What Changes

- `scripts/hooks/post-skill-chain-nudge.sh` を新規作成（PostToolUse hook スクリプト）
- `~/.claude/settings.json` の `PostToolUse` 配列に hook エントリを追加（`matcher: "Skill"`）
- `scripts/autopilot-orchestrator.sh` の `check_and_nudge()` に `last_hook_nudge_at` 参照を追加（二重 nudge 防止）
- `deps.yaml` に新規 script コンポーネント `post-skill-chain-nudge` を追加

## Capabilities

### New Capabilities

- **PostToolUse hook による chain 継続注入**: Skill tool 完了後に自動発火し、autopilot 配下の Worker に対して次ステップコマンドを stdout に注入する。compaction 後も LLM コンテキストに直接差し込まれるため、attention 依存を排除する。
- **非 autopilot 時の完全透過**: `AUTOPILOT_DIR` 環境変数が未設定の場合、hook は何も出力せずに終了する（通常利用への影響ゼロ）。
- **`last_hook_nudge_at` タイムスタンプ記録**: hook が注入するたびに `issue-{N}.json` に記録し、orchestrator との競合を防止する。

### Modified Capabilities

- **orchestrator の二重 nudge 防止**: `check_and_nudge()` が `last_hook_nudge_at` を確認し、直近 `NUDGE_TIMEOUT`（30s）以内に hook 注入があれば tmux nudge をスキップする。

## Impact

- **影響コンポーネント**: `scripts/autopilot-orchestrator.sh`、`~/.claude/settings.json`
- **新規ファイル**: `scripts/hooks/post-skill-chain-nudge.sh`
- **deps.yaml**: `post-skill-chain-nudge` script エントリ追加
- **依存関係**: `chain-runner.sh next-step`（既存、副作用なし）、`state-read.sh` / `state-write.sh`（既存）
- **Layer 2（#185）との分離**: orchestrator の health-check 統合は本 Issue のスコープ外。本 Issue は Layer 1（予防的 hook）と orchestrator の `last_hook_nudge_at` 参照のみ。
