## Why

autopilot の Worker 監視は現在 10 秒間隔の sleep ポーリング + tmux list-panes による crash 検知に依存しており、Worker の状態変化（error/exited）を検知するまでに最大 10 秒の遅延が発生する。ubuntu-note-system の Session Interop 基盤（session-state.sh）を活用することで、5 状態（idle/input-waiting/processing/error/exited）の細粒度検出が可能になる。

## What Changes

- `scripts/crash-detect.sh`: tmux list-panes のみの検知から `session-state.sh state <window>` による 5 状態検出に置換
- `commands/autopilot-poll.md`: sleep 10 ループから `session-state.sh wait <window> <target-state>` の活用へ変更
- `tests/bats/scripts/crash-detect.bats`: 既存 8 テストケースを新インターフェースに更新
- `deps.yaml`: autopilot-poll の calls セクションに session-state 外部依存を明示
- `skills/co-autopilot/SKILL.md`: crash-detect.sh 参照記述の更新

## Capabilities

### New Capabilities

- 5 状態検出: crash-detect.sh が idle/input-waiting/processing/error/exited を区別可能に
- error 状態検知: Worker が error 状態（APIError 等）の場合を crash とは別に検知
- フォールバック: session-state.sh 非存在時に既存の tmux list-panes ベース検知に自動復帰

### Modified Capabilities

- crash-detect.sh: exit code 体系の拡張（exited=2 に加え error 状態の扱い）
- autopilot-poll: ポーリング間隔の改善（session-state.sh wait による効率化）

## Impact

- **scripts/crash-detect.sh**: ロジック全面書き換え（外部依存 session-state.sh 追加）
- **commands/autopilot-poll.md**: ポーリングループの書き換え
- **tests/bats/scripts/crash-detect.bats**: 8 テストケースの更新 + 新状態テスト追加
- **deps.yaml**: autopilot-poll の calls に session-state.sh 参照追加
- **skills/co-autopilot/SKILL.md**: crash-detect 関連記述の更新
- **外部依存**: `~/ubuntu-note-system/scripts/session-state.sh`（ubuntu-note-system リポジトリ）
