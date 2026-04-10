## MODIFIED Requirements

### Requirement: Wave 管理フローの完全実装

su-observer SKILL.md の Step 4 は、Wave 分割計画から co-autopilot spawn、観察ループ、wave-collect、externalize-state、su-compact までの完全な 8 サブステップフローを記述しなければならない（SHALL）。

#### Scenario: Wave 管理フロー記述の検証
- **WHEN** `plugins/twl/skills/su-observer/SKILL.md` の Step 4 を参照する
- **THEN** Wave 分割計画→co-autopilot spawn→observe ループ→Wave 完了検知→wave-collect→externalize-state→su-compact→次 Wave ループの 8 ステップが記述されている

### Requirement: wave-collect 呼出の明示

Step 4 は Wave 完了検知後に `commands/wave-collect.md` を Read → 実行し、WAVE_NUM 引数を渡すことを明示しなければならない（SHALL）。

#### Scenario: wave-collect 呼出の確認
- **WHEN** Step 4 の Wave 完了ステップを参照する
- **THEN** `commands/wave-collect.md` を Read → 実行（WAVE_NUM 付き）が記述されている

### Requirement: externalize-state 呼出の明示

Step 4 は wave-collect 実行後に `commands/externalize-state.md` を Read → 実行し、`--trigger wave_complete` を渡すことを明示しなければならない（SHALL）。

#### Scenario: externalize-state 呼出の確認
- **WHEN** Step 4 の状態外部化ステップを参照する
- **THEN** `commands/externalize-state.md` を Read → 実行（--trigger wave_complete）が wave-collect の後に記述されている

### Requirement: SU-6 制約の組み込み

Step 4 は Wave 完了後に `Skill(twl:su-compact)` を呼び出す SU-6 制約が実フローとして組み込まれていなければならない（SHALL）。

#### Scenario: SU-6 組み込みの確認
- **WHEN** Step 4 の su-compact 呼出ステップを参照する
- **THEN** `Skill(twl:su-compact)` の呼び出しが externalize-state の後に記述されており、SU-6 制約として明示されている
