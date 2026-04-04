## MODIFIED Requirements

### Requirement: workflow-setup Step 4 autopilot 判定と遷移指示

workflow-setup SKILL.md の Step 4 は、autopilot 判定 bash スニペットを実行し、IS_AUTOPILOT=true の場合に即座に `/dev:workflow-test-ready` を Skill tool で呼び出さなければならない（SHALL）。

#### Scenario: autopilot セッションでの setup → test-ready 自動遷移
- **WHEN** IS_AUTOPILOT=true（state-read.sh が status=running を返す）
- **THEN** `/dev:workflow-test-ready` を Skill tool で即座に実行し、プロンプトで停止しない

#### Scenario: 非 autopilot セッションでの setup 完了
- **WHEN** IS_AUTOPILOT=false
- **THEN** 「setup chain 完了」と案内し、手動で次の chain を実行するよう促す

---

### Requirement: workflow-test-ready Step 4 opsx-apply 後の遷移責務

workflow-test-ready SKILL.md の Step 4 は、opsx-apply 完了後に autopilot 判定を実行し、IS_AUTOPILOT=true の場合に `/dev:workflow-pr-cycle --spec <change-id>` を Skill tool で呼び出さなければならない（SHALL）。遷移責務は SKILL.md 側が持ち、opsx-apply 内部の判定に依存してはならない（MUST NOT）。

#### Scenario: autopilot セッションでの test-ready → pr-cycle 自動遷移
- **WHEN** opsx-apply が完了し IS_AUTOPILOT=true
- **THEN** `/dev:workflow-pr-cycle --spec <change-id>` を Skill tool で即座に実行し、プロンプトで停止しない

#### Scenario: 非 autopilot セッションでの test-ready 完了
- **WHEN** opsx-apply が完了し IS_AUTOPILOT=false
- **THEN** 「workflow-test-ready 完了」と案内し、`/dev:workflow-pr-cycle --spec <change-id>` の手動実行を促す

---

### Requirement: opsx-apply Step 3 の遷移ロジック削除

opsx-apply.md の Step 3 から IS_AUTOPILOT 判定と `/dev:workflow-pr-cycle` 呼び出しロジックを削除し、実装完了チェックポイント出力のみにしなければならない（SHALL）。

#### Scenario: opsx-apply 完了後のチェックポイント出力
- **WHEN** 全タスク完了後
- **THEN** `>>> 実装完了: <change-id>` と次のステップ案内のみを出力し、pr-cycle を自動実行しない

---

### Requirement: check.md CRITICAL FAIL 時の opsx-apply スキップ

check.md のチェックポイント指示は、CRITICAL FAIL 項目が存在する場合に `/dev:opsx-apply` を実行してはならない（MUST NOT）。CRITICAL FAIL なしの場合のみ自動実行しなければならない（SHALL）。

#### Scenario: CRITICAL FAIL なしでの check → opsx-apply 遷移
- **WHEN** 全チェック項目で CRITICAL FAIL が存在しない
- **THEN** `/dev:opsx-apply` を Skill tool で自動実行する

#### Scenario: CRITICAL FAIL ありでの停止
- **WHEN** 1 件以上の CRITICAL FAIL 項目が存在する
- **THEN** opsx-apply をスキップし、FAIL 内容を報告して停止する

---

## ADDED Requirements

### Requirement: 遷移指示への停止禁止明文化

各 workflow SKILL.md の chain 間遷移指示には「即座に Skill tool を実行せよ。プロンプトで停止するな」の文言を含めなければならない（SHALL）。

#### Scenario: 遷移指示に停止禁止文言が含まれる
- **WHEN** workflow chain の最終ステップに遷移指示がある
- **THEN** 「即座に Skill tool を実行せよ。プロンプトで停止するな」またはこれと同義の文言が明記されている
