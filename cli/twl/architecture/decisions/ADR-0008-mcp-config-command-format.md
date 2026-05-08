# ADR-0008: MCP Config Command Format

- **Status**: Accepted
- **Date**: 2026-05-08
- **Issue**: #1588

## Context

PR #1412 (#1398) で `_validate_command()` の allowlist validation を導入したが、既存 deployed `.mcp.json`
(#964 PR #972) を migration せずに silent regression が発生した。

`.mcp.json.mcpServers.twl.command` に `<project>/cli/twl/.venv/bin/fastmcp`（絶対パス）が設定されており、
`lifecycle.py:_validate_command()` の allowed_prefixes (`/usr/bin`, `/usr/local/bin`, `~/.local/bin`) 外として
`ValueError` で reject される。結果として `restart_mcp_server()` が SIGTERM で既存 server を停止後に起動失敗し、
session ↔ MCP disconnect が永続化する問題が生じた（詳細: #1588）。

## Decision

`.mcp.json.mcpServers.twl.command` の標準形式を以下に定める:

```json
{
  "type": "stdio",
  "command": "uv",
  "args": [
    "run",
    "--directory", "<cli/twl 絶対 path>",
    "--extra", "mcp",
    "fastmcp", "run",
    "<server.py 絶対 path>"
  ],
  "env": {}
}
```

`command: "uv"` は `_ALLOWED_COMMANDS = {"uv", "uvx"}` の allowlist に該当し、
かつ `which uv` = `~/.local/bin/uv`（allowed_prefixes 内）の双方を満たす。

`<cli/twl 絶対 path>` および `<server.py 絶対 path>` は `.mcp.json` 自身がシェル展開不可のため
static value を直書きする。実装時は `git rev-parse --show-toplevel` で動的解決した値を埋め込む。

## Alternatives Considered

- **案 B**: `~/.local/bin/twl-mcp` wrapper スクリプト配置 — setup drift リスクが高く却下
- **案 C**: allowlist に `fastmcp` を追加 — security 緩和（任意 venv バイナリを許可する前例を作る）のため却下

（詳細: `.explore/twl-mcp-restart-allowed-prefixes/summary.md` §3）

## Consequences

- 将来 `.mcp.json` を変更する際は本 ADR を参照し `command: "uv"` 形式を維持すること
- `uv run --extra mcp` は `pyproject.toml` の `[project.optional-dependencies] mcp = [...]` に依存するため、extras 削除時は本 ADR の更新が必要
- `restart_mcp_server()` は SIGTERM 実行前に `_find_mcp_server_cmd()` で validation を dry-run し、失敗時は server を停止せずに early exit する（fail-fast regression 二次予防、AC3）
