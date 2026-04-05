## Context

`project-board-status-update.md` の Step 2 は「GraphQL で linked repositories を確認し、現在のリポジトリにリンクされた Project を特定」とだけ記述されており、具体的なマッチングロジックが欠如。LLM が毎回独自に解釈するため、正しい Project (#3) ではなく別の Project を選択する場合がある。

`project-board-sync.md` (#45) では同じ問題を TITLE_MATCH_PROJECT パターンで解決済み。このロジックを移植する。

## Goals / Non-Goals

**Goals:**

- Step 2 の Project 検出を `project-board-sync.md` と同等の確定的ロジックに統一
- 欠落した Issue (#41-#58, #62等) を Board に一括追加するバッチスクリプト提供
- バッチ実行結果の検証手順を明文化

**Non-Goals:**

- `project-board-sync.md` 自体の変更
- deps.yaml の構造変更
- Context/Phase フィールドのミラーリング（status-update の責務外）

## Decisions

1. **Step 2 の全面書き換え**: 曖昧な1行記述を `project-board-sync.md` Step 2 と同等の詳細な bash ブロック付きフローに置換。MATCHED_PROJECTS 収集 → TITLE_MATCH_PROJECT 優先選択の 2 段階ロジック。

2. **バッチスクリプトは shell script**: `scripts/project-board-backfill.sh` として配置。引数で Issue 範囲を指定可能（例: `41 58`）。内部で `gh project item-add` + `gh project item-edit` を Issue ごとにループ実行。

3. **Status フィールド取得をループ外に移動**: 現行の Step 4 は Status フィールド情報を毎回取得する前提だが、バッチスクリプトでは効率化のため Project フィールド情報はループ前に 1 回だけ取得。

## Risks / Trade-offs

- **GitHub API レート制限**: バッチスクリプトで大量の Issue を処理する場合、GraphQL API のレート制限に到達する可能性。対策: Issue 間に 1 秒の wait を挿入。
- **`project-board-sync.md` との重複**: Step 2 ロジックが 2 箇所に存在することになる。将来的には共通シェル関数への抽出が望ましいが、本 Issue のスコープ外。
