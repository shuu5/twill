## Why

autopilot Worker がコンテキスト乱れ（nudge 後の IS_AUTOPILOT 消失）により PR を直接 squash merge し、不変条件C（Worker マージ禁止）を違反する。LLM の判断に依存した分岐ロジックでは防げないため、スクリプトレベルの機械的ガードが必要。

## What Changes

- `scripts/merge-gate-execute.sh`: merge 実行パス先頭に status=running 検出時 `exit 1` ブロックを追加
- `scripts/auto-merge.sh`: IS_AUTOPILOT=false かつ status=running の矛盾を検出した場合、merge-ready を宣言して exit 0（merge 実行しない）
- `tests/bats/scripts/fix-worker-merge-gate-invariant-c.bats`: 新規テストケース追加

## Capabilities

### New Capabilities

- **status=running ブロック（merge-gate-execute.sh）**: merge パス実行時に IssueState.status が running の場合、merge を拒否して exit 1 を返す。不変条件C の機械的保証。
- **矛盾状態フォールバック（auto-merge.sh）**: IS_AUTOPILOT=false かつ status=running の矛盾を検出した場合、merge-ready を宣言して merge を中止する。コンテキスト乱れでも安全側に倒す。

### Modified Capabilities

- **merge-gate-execute.sh Layer 3**: autopilot 検出時のログ出力のみ → status=running 時は exit 1 で merge を拒否、status=merge-ready 時は Pilot フローとして正常続行

## Impact

- `scripts/merge-gate-execute.sh`: merge パス（デフォルト分岐）のみ変更。`--reject` / `--reject-final` パスは影響なし
- `scripts/auto-merge.sh`: IS_AUTOPILOT 判定後に矛盾チェックを追加
- 非 autopilot 環境（status 空）: `state-read.sh` が空を返すため既存フローに影響なし
- Pilot の正常フロー（status=merge-ready で merge-gate-execute.sh 呼び出し）: 正常動作を維持
