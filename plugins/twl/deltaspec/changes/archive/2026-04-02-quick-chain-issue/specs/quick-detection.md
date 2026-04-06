## ADDED Requirements

### Requirement: co-issue Phase 2 quick 判定基準

co-issue Phase 2（分解判断）は、Issue の記述内容から quick 候補を推定しなければならない（SHALL）。以下の条件を全て満たす場合に quick 候補とする:

- 変更ファイル 1-2 個
- 変更量 ~20行以下の見込み
- 修正内容が patch レベルで記述済み（tech-debt 系）
- OR テスト対象コードの変更なし（Markdown/config のみ）

#### Scenario: tech-debt 系の極小 Issue
- **WHEN** Issue body に「state-write の出力形式を修正（5行）」のような patch レベルの記述がある
- **THEN** Phase 2 が quick 候補として推定し、Phase 3b に quick-classification 検証を指示する

#### Scenario: Markdown のみの変更
- **WHEN** Issue body の変更対象が SKILL.md や CLAUDE.md のみ
- **THEN** Phase 2 が quick 候補として推定する

#### Scenario: 複数ファイルにまたがる変更
- **WHEN** Issue body に 3 ファイル以上の変更が記述されている
- **THEN** Phase 2 は quick 候補としない

### Requirement: co-issue Phase 3b quick 分類妥当性検証

co-issue Phase 3b の specialist（issue-critic, issue-feasibility）は、quick 分類の妥当性を検証しなければならない（MUST）。findings に `quick-classification` カテゴリを使用する。

#### Scenario: specialist が quick 不適切と判定
- **WHEN** issue-feasibility が実コードベースで変更量を検証し、20行を超えると判定した
- **THEN** `quick-classification: inappropriate` finding（severity: WARNING）を出力し、quick ラベル付与を阻止する

#### Scenario: specialist が通常 Issue に quick を推奨
- **WHEN** issue-critic が Issue を分析し、変更量が極小と判定した
- **THEN** `quick-classification: recommended` finding（severity: INFO）を出力し、ユーザーに quick ラベル付与を提案する

#### Scenario: --quick フラグ使用時
- **WHEN** co-issue が `--quick` フラグ付きで実行された
- **THEN** Phase 3b がスキップされるため、quick 分類検証も行われない。quick ラベルは付与しない（MUST NOT）

## MODIFIED Requirements

### Requirement: co-issue Phase 4 quick ラベル付与

co-issue Phase 4（一括作成）は、Phase 3b で quick 分類が妥当と検証された Issue に `quick` ラベルを付与しなければならない（SHALL）。

#### Scenario: quick 検証済み Issue の作成
- **WHEN** Phase 3b の findings に `quick-classification: inappropriate` がなく、Phase 2 で quick 候補と推定された Issue を作成する
- **THEN** `gh issue create` に `--label quick` を追加する

#### Scenario: ユーザーが quick を却下
- **WHEN** Phase 4 のユーザー確認で quick ラベルを削除するよう指示された
- **THEN** `--label quick` を付与しない（MUST）
