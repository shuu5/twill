## MODIFIED Requirements

### Requirement: workflow-setup quick フロー分岐

`workflow-setup SKILL.md` Step 4 は、IS_AUTOPILOT と is_quick の両方を判定して遷移を決定しなければならない（SHALL）。
quick + IS_AUTOPILOT=true の場合、`/dev:workflow-test-ready` を呼び出してはならない（MUST NOT）。

#### Scenario: quick Issue かつ autopilot 実行時

- **WHEN** `is_quick=true` かつ `IS_AUTOPILOT=true` の状態で Step 4 に到達したとき
- **THEN** workflow-test-ready Skill 呼び出しを行わず、「直接実装 → commit → push → `gh pr create --fill --label quick` → merge-gate のみ実行せよ」と Worker に指示しなければならない（MUST）

#### Scenario: 通常 Issue かつ autopilot 実行時

- **WHEN** `is_quick=false` かつ `IS_AUTOPILOT=true` の状態で Step 4 に到達したとき
- **THEN** 従来通り即座に `/dev:workflow-test-ready` を Skill tool で実行しなければならない（SHALL）

### Requirement: autopilot-launch quick ラベル情報の提供

`autopilot-launch.sh` は、起動対象 Issue に `quick` ラベルがある場合、Worker プロンプトに quick フロー向けの文脈情報を含めなければならない（SHALL）。

#### Scenario: quick ラベル付き Issue の起動

- **WHEN** `autopilot-launch.sh` が quick ラベル付き Issue を対象に起動するとき
- **THEN** プロンプトに「このIssueはquickラベル付きです。直接実装→merge-gateのみを実行してください」相当の情報が含まれていなければならない（MUST）

#### Scenario: 通常 Issue の起動

- **WHEN** `autopilot-launch.sh` が quick ラベルなし Issue を対象に起動するとき
- **THEN** プロンプトは現行通り `/dev:workflow-setup #${ISSUE}` のままでよい（SHALL）

## ADDED Requirements

### Requirement: workflow-test-ready quick 判定ガード

`workflow-test-ready SKILL.md` は実行開始時に対象 Issue の is_quick 状態を確認しなければならない（SHALL）。
quick Issue の場合は workflow-test-ready の処理を続行してはならない（MUST NOT）。

#### Scenario: quick Issue に対する workflow-test-ready 呼び出し

- **WHEN** quick ラベル付き Issue のコンテキストで workflow-test-ready が実行されたとき
- **THEN** 「quick Issue は workflow-test-ready をスキップ。merge-gate のみ実行してください」とメッセージを出して即座に終了しなければならない（MUST）

#### Scenario: 通常 Issue に対する workflow-test-ready 呼び出し

- **WHEN** quick ラベルなし Issue のコンテキストで workflow-test-ready が実行されたとき
- **THEN** 従来通りのフロー（テスト生成・準備確認）を実行しなければならない（SHALL）
