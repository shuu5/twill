## Why

co-autopilot が test-target worktree で spawn された際、Worker bash プロセスに `AUTOPILOT_DIR` 環境変数が継承されず、main worktree の `.autopilot/` を汚染する経路が存在する。Pilot→Worker spawn 時の env 伝搬を明示・保証することで、#470 (state file パス誤認) の構造的再発を防ぐ。

## What Changes

- `plugins/twl/scripts/autopilot-launch.sh` の Worker spawn 経路で `AUTOPILOT_DIR` を明示的に渡す
- `plugins/twl/skills/co-autopilot/SKILL.md` に「state file 解決ルール」セクションを追加し、`AUTOPILOT_DIR` SSOT と `autopilot-init.sh` L9 実装への参照を明文化
- `plugins/twl/tests/bats/` に Pilot→Worker env 継承テストを追加

## Capabilities

### New Capabilities

- `AUTOPILOT_DIR=/tmp/foo` を設定した状態で co-autopilot を起動すると `/tmp/foo/issues/{N}.json` に書き込まれる（カスタムディレクトリ隔離）
- Pilot→Worker spawn 後に Worker プロセスの env で `AUTOPILOT_DIR` が継承されていることをテストで検証可能

### Modified Capabilities

- env 未設定時は従来通り `$PROJECT_ROOT/.autopilot/` を使用（既存動作維持）
- co-autopilot SKILL.md が state file 解決ルールを明記し、ドキュメントと実装の乖離を解消

## Impact

- `plugins/twl/scripts/autopilot-launch.sh` — env 伝搬の確認・修正
- `plugins/twl/skills/co-autopilot/SKILL.md` — ドキュメント追加
- `plugins/twl/tests/bats/` — 新規テスト追加
- `autopilot-init.sh` の既存実装（L9-12）は変更なし（参照のみ）
