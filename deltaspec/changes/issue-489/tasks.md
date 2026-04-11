## 1. co-issue/SKILL.md Phase 1 改修

- [ ] 1.1 現行 Phase 1（L35-39 周辺）を読み込み、ループ構造の挿入箇所を特定する
- [ ] 1.2 Phase 1 に explore ループ構造を実装する（最低 1 回の `/twl:explore` 呼び出し後に loop-gate を発火）
- [ ] 1.3 `[B]` 選択時の `accumulated_concerns` 蓄積・エスケープ・`<additional_concerns>` 注入ロジックを追加する
- [ ] 1.4 `[C]` 選択時の `edit-complete-gate`（編集完了確認 AskUserQuestion）を追加する
- [ ] 1.5 `Phase 1.5` の呼称を `Step 1.5` に変更し、ループ外（`[A]` 選択後）に配置する

## 2. テストケース追加

- [ ] 2.1 `plugins/twl/tests/scenarios/co-issue-skill.test.sh` を読み込み、既存テスト構造を確認する
- [ ] 2.2 ケース 1（1 ループで Phase 2 へ進むゲート記述 grep）を追加する
- [ ] 2.3 ケース 2（追加探索再呼び出しループ記述 grep）を追加する
- [ ] 2.4 ケース 3（edit-complete-gate 記述 grep）を追加する
- [ ] 2.5 ケース 4（Step 1.5 のループ外配置 grep）を追加する

## 3. 検証

- [ ] 3.1 `bash plugins/twl/tests/scenarios/co-issue-skill.test.sh` で全テストが green になることを確認する
- [ ] 3.2 `twl check` / `twl validate` で違反がないことを確認する
