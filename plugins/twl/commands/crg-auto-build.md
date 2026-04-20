---
type: atomic
tools: [Bash, Read]
effort: low
maxTurns: 10
---
# CRG グラフ自動ビルド

CRG 導入済みプロジェクトで graph.db が不在の場合、自動でフルビルドを実行する。

## 処理フロー（MUST）

### Step 1: CRG 導入状態の判定

- .mcp.json が存在しない → 何も出力せず正常終了
- .mcp.json に code-review-graph エントリがない → 何も出力せず正常終了
- .code-review-graph/graph.db が存在する → 何も出力せず正常終了
- .code-review-graph がシンボリックリンク → 何も出力せず正常終了（worktree は main の DB を参照、#532）

### Step 2: フルビルド実行（timeout ガード）

Bash で以下を実行する:

```bash
timeout 600 uvx code-review-graph build
BUILD_EXIT=$?
```

並列実行時の MCP RPC ハング（#754）を防ぐため、MCP ツールではなく CLI を `timeout` でラップして呼び出す。

### Step 3: 結果判定

- `BUILD_EXIT=0` → `"✓ CRG グラフビルド完了"`（60 秒以上は警告）
- `BUILD_EXIT=124` → `"⚠️ CRG グラフビルドに失敗しました（timeout 600s）"`、正常終了
- その他 non-zero → `"⚠️ CRG グラフビルドに失敗しました"`、正常終了

## 禁止事項（MUST NOT）

- CRG 未導入プロジェクトでエラーを出力してはならない
- ビルド失敗でワークフロー全体を停止してはならない
- `ln` コマンドを実行してはならない（symlink 作成禁止 — #674）
- `.code-review-graph` ディレクトリ・ファイルを手動で作成・削除・移動・symlink 操作してはならない（#674）
- MCP ツール `build_or_update_graph_tool` を呼び出してはならない（RPC ハングの原因 — #754）

