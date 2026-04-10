## Context

`chain-steps.sh` は `chain-runner.sh` が参照する dispatch_mode の SSOT。`deps.yaml` も同じ情報を持つが、両者が乖離するとバリデーションが Critical エラーを報告する。`post-change-apply` は `workflow-test-ready` 内で state 書き込みのみ行う runner パターンのステップであり、LLM dispatch は不要。

## Goals / Non-Goals

**Goals:**
- `chain-steps.sh` と `deps.yaml` の dispatch_mode を `runner` に統一する
- `twl check` の Critical エラーを解消する

**Non-Goals:**
- `post-change-apply` の実際の動作変更
- 他ステップの dispatch_mode 見直し

## Decisions

- **`chain-steps.sh` を修正する**: `deps.yaml` の `runner` が正しい。`workflow-test-ready` での実際の動作（`python3 -m twl.autopilot.state write` で直接 state 書き込み、LLM dispatch なし）と一致する。
- **`chain-runner.sh` コメントも更新**: 誤解を招く "LLM スキル実行" コメントを削除し、実態を反映する。

## Risks / Trade-offs

- リスクなし。dispatch_mode の変更は既存の実際の動作を変えない（`post-change-apply` は元々 runner パターンで動いている）。
