## Why

feature branch で `meta_generate.py` を変更しても、インストール済みの `twl` CLI は main ブランチのコード（editable install）を参照するため、`twl chain generate --write` が stale コードで実行され、SKILL.md に誤ったコンテンツが追記・重複する問題がある。

## What Changes

- `twl chain generate` サブコマンドに `--plugin-root <path>` オプションを追加
- `--plugin-root` 指定時は `get_plugin_root()` の代わりに指定パスを plugin_root として使用
- `meta_generate.py` のインポートを指定パスの `meta_generate.py` から動的ロードできるようにする
- `chain-runner.sh` 内の `twl chain generate --write` 呼び出しで、PYTHONPATH または `--plugin-root` を指定する

## Capabilities

### New Capabilities

- **`--plugin-root <path>` オプション**: `twl chain generate` で任意の plugin_root を指定可能にする。これにより feature branch の `meta_generate.py` を使った正確なコンテンツ生成が可能になる

### Modified Capabilities

- **`handle_chain_subcommand`**: `--plugin-root` 引数を受け取り、`get_plugin_root()` 呼び出しを置き換える
- **`chain-runner.sh` の generate 呼び出し**: `PYTHONPATH` を指定して feature branch のコードを優先させる

## Impact

- 影響ファイル: `cli/twl/src/twl/chain/generate.py`（`--plugin-root` 引数追加）
- 影響ファイル: `plugins/twl/scripts/chain-runner.sh`（PYTHONPATH 指定）
- 依存: なし
- 破壊的変更: なし（新規オプション追加のみ）
