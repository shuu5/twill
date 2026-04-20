## ADDED Requirements

### Requirement: phase-review checkpoint 存在チェック

merge-gate は `phase-review.json` checkpoint の存在を検査しなければならない（SHALL）。`phase-review.json` が不在の場合、merge-gate は REJECT を返さなければならない（MUST）。

#### Scenario: phase-review checkpoint が不在の場合は REJECT
- **WHEN** `.autopilot/checkpoints/phase-review.json` が存在しない状態で merge-gate が実行される
- **THEN** merge-gate は REJECT を返し、「phase-review checkpoint が不在です。specialist review を実行してください」というエラーメッセージを出力する

#### Scenario: scope/direct ラベル付き Issue は phase-review チェックをスキップ
- **WHEN** Issue に `scope/direct` ラベルが付与されており、`phase-review.json` が不在の状態で merge-gate が実行される
- **THEN** merge-gate は phase-review チェックをスキップし、他のチェックの結果で判定を続行する

#### Scenario: quick ラベル付き Issue は phase-review チェックをスキップ
- **WHEN** Issue に `quick` ラベルが付与されており、`phase-review.json` が不在の状態で merge-gate が実行される
- **THEN** merge-gate は phase-review チェックをスキップし、他のチェックの結果で判定を続行する

### Requirement: phase-review CRITICAL findings の統合

merge-gate は `phase-review.json` が存在する場合、その CRITICAL findings (confidence >= 80) を判定に統合しなければならない（MUST）。

#### Scenario: phase-review に CRITICAL findings がある場合は REJECT
- **WHEN** `.autopilot/checkpoints/phase-review.json` に confidence >= 80 の CRITICAL finding が含まれる状態で merge-gate が実行される
- **THEN** merge-gate は REJECT を返し、該当 finding の詳細をエラーメッセージに含める

#### Scenario: phase-review に CRITICAL findings がない場合は継続
- **WHEN** `.autopilot/checkpoints/phase-review.json` が存在し、confidence >= 80 の CRITICAL finding が含まれない状態で merge-gate が実行される
- **THEN** merge-gate は phase-review チェックを通過し、他のチェックの結果で判定を続行する

### Requirement: --force 使用時の phase-review 不在 WARNING

`--force` オプション使用時でも、phase-review checkpoint が不在の場合は WARNING としてログに記録しなければならない（SHALL）。

#### Scenario: --force 使用時も phase-review 不在は WARNING 記録
- **WHEN** `--force` オプションを使用して merge-gate が実行され、`phase-review.json` が不在の場合
- **THEN** merge-gate は REJECT を返さずに続行するが、「WARNING: phase-review checkpoint が不在です（--force により続行）」というメッセージをログに記録する
