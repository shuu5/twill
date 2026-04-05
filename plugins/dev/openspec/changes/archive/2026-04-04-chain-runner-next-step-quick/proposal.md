## Why

`is_quick` の分岐判断が SKILL.md の自然言語記述に依存しており、コンテキスト圧縮で `is_quick=true` が消失すると不要な workflow-test-ready/pr-cycle が実行される。設計哲学「LLM は判断のために使う。機械的にできることは機械に任せる」に反する構造的欠陥を修正する。

## What Changes

- `chain-runner.sh` に `next-step` コマンドを追加（`current_step` + `is_quick` → 次ステップ名を stdout に返す）
- `step_init` で `is_quick` を `issue-{N}.json` に永続化（`state-write.sh --role worker --set "is_quick=..."` 経由）
- `state-write.sh` / `state-read.sh` の issue-{N}.json スキーマに `is_quick` フィールドを追加
- `chain-steps.sh` に quick スキップ対象ステップの配列 `QUICK_SKIP_STEPS` を追加
- `compaction-resume.sh` で `is_quick` を state から取得しスキップ判定に利用
- `workflow-setup/SKILL.md` の quick 分岐判断記述を `chain-runner.sh next-step` 出力委譲形式に書き換え

## Capabilities

### New Capabilities

- `chain-runner.sh next-step`: 現在の Issue 状態（is_quick + current_step）から次に実行すべきステップ名を機械的に返す
- `is_quick` の state 永続化: ラベル情報を一度だけ読み取り state に保存、以降は state から参照可能

### Modified Capabilities

- `compaction-resume.sh`: is_quick を state-read.sh から取得し、quick スキップ対象ステップを自動除外
- `workflow-setup/SKILL.md`: quick 分岐の LLM 判断を除去し `chain-runner.sh next-step` の出力に従う形式に変更

## Impact

- 影響ファイル: `scripts/chain-runner.sh`, `scripts/chain-steps.sh`, `scripts/state-write.sh`, `scripts/state-read.sh`, `scripts/compaction-resume.sh`, `skills/workflow-setup/SKILL.md`
- 後方互換: is_quick フィールドが存在しない既存 state では false として扱う（デフォルト）
- 依存: state-write.sh / state-read.sh の issue-{N}.json スキーマ変更が前提
