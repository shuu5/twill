## Why

`skills/co-issue/SKILL.md` でユーザー入力由来の Issue body を specialist agent に XML タグで渡しているが、
悪意ある XML を含む Issue body によって specialist の指示境界が操作されるプロンプトインジェクションリスクが存在する。

## What Changes

- `agents/worker-codex-reviewer.md` に入力サニタイズ処理（XML タグエスケープ）を追加
- `skills/co-issue/SKILL.md` のコンテキスト境界分離の注記を全 specialist に拡張
- 必要に応じて他の specialist（issue-critic, issue-feasibility）にも同様の対策を適用

## Capabilities

### New Capabilities

- worker-codex-reviewer が `<review_target>` ブロック内の XML インジェクションを無力化して処理できる

### Modified Capabilities

- worker-codex-reviewer の入力処理: エスケープ済みデータとして Issue body を解釈
- co-issue の specialist 呼び出し: セキュリティノートの範囲を全 specialist に明示

## Impact

- `agents/worker-codex-reviewer.md`
- `skills/co-issue/SKILL.md`
- 潜在的に `agents/worker-issue-critic.md`, `agents/worker-issue-feasibility.md`（スコープ次第）
