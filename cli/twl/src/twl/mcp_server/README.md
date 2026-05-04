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

## Restart（再起動）

`tools.py` を編集した後は MCP server を再起動する必要があります。長時間稼働するサーバープロセスは古いコードのままであるため、編集内容が反映されません。

```bash
twl mcp restart
```

このコマンドは以下を行います:
1. 既存の `fastmcp run` プロセスを SIGTERM で停止
2. `.mcp.json` に定義されたコマンドでサーバーを detach 再起動

**重要**: サーバー再起動後、**Claude Code セッション自体も再起動**する必要があります。既存セッションの MCP 接続はリフレッシュされません。

### 再起動が必要なタイミング

- `cli/twl/src/twl/mcp_server/tools.py` を編集したとき
- `cli/twl/src/twl/mcp_server/server.py` を編集したとき
- `twl` パッケージをアップデートしたとき（`pip install -e .` 後）

### 手動再起動

`twl mcp restart` が使えない場合:

```bash
# 1. 既存プロセスを停止
pkill -f 'fastmcp run.*src/twl/mcp_server/server.py'

# 2. サーバーを再起動
uv run --directory cli/twl --extra mcp fastmcp run src/twl/mcp_server/server.py &

# 3. Claude Code セッションを再起動
```

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

## Phase 1: Autopilot State ツール (ADR-0006)

Phase 1 で `twl_state_read` / `twl_state_write` を追加しました。
autopilot の issue/session JSON を MCP ツール経由で読み書きできます。

- **Issue**: [#1018](https://github.com/shuu5/twill/issues/1018) — Phase 1 α
- **ADR**: [ADR-0006](../architecture/decisions/ADR-0006-state-mcp-ssot.md) — Hybrid Path 5 原則

### `twl_state_read(...) -> str`

autopilot state JSON またはフィールド値を返します。

引数:

| 引数 | 型 | 必須 | 説明 |
|------|-----|------|------|
| `type_` | `str` | ✓ | `"issue"` or `"session"` |
| `issue` | `str \| None` | — | Issue 番号 (`type_="issue"` 時必須) |
| `repo` | `str \| None` | — | リポジトリ名（cross-repo 用） |
| `field` | `str \| None` | — | 取得フィールド（省略時: 全 JSON） |
| `autopilot_dir` | `str \| None` | — | `.autopilot` ディレクトリパス（省略時: 環境変数 / git worktree から解決） |

戻り値 envelope:

```json
{"ok": true, "result": "<value_or_json>", "exit_code": 0}
{"ok": false, "error": "<msg>", "error_type": "state_error", "exit_code": 1}
{"ok": false, "error": "<msg>", "error_type": "arg_error", "exit_code": 2}
```

### `twl_state_write(...) -> str`

autopilot state JSON を書き込みます。

引数:

| 引数 | 型 | 必須 | 説明 |
|------|-----|------|------|
| `type_` | `str` | ✓ | `"issue"` or `"session"` |
| `role` | `str` | ✓ | `"worker"` or `"pilot"` (RBAC 制御) |
| `issue` | `str \| None` | — | Issue 番号 |
| `repo` | `str \| None` | — | リポジトリ名 |
| `sets` | `list[str] \| None` | — | `["key=value", ...]` 形式の更新フィールド |
| `init` | `bool` | — | `true` で issue-N.json を新規作成 |
| `autopilot_dir` | `str \| None` | — | `.autopilot` ディレクトリパス |
| `cwd` | `str \| None` | — | 作業ディレクトリ（RBAC enforcement 用） |
| `force_done` | `bool` | — | `true` で `done` への強制遷移を許可 |
| `override_reason` | `str \| None` | — | 強制遷移の理由 |

戻り値 envelope:

```json
{"ok": true, "message": "OK: <path> を更新しました", "exit_code": 0}
{"ok": false, "error": "<msg>", "error_type": "state_error", "exit_code": 1}
{"ok": false, "error": "<msg>", "error_type": "arg_error", "exit_code": 2}
```

### In-process テスト (Hybrid Path 5 原則)

MCP tool wrapper を使わず、handler 関数を直接 pytest で呼び出せます:

```python
from twl.mcp_server.tools import twl_state_read_handler, twl_state_write_handler

result = twl_state_read_handler(type_="issue", issue="1", field="status",
                                autopilot_dir="/path/to/.autopilot")
assert result["ok"] is True
assert result["result"] == "running"
```
