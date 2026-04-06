## Why

`twl chain generate` は単一 chain の生成・書き込みのみ対応しており、書き込み後のドリフト検出手段と複数 chain の一括処理がない。chain-driven アーキテクチャの信頼性維持には、`sync-docs --check` と同パターンの機械的な乖離検出と一括操作が必要。

## What Changes

- `--check` フラグ追加: 生成結果と現在のファイル内容を正規化済みハッシュで比較し、不一致時に unified diff を表示
- `--all` フラグ追加: deps.yaml 内の全 chain に対して一括操作（stdout / --write / --check）
- `--all` と chain name の同時指定をエラーとして排他制御

## Capabilities

### New Capabilities

- `chain generate <name> --check`: 単一 chain の Template A ドリフト検出（正規化ハッシュ比較 + diff 表示）
- `chain generate --all`: 全 chain の stdout 出力
- `chain generate --all --write`: 全 chain の一括書き込み
- `chain generate --all --check`: 全 chain の一括ドリフト検出（ファイルサマリー + 末尾 diff）

### Modified Capabilities

- `handle_chain_subcommand()`: `--check` / `--all` フラグのパース追加
- exit code の体系化: 0 = 正常/乖離なし, 1 = 乖離あり

## Impact

- 変更対象: `twl-engine.py`（`handle_chain_subcommand`, `chain_generate_write` 周辺）
- テスト追加: `tests/test_chain_generate_check.py`, `tests/test_chain_generate_all.py`（新規）
- 依存: なし（既存の `chain_generate()` ロジックを流用）
- 下流への影響: #32 が Template B の --check 拡張を担当
