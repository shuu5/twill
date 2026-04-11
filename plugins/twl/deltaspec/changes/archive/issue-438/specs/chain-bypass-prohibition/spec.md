## ADDED Requirements

### Requirement: chain bypass 禁止の明文化（co-autopilot SKILL.md）
Worker chain が停止した場合、Pilot は直接 nudge して PR 作成 → マージを実行してはならない（MUST NOT）。chain 停止時の正規復旧手順のみが許可される。

#### Scenario: chain 停止時に Pilot が直接 nudge を行わない
- **WHEN** Worker の chain 遷移が停止し、orchestrator が inject を実行していない状態で Pilot が停止を検知する
- **THEN** Pilot は orchestrator 再起動または手動 `/twl:workflow-<name>` inject を実行し、直接 nudge によるチェーン迂回を行わない

#### Scenario: chain 停止時の正規復旧手順が定義されている
- **WHEN** orchestrator が停止して chain 遷移が行われない状態が検知される
- **THEN** Pilot は co-autopilot SKILL.md に記載された復旧手順（orchestrator 再起動 or 手動 skill inject）に従い chain を再開する

### Requirement: 不変条件 M（autopilot.md）
chain 遷移（workflow_done 検知後の次 workflow 起動）は orchestrator の `inject_next_workflow` または手動 skill inject（`/twl:workflow-<name>`）のみ許可されなければならない（SHALL）。Pilot の直接 nudge による chain bypass は禁止される。

#### Scenario: 不変条件 M が autopilot.md に追加される
- **WHEN** autopilot.md の不変条件テーブルを参照する
- **THEN** 不変条件 M「chain 遷移は orchestrator/手動 inject のみ」が定義されており、Pilot の直接 nudge による chain bypass が禁止であることが明記されている

#### Scenario: 不変条件 M の参照先が co-autopilot SKILL.md に記載される
- **WHEN** co-autopilot SKILL.md の禁止事項セクションを参照する
- **THEN** chain bypass 禁止が不変条件 M として参照され、正規復旧手順へのリンクが明記されている
