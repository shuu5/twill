## Why

`workflow-test-ready` Step 4 の post-opsx-apply IS_AUTOPILOT 判定が、`opsx-apply` 実行中のコンテキスト compaction で消失し、autopilot セッションで `pr-cycle` への自動遷移が失敗する。

## What Changes

- `workflow-test-ready` SKILL.md の compaction 復帰プロトコルに `post-opsx-apply` を独立ステップとして追加する
- compaction-resume.sh に `post-opsx-apply` ステップのサポートを追加する（またはステップ定義の拡張）
- opsx-apply の完了後に IS_AUTOPILOT 判定を再実行するためのガード節を追加する

## Capabilities

### New Capabilities

- compaction 後に `workflow-test-ready` を再起動した際、`post-opsx-apply` フェーズを検出し IS_AUTOPILOT 判定を自動再実行できる

### Modified Capabilities

- `workflow-test-ready` Step 4: compaction 復帰プロトコルが `post-opsx-apply` フェーズを含む形に拡張される
- `compaction-resume.sh`（または state-read の定義）: `post-opsx-apply` ステップを認識できるよう拡張される

## Impact

- 変更ファイル: `skills/workflow-test-ready/SKILL.md`（compaction 復帰プロトコルのステップ追加）
- 変更ファイル: `scripts/compaction-resume.sh`（`post-opsx-apply` ステップの追加）
- 影響スコープ: autopilot セッションの `opsx-apply` → `pr-cycle` 遷移フローのみ
- `skillmd-chain-transition`（#134）の設計原則（遷移責務は SKILL.md 側）は維持される
