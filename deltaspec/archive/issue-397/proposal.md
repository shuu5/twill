## Why

autopilot ワークフローで「実装済み Issue の DeltaSpec 後付け追加」ケースを扱う際、AC 達成証跡が PR diff から直接読み取れないため、merge-gate が実装完了を正しく検証できない。また Issue close の根拠（どの PR で実装されたか）が追跡不可能になる。

## What Changes

- `plugins/twl/skills/workflow-setup/SKILL.md`
  - 「実装済み Issue の DeltaSpec 後付け追加」パターンを明示的に定義（`retroactive_deltaspec` モード）
  - `arch-ref` タグ経由で参照 PR を記録する仕組みを追加
- `plugins/twl/skills/workflow-pr-verify/SKILL.md`
  - AC 検証時に「実装 PR が origin/main にマージ済み」ケースを許容するロジックを追加
  - `closes_via_pr` フィールドで実装 PR 番号を参照可能にする
- `.autopilot/issues/issue-<N>.json` スキーマ拡張
  - `implementation_pr` フィールドを追加（実装済み外部 PR 番号を保持）
  - `deltaspec_mode: retroactive` フィールドを追加

## Capabilities

### New Capabilities

- **Retroactive DeltaSpec モード**: 実装済み Issue に対して DeltaSpec を後付けで追加する際、`implementation_pr` を記録することで AC 達成証跡の追跡を可能にする
- **Cross-PR AC 追跡**: AC の実装が別 PR にある場合でも、`implementation_pr` → merged commit → AC 達成という証跡チェーンを形成できる

### Modified Capabilities

- `workflow-setup`: retroactive DeltaSpec の検出と `implementation_pr` の自動記録
- `merge-gate`: `implementation_pr` が存在する場合に cross-PR AC 検証モードで動作

## Impact

- `plugins/twl/skills/workflow-setup/SKILL.md`
- `plugins/twl/skills/workflow-pr-verify/SKILL.md`
- `.autopilot/issues/issue-<N>.json` スキーマ（autopilot state の拡張）
- `plugins/twl/scripts/chain-runner.sh`（retroactive モード分岐の追加）
