## MODIFIED Requirements

### Requirement: workflow-test-ready chain 実行指示

`workflow-test-ready/SKILL.md` に chain 実行指示セクションを追加し、全ステップを `### Step N: name` 形式で明示列挙しなければならない（MUST）。

Claude が各ステップ間で停止せず自動遷移するために、テーブル形式のライフサイクル一覧ではなく、各ステップを個別の `### Step N:` 見出しで列挙しなければならない（SHALL）。

#### Scenario: chain 実行指示セクションの構造
- **WHEN** workflow-test-ready/SKILL.md を読んだとき
- **THEN** `## chain 実行指示（MUST — 全ステップを順に実行せよ。途中で停止するな）` セクションが存在する
- **THEN** Step 1〜4 が `### Step N: name` 形式で明示列挙されている
- **THEN** 各 Step に実行対象のコマンド/スキルが記載されている

#### Scenario: autopilot 判定と pr-cycle 遷移
- **WHEN** Step 4 の opsx-apply 実行が完了したとき
- **THEN** autopilot 判定（IS_AUTOPILOT）を実行する
- **THEN** IS_AUTOPILOT=true の場合、自動的に `/twl:workflow-pr-cycle` を Skill tool で実行する
- **THEN** IS_AUTOPILOT=false の場合、ユーザーに案内を表示して停止する

#### Scenario: check FAIL 時の遷移制御
- **WHEN** Step 3 の check で CRITICAL FAIL 項目が存在するとき
- **THEN** Step 4 の opsx-apply をスキップし、FAIL 内容を報告して停止しなければならない（MUST）

### Requirement: check.md チェックポイント追加

`check.md` の末尾にチェックポイント（MUST）セクションを追加しなければならない（SHALL）。chain 遷移の連続性を保証するため、次のコマンドへの自動実行指示を記載する。

#### Scenario: check 完了後の遷移
- **WHEN** check コマンドの実行が完了したとき
- **THEN** `## チェックポイント（MUST）` セクションに従い `/twl:opsx-apply` を Skill tool で自動実行する

### Requirement: opsx-apply.md フロー制御統一

`opsx-apply.md` のフロー制御を `### Step N:` 形式に統一しなければならない（MUST）。

#### Scenario: Step 形式のフロー制御
- **WHEN** opsx-apply.md を読んだとき
- **THEN** Step 1（change-id 解決）、Step 2（apply 実行）、Step 3（autopilot 判定 + pr-cycle 遷移）が明示列挙されている

#### Scenario: autopilot 判定による自動遷移
- **WHEN** opsx-apply の Step 3 で IS_AUTOPILOT=true のとき
- **THEN** 即座に `/twl:workflow-pr-cycle --spec <change-id>` を Skill tool で実行しなければならない（MUST）
