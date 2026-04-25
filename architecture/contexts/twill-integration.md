# twill-integration (Phase 0 γ #964 更新済み)

## 概要

`cli/twl` を **MCP server 経由で提供**するコンテキスト境界。

- **Phase 0 α (#962)**: FastMCP stdio server 実装（`cli/twl/src/twl/mcp_server/`）
- **Phase 0 β (#963)**: cli.py if-chain → SSoT pure 関数化
- **Phase 0 γ (#964)**: Deploy 戦略確立（`.mcp.json` Path B primary 採用）

## 提供ツール (Phase 0)

| MCP ツール名 | 対応 twl コマンド | 説明 |
|---|---|---|
| `twl_validate` | `twl validate` | 型ルール・body refs・v3 schema・chain 整合性の検証 |
| `twl_audit` | `twl audit` | 10 セクションにわたる TWiLL コンプライアンス監査 |
| `twl_check` | `twl check` | ファイル存在確認と chain integrity チェック |

## OHS (Open Host Service) パターン拡張

cli/twl の公開インターフェースは従来の CLI コマンドに加えて MCP ツールとして **二重チャネル化** されている。

| チャネル | コマンド | 用途 |
|---|---|---|
| CLI | `twl validate/audit/check` | 直接実行・CI・degradation path |
| MCP | `twl_validate/twl_audit/twl_check` | AI session からの呼び出し |

plugins/twl からの呼び出し経路選択は plugins/twl 側の責務。

## インターフェース

```
stdio MCP server (FastMCP, Layer 1 系のみ Phase 0)
```

## 起動方法

開発時の手動起動（MCP auto-connect とは独立した手順）:
```bash
cd cli/twl
uv run --extra mcp fastmcp run src/twl/mcp_server/server.py
```

AI session からの自動接続は下記「Deploy 戦略」セクションを参照。

## Deploy 戦略 (Phase 0 γ)

> 「起動方法」セクション（手動起動）との違い: 本セクションは AI session からの **自動接続経路** を扱う。

### 採用方針: Path B (.mcp.json) primary

`.mcp.json` を git-tracked で管理することで、全 worktree・将来の全ホスト・コンテナへ `git pull` のみで配布する。

**Path B primary 採用理由**:
- `.mcp.json` は **per-repo MCP 設定の SSOT**（deps.yaml/types.yaml とは責務領域が異なる）
- git checkout / git worktree add 時に自動継承（追加の deploy 手順不要）
- 既存 code-review-graph entry と共存（JSON merge で冪等追加）

### MCP サーバー設定 (`.mcp.json` エントリ)

```json
{
  "mcpServers": {
    "twl": {
      "type": "stdio",
      "command": "uv",
      "args": [
        "run",
        "--directory",
        "/home/shuu5/projects/local-projects/twill/main/cli/twl",
        "--extra", "mcp",
        "fastmcp", "run",
        "src/twl/mcp_server/server.py"
      ],
      "env": {}
    }
  }
}
```

**`--directory` 絶対パス制約 (Phase 0)**:
`/home/shuu5/projects/local-projects/twill/main/cli/twl` を hardcode。
ipatho-1 / shuu5 user 依存であり、他ホストへ展開時に無音失敗する。
**Phase 1 で相対化する方針**（worktree の WIP は main merge まで反映されない点も含めて改善対象）。

### worktree 振る舞い

`.mcp.json` は git-tracked であるため、`git worktree add` で作成された全 worktree に自動継承される。`main/.mcp.json` が単一 source of truth。

```
twill/main/.mcp.json (git-tracked, per-repo MCP 設定 SSOT)
       │ git checkout / git worktree add
       ▼
全 worktree が同一 .mcp.json を保持
```

### host scope (Phase 0 γ)

**ipatho-1 only**。Phase 1 で以下を展開予定:
- ipatho-2（host expansion 別 Issue）
- コンテナ 3 種（omics-dev / webapp-dev / repordev）— Python/uv 有無の事前調査が前提
- Path C（plugin manifest `mcpServers`）— enabledPlugins 整理後に再評価

### Path A (将来検討)

user-global 用途（`~/.claude.json` の `mcpServers`）。
Path B と重複・衝突しない merge 戦略が必要。別 Issue で議論予定（ipatho-1 では現在不在）。

### CLI fallback (degradation path)

MCP server 接続成功時も、CLI 直接呼び出しは引き続き機能する（degradation path として）:

```bash
cd cli/twl && uv run --extra mcp twl --validate
```

**Phase 1 実装予定 — MCP server 起動失敗時の自動 fallback**:
- 現 Phase 0 では MCP 接続失敗時の自動 degradation は未実装
- Phase 1 で plugins/twl 側に fallback ロジックを追加する
- 必要な検証項目: (1) MCP 接続状態の検知方法、(2) CLI への自動切り替えトリガー、(3) fallback 時のユーザー通知

## 依存関係

- `fastmcp>=3.0` (optional, `mcp` extra — `pyproject.toml` の `[project.optional-dependencies]`)
- `twl` コアロジック (`twl.validation`, `twl.chain`, `twl.core`)
