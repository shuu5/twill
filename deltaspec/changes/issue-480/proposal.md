## Why

`co-autopilot` の chain 遷移（Issue 選択 → Worker spawn → PR 作成 → merge）を実際に駆動するには GitHub 上に実際の Issue が必要だが、現状の `test-project-scenario-load` はローカルファイルのみ生成するため、E2E 統合テストが不完全なループになっている。

## What Changes

- `plugins/twl/commands/test-project-scenario-load.md` — `--real-issues` フラグを追加し、シナリオカタログの `issue_templates` を `gh issue create` で専用リポに起票するフローを実装する
- `.test-target/loaded-issues.json` — 起票された Issue 番号と scenario ID のマッピングを記録するファイルを新規生成

## Capabilities

### New Capabilities

- **`--real-issues` モード**: `gh issue create` を使って専用テストリポに実 Issue を起票する。起票結果（Issue 番号）を `.test-target/loaded-issues.json` に保存し、後続の co-autopilot テストで参照可能にする
- **二重起票ガード**: `.test-target/loaded-issues.json` が既に存在する場合の挙動（skip/overwrite/error のいずれか）を定義し、冪等性を確保する

### Modified Capabilities

- **デフォルト動作（`--local-only` または未指定）**: 既存のローカルファイル生成動作を維持する（後退互換）

## Impact

- `plugins/twl/commands/test-project-scenario-load.md` — `--real-issues` 分岐フロー追加（+30 行程度）
- `.test-target/loaded-issues.json` — テスト実行時に生成されるランタイムファイル（新規）
- 専用テストリポ（Issue C で init 済み）への `gh issue create` 呼び出しが発生
