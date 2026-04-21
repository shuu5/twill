---
type: reference
---

# 自動起票 Issue の Board Status 運用ガイド

## 背景

autopilot Worker が実装中に自動起票した Issue（tech-debt / self-improve / warning-fix / scope-judge / prompt-audit-apply 経由）は、
Board Status が **"Todo"** で追加されるべきである。
これらの Issue は実装が完了していないため、In Progress にしてはならない。

仕様制約（`deltaspec/specs/issue-lifecycle.md`）:
> `chain-runner.sh board-status-update` を直接呼ばない（デフォルトが In Progress のため）

## 自動起票フローの正しい Board Status

| 自動起票フロー | 使用コマンド | 期待 Status |
|-------------|------------|-------------|
| scope-judge（Deferred Issue） | `gh issue create` + `/twl:project-board-sync` | **Todo** |
| warning-fix（未修正 WARNING） | `gh issue create` + `/twl:project-board-sync` | **Todo** |
| prompt-audit-apply（FAIL Issue） | `gh issue create` + `/twl:project-board-sync` | **Todo** |
| co-self-improve（from-observation） | `gh issue create` + `/twl:project-board-sync` | **Todo** |
| workflow-issue-lifecycle | `issue-create` + `project-board-sync` (Step 6.5) | **Todo** |

## 既存の In Progress 放置 Issue を検出する手順

以下のコマンドで Board 上の "In Progress" Issue を一覧表示し、自動起票ラベル（`tech-debt`, `self-improve` 等）が付いているものを確認する。

```bash
# Board の In Progress アイテムを取得（プロジェクト番号とオーナーは project-links.yaml 参照）
gh project item-list "$(twl config get project-board.number)" --owner "$(twl config get project-board.owner)" --format json --limit 200 \
  | jq -r '.items[] | select(.status == "In Progress") | "\(.content.number) \(.content.title)"'

# In Progress + tech-debt ラベルを持つ Issue を確認
gh issue list --label "tech-debt" --state open --json number,title,labels \
  | jq -r '.[] | "\(.number) \(.title)"'
```

## 自動起票 Issue の Board Status を修正する手順

誤って In Progress になっている自動起票 Issue を "Todo" に戻す:

```bash
# chain-runner.sh board-status-update の第2引数に "Todo" を指定
CR="$(git rev-parse --show-toplevel)/scripts/chain-runner.sh"
bash "$CR" board-status-update <ISSUE_NUM> "Todo"
```

または `/twl:project-board-sync <ISSUE_NUM>` を Skill tool で実行する（常に "Todo" で設定する）。

## 関連ファイル

| ファイル | 役割 |
|---------|------|
| `scripts/chain-runner.sh:402-466` | `board-status-update` 実装（第2引数で Status 指定可） |
| `commands/project-board-sync.md` | `project-board-sync` 実装（常に "Todo"） |
| `commands/scope-judge.md` | Deferred Issue 作成後 `project-board-sync` を呼ぶ |
| `commands/warning-fix.md` | 未修正 WARNING Issue 作成後 `project-board-sync` を呼ぶ |
| `commands/prompt-audit-apply.md` | FAIL Issue 作成後 `project-board-sync` を呼ぶ |
| `deltaspec/specs/issue-lifecycle.md:93` | 自動起票時の仕様制約 |
| `tests/bats/scripts/board-merge-done-transition.bats` | Done 遷移テスト（自動起票 Issue は Done に遷移しない） |
