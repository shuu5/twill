# /dev:setup-crg

プロジェクトに code-review-graph MCP を導入します。

## 前提

- プロジェクトルート（git リポジトリ内）で実行すること
- `uv`（uvx）がグローバルにインストール済みであること
- `jq` がインストール済みであること（既存 `.mcp.json` マージに使用）

## 実行フロー

### 1. uvx 前提確認

```bash
if ! command -v uvx >/dev/null 2>&1; then
  echo "❌ uvx が見つかりません。uv をインストールしてください:"
  echo "  curl -LsSf https://astral.sh/uv/install.sh | sh"
  → 終了
fi
echo "✓ uvx $(uvx --version)"

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq が見つかりません。インストールしてください:"
  echo "  sudo apt install jq"
  → 終了
fi
```

### 2. .mcp.json 生成

プロジェクトルートの `.mcp.json` を確認し、`code-review-graph` サーバー定義を追加する。

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
MCP_JSON="$PROJECT_ROOT/.mcp.json"
```

**場合分け:**

1. `.mcp.json` が存在しない → 新規作成:
   ```json
   {
     "mcpServers": {
       "code-review-graph": {
         "command": "uvx",
         "args": ["code-review-graph", "serve"]
       }
     }
   }
   ```

2. `.mcp.json` が存在し `code-review-graph` エントリがない → jq でマージ:
   ```bash
   tmp=$(mktemp) && jq '.mcpServers["code-review-graph"] = {"command": "uvx", "args": ["code-review-graph", "serve"]}' "$MCP_JSON" > "$tmp" && mv "$tmp" "$MCP_JSON"
   ```

3. `.mcp.json` に `code-review-graph` エントリが既にある → スキップ:
   ```
   ℹ️ code-review-graph は既に .mcp.json に登録済みです。スキップします。
   ```

### 3. 初回グラフビルド

```bash
uvx code-review-graph build
```

- 成功 → `✓ グラフビルド完了`
- 失敗 → `⚠️ グラフビルドに失敗しました。Claude の build_or_update_graph_tool で後から再ビルドできます。`（処理続行）

### 4. .gitignore 追加

```bash
GITIGNORE="$PROJECT_ROOT/.gitignore"
```

- `.gitignore` が存在し `.code-review-graph/` が含まれていない → 追記
- `.gitignore` に既に含まれている → スキップ
- `.gitignore` が存在しない → `.code-review-graph/` を含む新規作成

### 5. 完了案内

```
✓ code-review-graph セットアップ完了

  .mcp.json に code-review-graph サーバーを登録しました。
  .code-review-graph/ を .gitignore に追加しました。

  ⚠️ Claude Code を再起動してください（MCP サーバーの読み込みに必要です）。
```
