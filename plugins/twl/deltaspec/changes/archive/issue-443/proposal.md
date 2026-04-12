## Why

`observation-pattern-catalog.md` は Bug #436（deltaspec archive 失敗）、#438（chain 遷移停止）、#439（phase-review スキップ）の failure mode に対応する regex パターンを持っていない。`workflow-observe-loop` の `problem-detect` ステップでこれらを rule-based に検知するため、専用パターンの追加が必要。

## What Changes

- `plugins/twl/refs/observation-pattern-catalog.md` に `## bug-reproduction patterns` セクションを追加し、以下の 3 パターンを追加:
  - `bug-deltaspec-archive`（deltaspec archive 失敗メッセージの regex）
  - `bug-chain-stall`（chain 遷移停止 / polling timeout の regex）
  - `bug-phase-review-skip`（phase-review スキップ / phase-review.json 不在の regex）
- `tests/bats/refs/observation-references.bats` を更新し、`bug-` プレフィックスの追加に対応

## Capabilities

### New Capabilities

- `bug-deltaspec-archive` パターン: deltaspec archive 失敗を rule-based で自動検出（category: `deltaspec-archive-failure`, related_issue: "436"）
- `bug-chain-stall` パターン: chain 遷移停止 / polling timeout を自動検出（category: `chain-transition-stall`, related_issue: "438"）
- `bug-phase-review-skip` パターン: phase-review スキップ / phase-review.json 不在を自動検出（category: `phase-review-skip`, related_issue: "439"）

### Modified Capabilities

- `workflow-observe-loop` の `problem-detect` ステップが上記 3 パターンを検知対象に含める（カタログ参照で自動反映）

## Impact

- `plugins/twl/refs/observation-pattern-catalog.md` — 既存 YAML フォーマットに新セクションを追加
- `tests/bats/refs/observation-references.bats` — `bug-` プレフィックスの prefix 別カウント検証に対応するテスト更新
