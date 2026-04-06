---
name: twl:workflow-plugin-create
description: |
  新規プラグイン作成ワークフロー（interview → research → design → generate）。

  Use when user: says プラグイン作りたい/作成したい/新規プラグイン,
  or when called from co-project plugin-create mode.
type: workflow
effort: medium
spawnable_by: [controller]
can_spawn: [atomic]
---

# workflow-plugin-create

新規 AT プラグイン作成の 4 ステップワークフロー。

## Step 1: plugin-interview（要件ヒアリング）

`/twl:plugin-interview` を実行。

ユーザーから以下を収集:
- プラグイン名・目的
- ワークフロー分割・AT 並列タスク要否
- フェーズ構成・情報引継ぎ手段
- ツール要件・チェックポイント・チームサイズ
- Context Snapshot / Subagent Delegation 要否

## Step 2: plugin-research（最新仕様取得）

`/twl:plugin-research` を実行。

AT 仕様および Claude Code 設定仕様（スキル/コマンド/エージェント/フック/frontmatter）の
最新ドキュメントを取得してサマリーを構築。

## Step 3: plugin-design（型マッピング + deps.yaml 設計）

`/twl:plugin-design` を実行。

interview の要件を 6 型にマッピングし、deps.yaml ドラフトを生成。
ユーザー確認後に確定。

## Step 4: plugin-generate（ファイル一式生成）

`/twl:plugin-generate` を実行。

design で確定した設計に基づきプラグインファイル一式を生成:
- ディレクトリ構造・plugin.json・deps.yaml
- 各コンポーネントファイル（controller/workflow/phase/worker/atomic/reference）
- Context Snapshot / Subagent Delegation インフラ（該当時）
- README.md + SVG 依存関係図

## 完了

生成されたファイル一覧を表示。
`twl validate` / `twl audit` の通過を確認。
