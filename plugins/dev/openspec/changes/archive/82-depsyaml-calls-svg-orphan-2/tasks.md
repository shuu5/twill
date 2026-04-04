## 1. calls 宣言漏れ修正

- [x] 1.1 co-autopilot → autopilot-plan: controller→script は型ルール上 calls 不可 → standalone コメント付与

## 2. dead code 判定（merge-gate 関連）

- [x] 2.1 merge-gate-execute.sh の全 .md / .sh 内の参照を grep で確認
- [x] 2.2 merge-gate-init.sh の全 .md / .sh 内の参照を grep で確認
- [x] 2.3 merge-gate-issues.sh の全 .md / .sh 内の参照を grep で確認
- [x] 2.4 判定結果: merge-gate.md から呼ばれていない → standalone コメント付与（テスト・アーキテクチャドキュメントで参照あり、削除不可）

## 3. dead code 判定（fix-phase 関連）

- [x] 3.1 classify-failure.sh の参照を確認: fix-phase.md から未呼出、テスト・アーキテクチャで参照あり
- [x] 3.2 codex-review.sh の参照を確認: fix-phase.md から未呼出、テスト・アーキテクチャで参照あり
- [x] 3.3 create-harness-issue.sh の参照を確認: fix-phase.md から未呼出、テスト・アーキテクチャで参照あり
- [x] 3.4 判定結果: standalone コメント付与（テスト参照あり、削除不可）

## 4. dead code 判定（その他スクリプト）

- [x] 4.1 switchover.sh: スイッチオーバー完了済み → deps.yaml エントリ削除（スクリプト保持）
- [x] 4.2 branch-create.sh: 通常 repo 用（worktree-create とは別用途）→ standalone コメント付与
- [x] 4.3 check-db-migration.py: webapp 固有 → deps.yaml エントリ削除（スクリプト保持）

## 5. 意図的孤立の明示

- [x] 5.1 ユーザー直接起動コマンド（check, propose, apply, archive, explore, self-improve-review, worktree-list）に `# standalone` コメント付与
- [x] 5.2 プロジェクト固有コマンド（loom-validate, services, schema-update）に `# standalone` コメント付与
- [x] 5.3 低頻度ユーティリティ（ui-capture, spec-diagnose, e2e-plan, opsx-archive）に `# standalone` コメント付与
- [x] 5.4 孤立 agent（autofix-loop, context-checker, docs-researcher, e2e-heal, e2e-visual-heal, template-validator）: Task tool 動的 spawn → `# standalone` コメント付与

## 6. 検証・SVG 再生成

- [x] 6.1 `loom check` PASS（OK: 147, Missing: 0）
- [x] 6.2 `loom validate` PASS（OK: 1107, Violations: 0）
- [x] 6.3 `loom orphans`: Isolated 27（全て standalone コメント付き）、switchover/check-db-migration 削除で 29→27
- [x] 6.4 `loom update-svgs` で全 SVG 再生成完了（注: autopilot-plan エッジは controller→script 型制約により不可）
- [x] 6.5 `loom update-readme` で README 更新完了
