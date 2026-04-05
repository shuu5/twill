# CRG グラフ自動ビルド

CRG 導入済みプロジェクトで graph.db が不在の場合、自動でフルビルドを実行する。

## 処理フロー（MUST）

### Step 1: CRG 導入状態の判定

- .mcp.json が存在しない → 何も出力せず正常終了
- .mcp.json に code-review-graph エントリがない → 何も出力せず正常終了
- .code-review-graph/graph.db が存在する → 何も出力せず正常終了

### Step 2: フルビルド実行

MCP ツール `build_or_update_graph_tool(full_rebuild=True)` を呼び出す。

### Step 3: 結果判定

- 成功 → `"✓ CRG グラフビルド完了"`（60 秒以上は警告）
- 失敗 → `"⚠️ CRG グラフビルドに失敗しました"`、正常終了

## 禁止事項（MUST NOT）

- CRG 未導入プロジェクトでエラーを出力してはならない
- ビルド失敗でワークフロー全体を停止してはならない

## チェックポイント（MUST）

`/twl:change-propose` を Skill tool で自動実行。

