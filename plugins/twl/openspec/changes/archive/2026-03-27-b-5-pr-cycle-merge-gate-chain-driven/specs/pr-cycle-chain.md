## ADDED Requirements

### Requirement: pr-cycle chain 定義

deps.yaml の chains セクションに pr-cycle chain を定義しなければならない（SHALL）。chain は Type A で、verify → parallel-review → test → fix → post-fix-verify → visual → report → all-pass-check → merge のステップ順序を宣言的に管理する。

#### Scenario: chain 定義の完全性
- **WHEN** deps.yaml に pr-cycle chain が定義される
- **THEN** chains セクションに type: "A" と steps リストが含まれる
- **AND** 全ステップのコンポーネントが deps.yaml の commands/skills セクションに存在する

#### Scenario: chain validate パス
- **WHEN** `loom chain validate` を実行する
- **THEN** pr-cycle chain の双方向参照整合性が検証され pass する
- **AND** 各コンポーネントの chain/step_in フィールドが chain 定義と一致する

#### Scenario: chain ステップと SKILL.md の責務分離
- **WHEN** workflow-pr-cycle SKILL.md が chain-driven に縮小される
- **THEN** SKILL.md にはステップ順序やルーティングロジックが含まれない
- **AND** ドメインルール（fix ループ条件、merge-gate 判定基準、エスカレーション条件）のみが残る

### Requirement: pr-cycle chain コンポーネント登録

pr-cycle chain に参加するコンポーネントを deps.yaml に登録しなければならない（MUST）。各コンポーネントには chain, step_in, calls フィールドを設定する。

#### Scenario: 新規 atomic コンポーネント登録
- **WHEN** ts-preflight, scope-judge, pr-test, post-fix-verify, warning-fix, pr-cycle-report, all-pass-check, ac-verify を deps.yaml に追加する
- **THEN** 各コンポーネントに type: atomic, chain: "pr-cycle", step_in（parent と step 番号）が設定される
- **AND** COMMAND.md ファイルが commands/ 配下に存在する

#### Scenario: 新規 composite コンポーネント登録
- **WHEN** merge-gate, phase-review, fix-phase, e2e-screening を deps.yaml に追加する
- **THEN** 各コンポーネントに type: composite, chain: "pr-cycle", step_in, calls（呼び出す specialist/atomic のリスト）が設定される
- **AND** SKILL.md ファイルが skills/ 配下に存在する

## MODIFIED Requirements

### Requirement: workflow-pr-cycle SKILL.md 縮小

workflow-pr-cycle SKILL.md を chain で表現可能なステップ順序・条件分岐を排除し縮小しなければならない（SHALL）。

#### Scenario: ドメインルールのみ残留
- **WHEN** workflow-pr-cycle SKILL.md を更新する
- **THEN** fix ループの条件（テスト失敗時の fix-phase 発動と再テスト）が記述されている
- **AND** merge-gate 判定基準（CRITICAL && confidence >= 80）が記述されている
- **AND** エスカレーション条件（retry_count >= 1 で Pilot 報告）が記述されている
- **AND** ステップ番号のルーティング（Step 1: verify, Step 2: review...）は含まれない
