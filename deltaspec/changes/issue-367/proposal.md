## Why

su-observer の SupervisorSession 状態を外部ファイルに書き出す仕組みがなく、wave終了時やコンパクション時の状態保全・引き継ぎが困難。atomic な externalize-state コマンドを作成することで、状態の永続化を明示的に制御可能にする。

## What Changes

- `plugins/twl/commands/externalize-state.md`（新規）: externalize-state atomic コマンド定義
- `plugins/twl/deps.yaml`: externalize-state エントリ追加

## Capabilities

### New Capabilities

- `externalize-state`: SupervisorSession の現在状態を externalization-schema に従って外部ファイルへ書き出す atomic コマンド
  - 書き出し先: `.supervisor/working-memory.md` または `.supervisor/wave-{N}-summary.md`
  - ExternalizationRecord を `session.json` に追記

### Modified Capabilities

なし（新規追加のみ）

## Impact

- `plugins/twl/commands/externalize-state.md`（新規作成）
- `plugins/twl/deps.yaml`（externalize-state エントリ追加）
- 依存: `plugins/twl/refs/externalization-schema.md`（#363 で作成予定）
- su-compact コマンドが orchestrate し externalize-state を呼び出す関係
