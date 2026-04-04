## MODIFIED Requirements

### Requirement: auto-merge.sh が IS_AUTOPILOT=false && status=running の矛盾を検出して merge-ready を宣言する

auto-merge.sh は IS_AUTOPILOT=false かつ AUTOPILOT_STATUS=running の矛盾状態を検出した場合、merge-ready を宣言して merge を中止しなければならない（SHALL）。

#### Scenario: IS_AUTOPILOT=false && status=running の矛盾検出
- **WHEN** auto-merge.sh が呼ばれ、Layer 1 で IS_AUTOPILOT=false と判定されたが AUTOPILOT_STATUS=running が返る
- **THEN** state-write.sh で status=merge-ready を宣言し、exit 0 で終了する（merge を実行しない）

#### Scenario: 矛盾検出時の state-write.sh 失敗
- **WHEN** 矛盾を検出し、state-write.sh が失敗する（exit 1）
- **THEN** エラーを握りつぶして exit 0 で終了する（merge を実行しないことを最優先）

#### Scenario: 非 autopilot 環境への影響なし
- **WHEN** auto-merge.sh が呼ばれ、AUTOPILOT_STATUS が空（非 autopilot 環境）
- **THEN** 矛盾検出ロジックをスキップして既存フロー（squash merge）を実行する
