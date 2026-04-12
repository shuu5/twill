## Context

autopilot の state file (`issue-{N}.json`) には3つの進捗フィールドが存在する:

| フィールド | 現状の役割 |
|---|---|
| `status` | Issue ライフサイクル全体の状態（running/merge-ready/done/failed/conflict） |
| `current_step` | chain-runner が記録する実行中のステップ名 |
| `workflow_done` | chain terminal で書かれ、orchestrator の inject トリガーとして機能した後に null クリアされる |

Wave 7 で Monitor が `workflow_done` の null 逆戻りを異常と誤検知し、STAGNATE 警告を発した。根本原因は「外部観察者が正しい状態を判断するための SSOT フィールドが不明」なこと。

## Goals / Non-Goals

**Goals:**

- `status` を SSOT として確定し、Monitor/su-observer が単一フィールドで進捗判定できるようにする
- `workflow_done` を廃止し、orchestrator の inject トリガーを `status=merge-ready` 遷移検知に変更する
- `autopilot.md` の IssueState 表を正確な状態遷移グラフ（`conflict` 含む）に更新する
- ADR-016 を新規作成して Option 1 採用の設計決定を記録する

**Non-Goals:**

- `current_step` の廃止（chain-runner 内部での粒度管理に引き続き使用する）
- orchestrator の全面リファクタリング（inject トリガー変更のみにスコープを絞る）
- Monitor/su-observer 実装の変更（SSOT 確立後に単純化できるが本 Issue の範囲外）

## Decisions

### Decision 1: Option 1 (status SSOT) を採用

**理由**: Monitor/su-observer の主用途は「マージ可能か」「正常か」の判定であり、`status` の意味的粒度（running/merge-ready/done/failed/conflict）がそれに合致する。`current_step` は chain 内部の実装詳細であり、外部観察に露出すべきでない。

**代替 Option 2 (current_step SSOT) を選ばなかった理由**: chain-runner の都合に合わせた設計になりすぎる。状態遷移の意味的明確性が `status` より劣る。

### Decision 2: workflow_done 廃止、inject トリガーを status ベースに変更

**現在の仕組み**: chain terminal で `workflow_done=<name>` を書き → orchestrator がポーリングで検知 → `inject_next_workflow` 実行 → `workflow_done=null` にクリア

**新しい仕組み**: 各 workflow の terminal ステップで `status=merge-ready`（または該当する terminal 状態）を書く → orchestrator が `status` 遷移を検知してトリガー

**注意**: `resolve_next_workflow.py` が `workflow_done` を読んでいるため、`status` + `current_step` の組み合わせで次ワークフローを解決するロジックに変更する。

### Decision 3: current_step は維持（SSOT ではなく補助フィールドに格下げ）

chain-runner 内部のデバッグ・ロギング目的には有用。廃止は別途 Issue で判断する。

### Decision 4: ADR-016 を新規作成、ADR-003 からリンク

設計決定の正典を ADR に記録することで将来の参照を容易にする。

## Risks / Trade-offs

- **orchestrator のトリガー機構変更は破壊的**: `autopilot-orchestrator.sh` の L503/594/742-750/819/867 を変更するため、既存の bats テスト (inject-next-workflow/*.bats 3 ファイル) が全て失敗する。テストを先行更新する必要がある。
- **#494 との sequencing**: #494 は `workflow_done=pr-merge` の write を必須化する実装。#507 Phase A（Option 決定） → #494 → #507 Phase B/C の順序が必要。本 Issue で workflow_done 廃止を確定することで #494 の実装を調整できる（#494 は廃止対象への追加作業になるため #494 実装者に通知が必要）。
- **co-autopilot-smoke.test.sh の更新**: workflow_done 参照の削除が必要。スモークテストが壊れる可能性があるため注意が必要。
