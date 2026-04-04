## ADDED Requirements

### Requirement: co-autopilot SKILL.md 実装

co-autopilot の SKILL.md を stub から完全実装に置き換えなければならない（MUST）。architecture/domain/contexts/autopilot.md の設計定義に準拠し、旧 controller-autopilot のオーケストレーションフローを chain-driven アーキテクチャで再構築する。

SKILL.md は以下の Step 構成を持たなければならない（SHALL）:

- Step 0: 引数解析（MODE 判定、INPUT パース）
- Step 1: plan.yaml 生成（autopilot-plan スクリプト呼び出し）
- Step 2: 計画承認（--auto 時は自動承認、それ以外は AskUserQuestion）
- Step 3: セッション初期化（autopilot-init スクリプト呼び出し）
- Step 4: Phase ループ（autopilot-phase-execute → autopilot-phase-postprocess を Phase 数分繰り返し）
- Step 5: 完了サマリー（autopilot-summary 呼び出し）

#### Scenario: 通常の autopilot 実行
- **WHEN** ユーザーが `/dev:co-autopilot` を実行し、対象 Issue 群が存在する
- **THEN** plan.yaml が生成され、Phase ループで全 Issue が処理され、autopilot-summary が出力される

#### Scenario: --auto フラグ付き実行
- **WHEN** `--auto` フラグが指定されている
- **THEN** 計画承認ステップがスキップされ、自動的に Phase ループに進む

#### Scenario: Phase 内 Issue 失敗時
- **WHEN** Phase N で Issue が failed になる
- **THEN** 不変条件 D に従い、依存先の後続 Phase Issue が自動 skip される

### Requirement: self-improve ECC 照合の統合

co-autopilot は autopilot-patterns が self-improve Issue を検出した場合、ECC（Error Correction Code）照合を自動追加しなければならない（MUST）。旧 controller-self-improve の独立フローを co-autopilot の Phase ループ内に吸収する。

session.json の `self_improve_issues` フィールドに起票された Issue 番号を記録しなければならない（SHALL）。

#### Scenario: self-improve Issue 検出時
- **WHEN** autopilot-patterns が self-improve Issue 候補を検出する
- **THEN** ECC 照合が実行され、合致する場合は session.json の self_improve_issues に記録される

### Requirement: TaskCreate による進捗管理

co-autopilot は Phase ループ開始時に TaskCreate で Phase タスクを登録し、Issue 完了時に TaskUpdate で completed に更新しなければならない（MUST）。

#### Scenario: Phase 進捗の可視化
- **WHEN** Phase 1 が開始される
- **THEN** TaskCreate で「Phase 1: Issue #X, #Y」タスクが登録され、各 Issue 完了時に TaskUpdate で更新される
