## Context

co-issue の Phase 3b では specialist エージェント（issue-critic、issue-feasibility、worker-codex-reviewer）が Issue を精緻化する。この精緻化の完了状態は現在どこにも記録されず、GitHub Web 上での判別が不可能である。

Phase 4 では `recommended_labels`（ctx/* 等）と `quick` ラベルを付与するロジックが既にある。同じ箇所に `refined` ラベルを追加するのが最小侵襲の実装方法。`--quick` フラグは Phase 3b をスキップする唯一の経路であるため、`--quick` 未使用 ≡ Phase 3b 実行済み という 1:1 対応が成立する。

## Goals / Non-Goals

**Goals:**

- specialist レビューを経た Issue に `refined` ラベルを自動付与する
- `refined` ラベルが存在しない場合、冪等に作成する（カラー: `#0E8A16`）
- 3つの作成経路（単一・複数・クロスリポ）すべてに適用する
- `--quick` フラグ使用時は付与しない

**Non-Goals:**

- 既存 Issue への遡及付与
- ラベル付与条件のカスタマイズ
- `commands/issue-create.md` の変更（`--label` 引数で対応可能）

## Decisions

### 判定方法: `--quick` フラグの有無

`--quick` フラグ使用時のみ Phase 3b がスキップされる。追加の状態フラグを導入せず、既存フラグを判定条件として流用する。これにより実装が最小化される。

### ラベル作成: `gh label create` + `--force` フォールバック

`gh label create refined --color 0E8A16 --description "co-issue specialist review completed"` を実行し、既存時は `|| gh label edit refined --color 0E8A16 --description "..."` でフォールバックする。エラーで中断しない（MUST NOT）。

### 付与タイミング: Phase 4 の `REFINED_LABEL_OK` フラグ + 各経路個別対応

Phase 4 開始前に `refined` ラベルを冪等作成し、`REFINED_LABEL_OK` フラグでラベル作成成功を追跡する。その後、各作成経路（単一 `/twl:issue-create`、複数 `/twl:issue-bulk-create`、クロスリポ Step 4-CR）それぞれで `REFINED_LABEL_OK=true` かつ `is_split_generated != true` の場合にのみ `--label refined` を引数に追加する。クロスリポ経路では `CHILD_REFINED_OK` フラグを使って対象リポへのラベル作成成功を個別に追跡する。

## Risks / Trade-offs

- Phase 3b を将来スキップする別経路が追加された場合、判定条件の更新が必要になる（現時点では経路は1つのみ）
- `gh label create` が network エラーで失敗した場合、ラベルが作成されないが Issue 作成は続行される（警告のみ）
