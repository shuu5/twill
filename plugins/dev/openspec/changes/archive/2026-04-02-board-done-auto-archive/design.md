## Context

`chain-runner.sh` には既存の `step_board_status_update()` 関数（L124-256付近）があり、Project 番号・Owner 検出ロジックを持つ。今回は同パターンで `step_board_archive()` を追加し、`merge-gate-execute.sh` の PASS フローから呼び出す。

GitHub Projects V2 の `gh project item-archive` コマンドを使用。アーカイブ済みアイテムは `gh project item-list` に返らなくなるため、Board の肥大化を防止できる。

## Goals / Non-Goals

**Goals:**
- `chain-runner.sh board-archive <ISSUE_NUM>` で Board アイテムをアーカイブする
- merge-gate PASS 後に自動でアーカイブを実行する
- アーカイブ失敗時にマージフローをブロックしない

**Non-Goals:**
- 既存 Done アイテムの一括クリーンアップ
- Board の構造変更・新カラム追加
- GraphQL API への移行

## Decisions

### D1: `step_board_status_update()` のロジックを踏襲する
Project 番号・Owner の取得ロジックは `step_board_status_update()` と同一パターンを使用する。共通化（関数分離）は今回スコープ外とし、コードの独立性を優先する。

**理由**: 既存関数への変更リスクを避け、差分を最小化する。

### D2: アイテムID取得に `gh project item-list` + `jq` フィルタを使用
```bash
gh project item-list "$PROJECT_NUM" --owner "$OWNER" --format json --limit 200 \
  | jq -r --argjson n "$ISSUE_NUM" '.items[] | select(.content.number == $n and .content.type == "Issue") | .id'
```

**理由**: GraphQL API より実装が単純。`--limit 200` は既存パターンと一致。

### D3: エラー時は `skip` レベルで `return 0`
`step_board_status_update()` の既存パターンに合わせ、全エラーで warning を出力して正常終了する。

**理由**: マージは既に完了している段階でのアーカイブ失敗は致命的ではない。

### D4: merge-gate-execute.sh の呼び出し位置
worktree 削除後（PASS フロー末尾）に追加する。

**理由**: worktree 削除前に呼ぶとアーカイブ成功後に worktree 削除が失敗した場合の状態が複雑になる。

## Risks / Trade-offs

- **`--limit 200` 超過リスク**: アイテムが200件を超えると対象 Issue が取得できない場合があるが、アーカイブが進むことで自然に解消される
- **Project 未検出**: `loom-dev-ecosystem` プロジェクトが見つからない場合はスキップ（既存パターンと同様）
