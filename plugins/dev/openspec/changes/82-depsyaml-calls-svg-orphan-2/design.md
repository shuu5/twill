## Context

#41 で deps.yaml calls 完全化を実施したが、`loom orphans` で 29 Isolated + 2 Unused が残存。Issue #82 での調査により、以下が判明:

- co-autopilot: SKILL.md L57 で `autopilot-plan.sh` を呼ぶが calls に未宣言
- merge-gate: merge-gate-execute/init/issues の3スクリプトは deps.yaml に定義されるが、merge-gate.md 内に実際の呼び出しが**存在しない**（dead code 候補）
- fix-phase: classify-failure/codex-review/create-harness-issue は deps.yaml に定義されるが、fix-phase.md 内に実際の呼び出しが**存在しない**（dead code 候補）
- `intentional_orphan` フィールドは loom CLI 未対応（スコープ外）
- standalone コマンド13件はユーザー直接起動のため意図的孤立

## Goals / Non-Goals

**Goals:**

- co-autopilot → autopilot-plan の calls 宣言追加
- merge-gate-execute/init/issues, classify-failure/codex-review/create-harness-issue の dead code 判定
- switchover, branch-create, check-db-migration の dead code 判定
- 意図的孤立の明示（YAML コメント方式）
- `loom orphans` Isolated を意図的孤立のみに削減
- SVG 再生成でエッジ欠落解消

**Non-Goals:**

- loom CLI の orphan 検出ロジック変更
- `intentional_orphan` フィールドの loom サポート追加
- 孤立コンポーネントの機能的改修

## Decisions

### D1: co-autopilot → autopilot-plan calls 追加

SKILL.md L57 で `bash $SCRIPTS_ROOT/autopilot-plan.sh` を明確に呼んでいるため、`- script: autopilot-plan` を calls に追加する。

### D2: dead code 判定方針

merge-gate.md と fix-phase.md の実コードを確認した結果、以下のスクリプトは**呼び出されていない**:
- merge-gate-execute.sh, merge-gate-init.sh, merge-gate-issues.sh
- classify-failure.sh, codex-review.sh, create-harness-issue.sh

これらは `git log --follow` で使用履歴を確認し:
- 呼び出し元が存在しない → deps.yaml エントリ削除 + スクリプトファイル保持（YAML コメントで "unused, kept for reference" 記載）
- 他コンポーネントから呼ばれている → calls 追加

### D3: switchover, branch-create, check-db-migration の判定

- switchover: スイッチオーバー完了済み（memory 参照）→ 削除候補
- branch-create: worktree-create に統合済みかを確認
- check-db-migration: webapp 固有、dev plugin では不使用かを確認

### D4: 意図的孤立の明示方式

loom CLI が `intentional_orphan` フィールド未対応のため、YAML コメント `# standalone: ユーザー直接起動` を各エントリに付与する。これにより:
- 人間が意図を理解できる
- loom CLI に影響なし
- 将来 loom が対応した際にフィールド化が容易

### D5: SVG 再生成

calls 修正後に `loom --graphviz` → `dot -Tsvg` で全 SVG を再生成。新しいエッジ（co-autopilot → autopilot-plan）が描画されることを確認。

## Risks / Trade-offs

- **dead code 判定の誤り**: スクリプトが将来使われる予定だった可能性。deps.yaml からの削除は行うが、スクリプトファイル自体は保持してリスクを軽減
- **YAML コメント方式の限界**: 機械可読でないため `loom orphans` の出力には影響しない。意図的孤立は引き続き Isolated として表示される
- **SVG 差分の大きさ**: グラフ再生成で大量の SVG 差分が発生する可能性があるが、これは期待される動作
