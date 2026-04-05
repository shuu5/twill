## Why

autopilot セッションにおいて Worker が `merge-gate.md` の raw コマンドを直接 Bash 実行し、不変条件 C（Worker マージ禁止）に違反している。`merge-gate.md` に raw `gh pr merge` / `state-write --role pilot` が記載されているため、Worker LLM がこれを読んで直接実行するパスが存在し、auto-merge.sh / merge-gate-execute.sh の4層防御が完全にバイパスされる。

## What Changes

- `commands/merge-gate.md`: PASS セクションから raw `gh pr merge` と `state-write --role pilot` を除去し、merge-ready 宣言 + merge-gate-execute.sh 呼び出し案内に置き換え
- `scripts/state-write.sh`: `--role pilot` 指定時に呼び出し元 identity を検証（tmux window 名 + CWD の多層検証）し、Worker からの呼び出しを拒否
- `scripts/merge-gate-execute.sh`: autopilot 判定ロジックを追加（auto-merge.sh と同等の state-read ベース検出）
- `scripts/auto-merge.sh`: Layer 1 の status 判定に `merge-ready` を追加（`running` OR `merge-ready` → IS_AUTOPILOT=true）

## Capabilities

### New Capabilities

- state-write.sh による Worker identity 検証（tmux/CWD 多層チェック）
- merge-gate-execute.sh での autopilot 自動検出

### Modified Capabilities

- merge-gate.md の PASS 時フローが「merge-ready 宣言して停止」に変更
- auto-merge.sh Layer 1 が `merge-ready` 状態でも autopilot を正しく検出

## Impact

- `commands/merge-gate.md`（PASS セクション変更）
- `scripts/state-write.sh`（--role pilot 時の identity 検証追加）
- `scripts/merge-gate-execute.sh`（autopilot 判定追加）
- `scripts/auto-merge.sh`（Layer 1 status 判定拡張）
