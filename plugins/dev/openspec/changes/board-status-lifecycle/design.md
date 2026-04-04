## Context

`step_board_status_update()` に `target_status` パラメータは既に追加済み（#156）だが、全呼び出し元への適用が不完全。現状の Status 遷移:

| 呼び出し元 | タイミング | 設定 Status | 問題 |
|-----------|-----------|------------|------|
| project-board-sync | Issue 新規追加 | Todo | 正しい |
| chain-runner.sh board-status-update | workflow-setup 開始 | In Progress | 妥当 |
| project-board-backfill.sh | 未登録 Issue バックフィル | In Progress | 新規なのに In Progress |
| merge-gate-execute.sh | merge 成功 | (Done 経由せず) board-archive | Done 履歴なし |
| project-board-archive.sh | 手動/バッチ | Archive | autopilot から未使用 |

## Goals / Non-Goals

**Goals:**
- Status 遷移ルールを統一し、各責務を一意に割り当てる
- merge 成功時に Done を経由してから Archive する正しいライフサイクルを実現する
- autopilot Phase 完了時に当該 Phase の Issue のみをアーカイブする（他 Phase・手動 Issue は対象外）
- `project-board-backfill.sh` の冪等性確保（既存アイテムはスキップ）

**Non-Goals:**
- project-board-sync のロジック変更（既に Todo で正しい）
- Board カスタムフィールドの追加
- #186（refined ラベル自動付与）

## Decisions

### 1. backfill のデフォルト Status を Todo に変更

`project-board-backfill.sh` はバックフィル対象 Issue を Todo で追加する。既存 Board アイテムは Status を変更せずスキップ（冪等性）。実装: GitHub GraphQL で既存アイテムを確認してからスキップ判定。

### 2. merge-gate-execute.sh での Done 遷移

`merge-gate-execute.sh` は merge 成功後に `chain-runner.sh board-archive` を呼ぶ代わりに `chain-runner.sh board-status-update <issue> "Done"` を呼ぶ。board-archive コマンド自体は削除せず残す（Phase 完了処理から呼ばれる用途）。

### 3. autopilot Phase 完了処理での選択的 Archive

`autopilot-orchestrator.sh` の Phase 完了処理で、`plan.yaml` の当該 Phase に含まれる Issue 番号リストを取得し、それらの Done アイテムのみを `board-archive` で Archive する。他 Phase・手動 Issue は対象外とする。

## Risks / Trade-offs

- **backfill 冪等化の GraphQL 呼び出し**: 既存アイテム確認のための API 呼び出しが増加するが、重複防止の効果が上回る
- **board-archive の残置**: merge 文脈からの呼び出しを削除するが、コマンドは残すため混乱の可能性あり。コメントで用途を明記する
- **Phase 完了時の Archive スコープ**: plan.yaml の Issue 番号ベースの判定は、Phase をまたいで移動した Issue に対して不正確になる可能性があるが、現時点では許容範囲
