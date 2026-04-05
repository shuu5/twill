## ADDED Requirements

### Requirement: 設計経緯転記ドキュメント

旧 controller の SKILL.md から重要な設計判断の経緯を `docs/design-decisions.md` に転記しなければならない（MUST）。転記対象: merge-gate 2パス統合の理由、deps.yaml 競合 Phase 分離ロジック、autopilot 不変条件の由来。

#### Scenario: 必須転記項目の網羅
- **WHEN** docs/design-decisions.md を参照する
- **THEN** merge-gate 統合判断、deps.yaml 競合制御、autopilot 不変条件の3項目が記載されている

#### Scenario: 旧プラグインからの追跡可能性
- **WHEN** 各設計判断エントリを読む
- **THEN** 旧プラグインのどのファイル（SKILL.md 等）から転記されたかの出典が明記されている
