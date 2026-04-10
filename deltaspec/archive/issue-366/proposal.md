## Why

Wave 完了時に co-autopilot の実行結果（各 Issue の成功/失敗/介入回数）を収集・集約する仕組みがなく、Wave の品質評価や改善分析ができない。

## What Changes

- `plugins/twl/commands/wave-collect.md`（新規）: Wave 完了後に session.json を読み込んで結果を集約し `.supervisor/wave-{N}-summary.md` として出力する atomic コマンドを作成
- `plugins/twl/deps.yaml`: `wave-collect` エントリ（type: atomic）を追加

## Capabilities

### New Capabilities

- `wave-collect` コマンドが Wave 番号を引数に受け取り、対応する co-autopilot セッションの session.json を読み込んで各 Issue の成功/失敗/介入回数を集約する
- Wave サマリを `.supervisor/wave-{N}-summary.md` 形式（SupervisorSession スキーマ準拠）で出力する
- 介入パターンの統計（介入率・頻出パターン等）を計算して Wave サマリに含める

### Modified Capabilities

- なし

## Impact

- `plugins/twl/commands/wave-collect.md`（新規ファイル追加）
- `plugins/twl/deps.yaml`（`wave-collect` エントリ追加、type: atomic）
- `architecture/domain/contexts/supervision.md`（SupervisorSession スキーマ参照）
