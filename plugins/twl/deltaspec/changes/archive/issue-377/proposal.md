## Why

`post-change-apply` の dispatch_mode が `chain-steps.sh` では `llm` と定義されているが、`deps.yaml` では `runner` と定義されており不整合が生じている。`twl check` が Critical エラーとして報告し続けるため修正が必要。実際の動作（workflow-test-ready での state 書き込み）は runner パターンに一致するため、`chain-steps.sh` 側が誤り。

## What Changes

- `plugins/twl/scripts/chain-steps.sh` の `CHAIN_STEP_DISPATCH` 配列で `post-change-apply` を `llm` → `runner` に修正
- `plugins/twl/scripts/chain-runner.sh` の `post-change-apply` ケースのコメントを実態に合わせて更新

## Capabilities

### Modified Capabilities

- **chain-steps.sh CHAIN_STEP_DISPATCH**: `post-change-apply` の dispatch_mode を `runner` に統一
- **chain-runner.sh post-change-apply case**: コメントを「chain-runner がステップ記録を実行（runner ステップ）」に修正

## Impact

- 影響ファイル: `chain-steps.sh`（1行）、`chain-runner.sh`（1行コメント）
- `twl check` / `twl --validate` の Critical エラーが解消される
- 依存: なし
