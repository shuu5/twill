## Why

`autopilot-orchestrator.sh` の `check_and_nudge` 経路は `_nudge_command_for_pattern` が返す `next_cmd` を allow-list 検証なしで `tmux send-keys` に直接渡す。同スクリプトの `inject_next_workflow` は L777 で `^/twl:workflow-[a-z][a-z0-9-]*$` バリデーションを実装済みであるため、`check_and_nudge` との非対称が defense-in-depth の欠落になっている。

## What Changes

- `plugins/twl/scripts/autopilot-orchestrator.sh`: `check_and_nudge` に `inject_next_workflow` と同等の allow-list 検証を追加（`next_cmd` を `tmux send-keys` に渡す直前）
- バリデーション失敗時に WARNING ログと trace ログを出力し、nudge をスキップ
- `architecture/` に ADR を新規作成: tmux pane trust model と nudge inject 経路の脅威モデルを明文化
- `test-fixtures/` に shunit2 テストを追加: 既存 7 パターン全てが allow-list を通過すること、および不正パターンがブロックされることを検証

## Capabilities

### New Capabilities

なし（セキュリティ強化のみ）

### Modified Capabilities

- `check_and_nudge`: `next_cmd` を `tmux send-keys` に渡す前に allow-list 正規表現でバリデーション。不一致なら WARNING ログを出して nudge をスキップ
- ADR 追加: tmux pane trust model（信頼境界、信頼する入力源 vs 信頼しない入力源、最終防衛線の明文化）

## Impact

- **影響ファイル**: `plugins/twl/scripts/autopilot-orchestrator.sh`
- **新規ファイル**: `architecture/adr/` 配下に ADR を 1 件追加
- **テスト追加**: `test-fixtures/` 配下に shunit2 テストケース追加
- **スコープ外**: `_nudge_command_for_pattern` のロジック変更はしない。`inject_next_workflow` のコードは変更しない
