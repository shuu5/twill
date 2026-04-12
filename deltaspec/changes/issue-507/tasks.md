## 1. Phase A: 設計決定の文書化

- [x] 1.1 `plugins/twl/architecture/domain/contexts/autopilot.md` の IssueState 表に `conflict` を追加し、5値の完全な状態遷移グラフを明記する
- [x] 1.2 `plugins/twl/architecture/decisions/ADR-018-state-schema-ssot.md` を新規作成する（Option 1 採用根拠、廃止フィールド一覧、代替トリガー機構の説明を含む）
- [x] 1.3 `plugins/twl/architecture/decisions/ADR-003-unified-state-file.md` に ADR-018 への参照リンクを追加する

## 2. Phase B: state.py / resolve_next_workflow.py の修正

- [x] 2.1 `cli/twl/src/twl/autopilot/state.py` の `_PILOT_ISSUE_ALLOWED_KEYS` から `workflow_done` を削除する
- [x] 2.2 `cli/twl/src/twl/autopilot/resolve_next_workflow.py` の `workflow_done` 参照を `current_step` ベースのロジックに変更する

## 3. Phase C: orchestrator の inject トリガー変更

- [x] 3.1 `plugins/twl/scripts/autopilot-orchestrator.sh` L503/594 の `workflow_done` 読み込みを `current_step` ベースに変更する
- [x] 3.2 `autopilot-orchestrator.sh` AC-2 fallback の `workflow_done` write を削除する
- [x] 3.3 `autopilot-orchestrator.sh` inject 後の `workflow_done=null` クリア処理を削除する
- [x] 3.4 `inject_next_workflow` のトリガー判定を `current_step` terminal 値検知に変更し、`LAST_INJECTED_STEP` で重複防止する

## 4. Phase C: chain-runner / SKILL.md の workflow_done 書き込み削除

- [x] 4.1 `plugins/twl/skills/workflow-setup/SKILL.md` の `workflow_done=setup` write を削除する
- [x] 4.2 `plugins/twl/skills/workflow-test-ready/SKILL.md` の `workflow_done=test-ready` write を削除する
- [x] 4.3 `plugins/twl/skills/workflow-pr-verify/SKILL.md` の `workflow_done=pr-verify` write を削除する
- [x] 4.4 `plugins/twl/skills/workflow-pr-fix/SKILL.md` の `workflow_done=pr-fix` write を削除する
- [x] 4.5 `plugins/twl/skills/workflow-pr-merge/SKILL.md` の `workflow_done=pr-merge` write を削除する
- [x] 4.6 `plugins/twl/scripts/chain-runner.sh` の `workflow_done` write 箇所を全て削除する（参照なし — 変更不要）

## 5. Phase C: hooks / その他の cleanup

- [x] 5.1 `plugins/twl/scripts/hooks/pre-compact-checkpoint.sh` の `workflow_done` 参照を削除する

## 6. テスト更新

- [x] 6.1 `plugins/twl/tests/unit/inject-next-workflow/*.bats` 3ファイルを新しい `status` ベーストリガーに対応するよう更新する
- [x] 6.2 `plugins/twl/tests/scenarios/co-autopilot-smoke.test.sh` の `workflow_done` 検証ロジックを削除または更新する
- [x] 6.3 Wave 7 誤警告パターンを再現する bats テストを作成し、新 schema 下で誤警告が発生しないことを確認する（`status=merge-ready` 時に STAGNATE 警告なし）
