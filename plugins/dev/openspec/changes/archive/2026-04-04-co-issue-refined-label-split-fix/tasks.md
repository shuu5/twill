## 1. SKILL.md: Phase 3c Step 5 の is_split_generated フラグ設定

- [x] 1.1 `skills/co-issue/SKILL.md` の Phase 3c Step 5「split 提案ハンドリング」を読み、承認後の新 Issue candidate 生成箇所を特定する
- [x] 1.2 split 承認後に生成される新 Issue candidates に `is_split_generated: true` コンテキストフラグを設定する旨の指示を追記する
- [x] 1.3 クロスリポ split（`cross_repo_split = true`）の子 Issue は対象外である旨を明記する

## 2. SKILL.md: Phase 4 の refined 付与ロジック変更

- [x] 2.1 Phase 4 の `REFINED_LABEL_OK` チェック箇所（単一/複数経路）を読み、`is_split_generated: true` の場合にスキップする条件を追加する
- [x] 2.2 クロスリポ経路（Step 4-CR）の `CHILD_REFINED_OK` チェック箇所も同様に `is_split_generated` 条件を追加する
- [x] 2.3 Phase 4 の **注意** テキストに `is_split_generated` フラグの扱いを追記する

## 3. design.md の更新

- [x] 3.1 `openspec/changes/co-issue-refined-label/design.md` の「付与タイミング」Decisions セクションを読む
- [x] 3.2 「recommended_labels に refined を追加して既存のラベル付与ロジックに乗せる」の記述を削除し、`REFINED_LABEL_OK` フラグ + 各経路個別対応パターンの説明に差し替える

## 4. 検証

- [x] 4.1 SKILL.md の変更が受け入れ基準（split 後 Issue に refined が付かない / 通常フローは維持 / design.md が実装を反映）をすべて満たすことを確認する
