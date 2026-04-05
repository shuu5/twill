## ADDED Requirements

### Requirement: worker-architecture drift 検出（merge-gate）

worker-architecture は PR diff モードで以下の drift を検出しなければならない（SHALL）:
- `domain/model.md` の IssueState / SessionState に定義されていない新しい状態値
- `domain/model.md` に定義されていない新エンティティの追加
- `architecture/domain/glossary.md` の MUST 用語に存在しない新用語のコード内使用

検出時は `severity: WARNING`, `category: architecture-drift` として報告しなければならない（SHALL）。

architecture/ が存在しない場合、drift 検出ロジック全体をスキップしなければならない（SHALL）。WARNING はマージをブロックしてはならない（SHALL NOT）。

#### Scenario: 新しい状態値が追加される
- **WHEN** PR diff に `status: "paused"` という新しい IssueState 値が追加され、`architecture/domain/model.md` の IssueState に `paused` が定義されていない
- **THEN** `severity: WARNING`, `category: architecture-drift`, `message: "新しい状態値 'paused' が IssueState に未定義"` として報告し、マージをブロックしない

#### Scenario: glossary 未登録の用語がコードで使われる
- **WHEN** PR diff のコメントや文字列に `quick-issue` という用語が含まれ、`architecture/domain/glossary.md` の MUST 用語に存在しない
- **THEN** `severity: WARNING`, `category: architecture-drift` として報告する

#### Scenario: architecture/ が存在しない
- **WHEN** PR diff を分析するプロジェクトに `architecture/` ディレクトリが存在しない
- **THEN** drift 検出をスキップし、architecture-drift カテゴリの WARNING を出力しない

## MODIFIED Requirements

### Requirement: deps.yaml の worker-architecture 参照ファイル更新

worker-architecture の deps.yaml 定義の参照ファイルリストに以下を追加しなければならない（SHALL）:
- `architecture/domain/glossary.md`
- `architecture/domain/model.md`
- `architecture/vision.md`

#### Scenario: deps.yaml が更新される
- **WHEN** worker-architecture.md が architecture drift 検出ロジックを含む
- **THEN** deps.yaml の worker-architecture エントリに architecture/ 参照ファイルが列挙されている
