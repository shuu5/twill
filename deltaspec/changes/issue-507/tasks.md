## 1. Phase A: 設計決定の文書化

- [ ] 1.1 `plugins/twl/architecture/domain/contexts/autopilot.md` の IssueState 表に `conflict` を追加し、5値の完全な状態遷移グラフを明記する
- [ ] 1.2 `plugins/twl/architecture/decisions/ADR-016-state-schema-ssot.md` を新規作成する（Option 1 採用根拠、廃止フィールド一覧、代替トリガー機構の説明を含む）
- [ ] 1.3 `plugins/twl/architecture/decisions/ADR-003-unified-state-file.md` に ADR-016 への参照リンクを追加する

## 2. Phase B: state.py / resolve_next_workflow.py の修正

- [ ] 2.1 `cli/twl/src/twl/autopilot/state.py` の `_PILOT_ISSUE_ALLOWED_KEYS` から `workflow_done` を削除する
- [ ] 2.2 `cli/twl/src/twl/autopilot/resolve_next_workflow.py` の `workflow_done` 参照を `status` + `current_step` ベースのロジックに変更する

## 3. Phase C: orchestrator の inject トリガー変更

- [ ] 3.1 `plugins/twl/scripts/autopilot-orchestrator.sh` L503/594 の `workflow_done` 読み込み箇所を `status` 参照に変更する
- [ ] 3.2 `autopilot-orchestrator.sh` L742-750 の AC-2 fallback（`workflow_done` write）を削除する
- [ ] 3.3 `autopilot-orchestrator.sh` L819/867 の `workflow_done=null` クリア処理を削除する
- [ ] 3.4 `inject_next_workflow` のトリガー判定を `status=merge-ready` 遷移検知に変更する

## 4. Phase C: chain-runner / SKILL.md の workflow_done 書き込み削除

- [ ] 4.1 `plugins/twl/skills/workflow-setup/SKILL.md` の `workflow_done=setup` write を削除する
- [ ] 4.2 `plugins/twl/skills/workflow-test-ready/SKILL.md` の `workflow_done=test-ready` write を削除する
- [ ] 4.3 `plugins/twl/skills/workflow-pr-verify/SKILL.md` の `workflow_done=pr-verify` write を削除する
- [ ] 4.4 `plugins/twl/skills/workflow-pr-fix/SKILL.md` の `workflow_done=pr-fix` write を削除する
- [ ] 4.5 `plugins/twl/skills/workflow-pr-merge/SKILL.md` の `workflow_done=pr-merge` write を削除する
- [ ] 4.6 `plugins/twl/scripts/chain-runner.sh` の `workflow_done` write 箇所を全て削除する

## 5. Phase C: hooks / その他の cleanup

- [ ] 5.1 `plugins/twl/scripts/hooks/pre-compact-checkpoint.sh` の `workflow_done` 参照を削除する

## 6. テスト更新

- [ ] 6.1 `plugins/twl/tests/unit/inject-next-workflow/*.bats` 3ファイルを新しい `status` ベーストリガーに対応するよう更新する
- [ ] 6.2 `plugins/twl/tests/scenarios/co-autopilot-smoke.test.sh` の `workflow_done` 検証ロジックを削除または更新する
- [ ] 6.3 Wave 7 誤警告パターンを再現する bats テストを作成し、新 schema 下で誤警告が発生しないことを確認する（`status=merge-ready` 時に STAGNATE 警告なし）
