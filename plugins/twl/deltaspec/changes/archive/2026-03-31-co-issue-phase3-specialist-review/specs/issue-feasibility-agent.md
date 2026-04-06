## ADDED Requirements

### Requirement: issue-feasibility agent 作成

issue-feasibility agent は、構造化された Issue body と対象ファイルパスを受け取り、実コードを読んで実装可能性・影響範囲を検証しなければならない（SHALL）。Read/Grep/Glob ツールで実コードを確認し、Issue の記述と実際のコードベースとの乖離を検出する。

出力は ADR-004 findings 形式に準拠しなければならない（SHALL）。category は `feasibility` を使用する。

agent frontmatter: `model: sonnet`, `maxTurns: 15`

#### Scenario: 対象ファイルが存在しない
- **WHEN** Issue body のスコープに記載されたファイルパスが実際には存在しない
- **THEN** severity: CRITICAL, category: feasibility の finding を出力する

#### Scenario: 影響範囲の見落とし
- **WHEN** Issue body に記載されていないが、変更対象ファイルの呼び出し元が追加で影響を受ける
- **THEN** severity: WARNING, category: feasibility の finding を出力し、影響を受けるファイルを列挙する

#### Scenario: deps.yaml との不整合
- **WHEN** 新規 agent/command/ref の追加が Issue body に記載されているが、deps.yaml 更新への言及がない
- **THEN** severity: WARNING, category: feasibility の finding を出力する

#### Scenario: 実装可能性に問題なし
- **WHEN** 全対象ファイルが存在し、影響範囲が Issue body と一致する
- **THEN** status: PASS, findings: [] を出力する
