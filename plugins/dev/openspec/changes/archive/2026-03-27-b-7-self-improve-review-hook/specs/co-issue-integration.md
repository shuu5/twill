## MODIFIED Requirements

### Requirement: co-issue の explore-summary 検出

co-issue は起動時に `.controller-issue/explore-summary.md` の存在を検出し、前回の探索結果からの続行を提案しなければならない（SHALL）。

#### Scenario: explore-summary.md が存在する場合
- **WHEN** co-issue が起動され `.controller-issue/explore-summary.md` が存在する
- **THEN** 「前回の探索結果が残っています。継続しますか？」とユーザーに確認する

#### Scenario: 継続を選択した場合
- **WHEN** ユーザーが継続を選択する
- **THEN** co-issue は Phase 1（探索）をスキップし Phase 2（分解判断）から続行する

#### Scenario: 継続を拒否した場合
- **WHEN** ユーザーが継続を拒否する
- **THEN** explore-summary.md を削除し、通常の Phase 1 から開始する

#### Scenario: explore-summary.md が存在しない場合
- **WHEN** co-issue が起動され `.controller-issue/explore-summary.md` が存在しない
- **THEN** 通常の Phase 1（探索）から開始する（既存動作に影響なし）
