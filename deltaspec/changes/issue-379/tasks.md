## 1. generate.py: --plugin-root オプション追加

- [ ] 1.1 `handle_chain_subcommand` の argparse に `--plugin-root` 引数を追加
- [ ] 1.2 `--plugin-root` 指定時は `get_plugin_root()` の代わりに `Path(args.plugin_root)` を使用するよう変更
- [ ] 1.3 `--plugin-root` 指定パスのバリデーション（`deps.yaml` 存在確認）を追加

## 2. chain-runner.sh: PYTHONPATH 注入

- [ ] 2.1 `twl chain generate --write` 呼び出し箇所を特定
- [ ] 2.2 呼び出しに `PYTHONPATH=<plugin-src-dir>:$PYTHONPATH` を先頭に追加
- [ ] 2.3 `--plugin-root <plugin-root>` オプションも同時に渡す

## 3. テスト・確認

- [ ] 3.1 `twl chain generate --help` で `--plugin-root` が表示されることを確認
- [ ] 3.2 `twl --check` でエラーなし確認
