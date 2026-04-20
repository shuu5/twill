## Why

merge-gate が `phase-review` checkpoint（specialist review 結果）を検査せず、specialist review が完全にスキップされても PASS してしまう。defense-in-depth として phase-review checkpoint の必須チェックを追加し、review なしマージを防止する。

## What Changes

- `mergegate.py` に `phase-review.json` 存在チェックを追加
- `phase-review.json` が不在の場合に REJECT を返すロジックを実装
- `scope/direct` / `quick` ラベル付き Issue はチェックをスキップ
- `phase-review.json` の CRITICAL findings (confidence >= 80) を merge-gate 判定に統合
- `--force` 使用時でも phase-review 不在は WARNING としてログ記録
- `merge-gate.md` コマンドドキュメントに phase-review チェックの説明を追記

## Capabilities

### New Capabilities

- merge-gate が `phase-review.json` checkpoint の存在を検査する
- `phase-review.json` 不在時に REJECT を返す（silent fail 防止）
- phase-review の CRITICAL findings を merge-gate 判定に統合する
- `--force` 実行時も phase-review スキップを WARNING としてログ記録する

### Modified Capabilities

- merge-gate の判定ロジックに `_check_phase_review_guard()` を追加
- `scope/direct` / `quick` ラベル付き Issue では phase-review チェックをスキップ

## Impact

- `cli/twl/src/twl/autopilot/mergegate.py`: `_check_phase_review_guard()` 追加、既存 guard chain に統合
- `plugins/twl/commands/merge-gate.md`: phase-review チェックの説明追記
- `.autopilot/checkpoints/phase-review.json`: 読み込み対象として追加
