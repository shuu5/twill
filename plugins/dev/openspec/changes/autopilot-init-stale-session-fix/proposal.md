## Why

autopilot-init.sh の stale session 検出ロジックに2つのバグがある。完了済みセッション（全 issue done）が 24h 未満だと `--force` が効かずブロックされ、再実行不能になる。また autopilot-init.md が `eval` でスクリプト出力を実行しようとし、人間向けメッセージが eval されて exit 127 になる。

## What Changes

- `scripts/autopilot-init.sh`: 完了済みセッション（全 issue done）を `--force` で即座に削除可能にする。24h 制限は running issue がある場合のみ適用
- `commands/autopilot-init.md`: `eval` を削除し、直接 `bash` 実行に変更

## Capabilities

### New Capabilities

- 完了済みセッション（全 issue done）の即時強制削除: `--force` 指定時、session.json 内の全 issue が done であれば経過時間に関係なく削除可能

### Modified Capabilities

- stale session 判定ロジック: 24h 制限を「running issue がある場合」に限定（完了済みセッションは除外）
- autopilot-init.md の実行方式: `eval` ラッパーから直接 bash 実行に変更

## Impact

- 影響ファイル: `scripts/autopilot-init.sh`, `commands/autopilot-init.md`（2ファイルのみ）
- 依存コンポーネント: `co-autopilot` の Step 3 が autopilot-init.md を呼び出す
- 後方互換性: `--force` なしの動作は変更なし。`--force` ありの場合のみ完了済みセッションの扱いが緩和される
