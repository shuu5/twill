## Why

autopilot orchestrator の `check_and_nudge()` が chain 遷移停止を検知した際に空 Enter を送信しているため、停止した Worker が「次に何をすべきか」を判断できず復旧しない。具体例: ap-#130 が "setup chain 完了" で停止し手動 nudge が必要だった。

## What Changes

- `scripts/autopilot-orchestrator.sh`: `CHAIN_STOP_PATTERNS` を停止パターン→次コマンドのマッピング（連想配列）に変更し、`check_and_nudge()` が適切なコマンドを送信するよう修正

## Capabilities

### Modified Capabilities

- **orchestrator nudge コマンド送信**: `check_and_nudge()` が各 CHAIN_STOP_PATTERNS に対応する次の Skill tool コマンドを送信する。パターンに次コマンドが定義されていない場合（chain 内遷移・chain 終端）は従来通り空 Enter を送信する

## Impact

- **影響ファイル**: `scripts/autopilot-orchestrator.sh`
- **新規ファイル**: なし
- **後方互換性**: 次コマンドが空のパターンは従来通り空 Enter を送信するため、既存動作に変化なし
- **依存関係**: Issue 番号は `check_and_nudge()` の既存引数 `$issue` から取得するため、外部 API 変更なし
