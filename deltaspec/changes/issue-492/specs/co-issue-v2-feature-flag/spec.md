## ADDED Requirements

### Requirement: CO_ISSUE_V2 環境変数を SKILL.md に正典宣言する

`plugins/twl/skills/co-issue/SKILL.md` の冒頭（Overview 直下、Phase 定義の前）に `## Environment` セクションを追加し、`CO_ISSUE_V2` (default `0`) を宣言しなければならない（SHALL）。宣言には変数名・default 値・有効化条件・rollback 手順を含める。

#### Scenario: Environment セクションが SKILL.md に存在する

- **WHEN** `plugins/twl/skills/co-issue/SKILL.md` を確認する
- **THEN** `## Environment` セクションが存在し、`CO_ISSUE_V2` (default `0`) の宣言が含まれている

#### Scenario: 未設定時は旧パスで動作する

- **WHEN** `CO_ISSUE_V2` 環境変数が未設定または `0` で co-issue を実行する
- **THEN** Phase 2-3-4 は v1 既存パス（workflow-issue-refine + workflow-issue-create）で動作し、既存テスト `co-issue-skill.test.sh` が全 PASS する

### Requirement: CO_ISSUE_V2=1 で新パスに切り替わる

Phase 2, Phase 3, Phase 4 それぞれの冒頭で `if [[ "${CO_ISSUE_V2:-0}" == "1" ]]` 分岐を持ち、flag==1 時に新パス（dispatch/aggregate）を実行しなければならない（SHALL）。

#### Scenario: flag==1 で新パスが実行される

- **WHEN** `CO_ISSUE_V2=1` で co-issue を実行し要望を入力する
- **THEN** Phase 2 が DAG 構築・bundle 書き出しを実行し、Phase 3 が issue-lifecycle-dispatch.sh を呼び出し、Phase 4 が aggregate を実行する

#### Scenario: CO_ISSUE_V2=0 で即時 rollback できる

- **WHEN** `CO_ISSUE_V2=0` または unset で co-issue を実行する
- **THEN** v1 旧パスで動作し、v2 コードパスは実行されない
