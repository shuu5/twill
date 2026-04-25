# twill-integration (仮置き — Phase 0 PoC)

> **NOTE**: この Context 定義は Phase 0 PoC の仮置きです。所属層（monorepo / cli / plugin）の最終整理は γ #964 合流時に実施します。

## 概要

`cli/twl` を **MCP server 経由で提供**するコンテキスト境界。

- **Phase 0 (本 Issue #962)**: FastMCP を使用し、Layer 1 系ツール（validate / audit / check）のみを公開
- **Phase γ (#964)**: 他 Phase の統合・層の最終整理

## 提供ツール (Phase 0)

| MCP ツール名 | 対応 twl コマンド | 説明 |
|---|---|---|
| `twl_validate` | `twl validate` | 型ルール・body refs・v3 schema・chain 整合性の検証 |
| `twl_audit` | `twl audit` | 10 セクションにわたる TWiLL コンプライアンス監査 |
| `twl_check` | `twl check` | ファイル存在確認と chain integrity チェック |

## インターフェース

```
stdio MCP server (FastMCP, Layer 1 系のみ Phase 0)
```

起動方法:
```bash
pip install -e '.[mcp]'
fastmcp run cli/twl/src/twl/mcp_server/server.py
```

## 依存関係

- `fastmcp>=3.0` (optional, `mcp` extra)
- `twl` コアロジック (`twl.validation`, `twl.chain`, `twl.core`)
