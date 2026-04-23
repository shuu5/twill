## Why

`plugins/twl/commands/merge-gate.md` が 180 行に達しており、原則 2.5（controller は 120 行以下推奨）に違反している。コントローラーが実装詳細（インライン bash スクリプト）を直接保持しているため、責務の分離が不完全な状態にある。

## What Changes

- `merge-gate.md` 内の 6 つのインライン bash スクリプトブロックを専用スクリプトファイルへ抽出する
  - PR 存在確認 → `scripts/merge-gate-check-pr.sh`
  - 動的レビュアー構築 → `scripts/merge-gate-build-manifest.sh`
  - spawn 完了確認 → `scripts/merge-gate-check-spawn.sh`
  - Cross-PR AC 検証 → `scripts/merge-gate-cross-pr-ac.sh`
  - checkpoint 統合 → `scripts/merge-gate-checkpoint-merge.sh`
  - phase-review 必須チェック → `scripts/merge-gate-check-phase-review.sh`
- `merge-gate.md` 内のインライン bash を `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh"` の参照に置き換える
- `merge-gate.md` を 120 行以下に削減する

## Capabilities

### New Capabilities

- 6 つの新規スクリプトファイルにより、各処理ロジックが単体テスト可能になる

### Modified Capabilities

- `merge-gate.md`（controller）は component 指示のみを保持し、実装詳細はスクリプトへ委譲する

## Impact

- `plugins/twl/commands/merge-gate.md`（変更）
- `plugins/twl/scripts/merge-gate-*.sh`（新規 6 ファイル）
- 既存の動作は変わらない（リファクタリングのみ）
