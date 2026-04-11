## ADDED Requirements

### Requirement: explore ループ構造の静的テストケース追加
`plugins/twl/tests/scenarios/co-issue-skill.test.sh` に以下 4 ケースを追加しなければならない（SHALL）。各テストは SKILL.md の構造記述（grep）で検証する静的テストとする。

#### Scenario: ケース 1 — 1 ループで Phase 2 へ進むゲート記述
- **WHEN** `co-issue-skill.test.sh` を実行する
- **THEN** SKILL.md に「1 ループで Phase 2 へ進む」ゲート選択肢の記述があることを grep で検証し PASS する

#### Scenario: ケース 2 — 追加探索再呼び出しループ記述
- **WHEN** `co-issue-skill.test.sh` を実行する
- **THEN** SKILL.md に「追加探索」選択時の再呼び出しループ記述があることを grep で検証し PASS する

#### Scenario: ケース 3 — 手動編集対応記述（edit-complete-gate 含む）
- **WHEN** `co-issue-skill.test.sh` を実行する
- **THEN** SKILL.md に `edit-complete-gate` の記述があることを grep で検証し PASS する

#### Scenario: ケース 4 — Step 1.5 のループ外配置
- **WHEN** `co-issue-skill.test.sh` を実行する
- **THEN** SKILL.md に `Step 1.5` が loop-gate の `[A]` 選択後（ループ外）に配置されていることを grep で検証し PASS する

### Requirement: 既存テストの green 維持
既存の `co-issue-skill.test.sh` テストケースおよび `test_no_phase_5_or_above` が全て green を維持しなければならない（SHALL）。

#### Scenario: 既存テスト不破壊
- **WHEN** `co-issue-skill.test.sh` を実行する
- **THEN** 既存の全テストケースが PASS する
