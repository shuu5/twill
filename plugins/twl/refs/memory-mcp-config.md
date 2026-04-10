---
name: memory-mcp-config
description: Memory MCP の pluggable 設定（現在の MCP、ツール名、デフォルトパラメータ）
type: reference
---

# Memory MCP 設定リファレンス

Memory MCP の pluggable 設定。MCP を入れ替える場合はこのファイルのみを更新する。

## 現在の設定

```yaml
memory_mcp:
  current: doobidoo
  search_tool: mcp__doobidoo__memory_search
  store_tool: mcp__doobidoo__memory_store
  quality_tool: mcp__doobidoo__memory_quality
  search_defaults:
    mode: hybrid
    quality_boost: 0.3
    limit: 5
```

## ツール用途

| ツール | 用途 |
|--------|------|
| `mcp__doobidoo__memory_search` | 記憶の検索（hybrid mode 推奨） |
| `mcp__doobidoo__memory_store` | 新規記憶の保存 |
| `mcp__doobidoo__memory_quality` | 記憶品質の評価（rate=1 / rate=-1） |

## 検索デフォルトパラメータ

- `mode: hybrid` — semantic + keyword 複合検索
- `quality_boost: 0.3` — 高品質記憶を優先
- `limit: 5` — 取得上限（タスク開始時の標準値）

## MCP 入れ替え手順

1. このファイルの `current` と各 `*_tool` を新 MCP のツール名に更新する
2. `search_defaults` を新 MCP のパラメータに合わせて更新する
3. 参照スキル（su-observer, co-autopilot 等）が自動的に新設定を使用する
