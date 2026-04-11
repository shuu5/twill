## ADDED Requirements

### Requirement: chain generate --plugin-root オプション

`twl chain generate` コマンドは `--plugin-root <path>` オプションを受け付けなければならない（SHALL）。指定された場合、`get_plugin_root()` による CWD 探索の代わりに指定パスを plugin_root として使用しなければならない（SHALL）。

#### Scenario: --plugin-root 指定時の plugin_root 優先
- **WHEN** `twl chain generate <chain-name> --plugin-root /path/to/plugin --write` が実行される
- **THEN** `/path/to/plugin/deps.yaml` を読み込み、同パス配下の `meta_generate.py` を使用してテンプレートが生成される

#### Scenario: --plugin-root 未指定時の従来動作
- **WHEN** `twl chain generate <chain-name> --write` が `--plugin-root` なしで実行される
- **THEN** 従来通り `get_plugin_root()` により CWD から `deps.yaml` を探索して plugin_root を決定する

#### Scenario: --plugin-root に無効なパスを指定
- **WHEN** `twl chain generate <chain-name> --plugin-root /nonexistent/path` が実行される
- **THEN** エラーメッセージを出力して非ゼロ終了コードで終了する

## MODIFIED Requirements

### Requirement: chain-runner.sh の generate 呼び出しに PYTHONPATH 注入

`chain-runner.sh` 内で `twl chain generate --write` を呼び出す際は、feature branch の Python ソースディレクトリを PYTHONPATH の先頭に追加しなければならない（SHALL）。これにより、インストール済みパッケージより feature branch の `meta_generate.py` が優先されなければならない（MUST）。

#### Scenario: feature branch で meta_generate.py 変更後に --write 実行
- **WHEN** feature branch で `meta_generate.py` を変更し、`chain-runner.sh` 経由で `twl chain generate --write` が実行される
- **THEN** feature branch の変更後 `meta_generate.py` が使用され、正しいコンテンツが SKILL.md に書き込まれる

#### Scenario: main ブランチでの通常動作
- **WHEN** main ブランチで PYTHONPATH が注入された状態で `twl chain generate --write` が実行される
- **THEN** main ブランチのコードが使用され、従来と同じ動作をする
