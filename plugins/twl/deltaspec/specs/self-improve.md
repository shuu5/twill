# Self-Improve

workflow-self-improve による受動的 self-improvement（collect → propose → close + ecc-monitor）を定義するシナリオ。co-autopilot の後処理として呼び出される。能動的ライブセッション観察は live-observation.md を参照。

## Scenario: self-improve Issue 収集（Step 1）

- **WHEN** workflow-self-improve が実行される
- **THEN** self-improve ラベル付き Issue が収集・分類・優先度ソートされる
- **AND** 0 件の場合は「改善候補 Issue なし」と報告して終了する
- **AND** 1 件以上の場合は Step 2 に進む

## Scenario: 改善提案生成（Step 2）

- **WHEN** self-improve Issue が 1 件以上収集される
- **THEN** cooldown 判定が実行される
- **AND** ECC 照合が実行される
- **AND** 改善提案が生成されユーザー確認が求められる
- **AND** IS_AUTOPILOT=true 時は自動承認される
- **AND** 全件 cooldown または棄却の場合はその旨を報告して終了する

## Scenario: 改善適用 + クローズ（Step 3）

- **WHEN** Step 2 で承認済み Issue が 1 件以上ある
- **THEN** 各承認済み Issue に対して self-improve-close が実行される
- **AND** 改善が適用されファイルが変更される

## Scenario: ECC 変更検知（Step 4、autopilot 時のみ）

- **WHEN** IS_AUTOPILOT=true で workflow-self-improve が実行される
- **THEN** ecc-monitor の evaluate サブコマンドが実行される
- **WHEN** IS_AUTOPILOT=false の場合
- **THEN** ecc-monitor はスキップされる（ユーザーが手動で実行可能）

## Scenario: cooldown 判定の必須性

- **WHEN** 改善提案を生成する
- **THEN** cooldown 判定をスキップしてはならない
- **AND** 同一パターンの改善が短期間に繰り返されることを防止する

## Scenario: co-self-improve との責務分離

- **WHEN** self-improvement が必要な状況が発生する
- **THEN** 受動的改善（autopilot 後処理による蓄積 Issue の処理）は workflow-self-improve が担当する
- **AND** 能動的改善（ライブセッション観察による問題検出→Issue 起票）は co-self-improve が担当する
- **AND** 両者は責務が重ならず独立して動作する
