## Why

`workflow-test-ready` は quick Issue では呼ばれるべきでないが、LLM の不確定性によって誤って呼び出された場合にすべてのステップが実行されてしまう。defense in depth として、`workflow-test-ready` 自身が quick Issue を検出して即座にスキップする防御的ガードが必要。

## What Changes

- `workflow-test-ready/SKILL.md` の冒頭（Step 1 の前）に quick ガードセクションを追加
- `scripts/chain-runner.sh` に `quick-guard` コマンドを追加
  - ブランチから Issue 番号を抽出
  - `state-read.sh --field is_quick` で判定（優先）
  - fallback: `detect_quick_label()` を呼出して gh API で直接判定
  - quick なら exit 1、そうでなければ exit 0
- `deps.yaml` の更新（chain-runner.sh の依存関係反映）

## Capabilities

### New Capabilities

- `chain-runner.sh quick-guard`: ブランチの Issue が quick かどうかを判定するコマンド
- `workflow-test-ready` の quick Issue 自衛: quick Issue で呼ばれた場合、全ステップをスキップしてメッセージを出力して終了

### Modified Capabilities

- `workflow-test-ready/SKILL.md`: 冒頭に quick ガード実行セクションを追加

## Impact

- **変更ファイル**: `skills/workflow-test-ready/SKILL.md`, `scripts/chain-runner.sh`, `deps.yaml`
- **影響範囲**: workflow-test-ready の起動フロー（非 quick Issue への影響なし）
- **依存**: `state-read.sh`（既存）、`detect_quick_label()`（chain-runner.sh 内に実装済みまたは追加）
