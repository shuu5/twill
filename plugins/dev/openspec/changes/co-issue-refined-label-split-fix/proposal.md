## Why

co-issue の `refined` ラベル（"specialist review completed"）は、split 承認後に生成される新 Issue にも一律で付与されており、ラベルの定義と実態が乖離している。また `openspec/changes/co-issue-refined-label/design.md` の設計方針が実際の実装パターンと異なる記述になっている。

## What Changes

- Phase 3c Step 5（split 承認処理）で生成される新 Issue を `is_split_generated` フラグで追跡
- Phase 4 の `refined` ラベル付与ロジックに `is_split_generated == true` の場合はスキップする分岐を追加
- split 後の新 Issue には親 Issue の `recommended_labels`（ctx/* 等）を引き継ぐ
- `openspec/changes/co-issue-refined-label/design.md` の Decisions セクションを実装パターン（`REFINED_LABEL_OK` フラグ + 各経路個別対応）に合わせて更新

## Capabilities

### New Capabilities

- split で生成された Issue を `is_split_generated` フラグで区別できる
- `is_split_generated` な Issue への `refined` ラベル誤付与を防止

### Modified Capabilities

- Phase 4 の `refined` ラベル付与: 通常フローは既存動作を維持、`is_split_generated` フローのみスキップに変更
- `openspec/changes/co-issue-refined-label/design.md`: 「推奨ラベルに乗せる」方式の記述を削除し、`REFINED_LABEL_OK` パターンの説明に修正

## Impact

- `skills/co-issue/SKILL.md`: Phase 3c Step 5 と Phase 4 を変更
- `openspec/changes/co-issue-refined-label/design.md`: Decisions セクションを更新
- 既存 Issue への遡及修正なし
- Phase 3b specialist レビューロジックへの変更なし
- クロスリポ子 Issue（`cross_repo_split = true`）への refined 付与は変更なし
