## Context

`plugins/twl/skills/co-issue/SKILL.md` は現在 v1 構造（Phase 2-3-4 は `workflow-issue-refine` + `workflow-issue-create` への sequential 呼び出し）で動作している。Issue #491 で整備された Worker runtime（`scripts/issue-lifecycle-dispatch.sh`, `scripts/issue-lifecycle-wait.sh`, `workflow-issue-lifecycle` SKILL.md）を使うには Pilot 側の書き換えが必要。Feature flag `CO_ISSUE_V2` で新旧パスを並存させ、段階的ロールアウトと即時 rollback を可能にする。

## Goals / Non-Goals

**Goals:**

- `CO_ISSUE_V2` 環境変数の正典導入（SKILL.md の Environment セクション）
- Phase 2 に DAG 構築 + per-issue bundle 書き出し + policies.json 生成を追加（flag==1 パス）
- Phase 3 に `issue-lifecycle-dispatch.sh` 呼び出し + Bash-bg wait を追加（flag==1 パス）
- Phase 4 に全 report.json aggregate + summary table + failure 対話を追加（flag==1 パス）
- Phase 5（新規）: flag==1 かつ 1 件以上成功時に #493 へ run log 投稿
- `tests/scenarios/co-issue-v2-smoke.test.sh` 新規追加
- `deps.yaml` の calls 更新
- flag==0 既存動作の完全維持（回帰ゼロ原則）

**Non-Goals:**

- Worker runtime 実装（Issue #491 で完了前提）
- 旧 workflow-issue-refine / workflow-issue-create の削除（#493 cutover スコープ）
- `CO_ISSUE_V2=1` の default 化（#493 cutover スコープ）
- `tests/scenarios/spec-review-gate.test.sh` の v2 対応（#493 cutover スコープ）
- `docs/issue-mgmt.md` IM-1/2/3 制約更新（#493 cutover スコープ）
- `deltaspec/changes/issue-447/` の整理（#493 cutover スコープ）

## Decisions

### D1: Feature flag を環境変数（CO_ISSUE_V2）として SKILL.md に宣言する

SKILL.md 冒頭に `## Environment` セクションを新設。`${CO_ISSUE_V2:-0}` で参照し、default=0（旧パス）。Issue #493 (Cutover) まで default を変えない。

### D2: DAG edge 抽出は正規表現ベース、循環は Kahn's algorithm で検出

- ローカル ref: `(?<![A-Za-z0-9/])#(\d{1,3})(?![0-9])` → 現セッション内 draft index（1-based）
- クロスリポ ref: `[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#\d+` → GitHub issue 番号
- コードブロック内は除外
- 循環 edge 残存時は abort（エラーメッセージで停止）

### D3: policies.json は per-issue ディレクトリに書き出す

```
.controller-issue/<sid>/per-issue/<index>/IN/policies.json
```

quick: `max_rounds=1, specialists=["worker-codex-reviewer"], depth="shallow", quick_flag=true`
scope-direct: `max_rounds=1, specialists=["worker-codex-reviewer"], depth="shallow", scope_direct_flag=true`
通常: `max_rounds=3, specialists=["worker-codex-reviewer","issue-critic","issue-feasibility"], depth="normal"`

### D4: Level-based dispatch は `issue-lifecycle-dispatch.sh <sid> <level> --max-parallel 3`

level 0 → dispatch → Bash-bg wait → level 1 → ... 。前 level の OUT/report.json から parent URL を読み出し、current level の policies の `parent_refs_resolved` に注入。

### D5: failure 判定は DAG edge 参照

failed issue が次 level の依存対象 → circuit_broken（break）。依存対象でなければ warning のみ継続。

### D6: soak logging は gh issue comment 投稿（非ブロッキング）

失敗時は warning のみ。#493 が closed なら投稿をスキップ（`gh issue view 493` で事前確認）。

## Risks / Trade-offs

- **Worker runtime 依存**: Issue #491 が merge 済みでないと Phase 3 が実行できない。実装前に `scripts/issue-lifecycle-dispatch.sh` の存在を確認する
- **SKILL.md の肥大化**: v1/v2 両パス記述でファイル長が増大するが、#493 cutover で整理される前提
- **smoke テスト限定**: 本 Issue では v2 動作確認は smoke テストのみ（`co-issue-v2-smoke.test.sh`）。Full E2E は soak 期間での手動確認に委ねる
- **local-ref 判別**: クロスリポ ref との区別が正規表現頼みのため、edge ケース（3 桁超の数字など）で誤検出リスクあり。regex は Issue 仕様を正典とする
