## Context

`twl chain generate` コマンドは `get_plugin_root()` で CWD から `deps.yaml` を探索して plugin_root を決定し、`meta_generate.py` を呼び出す。しかし editable install 環境では、feature branch で `meta_generate.py` を変更しても `twl` CLI は main ブランチのインストール済みコードを参照する。`--write` 実行時に stale なコードでコンテンツが生成され、SKILL.md に誤ったセクションが追記される。

## Goals / Non-Goals

**Goals:**
- `twl chain generate` に `--plugin-root <path>` オプションを追加し、任意の plugin_root を指定可能にする
- `chain-runner.sh` の `twl chain generate --write` 呼び出し時に PYTHONPATH を注入し、feature branch のコードを優先させる

**Non-Goals:**
- `get_plugin_root()` 関数自体の変更（他コマンドへの影響を避ける）
- Python パッケージ管理方法の変更（editable install 廃止など）

## Decisions

### 1. `--plugin-root` オプション追加（generate.py）

`handle_chain_subcommand` 内で `--plugin-root` 引数を追加し、指定時は `get_plugin_root()` の代わりに `Path(args.plugin_root)` を使う。

**理由**: 最小変更で feature branch の plugin_root を明示的に指定できる。既存動作は変わらない。

### 2. `chain-runner.sh` で PYTHONPATH を注入

`twl chain generate --write` 呼び出しを `PYTHONPATH=<worktree-plugin-dir>:$PYTHONPATH twl chain generate --write` に変更する。

**理由**: Python がモジュールを解決する際に PYTHONPATH が優先されるため、インストール済みパッケージより feature branch のコードが先に読み込まれる。`--plugin-root` と組み合わせることで確実に feature branch の `meta_generate.py` が使われる。

### 3. `--plugin-root` の動的インポート不要

`meta_generate.py` は `plugin_root` を引数として受け取る関数 `meta_chain_generate(deps, name, plugin_root)` で設計されており、plugin_root の変更だけで feature branch のディレクトリを対象にできる。PYTHONPATH によりインポート自体も feature branch の実装を使う。

## Risks / Trade-offs

- **PYTHONPATH 注入の副作用**: chain-runner.sh から呼び出される `twl` の全モジュールが feature branch のコードを参照する。意図した動作だが、テスト時は注意が必要
- **`--plugin-root` 検証**: 指定パスに `deps.yaml` が存在しない場合のエラーハンドリングが必要（`get_plugin_root()` では CWD 探索でカバーされていた部分）
