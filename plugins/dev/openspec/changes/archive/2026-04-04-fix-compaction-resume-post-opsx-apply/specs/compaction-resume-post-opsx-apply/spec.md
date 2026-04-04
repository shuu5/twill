## ADDED Requirements

### Requirement: post-opsx-apply を chain-steps.sh に追加

`chain-steps.sh` の `CHAIN_STEPS` 配列に `post-opsx-apply` ステップを `opsx-apply` の直後に追加しなければならない（SHALL）。これにより `compaction-resume.sh` が既存のインデックス比較ロジックで `post-opsx-apply` を正しく認識できるようになる。

#### Scenario: post-opsx-apply のインデックスが opsx-apply より後になる

- **WHEN** `compaction-resume.sh` が `post-opsx-apply` を query_step として呼び出される
- **THEN** `post-opsx-apply` のインデックスが `opsx-apply` のインデックスより大きい状態で返却され、順序比較が正しく機能する

### Requirement: opsx-apply 開始時の state 記録

`workflow-test-ready` SKILL.md Step 4 で opsx-apply を呼び出す前に、`current_step=opsx-apply` を `state-write.sh` で記録しなければならない（SHALL）。

#### Scenario: compaction が opsx-apply 実行中に発生した場合の復帰

- **WHEN** opsx-apply 実行中にコンテキスト compaction が発生し、workflow-test-ready が再起動される
- **THEN** `current_step=opsx-apply` の状態が残っており、compaction-resume.sh が `change-id-resolve`・`test-scaffold`・`check` をスキップし、`opsx-apply` から再実行する

### Requirement: opsx-apply 完了時の post-opsx-apply state 記録

`workflow-test-ready` SKILL.md Step 4 で opsx-apply が完了した直後、IS_AUTOPILOT 判定の実行前に `current_step=post-opsx-apply` を `state-write.sh` で記録しなければならない（SHALL）。

#### Scenario: IS_AUTOPILOT 判定前に state が記録される

- **WHEN** opsx-apply が正常完了し、IS_AUTOPILOT 判定を開始する前
- **THEN** `current_step=post-opsx-apply` が state ファイルに書き込まれており、以降のいかなる compaction からも復帰可能である

#### Scenario: post-opsx-apply state 後に compaction が発生した場合の復帰

- **WHEN** `current_step=post-opsx-apply` が記録された後にコンテキスト compaction が発生し、workflow-test-ready が再起動される
- **THEN** compaction-resume.sh が `opsx-apply` をスキップし（インデックスが current より小さいため）、`post-opsx-apply`（IS_AUTOPILOT 判定）から再実行する

## MODIFIED Requirements

### Requirement: compaction 復帰プロトコルに post-opsx-apply を含む

`workflow-test-ready` SKILL.md の compaction 復帰プロトコルの for ループに `post-opsx-apply` ステップを追加しなければならない（SHALL）。

#### Scenario: compaction 復帰ループが post-opsx-apply を処理する

- **WHEN** compaction-resume.sh が `post-opsx-apply` で exit 0（要実行）を返す
- **THEN** IS_AUTOPILOT 判定スニペットが実行され、IS_AUTOPILOT=true であれば `/dev:workflow-pr-cycle --spec <change-id>` が Skill tool で呼び出される

#### Scenario: opsx-apply 完了後の通常フローで IS_AUTOPILOT=false の場合

- **WHEN** opsx-apply 完了後に IS_AUTOPILOT 判定が実行され、IS_AUTOPILOT=false である
- **THEN** 従来通り案内メッセージ「workflow-test-ready 完了。次のステップ: /dev:workflow-pr-cycle」を表示して停止する（動作変更なし）

### Requirement: state-write 失敗時の非停止

`state-write.sh` の呼び出しは `|| true` で失敗を無視しなければならない（SHALL）。state 記録の失敗は compaction 復帰の精度を低下させるが、chain 全体を停止させてはならない（MUST NOT）。

#### Scenario: state-write.sh がエラーを返す

- **WHEN** `state-write.sh` が非ゼロで終了する
- **THEN** chain は継続し、次の処理（opsx-apply 呼び出しまたは IS_AUTOPILOT 判定）に進む
