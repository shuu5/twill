## Context

`autopilot-plan.sh` は `--explicit` と `--issues` の2モードで Issue リストを受け取り plan.yaml を生成する。Board の Todo/In Progress Issue を自動取得する手段がなく、手動でリストアップが必要。

Board API（`gh project item-list`）のレスポンスには `content.number`、`content.repository`、`status` が含まれる。これを使えば既存の `parse_issues()` に渡すだけで plan.yaml を生成できる。

## Goals / Non-Goals

**Goals:**

- `--board` モードで Board の非 Done Issue を自動取得し plan.yaml を生成
- Board item の `content.repository` からクロスリポジトリ `--repos` JSON を自動構築
- `--board` と `--explicit`/`--issues` の排他バリデーション

**Non-Goals:**

- ラベル/マイルストーンによるフィルタリング（将来拡張）
- Board Status の自動更新（#108, #109 で対応済み）
- 新規 Project Board の自動作成

## Decisions

### D1: Board 検出ロジックの再利用

`project-board-status-update.md` と同じ GraphQL クエリで Project を検出する。リポジトリにリンクされた Project が複数ある場合、タイトルマッチ優先 → 最初のマッチ。

### D2: `--board` モードの実装場所

`autopilot-plan.sh` 内で `--board` モードを新設し、Board API から Issue リストを取得後、既存 `parse_issues()` に渡す。新規関数 `fetch_board_issues()` を追加。

### D3: クロスリポジトリ自動解決

Board item の `content.repository`（`owner/name` 形式）から `--repos` JSON を自動構築。現在のリポジトリ以外の項目があれば `repo_id` を name から短縮形で生成し、worktree path は空（Worker が自動検出）。

### D4: co-autopilot SKILL.md の変更

Step 0 引数解析テーブルに `--board` パターンを追加。Board 検出に必要な `OWNER` と `PROJECT_NUM` は `autopilot-plan.sh` 内で自動解決するため、SKILL.md からの引数渡しは不要。

## Risks / Trade-offs

- **Board API のレート制限**: `gh project item-list` は1回の呼び出しで全 items を取得。Issue 数が多い場合は GraphQL のページネーション上限（デフォルト100件）に注意
- **依存 #114 未完了**: Board API アクセスに `project` scope の PAT が必要。#114 が先行完了しないと動作しない
- **Board item に Issue 以外が含まれる可能性**: Draft issue や PR は `content.type` でフィルタリングが必要
