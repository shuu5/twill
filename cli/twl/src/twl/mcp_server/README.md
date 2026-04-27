# twl MCP Server (Phase 0 PoC)

## 概要

twl MCP Server は TWiLL プラグイン検証ツール (`twl`) を AI セッションから利用可能にする
FastMCP ベースの MCP (Model Context Protocol) サーバーです。

Phase 0 PoC として Layer 1 系 3 ツール (`twl_validate` / `twl_audit` / `twl_check`) を
stdio プロトコル経由で AI セッションに schema 注入します。

- **Epic**: [#945](https://github.com/shuu5/twill/issues/945) — twl CLI MCP server 化 (Phase 0/1/2)
- **親 Issue**: [#962](https://github.com/shuu5/twill/issues/962) — Phase 0 PoC α

## インストール

```bash
pip install -e '.[mcp]'
```

`pyproject.toml` の `[project.optional-dependencies].mcp` に `fastmcp>=3.0` が定義されています。

`uv` を使う場合:

```bash
uv run --directory cli/twl --extra mcp fastmcp run src/twl/mcp_server/server.py
```

## 起動

pip install 経由でインストール後、`cli/twl/` ディレクトリから実行してください:

```bash
fastmcp run src/twl/mcp_server/server.py
```

stdio プロトコルで起動します。Claude Code / MCP クライアントから接続してください。

## 提供ツール

3 ツールを公開しています。いずれも `plugin_root: str` を必須引数として受け取り、
JSON envelope (`{command, version, plugin, items, summary, exit_code}`) を JSON 文字列として返します。

### `twl_validate(plugin_root: str) -> str`

プラグイン構造を検証します。type rules / body refs / v3 schema / chain consistency を確認します。

### `twl_audit(plugin_root: str) -> str`

TWiLL コンプライアンス 10 セクションの audit を実行します。

### `twl_check(plugin_root: str) -> str`

ファイル存在確認と chain integrity チェックを実行します。

## plugin_root 引数

`plugin_root` はプラグインディレクトリへのパスを指定してください。
ツール内部で `Path(plugin_root).expanduser().resolve()` によって絶対パスに正規化されるため、
`~` 始まりのホームディレクトリ相対パスも使用できます。

```
plugin_root 例:
  ~/projects/local-projects/twill/main/plugins/twl
  ~/projects/local-projects/twill/main/plugins/session
```

1 つの MCP サーバープロセスから複数プラグイン (`plugins/twl` / `plugins/session` など) を
同時に扱えます（multi-plugin 対応設計）。
