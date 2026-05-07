# ADR-035: Subagent MCP Server Inheritance — Behavior, Root Cause, and Fix Strategy

## Status

Accepted (2026-05-07)

## Context

### Problem (Issue #1506)

co-explore および co-autopilot Worker セッションの PreToolUse:Bash hook で `MCP server 'twl' not connected` エラーが連続出力される問題が 2026-05-07 に観測された。

```
PreToolUse:Bash hook error: MCP server 'twl' not connected
```

このエラーは epic #1034 (session-comm migration) および #1271 (twl-mcp Tier 1+) の前提条件である「Worker subagent から `mcp__twl__*` ツールを呼び出せること」を阻害する。

### Root Cause: Race Condition at Session Startup

**主因（verified）**: `.mcp.json` が `uv run ... fastmcp run` でサーバーを起動するため、初回起動時に uv の仮想環境セットアップ（数秒〜数十秒）が必要。`cld-spawn` でセッションを起動しプロンプトを inject すると、MCP サーバー起動完了前に最初の Bash ツール使用が発生し PreToolUse:Bash hook が `mcp_tool` を参照した際に "not connected" エラーになる。

**副因（deduced）**: Claude Code の Agent ツールで spawn した subagent は project-local `.mcp.json` の MCP サーバーを自動継承しない（claude-code-guide 調査、2026-05-07）。subagent frontmatter に `mcpServers` フィールドを明示指定することで解消可能。

### MCP Server Configuration at Time of Issue

```json
"twl": {
  "type": "stdio",
  "command": "uv",
  "args": ["run", "--directory", "/path/to/main/cli/twl", "--extra", "mcp", "fastmcp", "run", "src/twl/mcp_server/server.py"],
  "env": {}
}
```

`uv run` は初回に venv セットアップを行うため起動に 5〜30 秒かかる場合がある。

### Timing of Affected Epics

- **epic #1034** (session-comm mailbox migration): Worker から `mcp__twl__twl_send_msg` を呼ぶ前提
- **epic #1271** (twl-mcp Tier 1+): observer/controller bash 呼び出しを MCP 化する前提
- **epic #1037** (hooks-mcp 移行戦略): hooks の `mcp_tool` 型使用が subagent で動作する前提

## Decision

### Decision 1: `.mcp.json` を venv プリインストール fastmcp 直接起動に変更

**変更内容**:
```json
"twl": {
  "type": "stdio",
  "command": "/home/shuu5/projects/local-projects/twill/main/cli/twl/.venv/bin/fastmcp",
  "args": ["run", "/home/shuu5/projects/local-projects/twill/main/cli/twl/src/twl/mcp_server/server.py"],
  "env": {}
}
```

**効果**: `uv run` の venv セットアップオーバーヘッドを排除。起動時間を ~0.5秒 に短縮（実測）。

**制約**: `.venv` の絶対パスを使用するため、環境移行時は手動更新が必要。パスはホストに依存する。

**不採用案**:
- `uv run` 維持 + 起動待機ループ: hook 側で MCP 接続を待機する実装は設定ファイルベースの hook では実現困難
- HTTP/SSE 型への変更: 常駐デーモン管理が必要、複雑性が増す

### Decision 2: `.claude/subagent-mcp.json` による subagent MCP 設定の文書化

Agent ツール経由で spawn される subagent に `twl` MCP を使わせるには、subagent の frontmatter に `mcpServers` を明示指定する必要がある。`.claude/subagent-mcp.json` に参照設定を記録し、今後の agent 実装時の参照文書とする。

```json
// .claude/subagent-mcp.json
{
  "mcpServers": { "twl": { "command": "...", "args": [...] } }
}
```

これを必要とする agent 定義ファイルの frontmatter に `mcpServers` フィールドとして追記することで、対象 subagent が `twl` MCP に接続できる。

**不採用案**:
- project-local `.mcp.json` に `allowSubagents: true` フィールドを追加: Claude Code は現時点でこのフィールドをサポートしていない（claude-code-guide 調査 2026-05-07）
- Claude Code の設定ファイル変更で一括継承: `CLAUDE_CODE_SUBAGENT_MCP_INHERIT` 相当の env var は存在しない（verified）
- agent 定義ファイルごとに個別対応: 現状の選択と同じだが、将来的に scaffold 自動化が望ましい（Issue #1519）

### Decision 3: 適用対象 epic の前提条件として記録

本 ADR の Decision 1/2 は以下の epic 実装開始前に適用済みであることを前提条件として記録する:
- **epic #1034**: Tier C Phase 1 開始前に `.mcp.json` 修正が適用されていること
- **epic #1271**: Tier 1+ の Worker agent 定義に `mcpServers: twl` が含まれていること
- **epic #1037**: hooks の `mcp_tool` 型が subagent で動作するためのガード設計に本 ADR を参照すること

**不採用案**:
- epic 実装開始後に前提条件を記録: 前提未確認のまま実装を開始するとブロッカーになるリスクがあるため事前記録を選択
- 各 epic の Issue body に個別記述: ADR への集約で参照の一元化を優先

## Consequences

### Positive

- PreToolUse:Bash hook の `MCP server 'twl' not connected` エラーが解消される（セッション起動レース解消）
- Worker subagent から `mcp__twl__*` ツールを呼び出せる設計基盤が整う
- epic #1034/#1271/#1037 の実装開始ブロッカーが解除される

### Negative

- `.mcp.json` に `.venv` の絶対パスが入るため、ホスト変更・リポジトリ移動時は手動更新が必要
- Agent 定義の frontmatter に `mcpServers` を追記する作業が各 agent 実装時に必要

### Mitigations

- `.mcp.json` の絶対パスは `twl config` コマンドで自動更新できる仕組みを将来的に検討（#945 Phase 2 の工数として積む）
- `subagent-mcp.json` をテンプレートとして agent scaffold 時に自動注入する仕組みを co-project に追加検討

## Related

- Issue #1506 (本 bug fix)
- ADR-029 (twl MCP integration strategy)
- epic #1034 (session-comm mailbox)
- epic #1271 (twl-mcp Tier 1+)
- epic #1037 (hooks-mcp 移行戦略)

## References

- `.mcp.json` — MCP server configuration (project-local)
- `.claude/subagent-mcp.json` — subagent MCP reference configuration
- `cli/twl/src/twl/mcp_server/server.py` — FastMCP server entry point
- `cli/twl/.venv/bin/fastmcp` — pre-installed fastmcp binary
